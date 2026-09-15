import Foundation
import KanpanCore
import KanpanData
import Observation

/// 主界面的数据源：握着 `MarketFeed`，把它吐的事件收成一份可画的快照。
///
/// 为什么中间要有这一层——`MarketFeed` 是 actor，事件在它自己的执行器上来；
/// SwiftUI 要的是 `@MainActor` 上的值。这层就是那道闸，顺便把只有界面在意的规则
/// （切换隔离、异步结果范围校验）收在一处。
@MainActor
@Observable
final class MarketModel {
  private(set) var series: BarSeries?
  private(set) var oi: OISeries?
  private var oiTask: Task<Void, Never>?
  private var oiSource: OISource
  private var oiRegion: (from: Int64, to: Int64)?
  private var oiEnabled = false
  private var oiRequestedAt = Date.distantPast
  private var lastView: ViewWindow?
  private(set) var ticker: Ticker?
  private(set) var tradeQuote: TradeQuote?
  private(set) var info: SymbolInfo
  private(set) var status: FeedStatus = .offline
  private(set) var source: MarketSource
  private(set) var historyError: String?
  private(set) var routing: MarketRoutingState = .idle
  /// 最近一次 WS 推进来的时刻。顶栏圆点长按时报「多久没动了」——
  /// 「连上了但一帧不推」这种情况光看 `status` 是看不出来的（那时它还是 `.live`）。
  private(set) var lastPushAt: Date?
  /// 换品种/周期尚未取得新序列。旧蜡烛清空，宿主单独保留视野参数。
  private(set) var switching = false

  private(set) var symbol: String
  private(set) var interval: Interval

  private var feed: RoutedMarketFeed
  /// 品种表。域名可以改（A6.10），而品种页握着的是一条早就交出去的 `@Sendable`
  /// 闭包——中间夹这个盒子，换域名时换掉里面那份，闭包不用重发。
  nonisolated private let catalog: CatalogBox
  private var hosts: BinanceHosts
  /// 启动快照开关的当前值。换域名要把整条流重建一遍，得记着用哪个值重启。
  private var snapshot = true
  private var pump: Task<Void, Never>?
  private let network = MarketNetworkMonitor()
  private var foreground = true
  /// 补历史一次只放一发在路上，别一路拖着就连喊十几次。
  private var loading = false

  init(symbol: String = "BTCUSDT", interval: Interval = .h1,
       hosts: BinanceHosts = .default) {
    self.symbol = symbol
    self.interval = interval
    self.hosts = hosts
    self.info = MarketModel.placeholder(symbol)
    let initialSource = Self.preferredSource()
    self.source = initialSource
    let binanceRest = BinanceREST.upstream(.binance, hosts: hosts, log: MarketModel.log)
    let rest = BinanceREST.upstream(initialSource, hosts: hosts, log: MarketModel.log)
    self.oiSource = OISource(hosts: hosts, rest: binanceRest, store: OIStore(paths: .caches()))
    self.feed = RoutedMarketFeed(hosts: hosts, preferenceURL: Self.sourcePreferenceURL, log: MarketModel.log)
    self.catalog = CatalogBox(SymbolCatalog(rest: rest, paths: Self.catalogPaths(for: initialSource)))
  }

  /// 排查「图有数据但一动不动」的时候需要看得见连了没有、推没推进来。
  /// 默认静音；`KANPAN_LOG=1` 打开（Xcode Scheme 的环境变量，或 `simctl launch` 的
  /// `SIMCTL_CHILD_KANPAN_LOG=1`）。
  private static var sourcePreferenceURL: URL {
    var root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("kanpan-market")
    #if DEBUG
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1" {
      root = root.appendingPathComponent("tests/" + (ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"] ?? "normal"))
    }
    #endif
    return root.appendingPathComponent("source.json")
  }

  /// `RoutedMarketFeed` reads the same preference before it starts probing. The
  /// favorites page must use that source immediately too; otherwise it briefly
  /// creates a Binance catalog and waits for a failed request before switching.
  private static func preferredSource() -> MarketSource {
    guard let data = try? Data(contentsOf: sourcePreferenceURL),
          let value = try? JSONDecoder().decode(MarketSource.self, from: data) else { return .binance }
    return value
  }

  private static func catalogPaths(for source: MarketSource) -> Paths {
    source == .binance ? .caches() : Paths(root: Paths.caches().root.appendingPathComponent("sources/" + source.rawValue))
  }

  private static let log: FeedLog =
    ProcessInfo.processInfo.environment["KANPAN_LOG"] == "1" ? FeedLog { line in
      print(line)
      #if DEBUG
      Task { @MainActor in MarketNetworkDiagnostics.shared.lines = String((MarketNetworkDiagnostics.shared.lines + "\n" + line).suffix(8000)) }
      #endif
    } : .silent

  /// `exchangeInfo` 回来之前先顶上。冷启动第一帧不该等网络。
  private static func placeholder(_ symbol: String) -> SymbolInfo {
    let quote = ["USDT", "USDC", "BUSD"].first { symbol.hasSuffix($0) } ?? "USDT"
    return SymbolInfo(
      symbol: symbol, base: String(symbol.dropLast(quote.count)), quote: quote,
      pricePrecision: 2, tickSize: 0.01)
  }

  // ---------------------------------------------------------------- 生命周期

  private var selection = UUID()
  private var switchTask: Task<Void, Never>?
  private var markTime: Int64 = 0
  private var markPrice: Double?

  func start(snapshot: Bool, interval requestedInterval: Interval? = nil) {
    if let requestedInterval { interval = requestedInterval }
    self.snapshot = snapshot
    guard pump == nil else { return }
    network.start { [weak self] online in
      Task { @MainActor [weak self] in
        guard let self, self.pump != nil, self.foreground else { return }
        await self.feed.networkChanged(online: online)
      }
    }
    let sym = symbol, iv = interval, request = selection
    pump = Task { [feed] in
      let stream = await feed.events()
      await feed.setSnapshotEnabled(snapshot)
      await feed.start(symbol: sym, interval: iv, selection: request)
      for await e in stream {
        if Task.isCancelled { break }
        await MainActor.run { self.apply(e) }
      }
    }
    Task { await refreshInfo() }
  }

  func stop() {
    selection = UUID()
    switchTask?.cancel(); switchTask = nil
    network.stop()
    oiTask?.cancel(); oiTask = nil
    pump?.cancel()
    pump = nil
    Task { [feed] in await feed.stop() }
  }

  func enterBackground() { foreground = false; Task { [feed] in await feed.enterBackground() } }
  func enterForeground() { foreground = true; Task { [feed] in await feed.enterForeground() } }
  func memoryWarning() { Task { [feed] in await feed.memoryWarning() } }
  func setSnapshotEnabled(_ on: Bool) {
    snapshot = on
    Task { [feed] in await feed.setSnapshotEnabled(on) }
  }

  /// 换域名（A6.10）。REST 和推送是两台，改哪一边都得把整条流重建——
  /// `BinanceREST` / `BinanceWS` 的域名是 `let`，本来就不打算中途改。
  func setHosts(_ next: BinanceHosts) {
    guard next != hosts else { return }
    hosts = next
    let running = pump != nil
    stop()
    let source = source
    let binanceRest = BinanceREST.upstream(.binance, hosts: next, log: MarketModel.log)
    let rest = BinanceREST.upstream(source, hosts: next, log: MarketModel.log)
    oiSource = OISource(hosts: next, rest: binanceRest, store: OIStore(paths: .caches()))
    oi = nil; oiRegion = nil
    feed = RoutedMarketFeed(hosts: next, preferenceURL: Self.sourcePreferenceURL, log: MarketModel.log)
    let box = catalog
    Task { await box.replace(SymbolCatalog(rest: rest, paths: Self.catalogPaths(for: source))) }
    status = .offline
    lastPushAt = nil
    guard running else { return }
    switching = true
    start(snapshot: snapshot)
  }

  // ---------------------------------------------------------------- 事件

  private func apply(_ update: FeedUpdate) {
    guard update.selection == selection else { return }
    switch update.event {
    case .routing(let state):
      routing = state
      if state == .switching { historyError = nil }
    case .source(let next):
      source = next; ticker = nil; tradeQuote = nil; markPrice = nil; markTime = 0
      oiTask?.cancel(); oi = nil; oiRegion = nil; historyError = nil
      let paths = Paths(root: Paths.caches().root.appendingPathComponent("sources/" + next.rawValue))
      let catalog = SymbolCatalog(rest: .upstream(next, hosts: hosts), paths: paths)
      Task { await self.catalog.replace(catalog); await self.refreshInfo() }
    case .historyError(let error):
      historyError = error
    case .series(let s):
      guard s.symbol == symbol, s.interval == interval else { return }
      series = s
      switching = false
    case .lastBar(let b):
      guard series?.symbol == symbol, series?.interval == interval else { return }
      _ = series?.upsert(b)
      lastPushAt = Date()
    case .prepend:
      // `.prepend` 不带新序列，得自己去取。视野是绝对时间窗，补在左边天然不跳。
      let request = selection, expectedSource = source
      Task { [feed] in
        let s = await feed.currentSeries
        await MainActor.run {
          if request == self.selection, expectedSource == self.source, s.symbol == self.symbol, s.interval == self.interval { self.series = s }
        }
      }
    case .tradeQuote(let quote):
      guard quote.symbol == symbol else { return }
      tradeQuote = quote
    case .ticker(let t):
      guard t.symbol.uppercased() == symbol.uppercased() else { return }
      guard LatestQuote.accepts(t, after: ticker) else { return }
      var next = t; next.markPrice = markPrice
      ticker = next
      lastPushAt = Date()
    case .markPrice(let sym, let price, let time):
      guard sym.uppercased() == symbol, price.isFinite, price > 0,
            time > markTime else { return }
      markTime = time; markPrice = price
      ticker?.markPrice = price
    case .oi:
      break                                   // 副图 OI 由指标层自己取
    case .status(let s):
      status = s
    }
  }

  // ---------------------------------------------------------------- 切换

  func switchTo(symbol newSymbol: String? = nil, interval newInterval: Interval? = nil) {
    let sym = (newSymbol ?? symbol).uppercased()
    let iv = newInterval ?? interval
    guard sym != symbol || iv != interval else { return }
    let cold = sym != symbol
    selection = UUID()
    let request = selection
    switchTask?.cancel()
    symbol = sym
    interval = iv
    switching = true
    series = nil
    loading = false
    oiTask?.cancel(); oi = nil; oiRegion = nil; lastView = nil
    if cold {
      ticker = nil
      markPrice = nil; markTime = 0
      info = MarketModel.placeholder(sym)
    }
    switchTask = Task { [feed] in
      guard !Task.isCancelled else { return }
      await feed.switchTo(symbol: sym, interval: iv, coldStart: cold, selection: request)
      if cold { await refreshInfo() }
    }
  }

  /// 预热：把自选列表里的品种（当前周期）和当前品种的其他常用周期先拉回来落到快照里，
  /// 点进去、切周期就不用等网络（见 `RoutedMarketFeed.prefetch`）。
  func prefetchFavorites(_ symbols: [String], intervals: [Interval] = []) {
    guard !symbols.isEmpty || !intervals.isEmpty else { return }
    let iv = interval
    Task { [feed] in await feed.prefetch(symbols: symbols, interval: iv, intervals: intervals) }
  }

  /// 视野推到头部 200 根以内时叫（G9）。
  func loadMore() {
    guard !loading, series != nil else { return }
    loading = true
    let request = selection
    Task { [feed] in
      await feed.loadMore()
      await MainActor.run { if request == self.selection { self.loading = false } }
    }
  }

  /// Retry the initial history request (or a failed gap request). `loadMore`
  /// intentionally requires an existing series, so it cannot serve the
  /// cold-start error state where the retry button is shown.
  func retryHistory() {
    guard !loading else { return }
    selection = UUID()
    let request = selection
    switchTask?.cancel()
    loading = false
    historyError = nil
    switching = true
    switchTask = Task { [feed] in
      await feed.retry(selection: request)
    }
  }

  func setOIEnabled(_ enabled: Bool) {
    oiEnabled = enabled
    if !enabled { oiTask?.cancel(); oiTask = nil; return }
    if let view = lastView { loadOI(view: view) }
  }

  /// 历史OI是统计采样，不伪造成逐笔WS；前台每分钟更新可见尾桶。
  func refreshOIIfNeeded() {
    guard foreground, oiEnabled, Date().timeIntervalSince(oiRequestedAt) >= 60,
          let view = lastView, let series, view.to >= Double(series.lastTime) else { return }
    loadOI(view: view, refresh: true)
  }

  func loadOI(view: ViewWindow, refresh: Bool = false) {
    lastView = view
    guard source == .binance else { return }
    guard oiEnabled, let series, !series.isEmpty else { return }
    let from = max(series.firstTime, Int64(view.from) - series.step)
    let to = min(series.lastTime + series.step, Int64(view.to))
    guard to >= from else { return }
    if !refresh, let region = oiRegion, from >= region.from, to <= region.to { return }
    oiTask?.cancel()
    oiRequestedAt = Date()
    let sym = symbol, iv = interval, source = oiSource, request = selection
    let margin = max(series.step * 20, (to - from) / 2)
    let fetchFrom = max(series.firstTime, from - margin), fetchTo = to + series.step
    oiTask = Task {
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      let points = await source.rawPoints(symbol: sym, interval: iv, from: fetchFrom, to: fetchTo)
      guard !Task.isCancelled, request == self.selection, self.symbol == sym, self.interval == iv else { return }
      let ordered = OISource.dedup(points)
      if !ordered.isEmpty {
        self.oi = OISource.chartSeries(ordered, interval: iv)
        self.oiRegion = (fetchFrom, fetchTo)
      }
    }
  }

  /// 品种页要的品种表。`@Sendable` 是因为品种页把它当闭包存着，
  /// 跨隔离域传——所以捞的是 actor（`SymbolCatalog`），不是 `self`。
  nonisolated var catalogLoader: @Sendable () async -> [SymbolInfo] {
    let c = catalog
    return { await c.all() }
  }

  private func refreshInfo() async {
    let want = symbol
    guard let found = await catalog.find(want) else { return }
    if want == symbol { info = found }
  }
}


/// 换域名时要把 `SymbolCatalog` 整个换掉，但品种页握着的是早就交出去的闭包。
/// 夹这一层，闭包握盒子、盒子握当前那份。
actor CatalogBox {
  private var catalog: SymbolCatalog
  init(_ catalog: SymbolCatalog) { self.catalog = catalog }
  func replace(_ next: SymbolCatalog) { catalog = next }
  func all() async -> [SymbolInfo] { await catalog.all() }
  func find(_ symbol: String) async -> SymbolInfo? { await catalog.find(symbol) }
}

#if DEBUG
@MainActor @Observable final class MarketNetworkDiagnostics {
  static let shared = MarketNetworkDiagnostics()
  var lines = ""
}
#endif
