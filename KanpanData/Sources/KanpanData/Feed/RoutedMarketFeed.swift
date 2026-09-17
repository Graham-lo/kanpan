import Foundation
import KanpanCore

/// Switches complete feeds. Business views never merge candles from different exchanges.
public actor RoutedMarketFeed {
  private let hosts: BinanceHosts
  private let log: FeedLog
  private let paths: Paths
  private var freshHistory = false
  private let primary: BinanceREST
  private let backup: BinanceREST
  /// WS 工厂。默认就是真 `URLSessionSocketFactory`，测试里注假件。
  private let sockets: any WSSocketFactory
  /// 行情线路。用户定的，见 `MarketRoutePolicy`：线路决定交易所（直连=币安、网关=OKX），
  /// 这里从不自己换线。
  private var policy: MarketRoutePolicy
  /// 自己听 `marketRoutePolicyDidChange`，app 侧改完设置就不用再管了。
  private nonisolated(unsafe) var policyObserver: (any NSObjectProtocol)?
  /// 整条路由共用的一份内存缓存。
  ///
  /// 原来每次 `activate` 都 `MarketFeed(...)` 一个新的，而 `cache` 是有默认值的
  /// 参数——于是每换一次线路（币安 ↔ OKX、每一次自动重建 feed）内存缓存就被清零，
  /// 「本次会话里切回去不重拉」这件事在换线路之后完全失效。缓存本来就是按
  /// (品种, 周期) 建键的，跨线路共用没有混源问题：一次只有一条线路在写。
  private let cache = BarCache()
  private var source: MarketSource = .binance
  private var feed: MarketFeed?
  /// 当前这份 `feed` 是按哪家交易所建的。`source` 可能已经先一步改成新线路的交易所
  /// （见 `setRoutePolicy`），这里记的才是真正在跑的那家。
  private var activeSource: MarketSource?
  private var pump: Task<Void, Never>?
  private var monitor: Task<Void, Never>?
  private var selection = UUID()
  private var route = UUID()
  private var symbol = ""
  private var interval: Interval = .h1
  private var snapshots = true
  private var foreground = true
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

  public init(hosts: BinanceHosts, paths: Paths = .caches(), log: FeedLog = .silent) {
    self.hosts = hosts; self.paths = paths; self.log = log
    let policy = MarketRoutePolicyStore.current
    self.policy = policy
    self.source = policy.source
    self.sockets = URLSessionSocketFactory()
    primary = .upstream(.binance, hosts: hosts, log: log, policy: policy)
    backup = .upstream(.okx, hosts: hosts, log: log, policy: policy)
    observePolicy()
  }

  /// 测试注入：两条线路的 REST 与 socket 工厂全换成假件，整条路由就能离线跑。
  init(hosts: BinanceHosts, paths: Paths, log: FeedLog = .silent,
       primary: BinanceREST, backup: BinanceREST, sockets: any WSSocketFactory,
       policy: MarketRoutePolicy) {
    self.hosts = hosts; self.paths = paths; self.log = log
    self.policy = policy
    self.source = policy.source
    self.sockets = sockets
    self.primary = primary
    self.backup = backup
  }

  private nonisolated func observePolicy() {
    policyObserver = NotificationCenter.default.addObserver(
      forName: .marketRoutePolicyDidChange, object: nil, queue: nil) { [weak self] _ in
        let next = MarketRoutePolicyStore.current
        Task { await self?.setRoutePolicy(next) }
      }
  }

  deinit {
    if let policyObserver { NotificationCenter.default.removeObserver(policyObserver) }
  }

  /// 换线路：转给两条线路的 transport，并且立刻切到这条线路对应的交易所。
  ///
  /// 不等下一次换品种：REST 和已经连着的 WebSocket 一起换。不然 REST 已经改走
  /// 网关了，连着的直连 WS 还会一直挂到下次重连——「网关」就成了只管历史
  /// 不管实时的半个开关。
  public func setRoutePolicy(_ policy: MarketRoutePolicy) async {
    guard self.policy != policy else { return }
    self.policy = policy
    // 先把交易所定下来再去等 transport：这是个 actor，下面两个 await 期间 `start`
    // 可能抢先进来，它按 `source` 起步，得让它看到的已经是新线路的交易所。
    source = policy.source
    await primary.setRoutePolicy(policy)
    await backup.setRoutePolicy(policy)
    // 等的这两拍里线路又被改了，或者 `start` 已经按新交易所把 feed 起好了，都不用再起一遍。
    guard self.policy == policy, !symbol.isEmpty, activeSource != policy.source else { return }
    announceSwitch()
    await activate(policy.source)
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
    source = next
    activeSource = next
    let rest = next == .binance ? primary : backup
    var directHosts = hosts; directHosts.streamFallbacks = []
    let ws = BinanceWS(hosts: directHosts,
                       factory: SourceSocketFactory(source: next, hosts: hosts, factory: sockets, policy: policy),
                       silenceMs: 15_000, log: log)
    let sourcePaths = next == .binance ? paths : Paths(root: paths.root.appendingPathComponent("sources/okx"))
    // 首屏要多深，两条线路不一样：
    //
    // 直连币安：一次就要满深度（`deepenTarget` 会被夹到单请求上限 1500 根）。
    // `MarketFeed.fillOnce` 看见 `initialLimit > firstScreenLimit` 会另外并行发一发
    // 300 根的小页，谁先回谁先画——弱网上先看见图，满深度回来再铺开。原来这里写死
    // 300，那个条件永远不成立，两段式等于没开，而且满深度要等后台加深那一页（1.2 秒
    // 之后才发）才到手。请求数没变：以前是 300 + 加深一页，现在是 300 小页 + 1500 满页。
    //
    // OKX：网关只有「最新窗口且 limit ≤ 300」才是一次请求，再深就要在 VPS 上按 100 根
    // 翻十几页拼出来（见 Backend/kanpan-gateway/market_rest.py 的 klines 分支），首屏
    // 反而更慢、还平白给线上网关加活儿。所以 OKX 仍旧只要 300 根，深度交给后台加深。
    let initial = next == .binance ? MarketFeed.deepenTarget : MarketFeed.firstScreenLimit
    let created = MarketFeed(rest: rest, ws: ws, cache: cache,
      paths: sourcePaths,
      includeTicker: next == .binance, initialLimit: initial, log: log)
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
      freshHistory = true; settleRoute()
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
    settleRoute()
  }
  /// 新线路的历史和实时都到齐了：收掉「切换中」的提示。
  ///
  /// 不落盘。线路是用户在设置里定的（`Prefs.routePolicy`），开机按它起步就行，
  /// 没有「上次落在哪家交易所」这回事要记。
  private func settleRoute() {
    guard freshHistory, pendingStatus == .live, publishedRoute == route else { return }
    if announcingSwitch {
      announcingSwitch = false
      continuation?.yield(FeedUpdate(selection: selection, event: .routing(.switched)))
    }
  }
  private func healthy(_ candidate: MarketSource, symbol: String, interval: Interval,
                       requireStream: Bool = true) async -> Bool {
    let rest = candidate == .binance ? primary : backup
    let boundary = historyBoundary
    let streamFactory = SourceSocketFactory(source: candidate, hosts: hosts, factory: sockets, policy: policy)
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
        do { try await Task.sleep(for: .seconds(20)) } catch { return }
      }
    }
  }
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
  /// 定时巡检。线路是用户定的，这里**不换线**：
  /// 活着的 feed 什么都不用做；历史真的报错了就探一次当前线路——探通了就在**同一条线路**上
  /// 重拉一遍（首屏那一发可能只是撞上了网关的一次 busy），探不通照实说「点此重试」，
  /// 无论哪种都不会悄悄换成另一家交易所。OKX 的 24h 行情不在 WS 里，顺手补一份。
  private func checkSource(selection request: UUID) async {
    guard request == selection, foreground, !Task.isCancelled else { return }
    let sym = symbol, iv = interval, chosen = source
    if chosen == .okx { await refreshBackupTicker(symbol: sym, selection: request) }
    guard request == selection, foreground, !Task.isCancelled, pendingHistoryError != nil else { return }
    // 刚报错那 60 秒内不去探：feed 自己还在重试，探了也是重复打同一条线。
    let ready = Date() >= historyRetry ? await healthy(chosen, symbol: sym, interval: iv) : false
    guard request == selection, foreground, !Task.isCancelled, chosen == source else { return }
    if ready { await activate(chosen) } else { unavailable(request) }
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

  /// 预热的活儿本身：挨个拉回来，写盘**并且**塞进内存缓存。
  ///
  /// 原来只写盘。可点进一个预热过的品种时，`MarketFeed.switchTo` 先问的是内存缓存，
  /// 问不到才去读盘——等于每次都要走一趟「开文件 + 解码 + 改 mtime」。
  /// 一份 300 根只有 14KB，20 份合计不到 300KB，放内存里完全划得来。
  private func run(jobs: [(symbol: String, interval: Interval)], delayMs: Int) -> Task<Void, Never>? {
    guard !jobs.isEmpty else { return nil }
    let rest = source == .binance ? primary : backup
    let dir = (source == .binance ? paths : Paths(root: paths.root.appendingPathComponent("sources/okx"))).series
    let log = self.log
    let cache = self.cache
    return Task.detached(priority: .utility) {
      if delayMs > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        guard !Task.isCancelled else { return }
      }
      var done = 0
      var skipped = 0
      for job in jobs {
        guard !Task.isCancelled else { return }
        // 已经有一份够新的就跳过——落后不到几根的快照，点进去照样是秒开。
        if let have = SeriesStore.read(symbol: job.symbol, interval: job.interval, in: dir),
           have.count >= MarketFeed.firstScreenLimit / 2,
           Int64(Date().timeIntervalSince1970 * 1000) - have.lastTime < 3 * job.interval.stepMs { continue }
        do {
          let bars = try await rest.klines(symbol: job.symbol, interval: job.interval, limit: MarketFeed.firstScreenLimit)
          guard !bars.isEmpty else { continue }
          let series = BarSeries(symbol: job.symbol, interval: job.interval, bars: BinanceREST.dedup(bars))
          _ = try SeriesStore.write(series, in: dir)
          await cache.put(series)
          done += 1
        } catch {
          // 原来是「一个失败就整轮收工」。可自选里留着一个已下市的代号
          // （币安回 400 `Invalid symbol`）就会把后面十几个全带走——
          // 用户永远不知道，只觉得「有些品种点进去总是要转圈」。
          //
          // 现在分开看：这一个自己的问题（4xx，代号没了 / 参数不对）就跳过它接着干；
          // 只有线路层面的问题（超时、断网、429、5xx）才停——那种情况下
          // 后面几个确实也没戏，接着打只会把限流器顶得更死。
          if RoutedMarketFeed.skippable(error) {
            skipped += 1
            log("预热跳过 \(job.symbol) \(job.interval.rawValue)：\(error)")
            continue
          }
          log("预热停在 \(job.symbol) \(job.interval.rawValue)：\(error)")
          break
        }
      }
      log("预热 \(done)/\(jobs.count) 份快照\(skipped > 0 ? "，跳过 \(skipped) 个" : "")")
    }
  }

  /// 这个错误只是「这一个品种不行」，还是「整条线路不行」。
  ///
  /// 只有前者才跳过接着干。判据取严：**确知**是单品种问题（4xx，但不含 408 超时
  /// 和 418/429 限流）才算跳过，其余一律当线路问题停下——宁可少预热几份，
  /// 也不要在网络已经不行的时候接着打二十发。
  nonisolated static func skippable(_ error: any Error) -> Bool {
    guard let e = error as? BinanceError else { return false }
    guard (400..<500).contains(e.status) else { return false }
    return !e.isRateLimited && e.status != 408
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
    if online { startMonitoring() } else { monitor?.cancel() }
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
