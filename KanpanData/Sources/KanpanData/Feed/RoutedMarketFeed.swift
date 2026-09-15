import Foundation
import KanpanCore

/// Switches complete feeds. Business views never merge candles from different exchanges.
public actor RoutedMarketFeed {
  private let hosts: BinanceHosts
  private let log: FeedLog
  private let paths: Paths
  private let preferenceURL: URL
  private var freshHistory = false
  private let primary: BinanceREST
  private let backup: BinanceREST
  private var source: MarketSource = .binance
  private var feed: MarketFeed?
  private var pump: Task<Void, Never>?
  private var monitor: Task<Void, Never>?
  private var selection = UUID()
  private var route = UUID()
  private var symbol = ""
  private var interval: Interval = .h1
  private var snapshots = true
  private var foreground = true
  private var recovery = MarketRecoverySchedule()
  private var announcingSwitch = false
  private var pendingHistoryError: String?
  private var historyBoundary: Int64?
  private var seriesStart: Int64?
  private var historyRetry = Date.distantPast
  private var continuation: AsyncStream<FeedUpdate>.Continuation?
  private var prefetchTask: Task<Void, Never>?
  /// 换周期预热单独占一个槽：它跟自选预热是两件事，谁也不该把对方掐掉。
  private var warmTask: Task<Void, Never>?
  /// 上一次预热时带来的常用周期表。记下来，换品种之后自动给新品种也热一遍。
  private var warmIntervals: [Interval] = []
  /// 预热几个自选。自选列表通常也就这么长，等于「整张列表都热过一遍」。
  /// 一个品种一发 300 根（限频权重 2），20 个合计 40 点权重，币安一分钟的配额是 2400。
  public static let prefetchLimit = 20

  public init(hosts: BinanceHosts, paths: Paths = .caches(), preferenceURL: URL? = nil, log: FeedLog = .silent) {
    self.hosts = hosts; self.paths = paths; self.log = log
    self.preferenceURL = preferenceURL ?? paths.root.appendingPathComponent("market-source.json")
    if let data = try? Data(contentsOf: self.preferenceURL), let saved = try? JSONDecoder().decode(MarketSource.self, from: data) { source = saved }
    primary = .upstream(.binance, hosts: hosts, log: log)
    backup = .upstream(.okx, hosts: hosts, log: log)
  }
  public func events() -> AsyncStream<FeedUpdate> {
    let (stream, sink) = AsyncStream<FeedUpdate>.makeStream(); continuation = sink; return stream
  }
  public var currentSeries: BarSeries {
    get async { if let feed { return await feed.currentSeries }; return BarSeries(symbol: symbol, interval: interval, bars: []) }
  }
  public func setSnapshotEnabled(_ enabled: Bool) async {
    snapshots = enabled
    await feed?.setSnapshotEnabled(enabled)
    if !enabled {
      Snapshot.remove(paths.snapshot)
      SeriesStore.clear(in: paths.series)
      for name in ["binance", "okx"] {
        let sub = Paths(root: paths.root.appendingPathComponent("sources/" + name))
        Snapshot.remove(sub.snapshot)
        SeriesStore.clear(in: sub.series)
      }
    }
  }
  public func start(symbol: String, interval: Interval, selection: UUID = UUID()) async {
    await switchTo(symbol: symbol, interval: interval, coldStart: true, selection: selection)
  }
  public func switchTo(symbol: String, interval: Interval, coldStart: Bool = false, selection: UUID = UUID()) async {
    guard !Task.isCancelled else { return }
    freshHistory = false; pendingStatus = .offline
    pendingHistoryError = nil; historyBoundary = nil; seriesStart = nil; historyRetry = .distantPast
    self.symbol = symbol; self.interval = interval; self.selection = selection
    monitor?.cancel()
    if let feed { await feed.switchTo(symbol: symbol, interval: interval, coldStart: coldStart, selection: selection) }
    else { await activate(source, coldStart: coldStart) }
    if self.selection == selection { startMonitoring(immediate: historyRetry > Date()) }
    // 换了品种，新品种的其他常用周期也热一遍：用户看完这一档，下一个动作
    // 多半就是切周期。等首屏和后台加深先走完，别跟它们抢带宽。
    if coldStart, self.selection == selection { warmOtherIntervals(of: symbol, current: interval) }
  }
  private func activate(_ next: MarketSource, coldStart: Bool = false) async {
    let request = selection; let generation = UUID(); route = generation
    pump?.cancel(); await feed?.stop()
    guard request == selection, generation == route, !Task.isCancelled else { return }
    freshHistory = false
    pendingStatus = .offline
    source = next; recovery = MarketRecoverySchedule()
    let rest = next == .binance ? primary : backup
    var directHosts = hosts; directHosts.streamFallbacks = []
    let ws = BinanceWS(hosts: directHosts, factory: SourceSocketFactory(source: next, hosts: hosts), silenceMs: 15_000, log: log)
    let sourcePaths = next == .binance ? paths : Paths(root: paths.root.appendingPathComponent("sources/okx"))
    let created = MarketFeed(rest: rest, ws: ws,
      paths: sourcePaths,
      includeTicker: next == .binance, initialLimit: 300, log: log)
    feed = created
    await created.setSnapshotEnabled(snapshots)
    let stream = await created.events()
    pump = Task { [weak self] in
      for await update in stream {
        guard !Task.isCancelled, let self else { return }
        await self.forward(update, generation: generation, source: next)
      }
    }
    await created.start(symbol: symbol, interval: interval, selection: request)
  }
  private var publishedRoute: UUID?
  private var pendingStatus: FeedStatus = .offline
  private func forward(_ update: FeedUpdate, generation: UUID, source: MarketSource) {
    guard generation == route, update.selection == selection else { return }
    if case .series(let series) = update.event { seriesStart = series.firstTime }
    if case .historyError(let message) = update.event {
      pendingHistoryError = message
      if message != nil {
        announceSwitch()
        if source == .binance { historyBoundary = seriesStart; historyRetry = Date().addingTimeInterval(60) }
        startMonitoring(immediate: true)
        return // Internal retries stay quiet; report only when no complete source is available.
      }
      freshHistory = true; saveSourceIfReady()
      if source == .binance { historyRetry = .distantPast; historyBoundary = nil }
      continuation?.yield(update)
      return
    }
    if case .status(let status) = update.event {
      pendingStatus = status
      // Do not wait for the normal 20-second monitor cadence when a newly
      // selected source is already offline. This matters on mobile networks
      // that can open HTTP but black-hole WebSocket traffic.
      if status != .live { startMonitoring(immediate: true) }
    }
    if publishedRoute != generation {
      guard case .series(let series) = update.event, series.count >= 3 else { return }
      publishedRoute = generation
      continuation?.yield(FeedUpdate(selection: selection, event: .source(source)))
      continuation?.yield(FeedUpdate(selection: selection, event: .status(pendingStatus)))
    }
    continuation?.yield(update)
    saveSourceIfReady()
  }
  private var savedSource: MarketSource?
  private func saveSourceIfReady() {
    guard freshHistory, pendingStatus == .live, publishedRoute == route else { return }
    if announcingSwitch {
      announcingSwitch = false
      continuation?.yield(FeedUpdate(selection: selection, event: .routing(.switched)))
    }
    guard savedSource != source else { return }
    do {
      try FileManager.default.createDirectory(at: preferenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(source).write(to: preferenceURL, options: .atomic)
      savedSource = source
    } catch { log("行情线路偏好未保存：\(error)") }
  }
  private func healthy(_ candidate: MarketSource, symbol: String, interval: Interval,
                       requireStream: Bool = true) async -> Bool {
    let rest = candidate == .binance ? primary : backup
    let boundary = historyBoundary
    let streamFactory = SourceSocketFactory(source: candidate, hosts: hosts)
    let streamURL = hosts.combinedStream([
      BinanceHosts.klineStream(symbol: symbol, interval: interval.source.rawValue)
    ])

    // REST and WS are independent. The old serial probe paid both network
    // round trips before activating the source, even though the feed starts
    // its own REST and WS work immediately afterwards.
    async let restReady = Self.restHealthy(rest: rest, symbol: symbol, interval: interval,
                                           boundary: boundary)
    if !requireStream { return await restReady }
    async let streamReady = Self.streamHealthy(factory: streamFactory, url: streamURL)
    let restOK = await restReady
    let streamOK = await streamReady
    return restOK && streamOK
  }

  private static func restHealthy(rest: BinanceREST, symbol: String, interval: Interval,
                                  boundary: Int64?) async -> Bool {
    do {
      let bars = try await rest.klines(symbol: symbol, interval: interval, limit: 3)
      try Task.checkCancellation()
      guard bars.count >= 3, let last = bars.last else { return false }
      if let boundary {
        let older = try await rest.klines(symbol: symbol, interval: interval, limit: 3,
                                          endTime: boundary - 1)
        guard !older.isEmpty else { return false }
      }
      let current = Aggregator.bucketStart(ms: Int64(Date().timeIntervalSince1970 * 1000), interval: interval)
      return last.openTime >= current
    } catch { return false }
  }

  private static func streamHealthy(factory: SourceSocketFactory, url: URL) async -> Bool {
    do {
      let socket = try await factory.connect(to: url)
      await socket.cancel()
      try Task.checkCancellation()
      return true
    } catch { return false }
  }
  private func startMonitoring(immediate: Bool = false) {
    monitor?.cancel()
    guard foreground else { return }
    let request = selection
    monitor = Task { [weak self] in
      guard let self else { return }
      if !immediate { do { try await Task.sleep(for: .seconds(20)) } catch { return } }
      while !Task.isCancelled {
        await self.checkSource(selection: request)
        do { let seconds = await self.monitorDelay(); try await Task.sleep(for: .seconds(seconds)) } catch { return }
      }
    }
  }
  private func monitorDelay() -> Double { source == .okx && recovery.confirming ? 10 : 20 }
  private func announceSwitch() {
    guard !announcingSwitch else { return }
    announcingSwitch = true
    continuation?.yield(FeedUpdate(selection: selection, event: .routing(.switching)))
  }
  private func unavailable(_ request: UUID) {
    announcingSwitch = false
    continuation?.yield(FeedUpdate(selection: request, event: .routing(.idle)))
    continuation?.yield(FeedUpdate(selection: request, event: .historyError("暂时无法连接，点此重试")))
  }
  private func checkSource(selection request: UUID) async {
    guard request == selection, foreground, !Task.isCancelled else { return }
    // A healthy active Binance feed already proves connectivity; avoid duplicate startup probes.
    if source == .binance, pendingStatus == .live, pendingHistoryError == nil, Date() >= historyRetry { return }
    let sym = symbol, iv = interval, chosen = source
    // Source choice survives navigation. Healthy OKX never waits for a Binance probe.
    if source == .okx, pendingStatus == .live, pendingHistoryError == nil, !recovery.isDue(at: Date()) {
      await refreshBackupTicker(symbol: sym, selection: request)
      return
    }
    let primaryReady = Date() >= historyRetry ? await healthy(.binance, symbol: sym, interval: iv) : false
    guard request == selection, foreground, !Task.isCancelled, chosen == source else { return }
    if source == .binance {
      // The active Binance feed already made the full request and received a
      // real history error. Do not make the user wait for a second OKX probe:
      // activating OKX starts its REST and WS checks concurrently and only
      // publishes the source after a valid series arrives. A standalone
      // health check is still kept for WS-only failures where REST has not
      // conclusively failed yet.
      var fallbackReady = false
      if !primaryReady, !hosts.oiProxies.isEmpty {
        fallbackReady = pendingHistoryError != nil
          ? true
          : await healthy(.okx, symbol: sym, interval: iv)
      }
      if fallbackReady {
        guard request == selection, foreground, !Task.isCancelled else { return }
        if pendingHistoryError == nil, pendingStatus == .live { return }
        announceSwitch()
        await activate(.okx)
      } else if !primaryReady, pendingHistoryError != nil {
        unavailable(request)
      }
    } else {
      let recovered = recovery.record(healthy: primaryReady, at: Date())
      // A second complete REST + live-frame success confirms recovery, in the background.
      if primaryReady && (pendingHistoryError != nil || recovered) { await activate(.binance) }
      else {
        if pendingHistoryError != nil { unavailable(request) }
        await refreshBackupTicker(symbol: sym, selection: request)
      }
    }
  }
  private func refreshBackupTicker(symbol: String, selection request: UUID) async {
    if let ticker = try? await backup.ticker24h(symbol: symbol), request == selection, source == .okx, !Task.isCancelled {
      continuation?.yield(FeedUpdate(selection: request, event: .ticker(ticker)))
    }
  }
  public func loadMore(pages: Int = 1) async { await feed?.loadMore(pages: pages) }

  /// 预热：趁用户还在看自选列表，把他大概率会点开的东西先拉回来落到快照里。
  /// 点进去时 `switchTo` 直接命中磁盘，第一帧就有图，不用等网络。
  ///
  /// 两类活儿，按「多半会先发生」排序：先是自选列表里的品种（当前周期），
  /// 因为下一个动作大概率是点开其中一个；然后是**当前品种的其他常用周期**，
  /// 因为进图之后第二个动作大概率是切周期。
  ///
  /// 只花请求和磁盘，不占内存——拉回来直接写盘，不塞 `BarCache`。
  /// 失败就算了，预热不成功只是回到「点进去等一下」，不报错。
  public func prefetch(symbols: [String], interval: Interval, intervals: [Interval] = []) {
    prefetchTask?.cancel()
    guard snapshots, interval.source == interval else { return }
    if !intervals.isEmpty { warmIntervals = intervals }
    let current = symbol.uppercased()
    var seen = Set<String>([current])
    var jobs = symbols.map { $0.uppercased() }.filter { seen.insert($0).inserted }
      .prefix(Self.prefetchLimit).map { (symbol: $0, interval: interval) }
    // 当前品种换周期：本地已经有当前这档了，补其余几档。
    jobs += intervals.filter { $0 != interval && $0.source == $0 }.map { (symbol: current, interval: $0) }
    // 慢一步再开始。预热的每一份是 300 根、几十 KB，而此刻用户正盯着自选列表
    // 等那一屏报价（每条只有几百字节）补齐——先让小的过去。等得起：用户从
    // 看清列表到点进某一行，不会比这快。
    prefetchTask = run(jobs: jobs, delayMs: 1200)
  }

  /// 换品种之后，给新品种的其他常用周期也各拉一份。
  ///
  /// 常用周期表是上一次 `prefetch` 留下来的（`warmIntervals`），所以不用在每次
  /// 切换时都把偏好设置一路塞下来。延迟 2.5 秒是让首屏和后台加深先跑完——
  /// 用户此刻正盯着这一档，别跟它抢带宽。
  private func warmOtherIntervals(of symbol: String, current: Interval) {
    warmTask?.cancel()
    guard snapshots, !warmIntervals.isEmpty, current.source == current else { return }
    let name = symbol.uppercased()
    let jobs = warmIntervals.filter { $0 != current && $0.source == $0 }.map { (symbol: name, interval: $0) }
    warmTask = run(jobs: jobs, delayMs: 2500)
  }

  /// 预热的活儿本身：挨个拉回来写盘。只花请求和磁盘，不占内存。
  private func run(jobs: [(symbol: String, interval: Interval)], delayMs: Int) -> Task<Void, Never>? {
    guard !jobs.isEmpty else { return nil }
    let rest = source == .binance ? primary : backup
    let dir = (source == .binance ? paths : Paths(root: paths.root.appendingPathComponent("sources/okx"))).series
    let log = self.log
    return Task.detached(priority: .utility) {
      if delayMs > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        guard !Task.isCancelled else { return }
      }
      var done = 0
      for job in jobs {
        guard !Task.isCancelled else { return }
        // 已经有一份够新的就跳过——落后不到几根的快照，点进去照样是秒开。
        if let have = SeriesStore.read(symbol: job.symbol, interval: job.interval, in: dir),
           have.count >= MarketFeed.firstScreenLimit / 2,
           Int64(Date().timeIntervalSince1970 * 1000) - have.lastTime < 3 * job.interval.stepMs { continue }
        do {
          let bars = try await rest.klines(symbol: job.symbol, interval: job.interval, limit: MarketFeed.firstScreenLimit)
          guard !bars.isEmpty else { continue }
          _ = try SeriesStore.write(BarSeries(symbol: job.symbol, interval: job.interval, bars: BinanceREST.dedup(bars)), in: dir)
          done += 1
        } catch {
          // 一个失败多半意味着线路本身不行，后面几个也别再试了。
          log("预热停在 \(job.symbol) \(job.interval.rawValue)：\(error)")
          return
        }
      }
      log("预热 \(done)/\(jobs.count) 份快照")
    }
  }

  /// Retry the currently selected source after a visible history failure.
  /// This also clears the short-lived route backoff because the retry was an
  /// explicit user action, not an automatic probe.
  public func retry(selection requested: UUID = UUID()) async {
    await primary.resetRouteCooldowns()
    await backup.resetRouteCooldowns()
    await switchTo(symbol: symbol, interval: interval, coldStart: false, selection: requested)
  }

  public func networkChanged(online: Bool) async {
    await feed?.networkChanged(online: online)
    if online {
      recovery.networkRestored(at: Date())
      startMonitoring()
    } else { monitor?.cancel() }
  }
  public func enterBackground() async { foreground = false; monitor?.cancel(); await feed?.enterBackground() }
  public func enterForeground() async { foreground = true; await feed?.enterForeground(); startMonitoring() }
  public func memoryWarning() async { await feed?.memoryWarning() }
  public func stop() async {
    selection = UUID(); route = UUID(); monitor?.cancel(); pump?.cancel()
    prefetchTask?.cancel(); warmTask?.cancel()
    await feed?.stop(); feed = nil; continuation?.finish(); continuation = nil
  }
}
