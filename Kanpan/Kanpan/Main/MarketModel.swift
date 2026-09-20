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
  /// 这一程已经去补过的洞（按洞的左端记）。币安确实没有那一根时补也补不回来，
  /// 记一笔就不会每次平移、每次开图都为它重发同一个请求。换品种 / 换周期时清空。
  private var oiPatched: Set<Int64> = []
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
  /// 持仓量（**美元名义**）与总供应量，都由 VPS 后端给，客户端不自己算。
  /// 取不到就是 `nil`，那一格显示 `--`。
  ///
  /// 审查 A-02：币本位数量（后端照发的 `openInterest`）这儿**不存也不显示**。
  /// 名义拿不到时退回数量，等于同一格一会儿是「多少钱」一会儿是「多少个币」，
  /// 而界面上没有任何记号能区分——宁可空着。
  private(set) var openInterestValue: Double?
  /// 持仓量的单位也按品种钉住，理由和 `volumeUnit` 一样：币安和 OKX 的持仓口径
  /// 差着一截，换线路时数字跨过进位坎，顶栏那一格看上去像换了个品种。
  /// 单位和值同生同死：值被清掉时单位也要清，否则下一个品种会沿用上一个的坎。
  private(set) var openInterestUnit: VolUnit?
  private(set) var totalSupply: Double?
  /// 顶栏「仓」那一格显示的数。就是美元名义，没有第二个来源。
  var openInterestDisplay: Double? { openInterestValue }
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

  // `deinit` 要把这条流停掉，所以和 `policyObserver` 一样不进主 actor 的隔离存储，
  // 也不进 `@Observable` 的跟踪存储（它是条 actor 引用，界面从不读它）。
  // 写只发生在主 actor；`deinit` 读到它的时候已经没有第二个引用了。
  @ObservationIgnored nonisolated(unsafe) private var feed: RoutedMarketFeed
  // `deinit` 不在主 actor 上，注销通知得能从那儿读到它。它不是界面状态，别让
  // `@Observable` 把它包进跟踪存储——包进去之后 `nonisolated(unsafe)` 落在合成的
  // 后备变量上，写在这儿的那个就成了空话，编译器会照实报「没有效果」。
  @ObservationIgnored nonisolated(unsafe) private var policyObserver: (any NSObjectProtocol)?
  /// 品种表。域名可以改（A6.10），而品种页握着的是一条早就交出去的 `@Sendable`
  /// 闭包——中间夹这个盒子，换域名时换掉里面那份，闭包不用重发。
  nonisolated private let catalog: CatalogBox
  private var hosts: BinanceHosts
  /// 启动快照开关的当前值。换域名要把整条流重建一遍，得记着用哪个值重启。
  private var snapshot = true
  // 同上：`deinit` 要 cancel 它。
  @ObservationIgnored nonisolated(unsafe) private var pump: Task<Void, Never>?
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
    // 宿主销毁时的停机契约。能跑到这儿，就说明再没有人要这份数据了——
    // 那条事件流和它身后的 `RoutedMarketFeed`（socket、重连、后台宽限）必须一起收。
    // 光靠 `pump` 弱持有只是让模型**能**被释放；真正把流关掉的是这两行。
    pump?.cancel()
    Task { [feed] in await feed.stop() }
  }

  private func routePolicyDidChange() {
    oiSource = OISource(hosts: hosts, rest: .upstream(.binance, hosts: hosts, log: MarketModel.log),
                        store: oiStore)
    resetOI()
    if let lastView { loadOI(view: lastView, refresh: true) }
  }

  /// 非默认行情源的品种表另存一棵：okx 的 BTCUSDT 不是币安那根，共用一份表会串。
  /// 目录一律问 `Paths` 要、不在这儿手拼字符串——手拼出来的那棵树「清缓存」逐个点名时
  /// 点不到，会永远躺在盘上，用量也算不进去。
  private static func catalogPaths(for source: MarketSource) -> Paths {
    source == .binance ? .caches() : Paths.caches().source(source.rawValue)
  }

  /// 排查「图有数据但一动不动」的时候需要看得见连了没有、推没推进来。
  /// 默认静音；`KANPAN_LOG=1` 打开（Xcode Scheme 的环境变量，或 `simctl launch` 的
  /// `SIMCTL_CHILD_KANPAN_LOG=1`）。
  ///
  /// `KANPAN_CHART_DIAGNOSTICS=1`（DEBUG 构建）也要打开它，只是不往 stdout 打印。
  /// 原因是 `MainScreen` 那层诊断浮层里有一格 `market.network`，读的正是
  /// `MarketNetworkDiagnostics.shared.lines`——以前它只在 `KANPAN_LOG=1` 时才有内容，
  /// 而 UI 测试只开 `KANPAN_CHART_DIAGNOSTICS`，于是那一格永远是空的。
  /// 「首屏取不到行情」这类用例挂在 CI 上时，恰恰只有这一格能回答「哪条路、哪个主机、
  /// 第几步断的」，空着等于把唯一的现场证据丢了。
  ///
  /// 两个开关**都只在 DEBUG 构建里读**（审查 C-02）：正式包一律静音，
  /// 同一个二进制不该因为启动环境不同而多出一条日志通路。
  private static let log: FeedLog = {
    #if DEBUG
    let env = ProcessInfo.processInfo.environment
    let stdout = env["KANPAN_LOG"] == "1"
    let collect = env["KANPAN_CHART_DIAGNOSTICS"] == "1"
    guard stdout || collect else { return .silent }
    return FeedLog { line in
      if stdout { print(line) }
      Task { @MainActor in MarketNetworkDiagnostics.shared.lines = String((MarketNetworkDiagnostics.shared.lines + "\n" + line).suffix(8000)) }
    }
    #else
    // 正式包一律静音。写成 `#if DEBUG … #else` 而不是 `#if !DEBUG … #else`，
    // 是为了让「所有读启动环境的地方都在 `#if DEBUG` 里」这句话能被一条机械扫描
    // 直接证明（审查 C-02 的收口证据），不必人工再读一遍取反分支。
    return .silent
    #endif
  }()

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

  /// 开张。`symbol` / `interval` 给了就先按它们落位再开——冷启动那一刻档案（访客或账号）
  /// 才刚装进来，「上次看的那张图、上次用的那个周期」只有到这一步才知道；先开再
  /// `switchTo` 等于白打一趟请求，还会让人先看一眼不是他上次那张图。
  func start(snapshot: Bool, symbol requestedSymbol: String? = nil, interval requestedInterval: Interval? = nil) {
    if let requestedSymbol, !requestedSymbol.isEmpty { symbol = requestedSymbol.uppercased() }
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
    // `[weak self]` 是这条流的命门。它原来强持有 self：`pump` 握着闭包、闭包握着
    // 模型、模型握着 `pump`——这个环只有 `stop()` 能拆，而宿主被销毁时没人叫 `stop()`。
    // 于是「这个模型没人要了」这件事永远不会发生，socket、重连计时器、45 秒一轮的
    // 持仓量轮询就在没有界面的情况下一直跑下去。
    pump = Task { [weak self, feed] in
      let stream = await feed.events()
      await feed.setSnapshotEnabled(snapshot)
      await feed.start(symbol: sym, interval: iv, selection: request)
      for await e in stream {
        if Task.isCancelled { break }
        // 宿主已经走了：这条流没有收件人了，顺手把 feed 也关掉再退出。
        guard let self else { await feed.stop(); return }
        await MainActor.run { self.apply(e) }
      }
    }
    // `[weak self]`：这一发只是去补品种的小数位与名字。宿主要是在这一个往返里
    // 就没了，它不该成为「模型还活着」的最后一根绳子——强持有的话，模型至少要陪
    // 它等到超时才肯释放。
    Task { [weak self] in await self?.refreshInfo() }
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
      funding = nil; fundingExpired = false
      // 持仓量是按交易所报的，换了线路就得按新交易所重取；供应量与交易所无关，留着。
      openInterestValue = nil; openInterestUnit = nil
      startStats()
      resetOI(); historyError = nil
      // 和启动时同一条规则（含「切回币安就用根上那份」）：这儿以前单独手拼，
      // 于是切回币安后品种表会落到 `sources/binance/` 下、和启动时读的那份对不上。
      let paths = Self.catalogPaths(for: next)
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
      sweepDisplayLifetimes()
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
      openInterestValue = nil; openInterestUnit = nil; totalSupply = nil
      return
    }
    statsTask = Task { [weak self] in
      // 供应量和持仓量是两条互不相干的接口，谁先回来先填谁那一格。以前是先等供应量
      // （取不到就得等它超时），顶栏的「仓」跟着白等一次往返。
      //
      // 两条都必须是 `statsTask` 的**结构化**子任务。供应量那条原来是另起的
      // `Task {}`：`statsTask.cancel()`（换品种、进后台、`stop()`）拦不住它，
      // 它照样会在几秒后带着**上一个品种**的供应量回来，撞上 `applyMeta` 那道
      // `sym == symbol` 的门才停下——门后面是对的，门本身不该指望。
      await withTaskGroup(of: Void.self) { group in
        group.addTask { [weak self] in
          guard let meta = await MarketStatsClient.shared.meta(symbol: sym, base: base, hosts: proxies) else { return }
          if Task.isCancelled { return }
          await MainActor.run { self?.applyMeta(meta, for: sym) }
        }
        group.addTask { [weak self] in
          while !Task.isCancelled {
            let stat = await MarketStatsClient.shared.openInterest(symbol: sym, source: src, hosts: proxies)
            if Task.isCancelled { return }
            await MainActor.run { self?.applyOpenInterest(stat, for: sym) }
            // 顺着这条循环做两件跟时间有关的事（审查 B-03 / B.8）：
            // 供应量过了 12 小时缓存就续一次（挂着不动的会话原来永远用开图那一下
            // 取的那个数算市值）；费率的展示寿命也在这儿扫——流断了之后没有任何
            // 事件会再进 `apply`，寿命判定要有人替它推一下。
            if let meta = await MarketStatsClient.shared.metaIfStale(symbol: sym, base: base, hosts: proxies) {
              if Task.isCancelled { return }
              await MainActor.run { self?.applyMeta(meta, for: sym) }
            }
            if Task.isCancelled { return }
            await MainActor.run { self?.sweepDisplayLifetimes() }
            try? await Task.sleep(for: .seconds(Double(Self.oiPollSeconds)))
          }
        }
      }
    }
  }

  /// 后端答了就以它为准：它给不出供应量（`meta` 里那几项全空）就把市值清掉。
  /// 「一台都没问通」不会走到这儿——`MarketStatsClient.meta` 那时返回 `nil`。
  private func applyMeta(_ meta: SymbolMeta, for sym: String) {
    guard sym == symbol else { return }
    totalSupply = meta.totalSupply.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
  }

  /// 规则全在 `MarketStatsClient.notionalOpenInterest` 里（纯函数，用例守着）：
  /// 请求没回来沿用旧值，回来了没有名义就清空。单位跟着值走。
  private func applyOpenInterest(_ stat: OpenInterestStat?, for sym: String) {
    guard sym == symbol else { return }
    let next = MarketStatsClient.notionalOpenInterest(stat, previous: openInterestValue)
    openInterestValue = next
    if let next {
      if openInterestUnit == nil { openInterestUnit = volUnit(next) }
    } else {
      openInterestUnit = nil
    }
  }

  // ---------------------------------------------------------------- 展示寿命

  /// 费率那一格是不是已经过了展示寿命（`markPrice` 帧超过一小时没更新）。
  /// 规则在 `HeaderStats.expired`；这儿存成状态是因为「时间流过去」本身不是事件，
  /// 流断掉之后没有任何帧会再进来触发重算，只能由持仓轮询每 45 秒推一下。
  private(set) var fundingExpired = false

  /// 顶栏上「拿到的时候是对的、现在不一定还对」的那几格，寿命在这儿统一扫。
  func sweepDisplayLifetimes(now: Date = Date()) {
    fundingExpired = HeaderStats.expired(frameMs: markTime, now: now,
                                         maxAge: HeaderStats.fundingMaxAge)
  }

  /// 这口价还能不能当「现在的价」看。假 = 顶栏整块灰显，额 / 费率 / 市值显示 `--`。
  ///
  /// 两种情形都算不新鲜：
  /// * `tickerStale`——换线路之后新线路还没推第一帧，屏上是上一条线路留下的那口价；
  /// * 品种已经不在交易（`SymbolInfo.status.hasLivePrice == false`，也就是已下架 /
  ///   已交割 / 还没开盘）——那种合约没有「现在的价」这回事，最后那口成交价不该
  ///   摆出一副实时的样子（审查 B-06）。
  ///
  /// **临时停牌（`.halted`）不在内**（审查复核项 3）：美股永续和贵金属每天收盘都是
  /// 这一档，它们的身份和外观一律照正常合约走；收盘之后价格自然停着不动，
  /// 那一面由 `tickerStale` 这条价格不新鲜的规则去说，不必让状态再说一遍。
  var priceFresh: Bool { !tickerStale && info.status.hasLivePrice }

  /// 顶栏费率那一格真正要显示的值。
  var displayedFundingRate: Double? { fundingExpired ? nil : funding?.fundingRate }

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
      openInterestValue = nil; openInterestUnit = nil; totalSupply = nil
      fundingExpired = false
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
    // 防抖是给连续平移用的：手指还在滑，就不该为中间每一帧各发一轮请求。第一次
    // 打开没有「连续」可言，那 250 ms 是白等的，所以只留够合并同一拍的那点时间。
    let quiet = oiRegion == nil && !refresh ? 30 : 250
    // 两段里先到的那段直接上屏。画而不动 `oiRegion`——区间由最后那次 mergeOI 定，
    // 否则半段到手就敢声称整段已有，平移时那块缺口再也不会被补。
    let paint: @Sendable ([OIPoint]) -> Void = { part in
      Task { @MainActor [weak self] in
        guard let self, request == self.selection, self.symbol == sym, self.interval == iv else { return }
        self.paintOI(part, interval: iv)
      }
    }
    oiTask = Task {
      do { try await Task.sleep(for: .milliseconds(quiet)) } catch { return }
      guard request == self.selection, self.symbol == sym, self.interval == iv else { return }
      // 上次留在磁盘上的那一段先上屏，用户不用对着「持仓量加载中」等一个往返。
      await self.seedOI(symbol: sym, interval: iv, step: step)
      guard !Task.isCancelled, request == self.selection, self.symbol == sym, self.interval == iv else { return }
      // 端点段（视野露出来的那截 + 刷新的尾巴）之外，还要扫一遍手里这串点自己断没断：
      // `oiRegion` 只是一对端点，表达不了「区间内部有洞」，旧版本漏在区间里面的那根
      // 空桶 `missingSegments` 永远看不见，跟着盘一起传到下一次会话（见 `holeSegments`）。
      var holes: [(from: Int64, to: Int64)] = []
      for hole in OISource.holeSegments(points: self.oiPoints, want: want, interval: iv,
                                        now: Int64(Date().timeIntervalSince1970 * 1000))
      where self.oiPatched.insert(hole.from).inserted {
        holes.append(hole)
      }
      let segments = OISource.mergeSegments(
        OISource.missingSegments(have: self.oiRegion, want: want, step: step, refresh: refresh) + holes)
      guard !segments.isEmpty else { return }
      let fetched = await withTaskGroup(of: OIFetch.self) { group in
        for segment in segments {
          group.addTask {
            await source.fetch(symbol: sym, interval: iv, from: segment.from, to: segment.to,
                               onPartial: paint)
          }
        }
        var all: [OIFetch] = []
        for await part in group {
          all.append(part)
          // 缺口不止一个时，先回来的那个缺口也立刻上屏。
          if segments.count > 1 { paint(part.points) }
        }
        return all
      }
      guard !Task.isCancelled, request == self.selection, self.symbol == sym, self.interval == iv else { return }
      // `oiPatched` 是「这个洞补过了」的记号，不是「试过了」的记号：这一轮只要有一段
      // 没问到，这些洞就当没补过，下次开图还会再问一次。
      if fetched.contains(where: { !$0.complete }) { for hole in holes { self.oiPatched.remove(hole.from) } }
      self.mergeOI(fetched.flatMap(\.points),
                   covered: OISource.coveredRegion(of: fetched, step: step),
                   want: want, step: step, symbol: sym, interval: iv)
    }
  }

  /// 磁盘上那份「品种 + 周期」只认一次：认过之后内存里的才是最新的。
  private func seedOI(symbol sym: String, interval iv: Interval, step: Int64) async {
    let key = sym + "|" + iv.rawValue
    guard oiDiskKey != key else { return }
    oiDiskKey = key
    guard oiRegion == nil, let cached = await oiStore.loadSeries(symbol: sym, interval: iv),
          !cached.points.isEmpty, sym == symbol, iv == interval, oiRegion == nil else { return }
    oiPoints = cached.points
    // 盘上那份 `to` 可能是旧版本留下的虚高右端（记的是请求区间），照单全收就会从这个
    // 虚高的右端往后补，在接缝上再留一个新洞。所以同样按真拿到的点收敛一次。
    // 注意收敛只防**新**洞：已经漏在区间内部的那根空桶，端点怎么收都碰不到它，
    // 得靠 `loadOI` 里的 `OISource.holeSegments` 扫点序列本身才补得回来。
    oiRegion = OISource.coveredRegion(want: (cached.from, cached.to), points: cached.points, step: step)
    oi = OISource.chartSeries(cached.points, interval: iv)
  }

  /// 半路到手的点：只管画，不碰 `oiRegion`，也不落盘。落盘和记账是 `mergeOI`
  /// 的事——它拿到的才是这一轮的完整结果。
  private func paintOI(_ points: [OIPoint], interval iv: Interval) {
    guard !points.isEmpty, iv == interval else { return }
    let merged = OISource.dedup(oiPoints + points)
    guard !merged.isEmpty else { return }
    oiPoints = merged
    oi = OISource.chartSeries(merged, interval: iv)
  }

  /// - Parameter covered: 这一轮**真的问到了**的那部分区间（`OISource.coveredRegion(of:)`）。
  ///   nil = 一段都没问到，那就一步都不推进记账。
  private func mergeOI(_ points: [OIPoint], covered: (from: Int64, to: Int64)?,
                       want: (from: Int64, to: Int64), step: Int64,
                       symbol sym: String, interval iv: Interval) {
    let previous = oiRegion
    let joins = previous.map { want.from <= $0.to && want.to >= $0.from } ?? false
    let merged = OISource.dedup(joins ? oiPoints + points : points)   // 同一时刻留新到的
    guard !merged.isEmpty else { return }
    oiPoints = merged
    oi = OISource.chartSeries(merged, interval: iv)
    // 记「真问到的」而不是「请求的」，两头各有一个理由：
    // 右端——`want.to` 伸到最后一根 K 线之后两根，那两根还没发生，原样记下来并落盘，
    // 下一次会话的接缝上就留一个永远补不上的空桶（`OISource.coveredRegion` 收右端）。
    // 左端——请求整段失败（网络错 / 451 / 网关超时 / 归档站给不出）时，把 `want.from`
    // 记成已有，那一截就再也不会被请求：`missingSegments` 只比端点，`holeSegments`
    // 又看不见第一个点之前缺的那一截。所以失败的段一段都不算覆盖。
    guard var region = covered else {
      // 视野整个跳到别处又什么都没问到：手里这串点和旧记账已经对不上了，记账清掉，
      // 下一轮整段重取；还挨着的话就原样留着旧记账，下一轮照样认得出缺哪一截。
      if !joins { oiRegion = nil }
      return
    }
    if joins, let old = previous { region = (from: min(old.from, region.from), to: max(old.to, region.to)) }
    oiRegion = region
    let store = oiStore
    Task { await store.saveSeries(symbol: sym, interval: iv, points: merged, from: region.from, to: region.to) }
  }

  /// 换品种、换周期、换线路都得从头来：手里的点要么周期对不上，要么是另一家交易所报的。
  private func resetOI() {
    oiTask?.cancel(); oiTask = nil
    oi = nil; oiPoints = []; oiRegion = nil; oiDiskKey = nil; oiPatched = []
  }

  /// 品种页要的品种表。`@Sendable` 是因为品种页把它当闭包存着，
  /// 跨隔离域传——所以捞的是 actor（`SymbolCatalog`），不是 `self`。
  nonisolated var catalogLoader: @Sendable () async -> [SymbolInfo] {
    let c = catalog
    return { await c.all() }
  }

  /// 品种页搜了一个**本机目录里没有**的代号（审查 B-06）。
  ///
  /// 这是「用户明确点名」的信号，允许不等 24 小时的 TTL 立刻重拉一次整表；
  /// 去抖（5 分钟）在 `SymbolCatalog.lookup` 那一层。表真的变了才回一份新的，
  /// 否则回 `nil`——没变还灌一次，品种页白重建一遍分区。
  func lookupMissingSymbol(_ symbol: String) async -> [SymbolInfo]? {
    let before = await catalog.all().count
    let found = await catalog.lookup(symbol)
    let after = await catalog.all()
    guard found != nil || after.count != before else { return nil }
    return after
  }

  // 这儿原来有个 `#if DEBUG func overrideInfoForTesting(_:)`，用例拿它直接往
  // `info` 里塞一份品种事实（审查 C-05）。两个毛病：Release 下这个方法根本不存在，
  // 于是 `KanpanTests` 在 Release 配置下连编都编不过，「Release 回归」永远只能是空话；
  // 而且它绕开了产品里真正把品种翻成下架的那条路。用例改走
  // `noteSymbolRejected(_:)`——那是交易所答不出代号时产品自己会走的入口，
  // 测它才算测到东西。钩子就此删掉，Debug / Release 两边的 `MarketModel` 一模一样。

  /// 交易所拿这个代号答不出来（`QuoteBook.onSymbolRejected`）。
  ///
  /// 唯一要做的事是把品种表里那一行标成下架——「下架」这个事实只存在一处
  /// （`SymbolInfo.status`），自选、搜索、图表三处都从那里读，所以标一次三处一致。
  /// 图上恰好就是它时顺手把手里这份 `info` 也翻过来，不然要等下一次目录刷新
  /// 头部才会跟着灰掉。自选表一个字都不动。
  func noteSymbolRejected(_ symbol: String) {
    let key = symbol.uppercased()
    Task { [catalog] in await catalog.markDelisted(key) }
    guard key == self.symbol, info.status != .delisted else { return }
    var value = info
    value.status = .delisted
    info = value
    sweepDisplayLifetimes()
  }

  private func refreshInfo() async {
    let want = symbol
    // 进一张图就是「用户点名了这个品种」：表里没有它（刚上市的新合约）时允许为他
    // 立刻重拉一次整表，不必等满 24 小时的 TTL（审查 B-06）。去抖在目录层。
    guard let found = await catalog.lookup(want) else { return }
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
  /// 用户明确点名的那次查询：表里没有就为他立刻重拉一次（带去抖，见 `SymbolCatalog.lookup`）。
  func lookup(_ symbol: String) async -> SymbolInfo? { await catalog.lookup(symbol) }
  /// 交易所不认这个代号：在表里把它标成下架，**不删**。
  func markDelisted(_ symbol: String) async { await catalog.markDelisted(symbol) }
}

#if DEBUG
@MainActor @Observable final class MarketNetworkDiagnostics {
  static let shared = MarketNetworkDiagnostics()
  var lines = ""
}
#endif
