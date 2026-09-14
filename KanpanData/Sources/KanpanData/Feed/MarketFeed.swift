import Foundation
import KanpanCore

/// 图表侧收到的东西（§3.1）。`BarSeries` 是值类型快照，每次事件换一份，
/// 绘制线程只读一份不可变数据，没有锁。
public enum FeedEvent: Sendable {
  case series(BarSeries)          // 整段替换
  case lastBar(Bar)               // 末根更新 / 新根追加
  case prepend(count: Int)        // 前面补了 N 根，视野要平移保持不跳
  case ticker(Ticker)
  case oi([OIPoint])
  case status(FeedStatus)
}

/// 把 REST + WS + 内存缓存合成「当前 (品种, 周期)」一条流（§3.1 / §4.4）。
public actor MarketFeed {
  private let rest: BinanceREST
  private let ws: BinanceWS
  private let cache: BarCache
  private let paths: Paths
  private let pacer: Pacer
  private let log: FeedLog

  private var composer = FeedComposer(series: BarSeries(
    symbol: "", interval: .h1, t0: 0, open: [], high: [], low: [], close: [], volume: []))
  private var symbol: String = ""
  private var interval: Interval = .h1
  private var continuation: AsyncStream<FeedEvent>.Continuation?
  private var wsTask: Task<Void, Never>?
  private var loadTask: Task<Void, Never>?
  /// ③ 那一发还在路上。它自己就会从快照末根补到现在，WS 连上时别再补一遍。
  private var filling = false
  private var backgroundTask: Task<Void, Never>?
  private var snapshotTask: Task<Void, Never>?
  /// 设置页「启动快照」。关掉：不写，并把已有的那份删掉。
  private var snapshotEnabled = true
  /// 只有 1y 用得上：WS 推的是月线，年线要拿月线重聚（§4.2）。
  private var sourceSeries: BarSeries?

  public init(rest: BinanceREST, ws: BinanceWS, cache: BarCache = BarCache(),
              paths: Paths = .caches(), pacer: Pacer = SystemPacer(), log: FeedLog = .silent) {
    self.rest = rest
    self.ws = ws
    self.cache = cache
    self.paths = paths
    self.pacer = pacer
    self.log = log
  }

  // ------------------------------------------------------------------ 对外

  public func events() -> AsyncStream<FeedEvent> {
    let (s, c) = AsyncStream<FeedEvent>.makeStream(bufferingPolicy: .unbounded)
    continuation = c
    return s
  }

  public var currentSeries: BarSeries { composer.series }

  public func setSnapshotEnabled(_ on: Bool) {
    snapshotEnabled = on
    if !on { Snapshot.remove(paths.snapshot) }
  }

  /// 冷启动：先读快照画第一帧，再拉网络（§4.3）。
  public func start(symbol: String, interval: Interval) async {
    await switchTo(symbol: symbol, interval: interval, coldStart: true)
  }

  public func switchTo(symbol newSymbol: String, interval newInterval: Interval, coldStart: Bool = false) async {
    writeSnapshotNow()
    loadTask?.cancel()
    symbol = newSymbol.uppercased()
    interval = newInterval
    let key = SeriesKey(symbol, interval)

    // ① 内存里有就先画内存的；没有再看快照；都没有就空着等网络。
    var seeded = false
    if let hit = await cache.get(key) {
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

    // ② 换订阅。同一条连接，连接 id 不变。
    await ws.replaceStreams(streamNames())
    if wsTask == nil { await startWS() }

    // ③ 网络补齐。
    let sym = symbol, iv = interval, had = seeded ? composer.series.lastTime : 0
    filling = true
    loadTask = Task { [weak self] in await self?.fill(symbol: sym, interval: iv, since: had) }
  }

  /// 向前补历史（拖到左边缘时叫）。
  public func loadMore(pages: Int = 1) async {
    let sym = symbol, iv = interval
    guard composer.series.count > 0 else { return }
    let first = composer.series.firstTime
    do {
      let bars = try await rest.history(symbol: sym, interval: iv, pages: pages, before: first)
      guard sym == symbol, iv == interval else { return }
      let n = composer.prepend(bars)
      if n > 0 {
        await cache.put(composer.series)
        emit(.prepend(count: n))
      }
      log("补历史 \(n) 根，现在 \(composer.series.count) 根")
    } catch {
      log("补历史失败：\(error)")
    }
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
    if wsTask == nil { await startWS() }
    await ws.replaceStreams(streamNames())
    let sym = symbol, iv = interval
    loadTask = Task { [weak self] in
      await self?.backfill(symbol: sym, interval: iv)
    }
  }

  public func memoryWarning() async {
    await cache.purge(keeping: SeriesKey(symbol, interval))
    log("内存警告：只留 \(symbol)|\(interval.rawValue)")
  }

  public func stop() async {
    writeSnapshotNow()
    loadTask?.cancel(); loadTask = nil
    backgroundTask?.cancel(); backgroundTask = nil
    wsTask?.cancel(); wsTask = nil
    await ws.stop()
    continuation?.finish()
    continuation = nil
  }

  // ------------------------------------------------------------------ 内部

  private func streamNames() -> [String] {
    // 1y 没有原生流，订 1M（§4.2）。
    let api = interval.source.rawValue
    return [BinanceHosts.klineStream(symbol: symbol, interval: api),
            BinanceHosts.tickerStream(symbol: symbol)]
  }

  private func startWS() async {
    let stream = await ws.start(streams: streamNames())
    wsTask = Task { [weak self] in
      for await ev in stream {
        guard let self else { return }
        await self.handle(ev)
      }
    }
  }

  private func suspendWS() async {
    wsTask?.cancel(); wsTask = nil
    await ws.stop()
    emit(.status(.offline))
    log("进后台 5 秒，断开 WS")
  }

  private func handle(_ ev: WSEvent) async {
    switch ev {
    case .connected:
      // 首连时 switchTo 已经派了一次 fill，别再补一遍（会重复拉 1500 根，而且两次
      // fill 并发谁后到谁说了算）。序列空着是冷启动，序列不空但 fill 还在路上是
      // 「快照打了底」的热启动——两种都归首连，只有重连才需要补缺。
      guard !filling, composer.series.count > 0 else { break }
      // 重连成功：先补缺再让 WS 落地（§4.4）。
      composer.beginBackfill()
      let sym = symbol, iv = interval
      Task { [weak self] in await self?.backfill(symbol: sym, interval: iv) }
    case .status(let s):
      emit(.status(s))
    case .payload(let p):
      switch p {
      case .kline(let k):
        guard k.symbol.uppercased() == symbol, k.interval == interval.source.rawValue else { return }
        applyKline(k)
      case .ticker(let t):
        if t.symbol.uppercased() == symbol { emit(.ticker(t)) }
      case .markPrice(let s, let px):
        if s.uppercased() == symbol { emit(.ticker(Ticker(symbol: s, last: px, changePercent: .nan,
                                                          high: .nan, low: .nan, quoteVolume: .nan, markPrice: px))) }
      case .other:
        break
      }
    }
  }

  private func applyKline(_ k: KlineEvent) {
    // 年线是聚出来的：WS 推的是月线，收一条就把当年那根重算（§4.2）。
    if interval == .y1 {
      guard var monthly = sourceSeries, monthly.count > 0 else { return }
      guard monthly.upsert(k.bar) else { return }
      sourceSeries = monthly
      composer.replace(Aggregator.bucket(series: monthly, into: .y1))
      emit(.series(composer.series))
      scheduleSnapshot()
      return
    }
    guard composer.apply(k) else { return }
    emit(.lastBar(composer.series.bar(at: composer.series.count - 1)))
    scheduleSnapshot()
  }

  /// 拉满一屏。`since > 0` 时先补快照到现在的缺口（§4.3 冷启动时序）。
  private func fill(symbol sym: String, interval iv: Interval, since: Int64) async {
    defer { if sym == symbol, iv == interval { filling = false } }
    do {
      // 聚出来的周期（1y）没法拿月线往年线上合，直接整段重拉重聚。
      if since > 0, iv.source == iv {
        let gap = try await rest.klines(symbol: sym, interval: iv, limit: BinanceREST.maxKlines, startTime: since)
        guard sym == symbol, iv == interval else { return }
        composer.merge(gap)
        log("补缺 startTime=\(since) → \(gap.count) 根")
      }
      let bars = try await rest.klines(symbol: sym, interval: iv, limit: BinanceREST.maxKlines)
      guard sym == symbol, iv == interval else { return }
      if iv.source != iv {
        let src = BarSeries(symbol: sym, interval: iv.source, bars: BinanceREST.dedup(bars))
        sourceSeries = src
        composer.replace(Aggregator.bucket(series: src, into: iv))
      } else {
        sourceSeries = nil
        composer.merge(bars)
      }
      await cache.put(composer.series)
      emit(.series(composer.series))
      scheduleSnapshot()

      let t = try await rest.ticker24h(symbol: sym)
      if sym == symbol { emit(.ticker(t)) }
    } catch {
      log("拉 \(sym)|\(iv.rawValue) 失败：\(error)")
      emit(.status(.offline))
    }
  }

  /// 重连 / 回前台后补缺：从末根开始重拉，排队的 WS 事件补完再放行。
  private func backfill(symbol sym: String, interval iv: Interval) async {
    guard iv.source == iv else {
      composer.endBackfill(with: [])
      await fill(symbol: sym, interval: iv, since: 0)
      return
    }
    guard composer.series.count > 0 else {
      composer.endBackfill(with: [])
      await fill(symbol: sym, interval: iv, since: 0)
      return
    }
    let from = composer.series.lastTime
    do {
      let bars = try await rest.klines(symbol: sym, interval: iv, limit: BinanceREST.maxKlines, startTime: from)
      guard sym == symbol, iv == interval else { composer.endBackfill(with: []); return }
      let added = composer.endBackfill(with: bars)
      await cache.put(composer.series)
      emit(.series(composer.series))
      log("补缺 \(bars.count) 根，净增 \(added)，队列已合并")
    } catch {
      log("补缺失败：\(error)")
      composer.endBackfill(with: [])
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

  private func emit(_ e: FeedEvent) { continuation?.yield(e) }
}
