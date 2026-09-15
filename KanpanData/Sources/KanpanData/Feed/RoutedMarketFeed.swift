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
      for name in ["binance", "okx"] { Snapshot.remove(Paths(root: paths.root.appendingPathComponent("sources/" + name)).snapshot) }
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
    await feed?.stop(); feed = nil; continuation?.finish(); continuation = nil
  }
}
