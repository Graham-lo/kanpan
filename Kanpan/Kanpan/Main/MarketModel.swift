import Foundation
import KanpanCore
import KanpanData
import Observation

/// 主界面的数据源：握着 `MarketFeed`，把它吐的事件收成一份可画的快照。
///
/// 为什么中间要有这一层——`MarketFeed` 是 actor，事件在它自己的执行器上来；
/// SwiftUI 要的是 `@MainActor` 上的值。这层就是那道闸，顺便把只有界面在意的规则
/// （换周期时旧图先留着别闪白）收在一处。
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
  private(set) var info: SymbolInfo
  private(set) var status: FeedStatus = .offline
  /// 最近一次 WS 推进来的时刻。顶栏圆点长按时报「多久没动了」——
  /// 「连上了但一帧不推」这种情况光看 `status` 是看不出来的（那时它还是 `.live`）。
  private(set) var lastPushAt: Date?
  /// 换品种/周期还没拿到新数据的这段空档。图上用它压暗旧图（§10.4）。
  private(set) var switching = false

  private(set) var symbol: String
  private(set) var interval: Interval

  private var feed: MarketFeed
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
    let rest = BinanceREST(hosts: hosts, log: MarketModel.log)
    self.oiSource = OISource(hosts: hosts, rest: rest, store: OIStore(paths: .caches()))
    self.feed = MarketFeed(rest: rest, ws: BinanceWS(hosts: hosts, log: MarketModel.log),
                           log: MarketModel.log)
    self.catalog = CatalogBox(SymbolCatalog(rest: rest))
  }

  /// 排查「图有数据但一动不动」的时候需要看得见连了没有、推没推进来。
  /// 默认静音；`KANPAN_LOG=1` 打开（Xcode Scheme 的环境变量，或 `simctl launch` 的
  /// `SIMCTL_CHILD_KANPAN_LOG=1`）。
  private static let log: FeedLog =
    ProcessInfo.processInfo.environment["KANPAN_LOG"] == "1" ? .stdout : .silent

  /// `exchangeInfo` 回来之前先顶上。冷启动第一帧不该等网络。
  private static func placeholder(_ symbol: String) -> SymbolInfo {
    let quote = ["USDT", "USDC", "BUSD"].first { symbol.hasSuffix($0) } ?? "USDT"
    return SymbolInfo(
      symbol: symbol, base: String(symbol.dropLast(quote.count)), quote: quote,
      pricePrecision: 2, tickSize: 0.01)
  }

  // ---------------------------------------------------------------- 生命周期

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
    let sym = symbol, iv = interval
    pump = Task { [feed] in
      let stream = await feed.events()
      await feed.setSnapshotEnabled(snapshot)
      await feed.start(symbol: sym, interval: iv)
      for await e in stream {
        if Task.isCancelled { break }
        await MainActor.run { self.apply(e) }
      }
    }
    Task { await refreshInfo() }
  }

  func stop() {
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
    let rest = BinanceREST(hosts: next, log: MarketModel.log)
    oiSource = OISource(hosts: next, rest: rest, store: OIStore(paths: .caches()))
    oi = nil; oiRegion = nil
    feed = MarketFeed(rest: rest, ws: BinanceWS(hosts: next, log: MarketModel.log),
                      log: MarketModel.log)
    let box = catalog
    Task { await box.replace(SymbolCatalog(rest: rest)) }
    status = .offline
    lastPushAt = nil
    guard running else { return }
    switching = true
    start(snapshot: snapshot)
  }

  // ---------------------------------------------------------------- 事件

  private func apply(_ e: FeedEvent) {
    switch e {
    case .series(let s):
      guard s.symbol == symbol, s.interval == interval else { return }
      series = s
      switching = false
    case .lastBar(let b):
      _ = series?.upsert(b)
      lastPushAt = Date()
    case .prepend:
      // `.prepend` 不带新序列，得自己去取。视野是绝对时间窗，补在左边天然不跳。
      Task { [feed] in
        let s = await feed.currentSeries
        await MainActor.run {
          if s.symbol == self.symbol, s.interval == self.interval { self.series = s }
        }
      }
    case .ticker(let t):
      guard t.symbol.uppercased() == symbol.uppercased() else { return }
      ticker = t
      lastPushAt = Date()
    case .price(let last, let mark):
      // 逐笔和标记价只知道「现在多少钱」，不许整份替换——涨跌幅和 24h 高低是
      // REST 那一路给的，被 NaN 盖掉顶栏就空了一大片。
      guard var t = ticker else {
        // 冷启动头几百毫秒还没拿到 24h 行情：先把价格立起来，其余留空等对表补。
        if let last {
          ticker = Ticker(symbol: symbol, last: last, changePercent: .nan,
                          high: .nan, low: .nan, quoteVolume: .nan, markPrice: mark)
          lastPushAt = Date()
        }
        return
      }
      if let last { t.last = last }
      if let mark { t.markPrice = mark }
      ticker = t
      lastPushAt = Date()
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
    symbol = sym
    interval = iv
    switching = true
    oiTask?.cancel(); oi = nil; oiRegion = nil; lastView = nil
    if cold {
      ticker = nil
      info = MarketModel.placeholder(sym)
    }
    Task { [feed] in
      await feed.switchTo(symbol: sym, interval: iv, coldStart: cold)
      if cold { await refreshInfo() }
    }
  }

  /// 视野推到头部 200 根以内时叫（G9）。
  func loadMore() {
    guard !loading, series != nil else { return }
    loading = true
    Task { [feed] in
      await feed.loadMore()
      await MainActor.run { self.loading = false }
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
    guard oiEnabled, let series, !series.isEmpty else { return }
    let from = max(series.firstTime, Int64(view.from) - series.step)
    let to = min(series.lastTime + series.step, Int64(view.to))
    guard to >= from else { return }
    if !refresh, let region = oiRegion, from >= region.from, to <= region.to { return }
    oiTask?.cancel()
    oiRequestedAt = Date()
    let sym = symbol, iv = interval, source = oiSource
    let margin = max(series.step * 20, (to - from) / 2)
    let fetchFrom = max(series.firstTime, from - margin), fetchTo = to + series.step
    oiTask = Task {
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      let points = await source.rawPoints(symbol: sym, interval: iv, from: fetchFrom, to: fetchTo)
      guard !Task.isCancelled, self.symbol == sym, self.interval == iv else { return }
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
