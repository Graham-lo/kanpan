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
  /// 归档缓存；`OISource` 和这里共用一份，聚好的整段也存在它里面。
  private let oiStore = OIStore(paths: .caches())
  /// 已经到手的点，按时间排好；`oiRegion` 是它们覆盖的区间。两个合起来就是
  /// 「这张图上已经有什么」，平移和刷新都据此只补差的那一段，不整段重下。
  private var oiPoints: [OIPoint] = []
  private var oiRegion: (from: Int64, to: Int64)?
  /// 磁盘上那份「品种 + 周期」只认一次，认过就以内存里的为准。
  private var oiDiskKey: String?
  private var oiEnabled = false
  private var oiRequestedAt = Date.distantPast
  private var lastView: ViewWindow?
  private(set) var ticker: Ticker?
  private(set) var tradeQuote: TradeQuote?
  private(set) var info: SymbolInfo
  /// 这个品种的小数位与成交额单位，一旦定下来这一程就不再变（§2B / 审查 §3.10 #53）。
  ///
  /// 换线路会把整张品种表换掉，备用源对同一个品种给的 `pricePrecision` 未必一样；
  /// 成交额口径也可能差一截，数字一跨过一亿的坎单位就从「万」跳成「亿」。用户看到的
  /// 是「我什么都没动，价格突然多了一位、成交额换了个单位」——那比数字本身更像出错。
  /// 展示口径按品种钉死：换品种才重新认，换线路一律沿用。
  private var lockedPrecision: [String: (precision: Int, tick: Double)] = [:]
  private(set) var volumeUnit: VolUnit?
  /// 顶栏右侧四格里 FR 那一格：`markPrice@1s` 那条流顺带捎回来的资金费率整帧。
  private(set) var funding: MarkPriceTick?
  /// 持仓量（币本位数量 / 美元名义）与总供应量，都由 VPS 后端给，客户端不自己算。
  /// 取不到就是 `nil`，那一格显示 `--`。
  private(set) var openInterestQty: Double?
  private(set) var openInterestValue: Double?
  /// 持仓量的单位也按品种钉住，理由和 `volumeUnit` 一样：币安和 OKX 的持仓口径
  /// 差着一截，换线路时数字跨过进位坎，顶栏那一格看上去像换了个品种。
  private(set) var openInterestUnit: VolUnit?
  private(set) var totalSupply: Double?
  /// 顶栏「仓」那一格显示的数：美元名义优先，后端没给名义就退回币本位数量。
  var openInterestDisplay: Double? { openInterestValue ?? openInterestQty }
  /// 总市值在顶栏那一格里现乘（`totalSupply × 正在显示的那口价`），这儿只管存供应量：
  /// 用户明确要总市值，不是流通市值。
  /// 当前这份 `ticker` 是不是「上一条线路留下的」。真 = 顶栏灰显（§2B #54）。
  private(set) var tickerStale = false
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
  // `deinit` 不在主 actor 上，注销通知得能从那儿读到它。
  nonisolated(unsafe) private var policyObserver: (any NSObjectProtocol)?
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
    // 线路是用户定的（`Prefs.routePolicy` 镜像到 `MarketRoutePolicyStore`），
    // 交易所跟着线路走：直连=币安、网关=OKX。品种页也从同一家起步，不用等一次失败再换。
    let initialSource = MarketRoutePolicyStore.current.source
    self.source = initialSource
    let binanceRest = BinanceREST.upstream(.binance, hosts: hosts, log: MarketModel.log)
    let rest = BinanceREST.upstream(initialSource, hosts: hosts, log: MarketModel.log)
    self.oiSource = OISource(hosts: hosts, rest: binanceRest, store: oiStore)
    self.feed = RoutedMarketFeed(hosts: hosts, log: MarketModel.log)
    self.catalog = CatalogBox(SymbolCatalog(rest: rest, paths: Self.catalogPaths(for: initialSource)))
    // 换线路时 `RoutedMarketFeed` 自己会切；历史 OI 的客户端是这里建的，也得跟着换，
    // 不然设置改成「网关」之后 OI 还在直连币安。
    policyObserver = NotificationCenter.default.addObserver(
      forName: .marketRoutePolicyDidChange, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.routePolicyDidChange() }
      }
  }

  deinit {
    if let policyObserver { NotificationCenter.default.removeObserver(policyObserver) }
  }

  private func routePolicyDidChange() {
    oiSource = OISource(hosts: hosts, rest: .upstream(.binance, hosts: hosts, log: MarketModel.log),
                        store: oiStore)
    resetOI()
    if let lastView { loadOI(view: lastView, refresh: true) }
  }

  private static func catalogPaths(for source: MarketSource) -> Paths {
    source == .binance ? .caches() : Paths(root: Paths.caches().root.appendingPathComponent("sources/" + source.rawValue))
  }

  /// 排查「图有数据但一动不动」的时候需要看得见连了没有、推没推进来。
  /// 默认静音；`KANPAN_LOG=1` 打开（Xcode Scheme 的环境变量，或 `simctl launch` 的
  /// `SIMCTL_CHILD_KANPAN_LOG=1`）。
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
  private var statsTask: Task<Void, Never>?

  func start(snapshot: Bool, interval requestedInterval: Interval? = nil) {
    if let requestedInterval { interval = requestedInterval }
    self.snapshot = snapshot
    // 第一帧就把盘上的快照摆出来。`feed` 是 actor，它那份快照要等一次跨执行器的
    // 跳转才回得来——冷启动时那一跳就是半秒的空图。这里同步读一次（几十 KB 的
    // 连续内存，读完直接是可画的值），图和价格一起出现。
    if snapshot, series == nil,
       let saved = SeriesStore.read(symbol: symbol, interval: interval,
                                    in: Self.catalogPaths(for: source).series, touch: false) {
      series = saved
    }
    // 顺手让快照目录的索引在后台扫一遍：之后换品种、淘汰旧文件都不用再碰 `contentsOfDirectory`。
    // 扫过一次就记住了，重复调用是空操作。
    if snapshot { SeriesStore.warm(Self.catalogPaths(for: source).series) }
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
    startStats()
  }

  func stop() {
    selection = UUID()
    switchTask?.cancel(); switchTask = nil
    network.stop()
    oiTask?.cancel(); oiTask = nil
    statsTask?.cancel(); statsTask = nil
    pump?.cancel()
    pump = nil
    Task { [feed] in await feed.stop() }
  }

  func enterBackground() {
    foreground = false
    statsTask?.cancel(); statsTask = nil     // 后台不轮询持仓量
    Task { [feed] in await feed.enterBackground() }
  }

  func enterForeground() {
    foreground = true
    if pump != nil { startStats() }
    Task { [feed] in await feed.enterForeground() }
  }
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
    oiSource = OISource(hosts: next, rest: binanceRest, store: oiStore)
    resetOI()
    feed = RoutedMarketFeed(hosts: next, log: MarketModel.log)
    let box = catalog
    Task { await box.replace(SymbolCatalog(rest: rest, paths: Self.catalogPaths(for: source))) }
    status = .offline
    lastPushAt = nil
    guard running else { return }
    switching = true
    start(snapshot: snapshot)
  }

  // ---------------------------------------------------------------- 事件

  private var applied = 0
  private var appliedDropped = 0
  private var applyReport = Date()

  private func apply(_ update: FeedUpdate) {
    // 「帧到了但图不动」最常见的哑法是事件在这一关被 `selection` 判出局：WS 那边
    // 收帧计数照样涨，界面却一帧不更新。所以收多少、丢多少都要报出来。
    if update.selection == selection { applied += 1 } else { appliedDropped += 1 }
    let now = Date()
    if now.timeIntervalSince(applyReport) >= 5 {
      Self.log("图表事件 收\(applied) 丢\(appliedDropped)/\(Int(now.timeIntervalSince(applyReport) * 1000))ms")
      applied = 0; appliedDropped = 0; applyReport = now
    }
    guard update.selection == selection else { return }
    switch update.event {
    case .routing(let state):
      routing = state
      if state == .switching { historyError = nil }
    case .source(let next):
      // 这儿**不**清 `ticker`：清掉顶栏立刻退回「—」，用户看到的是一屏骨架，
      // 而他什么都没做，只是我们换了台机器取数。备用线路本来就未必有这个品种，
      // 那样会一直空着。留着上一条线路的最后一口价，灰显标明「这是旧的」（§2B #54），
      // 新线路第一帧到了就自己转正。
      source = next; tickerStale = ticker != nil; tradeQuote = nil; markPrice = nil; markTime = 0
      funding = nil
      // 持仓量是按交易所报的，换了线路就得按新交易所重取；供应量与交易所无关，留着。
      openInterestQty = nil; openInterestValue = nil; openInterestUnit = nil
      startStats()
      resetOI(); historyError = nil
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
      guard tickerStale || LatestQuote.accepts(t, after: ticker) else { return }
      var next = t; next.markPrice = markPrice
      ticker = next
      tickerStale = false
      if volumeUnit == nil, next.quoteVolume.isFinite { volumeUnit = volUnit(next.quoteVolume) }
      lastPushAt = Date()
    case .markPrice(let sym, let price, let tick):
      guard sym.uppercased() == symbol, tick.timeMs >= markTime else { return }
      markTime = tick.timeMs
      // 费率那一格只认有值的帧：镜像偶尔发不带 `r` 的帧，别把已经显示的费率抹成 `--`。
      if tick.fundingRate != nil || funding == nil { funding = tick }
      guard price.isFinite, price > 0 else { return }
      markPrice = price
      ticker?.markPrice = price
    case .oi:
      break                                   // 副图 OI 由指标层自己取
    case .status(let s):
      status = s
    }
  }

  // ---------------------------------------------------------------- 顶栏右侧四格

  /// 持仓量轮询间隔。OI 本来就是分钟级统计，再密只是白跑请求。
  private static let oiPollSeconds: UInt64 = 45

  /// 供应量取一次（客户端缓存一天），持仓量按 `oiPollSeconds` 续着取。
  /// 两条都失败就让那两格一直是 `--`，不报错、不弹窗。
  private func startStats() {
    statsTask?.cancel()
    let sym = symbol, src = source, base = info.base, proxies = hosts.oiProxies
    guard !proxies.isEmpty else {
      openInterestQty = nil; openInterestValue = nil; openInterestUnit = nil; totalSupply = nil
      return
    }
    statsTask = Task { [weak self] in
      // 供应量和持仓量是两条互不相干的接口，谁先回来先填谁那一格。以前是先等供应量
      // （取不到就得等它超时），顶栏的「仓」跟着白等一次往返。
      Task { [weak self] in
        guard let meta = await MarketStatsClient.shared.meta(symbol: sym, base: base, hosts: proxies) else { return }
        await MainActor.run { self?.applyMeta(meta, for: sym) }
      }
      while !Task.isCancelled {
        let stat = await MarketStatsClient.shared.openInterest(symbol: sym, source: src, hosts: proxies)
        if Task.isCancelled { return }
        await MainActor.run { self?.applyOpenInterest(stat, for: sym) }
        try? await Task.sleep(for: .seconds(Double(Self.oiPollSeconds)))
      }
    }
  }

  private func applyMeta(_ meta: SymbolMeta, for sym: String) {
    guard sym == symbol else { return }
    totalSupply = meta.totalSupply.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
  }

  private func applyOpenInterest(_ stat: OpenInterestStat?, for sym: String) {
    guard sym == symbol else { return }
    // 取不到就保持上一口值：一次超时把已经在屏上的数字抹成 `--` 反而更像出错。
    guard let stat else { return }
    if let qty = stat.openInterest, qty.isFinite { openInterestQty = qty }
    if let value = stat.openInterestValue, value.isFinite { openInterestValue = value }
    if openInterestUnit == nil, let shown = openInterestDisplay, shown.isFinite {
      openInterestUnit = volUnit(shown)
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
    // 切换不留空白帧：盘上有新品种这个周期的快照就同步摆出来（和 `start` 一样，
    // 几十 KB 连续内存，读完即可画），feed 那份随后到了再覆盖。老图不能留——
    // 那是上一个品种的 K 线，顶着新品种的名字多一帧都是错的；没有快照才留空。
    series = snapshot
      ? SeriesStore.read(symbol: sym, interval: iv, in: Self.catalogPaths(for: source).series, touch: false)
      : nil
    loading = false
    resetOI(); lastView = nil
    if cold {
      ticker = nil
      tickerStale = false
      volumeUnit = nil                      // 单位按品种记，换品种就重新认
      markPrice = nil; markTime = 0
      funding = nil
      openInterestQty = nil; openInterestValue = nil; openInterestUnit = nil; totalSupply = nil
      // 这个品种以前认过小数位就照旧顶上，别让冷切换先用 2 位画一帧再跳回去。
      var seed = MarketModel.placeholder(sym)
      if let locked = lockedPrecision[sym] { seed.pricePrecision = locked.precision; seed.tickSize = locked.tick }
      info = seed
    }
    if cold { startStats() }
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
    let want = (from: max(series.firstTime, from - margin), to: to + series.step)
    let step = series.step
    oiTask = Task {
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      guard request == self.selection, self.symbol == sym, self.interval == iv else { return }
      // 上次留在磁盘上的那一段先上屏，用户不用对着「持仓量加载中」等一个往返。
      await self.seedOI(symbol: sym, interval: iv)
      guard !Task.isCancelled, request == self.selection, self.symbol == sym, self.interval == iv else { return }
      let segments = OISource.missingSegments(have: self.oiRegion, want: want, step: step, refresh: refresh)
      guard !segments.isEmpty else { return }
      let points = await withTaskGroup(of: [OIPoint].self) { group in
        for segment in segments {
          group.addTask { await source.rawPoints(symbol: sym, interval: iv, from: segment.from, to: segment.to) }
        }
        var all: [OIPoint] = []
        for await part in group { all += part }
        return all
      }
      guard !Task.isCancelled, request == self.selection, self.symbol == sym, self.interval == iv else { return }
      self.mergeOI(points, want: want, symbol: sym, interval: iv)
    }
  }

  /// 磁盘上那份「品种 + 周期」只认一次：认过之后内存里的才是最新的。
  private func seedOI(symbol sym: String, interval iv: Interval) async {
    let key = sym + "|" + iv.rawValue
    guard oiDiskKey != key else { return }
    oiDiskKey = key
    guard oiRegion == nil, let cached = await oiStore.loadSeries(symbol: sym, interval: iv),
          !cached.points.isEmpty, sym == symbol, iv == interval, oiRegion == nil else { return }
    oiPoints = cached.points
    oiRegion = (cached.from, cached.to)
    oi = OISource.chartSeries(cached.points, interval: iv)
  }

  private func mergeOI(_ points: [OIPoint], want: (from: Int64, to: Int64),
                       symbol sym: String, interval iv: Interval) {
    let previous = oiRegion
    let joins = previous.map { want.from <= $0.to && want.to >= $0.from } ?? false
    let merged = OISource.dedup(joins ? oiPoints + points : points)   // 同一时刻留新到的
    guard !merged.isEmpty else { return }
    var region = want
    if joins, let old = previous { region = (from: min(old.from, want.from), to: max(old.to, want.to)) }
    oiPoints = merged
    oiRegion = region
    oi = OISource.chartSeries(merged, interval: iv)
    let store = oiStore
    Task { await store.saveSeries(symbol: sym, interval: iv, points: merged, from: region.from, to: region.to) }
  }

  /// 换品种、换周期、换线路都得从头来：手里的点要么周期对不上，要么是另一家交易所报的。
  private func resetOI() {
    oiTask?.cancel(); oiTask = nil
    oi = nil; oiPoints = []; oiRegion = nil; oiDiskKey = nil
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
    guard want == symbol else { return }
    // 小数位只认第一次：见 `lockedPrecision`。
    if let locked = lockedPrecision[want] {
      var value = found
      value.pricePrecision = locked.precision
      value.tickSize = locked.tick
      info = value
    } else {
      lockedPrecision[want] = (found.pricePrecision, found.tickSize)
      info = found
    }
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
