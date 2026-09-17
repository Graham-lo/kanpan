import Foundation
import KanpanCore

/// 图表侧收到的东西（§3.1）。`BarSeries` 是值类型快照，每次事件换一份，
/// 绘制线程只读一份不可变数据，没有锁。
public enum FeedEvent: Sendable {
  case source(MarketSource)
  case routing(MarketRoutingState)
  case historyError(String?)
  case series(BarSeries)          // 整段替换
  case lastBar(Bar)               // 末根更新 / 新根追加
  case prepend(count: Int)        // 前面补了 N 根，视野要平移保持不跳
  case ticker(Ticker)
  case tradeQuote(TradeQuote)
  /// Mark price is independent of last trade price.
  /// 第三位是整帧 `MarkPriceTick`：资金费率、下次结算、指数价、预估结算价都在里面，
  /// 事件时间在 `tick.timeMs`。顶栏的 FR 那一格吃的就是它，不额外发请求。
  case markPrice(symbol: String, price: Double, tick: MarkPriceTick)
  case oi([OIPoint])
  case status(FeedStatus)
}

/// The caller assigns a selection ID before switching, so buffered events from a
/// previous visit (including A → B → A) cannot enter the current chart.
public struct FeedUpdate: Sendable {
  public var selection: UUID
  public var event: FeedEvent
}

/// 把 REST + WS + 内存缓存合成「当前 (品种, 周期)」一条流（§3.1 / §4.4）。
public actor MarketFeed {
  private let includeTicker: Bool
  private let initialLimit: Int
  private let rest: BinanceREST
  private let ws: BinanceWS
  private let cache: BarCache
  private let paths: Paths
  private let pacer: Pacer
  private let log: FeedLog

  private var composer = FeedComposer(series: BarSeries(
    symbol: "", interval: .h1, t0: 0, open: [], high: [], low: [], close: [], volume: []))
  private var selection = UUID()
  private var wsGeneration = UUID()
  private var symbol: String = ""
  private var interval: Interval = .h1
  private var continuation: AsyncStream<FeedUpdate>.Continuation?
  private var wsTask: Task<Void, Never>?
  private var networkGeneration = 0
  private var loadTask: Task<Void, Never>?
  /// ③ 那一发还在路上。它自己就会从快照末根补到现在，WS 连上时别再补一遍。
  private var filling = false
  /// 断过线、还没补回来的那段从哪根开始（0 = 不欠）。
  ///
  /// 为什么记的是**断的那一刻**的末根，而不是发补缺请求那一刻的：WS 一断，当时的末根
  /// 就停在半截上——它剩下的报文（含 `x=true` 那条）全丢在断线窗口里，重连之后推的
  /// 是更靠后的那根，半截的这根再也等不到第二条报文。而 kline 是累计值，断线期间只
  /// 收到一半的那些根，后面随便哪条报文都能自己补齐，唯独断线时正在走的那一根不行。
  /// 等真去发补缺请求时末根早跑到后面去了，从那儿拉只会拿回一根，中间欠的那段
  /// 永远补不回来（`apply(bar:)` 又会把它的报文当乱序丢掉，这根就定格在半截上）。
  private var gapFrom: Int64 = 0
  private var backgroundTask: Task<Void, Never>?
  private var snapshotTask: Task<Void, Never>?
  /// 落盘队列的队尾。写盘全在这条链上串行发生，不占 actor。
  private var snapshotWrite: Task<Void, Never>?
  /// 写盘与「关掉启动快照」之间的互斥闸门。
  private let snapshotGate = SnapshotGate()
  /// 两次落盘之间至少隔这么久。
  private let snapshotThrottleMs: Double = 15_000
  /// 上一次真正把序列交出去落盘的时刻（本地单调时钟）。
  private var lastSnapshotMs = -Double.infinity
  /// 设置页「启动快照」。关掉：不写，并把已有的那份删掉。
  private var snapshotEnabled = true
  /// 旧版 `last.kbar` 清过了没有。快照改成按对存之后它就是死文件。
  private var legacyCleaned = false
  /// 后台加深那一发。换品种、换周期、停机都要取消它。
  private var deepenTask: Task<Void, Never>?
  /// 首屏先拉这么多根。一屏实际只画 40~150 根，1500 根的包在弱网上就是
  /// 「图一直空着」的主因。先要一小页画出来，完整深度另一发并行补，
  /// 两发都落在同一个绝对时间窗里，补在左边不会让视野跳（见 `.prepend` 那段注释）。
  static let firstScreenLimit = 300
  /// 首屏历史最多发几次。上游偶发的 429 / 5xx 退避重试到这个次数为止，
  /// 之后才亮「历史行情暂未加载，点此重试」把决定权交回给用户。
  static let firstFillAttempts = 3
  /// 首屏之后在后台往回多铺到这个根数。
  ///
  /// app 里首发只拉 300 根——够画一屏，弱网上也快。代价是往左一拖就要现拉，
  /// 手指停在边上等。这一步把那次等待挪到用户还在看第一屏的时候做掉。
  /// 一屏 40~150 根，1800 根能往回拖十几屏，够了。再往深挖要多翻一页（权重 10），
  /// 换来的是第 13 屏往后——边际很小，所以停在一页。
  /// 这个数必须 ≤ `Snapshot.maxBars`，否则加深出来的那一段写盘时会被截掉，
  /// 下次冷启动白干。
  static let deepenTarget = 1800
  /// 快照旧到这个程度就不拿来打底了。中间缺的那段靠 `contiguousTail` 补，
  /// 它最多翻 4 页；超过这个跨度补不回来，图上会留个洞，宁可空着等网络。
  static let maxSeedGapBars: Int64 = 3000
  /// 只有 1y 用得上：WS 推的是月线，年线要拿月线重聚（§4.2）。
  private var sourceComposer: FeedComposer?
  /// 逐笔折线的合帧闸门。BTCUSDT 忙的时候一秒上百笔，每笔都往上抛一次
  /// `.lastBar` 会把主线程按在事件处理上；80ms 一拍（12 帧/秒）对肉眼已经是连续的，
  /// 图本身还是跟着 DisplayLink 走 120Hz。开新的一根不受闸门管，立刻放行。
  private var tickFlush: Task<Void, Never>?
  private var tickDirty = false
  private let tickCoalesceMs: Double = 80
  /// 上一次真正把末根抛上去的时刻（走 `nowMs()` 那把钟）。
  private var lastTickEmitMs = -Double.infinity
  /// 注进来的是真时钟吗。真时钟就直接读本地单调时钟，省掉每帧一次的异步调用；
  /// 测试注了虚拟时钟（`StepPacer` / `FastPacer`）才去问它。
  private let systemClock: Bool
  /// REST 对表循环。
  private var reconcileTask: Task<Void, Never>?
  /// 对表跑了第几拍：24h 行情每拍取，K 线每两拍取一次。
  private var reconcileTicks = 0
  /// 最后一笔真成交的撮合时间。挂单心跳只在成交停了之后才顶上。
  private var lastTradeMs: Int64 = 0
  private var lastKlineReceivedMs = -Double.infinity
  private var lastTickerReceivedMs = -Double.infinity
  /// 成交静默多久之后才让挂单接手。
  private let quoteTakeoverMs: Int64 = 3_000
  private let reconcileStepMs: Double

  /// - Parameter reconcileMs: REST 对表的节拍，0 = 不对表。回放测试要的是「WS 报文
  ///   按规矩合出来是什么」，多一路 REST 在旁边改序列就测不出那件事，所以那边传 0。
  public init(rest: BinanceREST, ws: BinanceWS, cache: BarCache = BarCache(),
              paths: Paths = .caches(), pacer: Pacer = SystemPacer(),
              reconcileMs: Double = 5000, includeTicker: Bool = true, initialLimit: Int = BinanceREST.maxKlines, log: FeedLog = .silent) {
    self.includeTicker = includeTicker
    self.initialLimit = min(BinanceREST.maxKlines, max(3, initialLimit))
    self.reconcileStepMs = reconcileMs
    self.rest = rest
    self.ws = ws
    self.cache = cache
    self.paths = paths
    self.pacer = pacer
    self.systemClock = pacer is SystemPacer
    self.log = log
  }

  // ------------------------------------------------------------------ 对外

  public func events() -> AsyncStream<FeedUpdate> {
    let (s, c) = AsyncStream<FeedUpdate>.makeStream(bufferingPolicy: .unbounded)
    continuation = c
    return s
  }

  public var currentSeries: BarSeries { composer.series }

  public func setSnapshotEnabled(_ on: Bool) {
    snapshotEnabled = on
    if on { snapshotGate.enable(); return }
    snapshotTask?.cancel(); snapshotTask = nil
    snapshotWrite?.cancel()
    // 写盘已经挪到别的线程了，删文件必须和它互斥：`disable` 会等在途的那一笔
    // 写完再清盘，清完之后闸门关着，后面排队的那几笔什么都不会写。
    snapshotGate.disable(clearing: paths.series, legacy: paths.snapshot)
  }

  /// 冷启动：先读快照画第一帧，再拉网络（§4.3）。
  public func start(symbol: String, interval: Interval, selection: UUID = UUID()) async {
    await switchTo(symbol: symbol, interval: interval, coldStart: true, selection: selection)
  }

  public func switchTo(symbol newSymbol: String, interval newInterval: Interval, coldStart: Bool = false, selection requested: UUID = UUID()) async {
    guard !Task.isCancelled else { return }
    selection = requested
    writeSnapshotNow()
    loadTask?.cancel()
    deepenTask?.cancel(); deepenTask = nil
    tickFlush?.cancel(); tickFlush = nil; tickDirty = false
    lastTickEmitMs = -.infinity
    lastTradeMs = 0
    lastKlineReceivedMs = -.infinity; lastTickerReceivedMs = -.infinity
    gapFrom = 0
    symbol = newSymbol.uppercased()
    interval = newInterval
    let key = SeriesKey(symbol, interval)

    // ① 内存里有就先画内存的；没有再看快照；都没有就空着等网络。
    var seeded = false
    let cached = await cache.get(key)
    guard current(requested) else { return }
    if let hit = cached {
      composer.replace(hit)
      emit(.series(hit))
      seeded = true
      log("内存命中 \(key) \(hit.count) 根")
    } else if snapshotEnabled, let snap = SeriesStore.read(symbol: symbol, interval: interval, in: paths.series),
              Self.seedUsable(snap, nowMs: await pacer.nowMs()) {
      guard current(requested) else { return }
      composer.replace(snap)
      emit(.series(snap))
      seeded = true
      log("快照命中 \(key) \(snap.count) 根\(coldStart ? "（冷启动）" : "")")
    } else {
      composer.replace(BarSeries(symbol: symbol, interval: interval, t0: 0,
                                 open: [], high: [], low: [], close: [], volume: []))
    }

    sourceComposer = nil
    // ② 换订阅。同一条连接，连接 id 不变。
    await ws.replaceStreams(streamNames())
    guard current(requested) else { return }
    if wsTask == nil { await startWS() }

    guard current(requested) else { return }
    // ③ 网络补齐。
    let sym = symbol, iv = interval, had = seeded ? composer.series.lastTime : 0
    filling = true
    // 图上已经有东西了就别再分两发——那只是多一个请求，省不下任何等待。
    let quick = !seeded
    loadTask = Task { [weak self] in
      await self?.fill(symbol: sym, interval: iv, since: had, selection: requested, quickFirst: quick)
    }
  }

  /// 向前补历史（拖到左边缘时叫）。
  public func loadMore(pages: Int = 1, quiet: Bool = false) async {
    let request = selection
    let sym = symbol, iv = interval
    guard composer.series.count > 0 else { return }
    let first = composer.series.firstTime
    do {
      let bars = try await rest.history(symbol: sym, interval: iv, pages: pages, before: first)
      guard current(request), sym == symbol, iv == interval else { return }
      let n = composer.prepend(bars)
      emit(.historyError(nil))
      if n > 0 {
        await cache.put(composer.series)
        guard current(request) else { return }
        emit(.prepend(count: n))
      }
      log("补历史 \(n) 根，现在 \(composer.series.count) 根")
    } catch {
      guard current(request) else { return }
      // 后台悄悄加深的那一发失败了就算了——用户没在等它，不该为它弹提示。
      if !quiet { emit(.historyError("历史行情暂未加载，点此重试")) }
      log("补历史失败\(quiet ? "（后台加深）" : "")：\(error)")
    }
  }

  /// Keep the series and viewport intact; restart only after a real network transition.
  public func networkChanged(online: Bool) async {
    guard !symbol.isEmpty else { return }
    networkGeneration += 1
    let generation = networkGeneration
    await suspendWS()
    guard online, generation == networkGeneration else { return }
    await startWS()
  }

  /// 进后台后延迟断 WS（§4.4）。iOS 进后台还留约 30 秒运行时间，宿主会用
  /// `beginBackgroundTask` 把这段时间要下来；在窗口内切走再回来就不必重连，
  /// 省掉 DNS + TCP + TLS + 订阅 + 等第一帧的整轮开销。超过窗口才真的挂起。
  static let backgroundGraceMs: Double = 25_000
  /// 进后台后延迟断 WS（§4.4）。
  public func enterBackground() {
    writeSnapshotNow()
    backgroundTask?.cancel()
    backgroundTask = Task { [weak self, pacer] in
      try? await pacer.sleep(ms: Self.backgroundGraceMs)
      guard !Task.isCancelled else { return }
      await self?.suspendWS()
    }
  }

  public func enterForeground() async {
    backgroundTask?.cancel()
    backgroundTask = nil
    // 内存里的序列还在，先把它重新发出去，让图表立刻有东西可画。
    // 下面的补齐是网络往返，不该由它决定用户什么时候看见行情。
    if composer.series.count > 0 { emit(.series(composer.series)) }
    if wsTask == nil { await startWS() } else { startReconcile() }
    await ws.replaceStreams(streamNames())
    let sym = symbol, iv = interval, request = selection
    loadTask?.cancel()
    // 缺口不到一根就别发请求了。切出去看一眼消息再回来是最常见的情形，这时候
    // 末根还是原来那根，WS 一帧（合约 kline 约 250ms 一条）就能把它带回来；
    // 万一 WS 没起来，对表任务 10 秒后也会用 limit=2 把它捞回来。
    // 原来这儿是无条件补缺，等于每次回前台都白花一个请求。
    guard pendingBars() > 1 else {
      log("回前台缺口不足一根，跳过补缺，交给 WS 和对表")
      return
    }
    // 补缺期间把 WS 事件挂起来排队。原来这条路径没有 `beginBackfill`，于是
    // 这一发 REST 在路上的时候 `reconcileOnce` 的 `!composer.isBackfilling`
    // 拦不住它，两边会同时朝同一段末根发请求、各自合并各自的结果。
    composer.beginBackfill()
    loadTask = Task { [weak self] in
      await self?.backfill(symbol: sym, interval: iv, selection: request)
    }
  }

  /// 回前台时还欠多少根。序列空着、另外记着缺口、或者是聚出来的周期（1y），
  /// 一律返回一个大数交给 `backfill` 走完整路径，这儿只负责认出「几乎没缺」。
  private func pendingBars() -> Int {
    guard composer.series.count > 0, gapFrom == 0, interval.source == interval else { return .max }
    let from = composer.series.lastTime
    guard from > 0 else { return .max }
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    return Int(max(0, (now - from) / max(interval.stepMs, 1)) + 1)
  }

  public func memoryWarning() async {
    await cache.purge(keeping: SeriesKey(symbol, interval))
    log("内存警告：只留 \(symbol)|\(interval.rawValue)")
  }

  public func stop() async {
    selection = UUID()
    wsGeneration = UUID()
    writeSnapshotNow()
    loadTask?.cancel(); loadTask = nil
    deepenTask?.cancel(); deepenTask = nil
    backgroundTask?.cancel(); backgroundTask = nil
    stopReconcile()
    tickFlush?.cancel(); tickFlush = nil; tickDirty = false
    wsTask?.cancel(); wsTask = nil
    await ws.stop()
    continuation?.finish()
    continuation = nil
  }

  // ------------------------------------------------------------------ 内部

  private func streamNames() -> [String] {
    // 1y 没有原生流，订 1M（§4.2）。
    let api = interval.source.rawValue
    // Binance's 2026 endpoint split: all three belong to /market, no /public quote mixed in.
    var streams = [BinanceHosts.klineStream(symbol: symbol, interval: api)]
    if includeTicker {
      streams += [BinanceHosts.tickerStream(symbol: symbol), BinanceHosts.markPriceStream(symbol: symbol)]
    }
    return streams
  }

  private func startWS() async {
    startReconcile()
    let generation = UUID()
    wsGeneration = generation
    let stream = await ws.start(streams: streamNames())
    guard wsGeneration == generation, !Task.isCancelled else { return }
    wsTask = Task { [weak self] in
      for await ev in stream {
        guard !Task.isCancelled, let self else { return }
        await self.handle(ev, generation: generation)
      }
    }
  }

  private func suspendWS() async {
    wsGeneration = UUID()
    stopReconcile()
    tickFlush?.cancel(); tickFlush = nil; tickDirty = false
    wsTask?.cancel(); wsTask = nil
    await ws.stop()
    noteGap(at: composer.series.count > 0 ? composer.series.lastTime : 0)
    emit(.status(.offline))
    log("暂停WS，保留当前图表与待补缺口")
  }

  private func handle(_ ev: WSEvent, generation: UUID) async {
    let request = selection
    let received = await nowMs()
    guard current(request), generation == wsGeneration else { return }
    switch ev {
    case .connected:
      // 首连时 switchTo 已经派了一次 fill，别再补一遍（会重复拉 1500 根，而且两次
      // fill 并发谁后到谁说了算）。序列空着是冷启动，序列不空但 fill 还在路上是
      // 「快照打了底」的热启动——两种都归首连，只有重连才需要补缺。
      //
      // 注意这里跳过的只是「这一发补缺」，不是缺口本身：机器忙的时候 fill 要几百
      // 毫秒起，重连完全可能赶在它前头。欠着的那段记在 `gapFrom` 里，`fill` 落地
      // 之后自己会接着补。
      guard !filling, composer.series.count > 0 else { break }
      // 重连成功：先补缺再让 WS 落地（§4.4）。
      composer.beginBackfill()
      let sym = symbol, iv = interval
      Task { [weak self] in await self?.backfill(symbol: sym, interval: iv, selection: request) }
    case .status(let s):
      // 断了：从当时的末根起就不可信了——那根是半截的，它之后的整段没收到。
      if s != .live, composer.series.count > 0 { noteGap(at: composer.series.lastTime) }
      emit(.status(s))
    case .payload(let p):
      switch p {
      case .kline(let k):
        guard k.symbol.uppercased() == symbol, k.interval == interval.source.rawValue else { return }
        guard k.bar.isValidMarketBar else { return }
        lastKlineReceivedMs = received
        if k.eventTime > 0, let id = k.lastTradeID {
          emit(.tradeQuote(TradeQuote(symbol: symbol, price: k.bar.close, timeMs: k.eventTime, tradeID: id)))
        }
        applyKline(k, now: received)
      case .ticker(let t):
        if t.symbol.uppercased() == symbol {
          lastTickerReceivedMs = received
          emit(.ticker(t))
        }
      case .markPrice(let s, let px, let tick):
        if s.uppercased() == symbol { emit(.markPrice(symbol: s, price: px, tick: tick)) }
      case .trade(let t):
        guard t.symbol.uppercased() == symbol else { return }
        lastTradeMs = max(lastTradeMs, t.timeMs)
        foldTick(price: t.price, qty: t.qty, timeMs: t.timeMs, allowAppend: true,
                 tradeID: t.tradeID, now: received)
      case .bookTicker(let s, let bid, let ask, let ms):
        guard s.uppercased() == symbol, bid.isFinite, ask.isFinite, bid > 0, ask > 0, bid <= ask
        else { return }
        // 成交还在推就别插手：真成交价才是最新价。
        guard ms - lastTradeMs > quoteTakeoverMs else { return }
        // 顶上来的时候取**贴着盘口的那一侧**，不取中间价：BTCUSDT 的价差就是一个
        // 最小变动价位，中间价永远落在半个 tick 上，顶栏会显示一个从没成交过的价。
        // 把上一个价夹进买一卖一之间——盘口往上走就跟着买一，往下走就跟着卖一，
        // 盘口没越过它就一动不动。
        guard composer.series.count > 0 else { return }
        let cur = composer.series.close[composer.series.count - 1]
        let px = min(max(cur, bid), ask)
        guard px != cur else { return }
        foldTick(price: px, qty: 0, timeMs: ms, allowAppend: false, now: received)
      case .tickerBatch:
        break
      case .other:
        break
      }
    }
  }

  /// 记一个缺口。已经欠着更早的就按更早的算。
  private func noteGap(at t: Int64) {
    guard t > 0 else { return }
    gapFrom = gapFrom > 0 ? min(gapFrom, t) : t
  }

  /// 取走缺口起点，没欠着就用 `fallback`（当前末根）。取走即清，补失败的那条路上
  /// 再记回去——留着的话 `fill` 末尾那次补缺会和 1M/1y 的整段重拉互相叫下去。
  private func takeGap(orElse fallback: Int64) -> Int64 {
    let t = gapFrom > 0 ? min(gapFrom, fallback) : fallback
    gapFrom = 0
    return t
  }

  private func applyKline(_ k: KlineEvent, now: Double) {
    // 年线是聚出来的：WS 推的是月线，收一条就把当年那根重算（§4.2）。
    if interval == .y1 {
      guard var monthly = sourceComposer, monthly.series.count > 0 else { return }
      guard monthly.apply(k) else { return }
      sourceComposer = monthly
      composer.replace(Aggregator.bucket(series: monthly.series, into: .y1))
      emit(.historyError(nil))
      emit(.series(composer.series))
      scheduleSnapshot()
      return
    }
    let before = composer.series.count > 0 ? composer.series.lastTime : 0
    guard composer.apply(k) else { return }
    // 同一根上的更新走合帧闸门；**开新的一根立刻放行**。
    //
    // 原来 kline 一律 `force: true`，等于 WS 那条最密的流完全绕开了 80ms 闸门：
    // 忙的时候一秒上百条报文，每条都往主线程抛一次 `.lastBar`。而逐笔（`foldTick`）
    // 早就是合帧的——两条路推的是同一根 K 线，没道理一条限速一条不限。
    //
    // 开新根是结构性变化（时间戳变了，图上要多出一根），晚 80ms 收线肉眼就是
    // 「顿一下」，所以它不受闸门管，和 `foldTick` 的 `.appended` 同一个规矩。
    emitTick(force: composer.series.lastTime != before, now: now)
    scheduleSnapshot()
  }

  // ------------------------------------------------------------------ 逐笔折线

  /// 一次报价折进当前那根（细节见 `FeedComposer.applyTick`）。
  private func foldTick(price: Double, qty: Double, timeMs: Int64, allowAppend: Bool,
                        tradeID: Int64? = nil, now: Double) {
    // 1y 是聚出来的：折进月线源，再把当年那根重算（和 applyKline 一个路数，§4.2）。
    if interval == .y1 {
      guard var src = sourceComposer, src.series.count > 0 else { return }
      guard src.applyTick(price: price, qty: qty, timeMs: timeMs, allowAppend: allowAppend, tradeID: tradeID) != .ignored
      else { return }
      sourceComposer = src
      composer.replace(Aggregator.bucket(series: src.series, into: .y1))
      emit(.historyError(nil))
      emit(.series(composer.series))
      scheduleSnapshot()
      return
    }
    switch composer.applyTick(price: price, qty: qty, timeMs: timeMs, allowAppend: allowAppend, tradeID: tradeID) {
    case .ignored:
      return
    case .updated:
      emitTick(force: false, now: now)
    case .appended:
      // 开新的一根是结构性变化，不进合帧闸门——晚 80ms 收线会看见图「顿一下」。
      emitTick(force: true, now: now)
      log("逐笔开新根 \(composer.series.lastTime)，现在 \(composer.series.count) 根")
    }
    scheduleSnapshot()
  }

  /// 合帧后往上抛末根。`force` 用于开新根这种不能等的事件。
  ///
  /// 闸门量的是**两次抛出之间隔了多久**（用注进来的那把钟），不是「有没有一个
  /// 定时任务挂着」。差别在于：报文密的时候两者一样都是 80ms 一拍；报文稀
  /// （真机上单品种 kline 大约一秒一条）的时候，前者每条都立刻放行，后者却要看
  /// 定时任务的调度延迟——那不是设计，是运气。
  private func emitTick(force: Bool, now: Double) {
    guard composer.series.count > 0 else { return }
    if force || now - lastTickEmitMs >= tickCoalesceMs {
      tickFlush?.cancel(); tickFlush = nil
      tickDirty = false
      lastTickEmitMs = now
      pushLastBar()
      return
    }
    // 还在这一拍里：攒着，到拍子末尾收口。在途最多一发。
    tickDirty = true
    guard tickFlush == nil else { return }
    let wait = tickCoalesceMs - (now - lastTickEmitMs)
    let request = selection
    tickFlush = Task { [weak self, pacer] in
      try? await pacer.sleep(ms: wait)
      guard !Task.isCancelled else { return }
      await self?.tickFlushed(selection: request)
    }
  }

  private func tickFlushed(selection request: UUID) async {
    tickFlush = nil
    guard current(request), tickDirty else { return }
    tickDirty = false
    lastTickEmitMs = await nowMs()
    pushLastBar()
  }

  private func pushLastBar() {
    guard composer.series.count > 0 else { return }
    let b = composer.series.bar(at: composer.series.count - 1)
    emit(.lastBar(b))
  }

  // ------------------------------------------------------------------ REST 对表

  /// REST is a fallback for silent market streams. Healthy WS kline frames carry
  /// authoritative cumulative OHLCV; polling must not overwrite them with older snapshots.
  private func startReconcile() {
    reconcileTask?.cancel()
    reconcileTask = nil
    reconcileTicks = 0
    guard reconcileStepMs > 0 else { return }
    let step = reconcileStepMs
    reconcileTask = Task { [weak self, pacer] in
      while !Task.isCancelled {
        try? await pacer.sleep(ms: step)
        guard !Task.isCancelled else { return }
        await self?.reconcileOnce()
      }
    }
  }

  private func stopReconcile() {
    reconcileTask?.cancel()
    reconcileTask = nil
  }

  private func reconcileOnce() async {
    let request = selection
    let sym = symbol, iv = interval
    guard !sym.isEmpty, composer.series.count > 0, !composer.isBackfilling else { return }
    reconcileTicks += 1

    let now = await nowMs()
    let tickerStamp = lastTickerReceivedMs
    if includeTicker, now - tickerStamp >= 5000,
       let t = try? await rest.ticker24h(symbol: sym), current(request), sym == symbol, iv == interval,
       lastTickerReceivedMs == tickerStamp {
      emit(.ticker(t))
    }

    // K 线两拍取一次，而且只有等距周期走这条——1y 得整段重聚，交给 fill。
    guard reconcileTicks % 2 == 0, iv.source == iv, sym == symbol, iv == interval else { return }
    let klineStamp = lastKlineReceivedMs
    guard now - klineStamp >= 10000 else { return }
    let from = composer.series.lastTime
    guard from > 0 else { return }
    do {
      let bars = try await rest.klines(symbol: sym, interval: iv, limit: 2, startTime: from)
      guard current(request), sym == symbol, iv == interval, !composer.isBackfilling,
            lastKlineReceivedMs == klineStamp else { return }
      if composer.reconcile(bars) {
        await cache.put(composer.series)
        guard current(request) else { return }
        emitTick(force: true, now: await nowMs())
      }
    } catch {
      log("对表失败：\(error)")
    }
  }

  /// 拉满一屏，完了把欠着的缺口补上。
  ///
  /// 后半截是为重连撞上首发 fill 那一下准备的：那会儿 `handle(.connected)` 只能跳过
  /// 补缺（两发 fill 并发谁后到谁说了算），缺口记在 `gapFrom` 里没人管。而这一发
  /// fill 拿到的是「它自己发请求那一刻」的快照，盖不住断线窗口里丢掉的那根——
  /// 不在这儿补一次，那根就永远定格在半截上。
  private func fill(symbol sym: String, interval iv: Interval, since: Int64, selection request: UUID,
                    quickFirst: Bool = false) async {
    guard current(request) else { return }
    await fillOnce(symbol: sym, interval: iv, since: since, selection: request, quickFirst: quickFirst)
    guard current(request), gapFrom > 0, sym == symbol, iv == interval, !composer.isBackfilling else { return }
    composer.beginBackfill()
    await backfill(symbol: sym, interval: iv, selection: request)
  }

  /// 首屏小页落地。只在图还空着的时候画——完整那发已经到了就什么都不做，
  /// 免得用一份更浅的历史把已经铺开的序列盖回去。
  private func applyFirstScreen(_ bars: [Bar], symbol sym: String, interval iv: Interval,
                                selection request: UUID) {
    guard current(request), sym == symbol, iv == interval else { return }
    guard composer.series.count == 0, !bars.isEmpty else { return }
    if iv.source != iv {
      sourceComposer = FeedComposer(series: BarSeries(symbol: sym, interval: iv.source, bars: BinanceREST.dedup(bars)))
      composer.replace(Aggregator.bucket(series: sourceComposer!.series, into: iv))
    } else {
      composer.merge(bars)
    }
    emit(.historyError(nil))
    emit(.series(composer.series))
    log("首屏 \(bars.count) 根先落地 \(sym)|\(iv.rawValue)")
  }

  /// 快照还能不能拿来打底：中间欠的那段要在 `contiguousTail` 的翻页能力之内。
  static func seedUsable(_ snap: BarSeries, nowMs: Double) -> Bool {
    guard snap.count > 0 else { return false }
    let step = snap.interval.source.stepMs
    guard step > 0 else { return false }
    let gap = Int64(nowMs) - snap.lastTime
    guard gap > 0 else { return true }
    return gap / step <= maxSeedGapBars
  }

  /// 拉满一屏。`since > 0` 时并行启动快照到现在的缺口回补（§4.3 冷启动时序）。
  private func fillOnce(symbol sym: String, interval iv: Interval, since: Int64, selection request: UUID,
                        quickFirst: Bool = false) async {
    guard current(request) else { return }
    defer { if current(request), sym == symbol, iv == interval { filling = false } }
    // 首屏小页：和完整那发并行发出去，谁先回谁先画。它只在图还空着时落地，
    // 完整那发要是先回来，这一发回来什么都不做。
    let quickTask: Task<[Bar], Error>? = (quickFirst && initialLimit > Self.firstScreenLimit)
      ? Task { [rest] in try await rest.klines(symbol: sym, interval: iv, limit: Self.firstScreenLimit) }
      : nil
    defer { quickTask?.cancel() }
    if let quickTask {
      Task { [weak self] in
        guard let bars = try? await quickTask.value else { return }
        await self?.applyFirstScreen(bars, symbol: sym, interval: iv, selection: request)
      }
    }
    // 启动快照缺口请求，但不要等待它挡住最新窗口。BinanceREST / transport
    // 都是 actor，可重入地让两个请求同时在路上；首屏先用最新窗口，缺口回来后再合并。
    let gapTask: Task<[Bar], Error>? = (since > 0 && iv.source == iv)
      ? Task { [rest] in try await rest.contiguousTail(symbol: sym, interval: iv, from: since) }
      : nil
    if gapTask != nil { await Task.yield() }
    do {
      // 先取最新窗口并发布，让用户先看到当前行情；快照到现在的旧缺口
      // 另行补齐。旧实现把这两步串成“先补缺、再取最新”，直连黑洞时
      // 会让实时尾部在动、整张历史却迟迟没有首屏。
      let revision = composer.wsRevision
      let sourceRevision = sourceComposer?.wsRevision
      // 首屏历史是整张图的地基：这一发拿不到，图上就只剩 WS 推来的那一根
      // （诊断里的 `bars: 1`），而实时价、成交量、持仓量各走各的路，照样有数，
      // 看上去就像「只有 K 线没加载」。上游一个随机的 429/5xx 不该把图钉死在
      // 那儿等用户去点横幅，所以这里自己退避重试几轮。只在失败路径上生效，
      // 顺利的首屏一次也不会多等。
      var bars: [Bar] = []
      var attempt = 0
      while true {
        attempt += 1
        do { bars = try await rest.klines(symbol: sym, interval: iv, limit: initialLimit); break }
        catch is CancellationError { throw CancellationError() }
        catch {
          guard current(request), sym == symbol, iv == interval, !Task.isCancelled else { throw CancellationError() }
          guard attempt < Self.firstFillAttempts else { throw error }
          log("首屏历史第 \(attempt) 发失败，退避重试：\(error)")
          try await pacer.sleep(ms: Double(attempt) * 1000)
        }
      }
      guard current(request), sym == symbol, iv == interval else { return }
      if iv.source != iv {
        let src = BarSeries(symbol: sym, interval: iv.source, bars: BinanceREST.dedup(bars))
        if var source = sourceComposer {
          source.merge(bars, preservingLiveTail: source.wsRevision != sourceRevision)
          sourceComposer = source
        } else { sourceComposer = FeedComposer(series: src) }
        composer.replace(Aggregator.bucket(series: sourceComposer!.series, into: iv))
      } else {
        sourceComposer = nil
        composer.merge(bars, preservingLiveTail: composer.wsRevision != revision)
      }
      await cache.put(composer.series)
      guard current(request) else { return }
      emit(.historyError(nil))
      emit(.series(composer.series))
      scheduleSnapshot()
    } catch is CancellationError {
      gapTask?.cancel()
      return
    } catch {
      gapTask?.cancel()
      guard current(request), !Task.isCancelled else { return }
      log("拉 \(sym)|\(iv.rawValue) 失败：\(error)")
      emit(.historyError("历史行情暂未加载，点此重试"))
      emit(.status(.offline))
      return
    }

    // 聚出来的周期（1y）没有可直接对齐的历史缺口；其它周期在最新窗口
    // 已显示后再补快照缺口。缺口失败时保留最新序列和实时 WS，不把整条
    // 可用行情降级为离线。
    if since > 0, iv.source == iv {
      do {
        let revision = composer.wsRevision
        let gap: [Bar]
        if let gapTask { gap = try await gapTask.value }
        else { gap = try await rest.contiguousTail(symbol: sym, interval: iv, from: since) }
        guard current(request), sym == symbol, iv == interval else { return }
        composer.merge(gap, preservingLiveTail: composer.wsRevision != revision)
        await cache.put(composer.series)
        emit(.historyError(nil))
        emit(.series(composer.series))
        log("补缺 startTime=\(since) → \(gap.count) 根")
      } catch is CancellationError {
        return
      } catch {
        guard current(request), !Task.isCancelled else { return }
        log("补缺失败，保留最新行情：\(error)")
        emit(.historyError("行情缺口暂未补齐，点此重试"))
      }
    }

    scheduleDeepen(symbol: sym, interval: iv, selection: request)

    // 历史序列已经落地后，ticker 只是顶栏校准。它失败不能把一张可用的
    // K 线降级成「历史失败/离线」，否则正好会出现“最新在动、历史提示失败”
    // 并触发不必要的整条线路切换。
    guard includeTicker else { return }
    do {
      let tickerStamp = lastTickerReceivedMs
      let t = try await rest.ticker24h(symbol: sym)
      if current(request), sym == symbol, lastTickerReceivedMs == tickerStamp { emit(.ticker(t)) }
    } catch is CancellationError {
      return
    } catch {
      guard current(request), !Task.isCancelled else { return }
      log("校准报价失败 \(sym)|\(iv.rawValue)，保留已加载历史：\(error)")
    }
  }

  /// 首屏落地之后，后台悄悄再往回拉一页。
  ///
  /// 补在左边不会让视野跳（视野是绝对时间窗，见 `.prepend` 那段注释），所以
  /// 用户完全无感；等他真把图拖到左边缘时，那段历史已经在内存里了。
  /// 失败不报错——没人在等它。
  private func scheduleDeepen(symbol sym: String, interval iv: Interval, selection request: UUID) {
    deepenTask?.cancel()
    guard current(request), composer.series.count > 0, composer.series.count < Self.deepenTarget else { return }
    // 首发本身已经按单请求上限要过一整页了，再翻一页只是多花一个权重 10 的请求
    // 换第 13 屏往后——边际很小。只有首发拉得浅（两段式的 300 根档、OKX 那条路）
    // 才值得在后台补这一页。这条保证「首屏改深」不会把请求数和权重顶上去。
    guard initialLimit < BinanceREST.maxKlines else { return }
    deepenTask = Task { [weak self, pacer] in
      // 让实时报文和 ticker 先走，别和首屏抢带宽。
      try? await pacer.sleep(ms: 1200)
      guard !Task.isCancelled else { return }
      await self?.deepen(symbol: sym, interval: iv, selection: request)
    }
  }

  private func deepen(symbol sym: String, interval iv: Interval, selection request: UUID) async {
    guard current(request), sym == symbol, iv == interval else { return }
    guard composer.series.count > 0, composer.series.count < Self.deepenTarget else { return }
    await loadMore(quiet: true)
    guard current(request), sym == symbol, iv == interval else { return }
    scheduleSnapshot()
  }

  /// 重连 / 回前台后补缺：从末根开始重拉，排队的 WS 事件补完再放行。
  private func backfill(symbol sym: String, interval iv: Interval, selection request: UUID) async {
    guard current(request) else { return }
    // 先取走缺口：下面几条路都不能把它留着，不然会和 `fill` 末尾那次补缺叫下去。
    let from = takeGap(orElse: composer.series.count > 0 ? composer.series.lastTime : 0)
    guard iv.source == iv, composer.series.count > 0, from > 0 else {
      composer.endBackfill(with: [])
      await fillOnce(symbol: sym, interval: iv, since: 0, selection: request)
      return
    }
    do {
      let bars = try await rest.contiguousTail(symbol: sym, interval: iv, from: from)
      guard current(request), sym == symbol, iv == interval else { return }
      let added = composer.endBackfill(with: bars)
      await cache.put(composer.series)
      guard current(request) else { return }
      emit(.series(composer.series))
      emit(.historyError(nil))
      log("补缺 startTime=\(from) → \(bars.count) 根，净增 \(added)，队列已合并")
    } catch {
      guard current(request) else { return }
      emit(.historyError("行情缺口暂未补齐，点此重试"))
      log("补缺失败：\(error)")
      composer.endBackfill(with: [])
      noteGap(at: from)          // 没补成，这段还欠着
    }
  }

  // ------------------------------------------------------------------ 快照

  /// 快照落盘的**节流**（§4.3）。
  ///
  /// 原来是防抖：每收一帧就把 2 秒的定时器取消重排。可 BTCUSDT 忙的时候一秒上百笔，
  /// 报文间隔远小于 2 秒 —— 那个定时器永远排不到头，**正在看的那个品种几乎从来不落盘**，
  /// 反倒是没人看的冷门品种才写得下去。冷启动想秒开的恰恰是热门品种，整件事是反的。
  ///
  /// 现在改成节流：距上次落盘已经 ≥ `snapshotThrottleMs` 就立刻写；不到就排一发到
  /// 「上次 + 间隔」那个点，在途最多一发，后来的帧只是搭这班车，不再重排。
  /// 于是无论报文多密，磁盘最多每 15 秒被碰一次，而热门品种一定写得下去。
  private func scheduleSnapshot() {
    guard snapshotEnabled else { return }
    let elapsed = Self.monotonicMs() - lastSnapshotMs
    if elapsed >= snapshotThrottleMs { writeSnapshotNow(); return }
    // 已经有一发在途了，搭它的车——不重排，不然又变回防抖。
    guard snapshotTask == nil else { return }
    let wait = snapshotThrottleMs - elapsed
    snapshotTask = Task { [weak self, pacer] in
      try? await pacer.sleep(ms: wait)
      guard !Task.isCancelled else { return }
      await self?.snapshotDeadline()
    }
  }

  private func snapshotDeadline() {
    snapshotTask = nil
    writeSnapshotNow()
  }

  /// 把当前序列排进落盘队列。**不等磁盘**。
  ///
  /// 原来这儿是同步写：`Snapshot.encode` 把几千根编成几百 KB，再做一次原子写
  /// （临时文件 + 替换），还可能顺带触发 `SeriesStore.prune` 那次 60 秒一回的
  /// 目录扫描。而调用它的第一个地方是 `switchTo` 的第一行——用户点下一个品种、
  /// 手指还按在屏幕上的那一刻，整条 feed actor 就卡在磁盘上。
  ///
  /// 现在把序列（值类型，拷出去就跟 actor 无关了）交给一条 utility 优先级的
  /// detached 任务。顺序靠 `await previous?.value` 串起来：同一条 feed 的写盘
  /// 严格按提交顺序发生，所以换品种之前那一份旧序列绝不会落在新序列后面。
  /// 落的文件本来也是按 (品种, 周期) 分开的，串行只是再堵死同一个 key 的乱序。
  /// 快照最少要几根。和 `RoutedMarketFeed` 放行一条线路的门槛（3 根）对齐：
  /// 存不出第一帧的快照没有意义，只会覆盖掉上一份能用的。
  static let snapshotFloor = 3

  private func writeSnapshotNow() {
    snapshotTask?.cancel()
    snapshotTask = nil
    // 至少要 `snapshotFloor` 根才值得落盘。快照存在的唯一理由是「下次点进来第一帧
    // 就有图」，而 `RoutedMarketFeed` 要收够 3 根才肯把这条线路的图交给界面——不到
    // 这个数的快照画不出第一帧，却会把上一次那份好的覆盖掉。首屏 429 拉不到历史时
    // 正好撞上这一条：序列里只剩 WS 推来的那一根，落盘之后下次冷启动读回来还是
    // 一根，图就永远停在「行情加载中」。宁可不存。
    guard snapshotEnabled, composer.series.count >= Self.snapshotFloor else { return }
    lastSnapshotMs = Self.monotonicMs()
    let series = composer.series
    let dir = paths.series
    let legacy = paths.snapshot
    let cleanLegacy = !legacyCleaned
    if cleanLegacy { legacyCleaned = true }
    let log = self.log
    let gate = snapshotGate
    let previous = snapshotWrite
    snapshotWrite = Task.detached(priority: .utility) {
      _ = await previous?.value
      guard !Task.isCancelled else { return }
      do {
        guard let n = try gate.write(series, in: dir) else { return }
        // 旧版只有一份 `last.kbar`，按对存之后它就是死文件，清一次。
        if cleanLegacy { Snapshot.remove(legacy) }
        log("快照 \(n)B → \(series.symbol)|\(series.interval.rawValue)")
      } catch {
        log("写快照失败：\(error)")
      }
    }
  }


  /// 进程内单调时钟，毫秒。
  ///
  /// 这些地方要的只是「两件事之间隔了多久」。`Pacer` 是给**可控睡眠**用的协议，
  /// 拿它当钟表读，每读一次就是一次跨 actor 的 `await`（读一个 `DispatchTime` 而已，
  /// 却要挂起、切执行器、再恢复）。单调时钟不跨 actor，也不受系统时间被改动影响。
  static func monotonicMs() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

  /// 当前时刻，毫秒。真机上就是上面那把单调钟（和 `SystemPacer.nowMs()` 同一个量），
  /// 只有测试注了虚拟时钟时才真的去问 `pacer`——回放用例要在被加速的时间里
  /// 观察合帧闸门，那把钟不能被绕过。
  private func nowMs() async -> Double {
    systemClock ? Self.monotonicMs() : await pacer.nowMs()
  }

  private func current(_ id: UUID) -> Bool { selection == id && !Task.isCancelled }

  private func emit(_ e: FeedEvent) { continuation?.yield(FeedUpdate(selection: selection, event: e)) }
}

/// 快照落盘的开关兼互斥锁。
///
/// 写盘已经挪到 feed actor 之外的 detached 任务里（换品种那一下不能卡在磁盘上），
/// 而「设置页关掉启动快照」要求立刻把磁盘上的那几份删干净。这两件事必须互斥：
/// 不然删完之后一笔在途的写又把文件建回来，用户关了开关磁盘上照样有东西。
///
/// 锁只在真正写/删的那一小段里握着，feed actor 不碰它。
final class SnapshotGate: @unchecked Sendable {
  private let lock = NSLock()
  private var enabled = true

  /// 写一份。闸门关着就什么都不做，返回 nil。
  func write(_ series: BarSeries, in dir: URL) throws -> Int? {
    lock.lock(); defer { lock.unlock() }
    guard enabled else { return nil }
    return try SeriesStore.write(series, in: dir)
  }

  /// 关闸并清盘。会等在途的那一笔写完。
  func disable(clearing dir: URL, legacy: URL) {
    lock.lock(); defer { lock.unlock() }
    enabled = false
    Snapshot.remove(legacy)
    SeriesStore.clear(in: dir)
  }

  func enable() {
    lock.lock(); defer { lock.unlock() }
    enabled = true
  }
}
