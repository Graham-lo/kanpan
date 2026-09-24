import Foundation
import KanpanCore
import KanpanNetwork

/// Switches complete feeds. Business views never merge candles from different exchanges.
///
/// 这一层不认识任何一家交易所：品种键（`InstrumentID.key`）说它是哪家的，
/// `resolver` 按「交易所 × 线路」给一个提供者，其余全看 `ProviderCapabilities`。
public actor RoutedMarketFeed {
  public typealias Resolver = @Sendable (_ venue: String, _ policy: MarketRoutePolicy) -> any MarketProvider
  private let log: FeedLog
  private let paths: Paths
  private var freshHistory = false
  private let resolver: Resolver
  /// 按交易所缓存的提供者。提供者对一条线路是不可变的，换线路整张表清掉重建
  /// （新建的 transport 冷却账本是空的，等于原来的「换线路顺手清冷却」）。
  private var providers: [String: any MarketProvider] = [:]
  /// 行情线路。用户定的，见 `MarketRoutePolicy`：线路 × 交易所决定谁供数，
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
  private var feed: MarketFeed?
  /// 当前这份 `feed` 是按哪个提供者建的（`交易所|上游`）。线路可能已经先一步改了
  /// （见 `setRoutePolicy`），这里记的才是真正在跑的那家。
  private var activeKey: String?
  /// 当前这份 `feed` 的提供者。
  private var activeProvider: (any MarketProvider)?
  private var pump: Task<Void, Never>?
  private var monitor: Task<Void, Never>?
  private var selection = UUID()
  private var route = UUID()
  private var symbol = ""
  private var interval: Interval = .h1
  private var takerEnabled = false
  private var depthEnabled = false
  /// 主力订单流（`OrderFlowSlot` / `OrderFlowFeed`）。
  private var orderFlow = OrderFlowSlot()
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
  /// 行情页顺手预热（扫图邻居、「看细节」要去的那一档）各占一个槽，按槽名分开：
  /// 同一个槽里新的一轮顶掉旧的一轮（扫得快时邻居一直在变），不同槽互不相掐，
  /// 也不碰自选预热和换周期预热那两个槽。
  private var prewarmTasks: [String: Task<Void, Never>] = [:]
  /// 板块品种列表的预热也单独占一个槽：进板块列表不该把自选那一轮掐掉，
  /// 离开列表也只掐自己这一轮。
  private var listPrefetchTask: Task<Void, Never>?
  /// 上一次预热时带来的常用周期表。记下来，换品种之后自动给新品种也热一遍。
  private var warmIntervals: [Interval] = []
  /// 预热几个自选。自选列表通常也就这么长，等于「整张列表都热过一遍」。
  /// 一个品种一发 300 根（限频权重 2），20 个合计 40 点权重，币安一分钟的配额是 2400。
  public static let prefetchLimit = 20
  /// 板块列表只热前面这几行——一屏看得见、最可能被点的那几只。
  public static let listPrefetchLimit = 10

  /// 线路从 `RouteResolver` 取：档位跟着本机的线路选择（换档时广播过来），
  /// 网关表默认是线上那两台。
  public init(endpoints: MarketEndpoints = .production, paths: Paths = .caches(), log: FeedLog = .silent) {
    self.paths = paths; self.log = log
    self.policy = MarketRoutePolicyStore.current
    self.resolver = { venue, policy in
      RouteResolver(policy: policy, endpoints: endpoints, log: log).provider(venue: venue)
    }
    observePolicy()
  }

  /// 测试注入：提供者（连同里面的 REST 与 socket 工厂）全换成假件，整条路由就能离线跑。
  init(paths: Paths, log: FeedLog = .silent, policy: MarketRoutePolicy, resolver: @escaping Resolver) {
    self.paths = paths; self.log = log
    self.policy = policy
    self.resolver = resolver
  }

  /// 一份 feed 的身份：交易所 × 上游 × **线路**。
  ///
  /// 提供者是按线路建的（主机名在它肚子里），所以线路本身必须进键。原来只看
  /// 「交易所|上游」：币安换线路时上游恰好也换（币安 ↔ OKX 替身），看不出毛病；
  /// 上游不随线路变的交易所（两条线路上游都是它自己），键一样，切到「网关」之后连着的
  /// 直连 feed 原样留着——REST 和推送照旧打交易所自己的域名，网关开关对它形同虚设。
  private func key(_ caps: ProviderCapabilities) -> String { Self.key(caps, policy) }
  private static func key(_ caps: ProviderCapabilities, _ policy: MarketRoutePolicy) -> String {
    caps.venue + "|" + caps.upstream + "|" + policy.rawValue
  }

  /// 某个品种在当前线路上该找谁。
  private func provider(forSymbol symbol: String) -> any MarketProvider {
    let venue = InstrumentID(symbol).venue
    if let cached = providers[venue] { return cached }
    let made = resolver(venue, policy)
    providers[venue] = made
    return made
  }

  /// 当前品种的提供者。
  private var current: any MarketProvider { provider(forSymbol: symbol) }

  /// 提供者的快照分区：替身上游单独一个子目录，免得和真身互相覆盖。
  private func paths(for caps: ProviderCapabilities) -> Paths { Self.snapshotPaths(for: caps, in: paths) }

  /// 某个提供者的 K 线快照落在哪棵树。品种键里已经带着交易所，同一家的各条线路共用根；
  /// 替身上游（`snapshotNamespace`）单独一个子目录。界面同步读快照时也按这条规则找。
  public static func snapshotPaths(for caps: ProviderCapabilities, in root: Paths) -> Paths {
    guard let ns = caps.snapshotNamespace else { return root }
    return root.source(ns)
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

  /// 换线路：换一套提供者，并且立刻切到这条线路上的那一份。
  ///
  /// 不等下一次换品种：REST 和已经连着的 WebSocket 一起换。不然 REST 已经改走
  /// 网关了，连着的直连 WS 还会一直挂到下次重连——「网关」就成了只管历史
  /// 不管实时的半个开关。
  public func setRoutePolicy(_ policy: MarketRoutePolicy) async {
    guard self.policy != policy else { return }
    self.policy = policy
    // 提供者表同步换掉（这里没有挂起点）：之后进来的 `start` / 预热看到的已经是新线路。
    providers.removeAll()
    // 线路一换键就不同（键里带线路），这里总会重起 feed：提供者是按线路建的，旧的那份
    // 连着的是旧线路的主机。只有换回了正在跑的那条（先前的切换还没落地）才不用动。
    guard !symbol.isEmpty, activeKey != key(current.capabilities) else { return }
    announceSwitch()
    await activate()
  }
  public func events() -> AsyncStream<FeedUpdate> {
    let (stream, sink) = AsyncStream<FeedUpdate>.makeStream(); continuation = sink; return stream
  }
  public var currentSeries: BarSeries {
    get async { if let feed { return await feed.currentSeries }; return BarSeries(symbol: symbol, interval: interval, bars: []) }
  }
  public func setMicrostructure(taker: Bool, depth: Bool) async {
    takerEnabled = taker; depthEnabled = depth
    let micro = activeProvider?.capabilities.hasMicrostructure == true
    await feed?.setMicrostructure(taker: micro && taker, depth: micro && depth)
  }
  /// 主力订单流开关与设置。簿订阅不在这里发：要等当前品种的 K 线交给界面之后（见 `forward`）。
  /// 开着时重复调用无妨：品种事实刚到（之前没起成）会在这里补起，用户改过的门槛会推给正在跑的那条。
  /// - Parameters:
  ///   - facts: 品种 → base、资产类别、最小变动价、成交额；还不知道就给 nil（先不订）。
  ///   - overrides: 用户改过的门槛 / 步长，键是去掉缩放前缀的 base（`OrderFlowFacts.overrideKey`）。
  public func setOrderFlow(enabled: Bool, overrides: [String: OrderFlowOverride] = [:],
                           facts: @escaping @Sendable (String) -> OrderFlowFacts?) {
    orderFlow.enabled = enabled; orderFlow.facts = facts
    orderFlow.setOverrides(overrides)
    if enabled { startOrderFlow() } else { stopOrderFlow(forgetChart: false) }
  }
  private func startOrderFlow() {
    guard orderFlow.start(symbol: symbol, foreground: foreground, provider: activeProvider, paths: paths, log: log,
                          publish: { [weak self] token, frame in await self?.publishOrderFlow(frame, token: token) })
    else { return }
    continuation?.yield(FeedUpdate(selection: selection, event: .orderFlow(.loading(symbol))))
  }
  private func stopOrderFlow(forgetChart: Bool) {
    if orderFlow.stop(forgetChart: forgetChart) { continuation?.yield(FeedUpdate(selection: selection, event: .orderFlow(nil))) }
  }
  private func publishOrderFlow(_ frame: OrderFlowSnapshot, token: UUID) {
    guard orderFlow.accept(frame, token: token, symbol: symbol) else { return }
    continuation?.yield(FeedUpdate(selection: selection, event: .orderFlow(frame)))
  }
  public func setSnapshotEnabled(_ enabled: Bool) async {
    snapshots = enabled
    if !enabled {
      // 关了快照，还在排队或跑着的预热一并叫停——否则它们会在下面清完盘之后
      // 接着把刚拉回来的几份写回去（审查 §4：关快照不取消 prefetch / warm）。
      cancelPrefetching()
    }
    await feed?.setSnapshotEnabled(enabled)
    if !enabled {
      Snapshot.remove(paths.snapshot)
      SeriesStore.clear(in: paths.series)
      // 各上游的独立分区（`ProviderCapabilities.snapshotNamespace`）一并清掉。
      let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.sources.path)) ?? []
      for name in names {
        let sub = paths.source(name)
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
    let sameSymbol = InstrumentID.canonical(symbol) == self.symbol
    self.symbol = InstrumentID.canonical(symbol); self.interval = interval; self.selection = selection
    // 主力订单流：换品种就清簿；只换周期时把最后一帧补给新的 selection。
    if !sameSymbol { stopOrderFlow(forgetChart: true) } else if let last = orderFlow.last {
      continuation?.yield(FeedUpdate(selection: selection, event: .orderFlow(last)))
    }
    monitor?.cancel()
    // 同一个提供者（同一家、同一条上游、同一条线路）就只换订阅；换到另一家交易所的品种要整份换 feed：
    // 一份 feed 永远只接一家的数据，不在同一条连接里混源。
    if let feed, activeKey == key(current.capabilities) {
      await feed.switchTo(symbol: symbol, interval: interval, coldStart: coldStart, selection: selection)
    } else { await activate(coldStart: coldStart) }
    if self.selection == selection { startMonitoring(immediate: historyRetry > Date()) }
    // 换了品种，新品种的其他常用周期也热一遍：用户看完这一档，下一个动作
    // 多半就是切周期。等首屏和后台加深先走完，别跟它们抢带宽。
    if coldStart, self.selection == selection { warmOtherIntervals(of: symbol, current: interval) }
  }
  private func activate(coldStart: Bool = false) async {
    let request = selection; let generation = UUID(); route = generation
    pump?.cancel()
    stopOrderFlow(forgetChart: true)  // 换了提供者，深度流也要换那一家的
    // 先把旧的那份摘下来再去停它。`stop()` 要等落盘和一次 WS 收尾，这中间进来的
    // `switchTo` 看到 `feed` 还在，就会把「切品种」交给一份正在被拆掉的 feed，
    // 那一笔切换从此没有下文。
    let dying = feed
    feed = nil
    activeKey = nil
    activeProvider = nil
    await dying?.stop()
    guard request == selection, generation == route, !Task.isCancelled else { return }
    freshHistory = false
    pendingStatus = .offline
    let next = current, nextPolicy = policy
    let caps = next.capabilities
    // 首帧前的静默窗口交给提供者定（A-07 第②层：线路是用户定死的、没有竞速，
    // 冷门品种 15 秒内完全可能一帧都不推，收窄就会变成无休止的重连）。
    let ws = next.makeStream(silenceMs: nil, log: log)
    // 首屏要多深、订不订 24h 行情，全按能力位（`initialKlines` / `hasTickerStream`）：
    // 深的那一家 `MarketFeed.fillOnce` 会另外并行发一发 300 根的小页，谁先回谁先画；
    // 深度翻页贵的那一家首屏只要 300 根，深度交给后台加深。
    let created = MarketFeed(provider: next, stream: ws, cache: cache,
      paths: paths(for: caps), log: log)
    // 装配（挂快照开关、取事件流）全在本地做完再挂到 `feed` 上。
    //
    // 原来是先 `feed = created` 再 await 装配：这中间进来的 `switchTo` 看见
    // `feed` 非空，就把新品种交给这份**还没 start** 的 feed，然后本方法回来又拿
    // 旧的 `request` 把它 start 一遍——`forward` 只认当前 selection，从此这份 feed
    // 吐的每一条都被丢掉，用户面前就是一张不再更新的空图。
    await created.setSnapshotEnabled(snapshots)
    await created.setMicrostructure(taker: caps.hasMicrostructure && takerEnabled,
                                    depth: caps.hasMicrostructure && depthEnabled)
    let stream = await created.events()
    // 装配的这两拍里世界可能已经变了（又切了品种、又换了线路），这份 feed 已经
    // 没人要了：就地扔掉，别让它挂上去顶掉真正在跑的那份。
    guard request == selection, generation == route, !Task.isCancelled else {
      await created.stop()
      return
    }
    // 从这儿开始对外才存在这份 feed。挂上、接管、开跑之间不再有任何挂起点，
    // 别人插不进来。
    feed = created
    activeKey = Self.key(caps, nextPolicy)
    activeProvider = next
    pump = Task { [weak self] in
      for await update in stream {
        guard !Task.isCancelled, let self else { return }
        await self.forward(update, generation: generation, caps: caps)
      }
    }
    await created.start(symbol: symbol, interval: interval, selection: request)
  }
  private var publishedRoute: UUID?
  private var pendingStatus: FeedStatus = .offline
  private func forward(_ update: FeedUpdate, generation: UUID, caps: ProviderCapabilities) {
    guard generation == route, update.selection == selection else { return }
    if case .series(let series) = update.event { seriesStart = series.firstTime }
    if case .historyError(let message) = update.event {
      pendingHistoryError = message
      if message != nil {
        // 这儿**不**报 `.routing(.switching)`。历史没拉下来不是换线路——本来也没换
        // （见本类开头：线路是用户定的，这里不换线）。而行情页收到 `.switching`
        // 的第一件事就是 `historyError = nil`（`MarketModel`），于是内部每重试一次
        // 就把「点此重试」那条横幅抹掉一次：巡检刚把它亮起来，下一发 429 回来又抹掉，
        // 用户最后看到的是一张空图 + 一个「行情加载中」，既没有错误也没有重试的路。
        if caps.probesHistoryBoundary { historyBoundary = seriesStart; historyRetry = Date().addingTimeInterval(60) }
        startMonitoring(immediate: true)
        return // 内部重试保持安静，由巡检统一决定要不要报「暂时无法连接」。
      }
      freshHistory = true; settleRoute()
      if caps.probesHistoryBoundary { historyRetry = .distantPast; historyBoundary = nil }
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
      // 交接给界面的门槛。原来只认一条：历史至少 3 根。于是首屏历史一慢（撞上 429
      // 罚停、网关 busy），`.status` 和 `.ticker` 全被这道门吃掉——WS 明明已经在推
      // 实时价了，顶栏还是死死的「—」，状态停在「离线」，而持仓量走的是网关那条独立
      // 的路照样有数。用户看到的是一屏自相矛盾的假象，而且那是**假的**：线路没离线。
      //
      // 所以多开一条出路：WS 报了 `.live` 就交接。图还是空的，但那件事由
      // `historyError` 的横幅去说（巡检那句「暂时无法连接，点此重试」不走这道门），
      // 报价是真的，状态也不再撒谎。
      //
      // 换线路那一路不放行（`announcingSwitch`）：用户手动切线时新交易所的 WS 往往
      // 先于历史活过来，这时候交接等于把旧线路还能看的那张图换成一张空图，比等着更糟。
      let live = pendingStatus == .live && !announcingSwitch
      let enough = { if case .series(let series) = update.event { return series.count >= 3 }; return false }()
      guard enough || live else { return }
      publishedRoute = generation
      continuation?.yield(FeedUpdate(selection: selection, event: .provider(caps)))
      continuation?.yield(FeedUpdate(selection: selection, event: .status(pendingStatus)))
      // 开门这一下已经把状态发出去了，别紧接着再发一遍同样的。
      if case .status = update.event { settleRoute(); return }
    }
    continuation?.yield(update)
    settleRoute()
    // 当前品种的 K 线刚交给界面：这之后才订簿，不跟首屏抢。
    if case .series(let series) = update.event, series.count >= 3, orderFlow.chartReady != symbol {
      orderFlow.chartReady = symbol; startOrderFlow()
    }
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
  private func healthy(_ candidate: any MarketProvider, symbol: String, interval: Interval,
                       requireStream: Bool = true) async -> Bool {
    let boundary = historyBoundary

    // REST and WS are independent. The old serial probe paid both network
    // round trips before activating the source, even though the feed starts
    // its own REST and WS work immediately afterwards.
    async let restReady = Self.restHealthy(provider: candidate, symbol: symbol, interval: interval,
                                           boundary: boundary)
    if !requireStream { return await restReady }
    async let streamReady = candidate.probeStream(symbol: symbol, interval: interval)
    let restOK = await restReady
    let streamOK = await streamReady
    return restOK && streamOK
  }

  private static func restHealthy(provider: any MarketProvider, symbol: String, interval: Interval,
                                  boundary: Int64?) async -> Bool {
    do {
      let bars = try await provider.klines(symbol: symbol, interval: interval, limit: 3)
      try Task.checkCancellation()
      guard bars.count >= 3, let last = bars.last else { return false }
      if let boundary {
        let older = try await provider.klines(symbol: symbol, interval: interval, limit: 3,
                                              endTime: boundary - 1)
        guard !older.isEmpty else { return false }
      }
      // 拉回来的是源周期：拿源周期的当前桶比。
      let source = provider.capabilities.source(for: interval)
      let current = Aggregator.bucketStart(ms: Int64(Date().timeIntervalSince1970 * 1000), interval: source)
      return last.openTime >= current
    } catch { return false }
  }
  private func startMonitoring(immediate: Bool = false) {
    monitor?.cancel()
    guard foreground else { return }
    let request = selection
    monitor = Task { [weak self] in
      // `weak` 只在这儿弱一下是不够的：循环前先 `guard let self` 等于把强引用
      // 一路握到任务结束，这条巡检 20 秒一轮、永不自然收尾，于是整份路由
      // （连同它手里的 feed、WS、REST）在页面关掉之后也一直活着。
      // 强引用只在真正要调的那一刻取，取完就放。
      if !immediate { do { try await Task.sleep(for: .seconds(20)) } catch { return } }
      while !Task.isCancelled {
        // 强引用只在这一句里短暂存在：用 `self?.` 直接调，调完就放掉，
        // 绝不让它跨过下面那一觉——睡着的 20 秒里没人引用这份路由，该释放就能释放。
        await self?.checkSource(selection: request)
        if self == nil { return }
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
  /// 无论哪种都不会悄悄换成另一家交易所。没有 24h 行情推送的提供者，顺手补一份。
  private func checkSource(selection request: UUID) async {
    guard request == selection, foreground, !Task.isCancelled else { return }
    let sym = symbol, iv = interval, chosen = current
    let chosenKey = key(chosen.capabilities)
    if !chosen.capabilities.hasTickerStream { await refreshPolledTicker(chosen, symbol: sym, selection: request) }
    guard request == selection, foreground, !Task.isCancelled, pendingHistoryError != nil else { return }
    // 刚报错那 60 秒内不去探：feed 自己还在重试，探了也是重复打同一条线。
    let ready = Date() >= historyRetry ? await healthy(chosen, symbol: sym, interval: iv) : false
    guard request == selection, foreground, !Task.isCancelled, chosenKey == key(current.capabilities) else { return }
    if ready { await activate() } else { unavailable(request) }
  }
  private func refreshPolledTicker(_ chosen: any MarketProvider, symbol: String, selection request: UUID) async {
    let key = self.key(chosen.capabilities)
    if let ticker = try? await chosen.ticker24h(symbol: symbol), request == selection,
       key == activeKey, !Task.isCancelled {
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
    guard snapshots else { return }
    if !intervals.isEmpty { warmIntervals = intervals }
    let currentSymbol = InstrumentID.canonical(symbol)
    var seen = Set<String>([currentSymbol])
    // 聚出来的周期不预热（要整段重聚，一页 300 根聚不出一屏）；各品种按自己那一家的能力位判。
    var jobs: [Job] = symbols.map { InstrumentID.canonical($0) }.filter { seen.insert($0).inserted }
      .prefix(Self.prefetchLimit).compactMap { job($0, interval) }
    // 当前品种换周期：本地已经有当前这档了，补其余几档。
    if !currentSymbol.isEmpty {
      jobs += intervals.filter { $0 != interval }.compactMap { job(currentSymbol, $0) }
    }
    // 慢一步再开始。预热的每一份是 300 根、几十 KB，而此刻用户正盯着自选列表
    // 等那一屏报价（每条只有几百字节）补齐——先让小的过去。等得起：用户从
    // 看清列表到点进某一行，不会比这快。
    prefetchTask = run(jobs: jobs, delayMs: 1200)
  }

  /// 行情页马上可能要用到的几份快照，立刻拉（不等 1.2 s）。
  ///
  /// 两个用处：扫图时的前后邻居（当前周期），以及十字线一出来就预取「看细节」
  /// 要切去的那档更细周期——那一档多半没钉在周期条上，自选预热从来不会碰它，
  /// 点下去时磁盘上没有快照，整张图就先空一拍。
  /// 已经有够新快照的会被 `run` 跳过，重复叫不会重复打请求。
  public func prewarm(symbols: [String], interval: Interval, slot: String) {
    prewarmTasks[slot]?.cancel()
    guard snapshots else { prewarmTasks[slot] = nil; return }
    // 聚出来的周期、这家不支持的周期不拉（`job` 按各品种那一家的能力位判）。
    var seen = Set<String>()
    let jobs = symbols.map { InstrumentID.canonical($0) }.filter { seen.insert($0).inserted }
      .compactMap { job($0, interval) }
    prewarmTasks[slot] = run(jobs: jobs, delayMs: 0)
  }

  /// 板块品种列表出现时，把列表最上面几行当前周期的 K 线先拉一份落盘。
  ///
  /// 从板块列表点进一只没看过的品种，原来第一帧图是白的——本地什么都没有。
  /// 这里只热前 `listPrefetchLimit` 行、只热当前周期；已经有够新快照的直接跳过
  /// （`run` 里判），所以反复进出同一张列表不会重复打请求。
  ///
  /// 克制：延迟 400ms 才开始（列表的报价先上屏），跑在 utility 优先级；
  /// 用户点进某一只时，那一只的首屏请求走的是自己的线路，不排在这后面。
  public func prefetchList(symbols: [String], interval: Interval) {
    listPrefetchTask?.cancel()
    listPrefetchTask = nil
    guard snapshots else { return }
    var seen = Set<String>([InstrumentID.canonical(symbol)])
    // 聚出来的周期不热（`job` 按各品种那一家的能力位判，和自选预热同一口径）。
    let jobs = symbols.map { InstrumentID.canonical($0) }.filter { seen.insert($0).inserted }
      .prefix(Self.listPrefetchLimit).compactMap { job($0, interval) }
    listPrefetchTask = run(jobs: jobs, delayMs: 400)
  }

  /// 离开板块列表：还没拉完的那几份不拉了。
  public func cancelListPrefetch() {
    listPrefetchTask?.cancel()
    listPrefetchTask = nil
  }

  /// 换品种之后，给新品种的其他常用周期也各拉一份。
  ///
  /// 常用周期表是上一次 `prefetch` 留下来的（`warmIntervals`），所以不用在每次
  /// 切换时都把偏好设置一路塞下来。延迟 2.5 秒是让首屏和后台加深先跑完——
  /// 用户此刻正盯着这一档，别跟它抢带宽。
  private func warmOtherIntervals(of symbol: String, current: Interval) {
    warmTask?.cancel()
    let name = InstrumentID.canonical(symbol)
    guard snapshots, !warmIntervals.isEmpty, job(name, current) != nil else { return }
    let jobs = warmIntervals.filter { $0 != current }.compactMap { job(name, $0) }
    warmTask = run(jobs: jobs, delayMs: 2500)
  }

  /// 一份预热：品种、周期、找谁拉、落到哪个分区。
  private struct Job: Sendable {
    let symbol: String
    let interval: Interval
    let provider: any MarketProvider
    let dir: URL
  }

  private func job(_ symbol: String, _ interval: Interval) -> Job? {
    let provider = provider(forSymbol: symbol)
    let caps = provider.capabilities
    guard !caps.isAggregated(interval), caps.supports(interval) else { return nil }
    return Job(symbol: symbol, interval: interval, provider: provider, dir: paths(for: caps).series)
  }

  /// 预热的活儿本身：挨个拉回来，写盘**并且**塞进内存缓存。
  ///
  /// 原来只写盘。可点进一个预热过的品种时，`MarketFeed.switchTo` 先问的是内存缓存，
  /// 问不到才去读盘——等于每次都要走一趟「开文件 + 解码 + 改 mtime」。
  /// 一份 300 根只有 14KB，20 份合计不到 300KB，放内存里完全划得来。
  private func run(jobs: [Job], delayMs: Int) -> Task<Void, Never>? {
    guard !jobs.isEmpty else { return nil }
    let log = self.log
    let cache = self.cache
    return Task.detached(priority: .utility) { [weak self] in
      if delayMs > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        guard !Task.isCancelled else { return }
      }
      var done = 0
      var skipped = 0
      for job in jobs {
        guard !Task.isCancelled else { return }
        // 已经有一份够新的就跳过——落后不到几根的快照，点进去照样是秒开。
        if let have = SeriesStore.read(symbol: job.symbol, interval: job.interval, in: job.dir),
           have.count >= MarketFeed.firstScreenLimit / 2,
           Int64(Date().timeIntervalSince1970 * 1000) - have.lastTime < 3 * job.interval.stepMs { continue }
        do {
          let bars = try await job.provider.klines(symbol: job.symbol, interval: job.interval, limit: MarketFeed.firstScreenLimit)
          guard !bars.isEmpty else { continue }
          let series = BarSeries(symbol: job.symbol, interval: job.interval, bars: MarketSeries.dedup(bars))
          // 写盘回到 actor 上做：和 `setSnapshotEnabled(false)` 的清盘排在同一条队里，
          // 快照一关，要么这份还没写（不写了），要么已经写了（跟着被清掉），不会漏一份在盘上。
          guard !Task.isCancelled, let self,
                try await self.persistPrefetched(series, in: job.dir) else { return }
          await cache.put(series)
          done += 1
        } catch {
          // 原来是「一个失败就整轮收工」。可自选里留着一个已下市的代号
          // （交易所回 400 `Invalid symbol`）就会把后面十几个全带走——
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

  /// 预热拉回来的一份落盘。快照已经关了就不写，返回假让那一轮收工。
  private func persistPrefetched(_ series: BarSeries, in dir: URL) throws -> Bool {
    guard snapshots else { return false }
    _ = try SeriesStore.write(series, in: dir)
    return true
  }

  /// 所有预热任务一起停：关快照、整个 feed 停掉时用。
  private func cancelPrefetching() {
    prefetchTask?.cancel(); prefetchTask = nil
    warmTask?.cancel(); warmTask = nil
    listPrefetchTask?.cancel(); listPrefetchTask = nil
    prewarmTasks.values.forEach { $0.cancel() }; prewarmTasks = [:]
  }

  /// 这个错误只是「这一个品种不行」，还是「整条线路不行」。
  ///
  /// 只有前者才跳过接着干。判据取严：**确知**是单品种问题（4xx，但不含 408 超时
  /// 和 418/429 限流）才算跳过，其余一律当线路问题停下——宁可少预热几份，
  /// 也不要在网络已经不行的时候接着打二十发。
  ///
  /// 「单品种问题」指的是交易所拿这个代号答不出来：400 `Invalid symbol`、-1121、404。
  /// 下面这几种都不是，一个都不许当成跳过：
  /// - 429/418 限流与 IP 封禁（`isRateLimited`，含本机限流器挡下的 `.blocked`）：
  ///   停的是整个出口，接着打二十发只会把封禁续下去；
  /// - 408 超时：线路的事；
  /// - 451 `upstream_blocked`（网关替上游转述的地域拒绝，`isGeoBlocked`）：
  ///   它虽然落在 4xx 里，但拒的是这条线路的出口 IP，跟品种没有半点关系——
  ///   当成「这个品种不行」就会把整张自选表一个个试完，每一个都失败（A-05）。
  nonisolated static func skippable(_ error: any Error) -> Bool {
    guard let e = error as? UpstreamError else { return false }
    guard (400..<500).contains(e.status) else { return false }
    return !e.isRateLimited && !e.isGeoBlocked && e.status != 408
  }

  /// Retry the currently selected source after a visible history failure.
  /// This also clears the short-lived route backoff because the retry was an
  /// explicit user action, not an automatic probe.
  public func retry(selection requested: UUID = UUID()) async {
    for provider in providers.values { await provider.resetRouteCooldowns() }
    await switchTo(symbol: symbol, interval: interval, coldStart: false, selection: requested)
  }

  public func networkChanged(online: Bool) async {
    await feed?.networkChanged(online: online)
    if online { startMonitoring() } else { monitor?.cancel() }
  }
  public func enterBackground() async {
    foreground = false; monitor?.cancel(); stopOrderFlow(forgetChart: false); await feed?.enterBackground()
  }
  public func enterForeground() async { foreground = true; await feed?.enterForeground(); startMonitoring(); startOrderFlow() }
  public func memoryWarning() async { await feed?.memoryWarning() }

  // ---------------------------------------------------------------- 测试缝

  /// 当前这条线路上、WS 等第一帧行情的窗口（毫秒）。两档线路都该是 60 秒：
  /// 提供者建推送时已经清空了竞速候选，「有竞速候选就夹到 15 秒」的钳子够不着（A-07 第②层）。
  func wsSilenceMsForTests() async -> Double? { await feed?.wsSilenceMsForTests() }
  public func stop() async {
    selection = UUID(); route = UUID(); monitor?.cancel(); pump?.cancel()
    cancelPrefetching()
    stopOrderFlow(forgetChart: true)
    await feed?.stop(); feed = nil; continuation?.finish(); continuation = nil
  }
}
