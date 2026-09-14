import Foundation
import KanpanCore

/// 图表侧收到的东西（§3.1）。`BarSeries` 是值类型快照，每次事件换一份，
/// 绘制线程只读一份不可变数据，没有锁。
public enum FeedEvent: Sendable {
  case series(BarSeries)          // 整段替换
  case lastBar(Bar)               // 末根更新 / 新根追加
  case prepend(count: Int)        // 前面补了 N 根，视野要平移保持不跳
  case ticker(Ticker)
  case tradeQuote(TradeQuote)
  /// Mark price is independent of last trade price.
  case markPrice(symbol: String, price: Double, timeMs: Int64)
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
  /// 设置页「启动快照」。关掉：不写，并把已有的那份删掉。
  private var snapshotEnabled = true
  /// 只有 1y 用得上：WS 推的是月线，年线要拿月线重聚（§4.2）。
  private var sourceComposer: FeedComposer?
  /// 逐笔折线的合帧闸门。BTCUSDT 忙的时候一秒上百笔，每笔都往上抛一次
  /// `.lastBar` 会把主线程按在事件处理上；80ms 一拍（12 帧/秒）对肉眼已经是连续的，
  /// 图本身还是跟着 DisplayLink 走 120Hz。开新的一根不受闸门管，立刻放行。
  private var tickFlush: Task<Void, Never>?
  private var tickDirty = false
  private let tickCoalesceMs: Double = 80
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
              reconcileMs: Double = 5000, includeTicker: Bool = true, log: FeedLog = .silent) {
    self.includeTicker = includeTicker
    self.reconcileStepMs = reconcileMs
    self.rest = rest
    self.ws = ws
    self.cache = cache
    self.paths = paths
    self.pacer = pacer
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
    if !on { Snapshot.remove(paths.snapshot) }
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
    tickFlush?.cancel(); tickFlush = nil; tickDirty = false
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
    } else if coldStart, snapshotEnabled, let snap = Snapshot.read(paths.snapshot),
              snap.symbol == symbol, snap.interval == interval {
      composer.replace(snap)
      emit(.series(snap))
      seeded = true
      log("快照命中 \(key) \(snap.count) 根")
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
    loadTask = Task { [weak self] in await self?.fill(symbol: sym, interval: iv, since: had, selection: requested) }
  }

  /// 向前补历史（拖到左边缘时叫）。
  public func loadMore(pages: Int = 1) async {
    let request = selection
    let sym = symbol, iv = interval
    guard composer.series.count > 0 else { return }
    let first = composer.series.firstTime
    do {
      let bars = try await rest.history(symbol: sym, interval: iv, pages: pages, before: first)
      guard current(request), sym == symbol, iv == interval else { return }
      let n = composer.prepend(bars)
      if n > 0 {
        await cache.put(composer.series)
        guard current(request) else { return }
        emit(.prepend(count: n))
      }
      log("补历史 \(n) 根，现在 \(composer.series.count) 根")
    } catch {
      log("补历史失败：\(error)")
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

  /// 进后台 5 秒后断 WS（§4.4）。
  public func enterBackground() {
    writeSnapshotNow()
    backgroundTask?.cancel()
    backgroundTask = Task { [weak self, pacer] in
      try? await pacer.sleep(ms: 5000)
      guard !Task.isCancelled else { return }
      await self?.suspendWS()
    }
  }

  public func enterForeground() async {
    backgroundTask?.cancel()
    backgroundTask = nil
    if wsTask == nil { await startWS() } else { startReconcile() }
    await ws.replaceStreams(streamNames())
    let sym = symbol, iv = interval, request = selection
    loadTask?.cancel()
    loadTask = Task { [weak self] in
      await self?.backfill(symbol: sym, interval: iv, selection: request)
    }
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
    let received = await pacer.nowMs()
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
        applyKline(k)
      case .ticker(let t):
        if t.symbol.uppercased() == symbol {
          lastTickerReceivedMs = received
          emit(.ticker(t))
        }
      case .markPrice(let s, let px, let ms):
        if s.uppercased() == symbol { emit(.markPrice(symbol: s, price: px, timeMs: ms)) }
      case .trade(let t):
        guard t.symbol.uppercased() == symbol else { return }
        lastTradeMs = max(lastTradeMs, t.timeMs)
        foldTick(price: t.price, qty: t.qty, timeMs: t.timeMs, allowAppend: true, tradeID: t.tradeID)
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
        foldTick(price: px, qty: 0, timeMs: ms, allowAppend: false)
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

  private func applyKline(_ k: KlineEvent) {
    // 年线是聚出来的：WS 推的是月线，收一条就把当年那根重算（§4.2）。
    if interval == .y1 {
      guard var monthly = sourceComposer, monthly.series.count > 0 else { return }
      guard monthly.apply(k) else { return }
      sourceComposer = monthly
      composer.replace(Aggregator.bucket(series: monthly.series, into: .y1))
      emit(.series(composer.series))
      scheduleSnapshot()
      return
    }
    guard composer.apply(k) else { return }
    emitTick(force: true)
    scheduleSnapshot()
  }

  // ------------------------------------------------------------------ 逐笔折线

  /// 一次报价折进当前那根（细节见 `FeedComposer.applyTick`）。
  private func foldTick(price: Double, qty: Double, timeMs: Int64, allowAppend: Bool, tradeID: Int64? = nil) {
    // 1y 是聚出来的：折进月线源，再把当年那根重算（和 applyKline 一个路数，§4.2）。
    if interval == .y1 {
      guard var src = sourceComposer, src.series.count > 0 else { return }
      guard src.applyTick(price: price, qty: qty, timeMs: timeMs, allowAppend: allowAppend, tradeID: tradeID) != .ignored
      else { return }
      sourceComposer = src
      composer.replace(Aggregator.bucket(series: src.series, into: .y1))
      emit(.series(composer.series))
      scheduleSnapshot()
      return
    }
    switch composer.applyTick(price: price, qty: qty, timeMs: timeMs, allowAppend: allowAppend, tradeID: tradeID) {
    case .ignored:
      return
    case .updated:
      emitTick(force: false)
    case .appended:
      // 开新的一根是结构性变化，不进合帧闸门——晚 80ms 收线会看见图「顿一下」。
      emitTick(force: true)
      log("逐笔开新根 \(composer.series.lastTime)，现在 \(composer.series.count) 根")
    }
    scheduleSnapshot()
  }

  /// 合帧后往上抛末根。`force` 用于开新根这种不能等的事件。
  private func emitTick(force: Bool) {
    guard composer.series.count > 0 else { return }
    if force {
      tickFlush?.cancel(); tickFlush = nil; tickDirty = false
      pushLastBar()
      return
    }
    guard tickFlush == nil else { tickDirty = true; return }
    pushLastBar()
    let request = selection
    let gap = tickCoalesceMs
    tickFlush = Task { [weak self, pacer] in
      try? await pacer.sleep(ms: gap)
      guard !Task.isCancelled else { return }
      await self?.tickFlushed(selection: request)
    }
  }

  private func tickFlushed(selection request: UUID) {
    guard current(request) else { return }
    tickFlush = nil
    guard tickDirty else { return }
    tickDirty = false
    emitTick(force: false)
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

    let now = await pacer.nowMs()
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
        emitTick(force: true)
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
  private func fill(symbol sym: String, interval iv: Interval, since: Int64, selection request: UUID) async {
    guard current(request) else { return }
    await fillOnce(symbol: sym, interval: iv, since: since, selection: request)
    guard current(request), gapFrom > 0, sym == symbol, iv == interval, !composer.isBackfilling else { return }
    composer.beginBackfill()
    await backfill(symbol: sym, interval: iv, selection: request)
  }

  /// 拉满一屏。`since > 0` 时先补快照到现在的缺口（§4.3 冷启动时序）。
  private func fillOnce(symbol sym: String, interval iv: Interval, since: Int64, selection request: UUID) async {
    guard current(request) else { return }
    defer { if current(request), sym == symbol, iv == interval { filling = false } }
    do {
      // 聚出来的周期（1y）没法拿月线往年线上合，直接整段重拉重聚。
      if since > 0, iv.source == iv {
        let revision = composer.wsRevision
        let gap = try await rest.klines(symbol: sym, interval: iv, limit: BinanceREST.maxKlines, startTime: since)
        guard current(request), sym == symbol, iv == interval else { return }
        composer.merge(gap, preservingLiveTail: composer.wsRevision != revision)
        log("补缺 startTime=\(since) → \(gap.count) 根")
      }
      let revision = composer.wsRevision
      let sourceRevision = sourceComposer?.wsRevision
      let bars = try await rest.klines(symbol: sym, interval: iv, limit: BinanceREST.maxKlines)
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
      emit(.series(composer.series))
      scheduleSnapshot()

      guard includeTicker else { return }
      let tickerStamp = lastTickerReceivedMs
      let t = try await rest.ticker24h(symbol: sym)
      if current(request), sym == symbol, lastTickerReceivedMs == tickerStamp { emit(.ticker(t)) }
    } catch {
      guard current(request) else { return }
      log("拉 \(sym)|\(iv.rawValue) 失败：\(error)")
      emit(.status(.offline))
    }
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
      let bars = try await rest.klines(symbol: sym, interval: iv, limit: BinanceREST.maxKlines, startTime: from)
      guard current(request), sym == symbol, iv == interval else { return }
      let added = composer.endBackfill(with: bars)
      await cache.put(composer.series)
      guard current(request) else { return }
      emit(.series(composer.series))
      log("补缺 startTime=\(from) → \(bars.count) 根，净增 \(added)，队列已合并")
    } catch {
      guard current(request) else { return }
      log("补缺失败：\(error)")
      composer.endBackfill(with: [])
      noteGap(at: from)          // 没补成，这段还欠着
    }
  }

  // ------------------------------------------------------------------ 快照

  /// 合并 2 秒内的写（§4.3）。
  private func scheduleSnapshot() {
    guard snapshotEnabled else { return }
    snapshotTask?.cancel()
    snapshotTask = Task { [weak self, pacer] in
      try? await pacer.sleep(ms: 2000)
      guard !Task.isCancelled else { return }
      await self?.writeSnapshotNow()
    }
  }

  private func writeSnapshotNow() {
    snapshotTask?.cancel()
    snapshotTask = nil
    guard snapshotEnabled, composer.series.count > 0 else { return }
    do {
      let n = try Snapshot.write(composer.series, to: paths.snapshot)
      log("快照 \(n)B → \(paths.snapshot.lastPathComponent)")
    } catch {
      log("写快照失败：\(error)")
    }
  }

  private func current(_ id: UUID) -> Bool { selection == id && !Task.isCancelled }

  private func emit(_ e: FeedEvent) { continuation?.yield(FeedUpdate(selection: selection, event: e)) }
}
