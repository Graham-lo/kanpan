import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 录制报文的回放：把 3000 条真报文按顺序喂给 `BinanceWS` → `MarketFeed`，
// 最终序列必须和「按规矩逐条合成」的期望完全一致（A2.6 / A2.7 / A2.8 / A2.9）。

/// 一段录制。`events` 是按行解出来的 kline 事件，`lines` 是原始报文。
struct Recording: Sendable {
  var lines: [String]
  var klines: [KlineEvent]
  var tickers: [Ticker]
  /// 第 i 行对应的 kline 下标（不是 kline 的行为 nil），做「断线丢了哪些」用。
  var klineIndexOfLine: [Int?]

  static func load(_ name: String = "ws-btcusdt-1m.jsonl") -> Recording {
    let lines = Fixture.lines(name)
    var klines: [KlineEvent] = []
    var tickers: [Ticker] = []
    var map: [Int?] = []
    let dec = JSONDecoder()
    for l in lines {
      guard let env = try? dec.decode(StreamEnvelope.self, from: Data(l.utf8)),
            let p = env.payload else { map.append(nil); continue }
      switch p {
      case .kline(let k): map.append(klines.count); klines.append(k)
      case .ticker(let t): tickers.append(t); map.append(nil)
      default: map.append(nil)
      }
    }
    return Recording(lines: lines, klines: klines, tickers: tickers, klineIndexOfLine: map)
  }

  /// 前 n 条 kline 事件合出来的「交易所此刻的真相」。
  func barsUpTo(_ n: Int) -> [Bar] {
    var m: [Int64: Bar] = [:]
    for k in klines.prefix(n) { m[k.bar.openTime] = k.bar }
    return m.keys.sorted().map { m[$0]! }
  }

  var finalBars: [Bar] { barsUpTo(klines.count) }
}

/// 假交易所：K 线请求按「回放到第几步」回答，和 WS 看到的是同一份真相。
/// 录制之前的历史按 1 分钟等距补齐，凑够 1500 根。
struct FakeExchange: Sendable {
  let rec: Recording
  let cursor: Counter
  let history: [Bar]

  init(rec: Recording, cursor: Counter, historyBars: Int = 1200) {
    self.rec = rec
    self.cursor = cursor
    let first = rec.klines.first?.bar.openTime ?? 0
    self.history = (1...historyBars).reversed().map { i in
      let t = first - Int64(i) * 60_000
      let x = 50_000 + Double(i)
      return Bar(openTime: t, open: x, high: x + 5, low: x - 5, close: x + 1, volume: Double(i))
    }
  }

  /// 回放推进到第 `cursor` 步时，交易所手上有的全部 1m K 线。
  func bars(now step: Int) -> [Bar] {
    let n = rec.klineIndexOfLine.prefix(step).compactMap { $0 }.count
    return history + rec.barsUpTo(n)
  }

  func reply(for url: URL) -> HTTPReply {
    let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func v(_ n: String) -> String? { q.first { $0.name == n }?.value }
    switch url.path {
    case "/fapi/v1/klines":
      var all = bars(now: cursor.value)
      if let st = v("startTime").flatMap(Int64.init) { all = all.filter { $0.openTime >= st } }
      if let et = v("endTime").flatMap(Int64.init) { all = all.filter { $0.openTime <= et } }
      let limit = v("limit").flatMap(Int.init) ?? 500
      let rows = all.suffix(limit).map { b in
        // 第 9 格是主动买成交量，照这一根自己的值发；这一根不知道就发 null，
        // 不能发 "1" ——REST 补回来的那一段会和 WS 报文里的 `V` 对不上。
        let taker = b.takerBuy.isFinite ? "\"\(b.takerBuy)\"" : "null"
        return "[\(b.openTime),\"\(b.open)\",\"\(b.high)\",\"\(b.low)\",\"\(b.close)\",\"\(b.volume)\",\(b.openTime + 59_999),\"1\",1,\(taker),\"1\",\"0\"]"
      }
      return json("[" + rows.joined(separator: ",") + "]")
    case "/fapi/v1/ticker/24hr":
      return json(#"{"symbol":"BTCUSDT","lastPrice":"1","priceChangePercent":"0","highPrice":"2","lowPrice":"0","quoteVolume":"3"}"#)
    default:
      return json("[]")
    }
  }
}

@Suite("WS 回放：合成规矩、断线补缺、静默重连")
struct FeedReplayTests {

  private func tempPaths() -> Paths {
    let p = Paths(root: URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-replay-\(UUID().uuidString)"))
    try? p.ensureRoot()
    return p
  }

  // ---------------------------------------------------------------- 纯规矩

  @Test("x=false 覆盖末根，x=true / 新 openTime 追加，乱序的丢掉")
  func composerRules() {
    var c = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1,
                                           bars: makeBars(t0: 0, step: 60_000, count: 3)))
    let last = c.series.lastTime
    // 覆盖末根
    let upd = KlineEvent(symbol: "BTCUSDT", interval: "1m", openTime: last, closed: false,
                         bar: Bar(openTime: last, open: 1, high: 9, low: 0, close: 5, volume: 42))
    let ok1 = c.apply(upd)
    #expect(ok1)
    #expect(c.series.count == 3)
    #expect(c.series.close[2] == 5)
    #expect(c.series.volume[2] == 42)
    // 收盘 + 新根
    let nt = last + 60_000
    let add = KlineEvent(symbol: "BTCUSDT", interval: "1m", openTime: nt, closed: true,
                         bar: Bar(openTime: nt, open: 5, high: 6, low: 4, close: 5.5, volume: 1))
    let ok2 = c.apply(add)
    #expect(ok2)
    #expect(c.series.count == 4)
    // 迟到的旧事件
    let stale = KlineEvent(symbol: "BTCUSDT", interval: "1m", openTime: 0, closed: true,
                           bar: Bar(openTime: 0, open: 1, high: 1, low: 1, close: 1, volume: 1))
    let ok3 = c.apply(stale)
    #expect(!ok3)
    #expect(c.droppedStale == 1)
    #expect(c.series.count == 4)
    // 别的品种不进来
    let other = KlineEvent(symbol: "ETHUSDT", interval: "1m", openTime: nt + 60_000, closed: true,
                           bar: Bar(openTime: nt + 60_000, open: 1, high: 1, low: 1, close: 1, volume: 1))
    let ok4 = c.apply(other)
    #expect(!ok4)
    #expect(c.series.count == 4)
  }

  @Test("补缺期间事件排队，补完按 openTime 合并、队列再放行")
  func backfillQueue() {
    var c = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1,
                                           bars: makeBars(t0: 0, step: 60_000, count: 3)))
    c.beginBackfill()
    let t3: Int64 = 3 * 60_000, t4: Int64 = 4 * 60_000
    let queuedOK = c.apply(bar: Bar(openTime: t4, open: 1, high: 1, low: 1, close: 1, volume: 1))
    #expect(!queuedOK)
    #expect(c.series.count == 3)              // 还没落地
    // REST 把断线期间的 3、4 两根补回来（4 那根是半截的，队列里的更新）
    let added = c.endBackfill(with: [
      Bar(openTime: t3, open: 2, high: 2, low: 2, close: 2, volume: 2),
      Bar(openTime: t4, open: 3, high: 3, low: 3, close: 3, volume: 3)])
    #expect(added == 2)
    #expect(c.series.count == 5)
    #expect(c.series.close[3] == 2)
    #expect(c.series.close[4] == 1)           // 队列里的覆盖了 REST 的
    #expect(c.queued.isEmpty)
    #expect(!c.isBackfilling)
  }

  /// 这条是上面两条回放用例里那个竞态的最小复现：REST 的 `klines` 回的是「请求那一刻」
  /// 的快照，末尾那根是半根。一次往返几百毫秒，回来时 WS 早把这根推完、甚至开了下一根，
  /// 拿半根盖回去就把收线值抹掉了，而之后这根的 kline 报文又会被当成乱序丢掉——这根
  /// 就永远定格在半截上（量偏小、收盘停在快照那一刻的价，边界上那笔跑进了下一根）。
  @Test("慢一拍的 REST 快照不许把已经收线的那根改回半截")
  func staleSnapshotCannotUnsealClosedBar() {
    let t2: Int64 = 2 * 60_000, t3: Int64 = 3 * 60_000
    // 半根：REST 在这根还在走的时候拍下来的样子。
    let half = Bar(openTime: t2, open: 10, high: 12, low: 9, close: 11, volume: 5)
    // 收线值：WS 的 x=true 报的。
    let sealed = Bar(openTime: t2, open: 10, high: 15, low: 9, close: 14, volume: 20)

    // ① 序列里已经有更晚的一根 → t2 封了。
    var a = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1,
                                           bars: makeBars(t0: 0, step: 60_000, count: 3)))
    _ = a.apply(KlineEvent(symbol: "BTCUSDT", interval: "1m", openTime: t2, closed: false, bar: sealed))
    _ = a.apply(KlineEvent(symbol: "BTCUSDT", interval: "1m", openTime: t3, closed: false,
                           bar: Bar(openTime: t3, open: 14, high: 14, low: 14, close: 14, volume: 1)))
    a.merge([half])                                   // 慢一拍的快照追上来
    #expect(a.series.count == 4)
    #expect(a.series.bar(at: 2) == sealed)            // 没被改回半截

    // ② 还没有更晚的一根，但收到过 x=true → 一样封了。
    var b = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1,
                                           bars: makeBars(t0: 0, step: 60_000, count: 3)))
    _ = b.apply(KlineEvent(symbol: "BTCUSDT", interval: "1m", openTime: t2, closed: true, bar: sealed))
    b.merge([half])
    #expect(b.series.bar(at: 2) == sealed)

    // ③ 没封的那根照旧认快照（对表、补缺得能把末根盖回去）。
    var c = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1,
                                           bars: makeBars(t0: 0, step: 60_000, count: 3)))
    _ = c.apply(KlineEvent(symbol: "BTCUSDT", interval: "1m", openTime: t2, closed: false, bar: sealed))
    c.merge([half])
    #expect(c.series.bar(at: 2) == half)

    // ④ 手上没有的那根必须接上，不许因为「时间比末根早」就留个洞。
    //    等距周期的 `BarSeries` 按下标排，中间本来就不可能有洞；1M 是查表的，能有。
    let mo: Int64 = 30 * 86_400_000
    var d = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .mo1, bars: [
      Bar(openTime: 0, open: 1, high: 1, low: 1, close: 1, volume: 1),
      Bar(openTime: mo, open: 1, high: 1, low: 1, close: 1, volume: 1),
      Bar(openTime: 3 * mo, open: 1, high: 1, low: 1, close: 1, volume: 1),   // 缺第 3 个月
    ]))
    let missing = Bar(openTime: 2 * mo, open: 7, high: 8, low: 6, close: 7.5, volume: 3)
    d.merge([missing])                                // 比末根早，但手上没有这根
    #expect(d.series.count == 4)
    #expect(d.series.bar(at: 2) == missing)

    // ⑤ 非末根的那些是快照眼里已经收线的权威值，照收不误。
    var e = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1,
                                           bars: makeBars(t0: 0, step: 60_000, count: 3)))
    _ = e.apply(KlineEvent(symbol: "BTCUSDT", interval: "1m", openTime: t2, closed: true, bar: sealed))
    e.merge([half, Bar(openTime: t3, open: 14, high: 14, low: 14, close: 14, volume: 1)])
    #expect(e.series.count == 4)
    #expect(e.series.bar(at: 2) == half)               // t2 这回不是末根了
  }

  /// 等 `feed` 的序列追平 `want`（逐根全等）。超时返回 `false`，让调用方的逐根断言
  /// 去报「差在哪儿」——这里只负责不要读得太早。
  /// 第一根对不上的，连两边的值一起报出来。只说「不全等」的话，挂了还得自己再跑一遍
  /// 才知道差在哪一根、差的是收盘还是成交量。
  private func firstDiff(_ got: BarSeries, _ want: [Bar]) -> String? {
    if got.count != want.count { return "根数 \(got.count) ≠ \(want.count)" }
    for i in 0..<min(got.count, want.count) where got.bar(at: i) != want[i] {
      return "第 \(i)/\(got.count) 根不等\n  got  \(got.bar(at: i))\n  want \(want[i])"
    }
    return nil
  }

  /// 超时取 20 秒，和上面等牌堆发完那句一致：机器被别的活（比如并行跑八台模拟器的
  /// UI 测试）占满时，这些 actor 的任务会被调度饿着，5 秒不够——那不是数据错了，
  /// 是根本没轮上跑。
  private func converged(_ feed: MarketFeed, _ want: [Bar], _ seconds: Double = 20) async -> Bool {
    await waitUntil(seconds) {
      let s = await feed.currentSeries
      guard s.count == want.count else { return false }
      return (0..<s.count).allSatisfy { s.bar(at: $0) == want[$0] }
    }
  }

  // ---------------------------------------------------------------- A2.6

  @Test("3000 条录制报文回放：最终序列与期望全等")
  func replayAll() async throws {
    let rec = Recording.load()
    #expect(rec.lines.count == 3000)
    #expect(rec.klines.count > 0)
    #expect(rec.tickers.count > 0)

    let deck = ReplayDeck(rec.lines.map { .frame(.text($0)) } + [.hang])
    let pacer = FastPacer()
    let ex = FakeExchange(rec: rec, cursor: deck.cursor)
    let server = FakeServer(pacer: pacer) { ex.reply(for: $0) }
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }

    let rest = BinanceREST(transport: FakeTransport(server), pacer: pacer)
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer)
    let feed = MarketFeed(rest: rest, ws: ws, paths: paths, pacer: pacer, reconcileMs: 0)

    let seen = Counter()
    let stream = await feed.events()
    let pump = Task {
      for await e in stream { if case .lastBar = e.event { seen.bump() } }
    }
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(20) { await deck.progress() >= rec.lines.count })
    // 末根事件够密：闸门没有把实时推送掐掉。
    //
    // 阈值从「≥ 报文数的一半」放宽到 1/8，是因为 kline 报文现在也要过 80ms 合帧闸门
    // （`MarketFeed.emitTick`，原来 kline 是 `force: true` 直接绕过去的）。
    // 这份录制是把 32 分钟的行情在几十毫秒里放完的——牌堆里没有任何 `.silence`，
    // 帧与帧之间等于零间隔，被加速了上千倍，闸门自然合得很狠（实测 2090 条报文
    // 合成 655 次末根事件）。真机上单品种的 kline 流约每 250ms 一条，拍子是 80ms，
    // 每条照样立刻放行，这条链路上的事件密度并不会变。
    #expect(await waitUntil(5) { seen.value > rec.klines.count / 8 })

    let want = ex.bars(now: rec.lines.count)
    // 牌堆把帧发完 ≠ 报文已经落进序列：中间还隔着 socket → AsyncStream → MarketFeed
    // 三道手，末根还要过 `tickCoalesceMs` 的合并。发完就立刻读 `currentSeries`，
    // 尾巴要么少几根、要么末根的高低收还没追平——这条用例过去就是这么飘的
    // （实测约一成概率，少 4 根或末根不等）。
    //
    // 所以等的是**整条序列收敛**，不是只等根数：等到了下面的逐根断言自然全过；
    // 5 秒等不到就带着下面的 `count` / `allSatisfy` 一起挂，真 bug 照样拦得住。
    #expect(await converged(feed, want))

    let got = await feed.currentSeries
    #expect(got.count == want.count)
    #expect(firstDiff(got, want) == nil, "\(firstDiff(got, want) ?? "")")
    // openTime 严格递增、等距、无重复。
    for i in 1..<got.count { #expect(got.time(at: i) == got.time(at: i - 1) + 60_000) }
    await feed.stop()
    pump.cancel()
  }

  // ---------------------------------------------------------------- A2.7

  @Test("第 1000 条处断线 20 秒：期间报文全丢，REST 补缺后仍与期望全等")
  func disconnectMidway() async throws {
    let rec = Recording.load()
    // 第 1000 条断开 → 之后 300 条当成断线期间没收到 → 再重连继续放剩下的。
    var steps: [ReplayStep] = rec.lines.prefix(1000).map { .frame(.text($0)) }
    steps.append(.drop("服务器掐了"))
    steps += rec.lines.dropFirst(1300).map { .frame(.text($0)) }
    steps.append(.hang)
    let stepCount = steps.count

    let deck = ReplayDeck(steps)
    let pacer = FastPacer()
    // 交易所的真相不受掉线影响：按「原录制里第几行」算，所以补缺能把丢的 300 条补回来。
    let lost = Counter()
    let ex = FakeExchange(rec: rec, cursor: lost)
    let server = FakeServer(pacer: pacer) { url in
      // 回放到第 k 步，对应原录制的第 k 行（断线那 300 条已经被跳过，但交易所知道）。
      let k = deck.cursor.value
      // 边界是 `< 1000` 不是 `<= 1000`：回放走到第 1000 帧的那一刻断线就已经发生了，
      // 交易所从这一刻起手上就有 1300 行。写成 `<=` 会留一个窗口——重连后的补缺如果
      // 恰好赶在 `.drop` 那一步把游标推到 1001 之前被应答，交易所会谎称自己只有 1000 行，
      // 那 300 行就永远补不回来，序列中间留个洞（这个竞态让这条用例有约四成概率挂）。
      lost.setTo(k < 1000 ? k : min(rec.lines.count, k + 300))
      return ex.reply(for: url)
    }
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }

    let rest = BinanceREST(transport: FakeTransport(server), pacer: pacer)
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer)
    let feed = MarketFeed(rest: rest, ws: ws, paths: paths, pacer: pacer, reconcileMs: 0)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(20) { await deck.progress() >= stepCount - 1 })
    #expect(await waitUntil(5) { await deck.stats().connects >= 2 })   // 真的重连了

    lost.setTo(rec.lines.count)
    let want = ex.bars(now: rec.lines.count)
    // 同上：等整条序列收敛再读。
    #expect(await converged(feed, want))

    let got = await feed.currentSeries
    #expect(got.count == want.count)
    #expect(firstDiff(got, want) == nil, "\(firstDiff(got, want) ?? "")")
    for i in 1..<got.count { #expect(got.time(at: i) == got.time(at: i - 1) + 60_000) }
    await feed.stop()
  }

  /// 退避每一档都再抖 ±20%（A.2：别让所有客户端在同一毫秒一起回来把上游再撞一次），
  /// 所以这里断言的是「第 N 次落在第 N 档的 ±20% 带里」，不是一个固定毫秒数。
  @Test("连断三次：退避 1s / 2s / 4s（各再抖 ±20%），日志可见")
  func backoffOnRepeatedDrops() async throws {
    let deck = ReplayDeck([.drop("1"), .drop("2"), .drop("3"), .hang])
    let pacer = FastPacer()        // 1000×，1 秒退避真的等 1 毫秒
    let waits = Waits()
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer,
                       log: FeedLog { waits.note($0) })
    let s = await ws.start(streams: ["btcusdt@kline_1m"])
    let t = Task { for await _ in s {} }
    #expect(await waitUntil(5) { await deck.stats().connects >= 4 })
    await ws.stop()
    t.cancel()
    let log = waits.all()
    /// 从「退避 1234ms 后重连（第 1 次）」里把毫秒数抠出来。
    func waited(attempt: Int) -> Double? {
      guard let line = log.first(where: { $0.contains("后重连（第 \(attempt) 次）") }),
            let range = line.range(of: #"退避 \d+ms"#, options: .regularExpression) else { return nil }
      return Double(line[range].dropFirst(3).dropLast(2))
    }
    for (attempt, nominal) in [(1, 1000.0), (2, 2000.0), (3, 4000.0)] {
      guard let ms = waited(attempt: attempt) else {
        Issue.record("日志里没有第 \(attempt) 次重连的退避")
        continue
      }
      #expect(ms >= nominal * 0.8 && ms <= nominal * 1.2, "第 \(attempt) 次退避 \(ms)ms 不在 \(nominal)ms 的 ±20% 内")
    }
  }

  // ---------------------------------------------------------------- A2.8

  @Test("60 秒一帧没有就主动重连")
  func silenceReconnect() async throws {
    // 静默 90 秒（虚拟），60 秒的看门狗该先响。
    let deck = ReplayDeck([.frame(.text("{}")), .silence(90_000), .hang])
    let pacer = FastPacer()
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer)
    let s = await ws.start(streams: ["btcusdt@kline_1m"])
    let t = Task { for await _ in s {} }
    #expect(await waitUntil(5) { await deck.stats().connects >= 2 })
    await ws.stop()
    t.cancel()
  }

  @Test("服务器 ping 立刻回 pong")
  func pingPong() async throws {
    let deck = ReplayDeck([.frame(.ping), .frame(.ping), .frame(.ping), .hang])
    let pacer = FastPacer()
    // This fixture has no market events: keep the separate valid-data watchdog
    // outside the pong assertion, even when UI builds delay this test task.
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer, silenceMs: 60_000_000)
    let s = await ws.start(streams: ["btcusdt@kline_1m"])
    let t = Task { for await _ in s {} }
    #expect(await waitUntil(5) { await deck.stats().pongs >= 3 })
    #expect(await deck.stats().connects == 1)    // 没重连
    await ws.stop()
    t.cancel()
  }

  // ---------------------------------------------------------------- A2.9

  @Test("连续切 20 次：连接 id 不变，走 SUBSCRIBE / UNSUBSCRIBE")
  func switchTwentyTimes() async throws {
    let rec = Recording.load()
    // 50 帧放完之后回放器就挂住了：这是一条**安静但健康**的连接，所以它得答保活探针
    // （`answersKeepalive: true`）。不答的话，A-07 第①层（传输层静默，默认 30 虚拟秒，
    // FastPacer 下只有 30 毫秒真实时间）会在最后一帧之后约 30～60ms 判它死了去重连——
    // 机器一忙，20 次切换还没切完就换成了第 2 条连接，新连接把订阅写在 URL 上，
    // 于是 `currentConnectionID == 1`、`connects == 1` 和「发过 SUBSCRIBE」一起红。
    // 那是看门狗在正确地工作，不是订阅复用出了问题；这条用例测的是后者。
    let deck = ReplayDeck(rec.lines.prefix(50).map { .frame(.text($0)) } + [.hang],
                          answersKeepalive: true)
    let pacer = FastPacer()
    let ex = FakeExchange(rec: rec, cursor: deck.cursor)
    let server = FakeServer(pacer: pacer) { ex.reply(for: $0) }
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let rest = BinanceREST(transport: FakeTransport(server), pacer: pacer)
    // 第②/③层（等首帧、等有效行情）同理挪到用例之外：这里只看订阅复用。
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer, silenceMs: 60_000_000)
    let feed = MarketFeed(rest: rest, ws: ws, paths: paths, pacer: pacer, reconcileMs: 0)
    _ = await feed.events()

    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(5) { await ws.currentConnectionID == 1 })
    let syms = ["ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT"]
    let ivs: [Interval] = [.m5, .m15, .h1, .h4, .d1]
    for i in 0..<20 {
      await feed.switchTo(symbol: syms[i % syms.count], interval: ivs[i % ivs.count])
    }
    // 控制帧是限速发的（币安每条连接入站 10 条/秒），等它追平再看。
    #expect(await waitUntil(5) { await ws.streamsInSync })
    #expect(await ws.currentConnectionID == 1)         // 全程一条连接
    #expect(await deck.stats().connects == 1)
    let sent = await deck.stats().sent
    #expect(sent.contains { $0.contains("UNSUBSCRIBE") })
    #expect(sent.contains { $0.contains("SUBSCRIBE") })
    // 订阅的永远只是当前那一组流，不会越积越多。
    let live = await ws.currentStreams
    // All subscribed streams belong to /market.
    #expect(live.count == 3)
    #expect(live.contains { $0.contains("@markPrice") })
    #expect(!live.contains { $0.contains("@bookTicker") || $0.contains("@trade") })
    #expect(live.allSatisfy { $0.hasPrefix(syms[19 % syms.count].lowercased()) })
    // 旧品种的报文不会进当前序列。
    let s = await feed.currentSeries
    #expect(s.symbol == InstrumentID.canonical(syms[19 % syms.count]))
    await feed.stop()
  }

  // ---------------------------------------------------------------- A2.5

  @Test("快照 → 补缺：重启后先按 startTime=末根补，再拉满，合并无重复")
  func snapshotThenGapFill() async throws {
    let rec = Recording.load()
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }

    // 先造一份「上次退出时」的快照：只到录制开始前 100 根。
    let ex0 = FakeExchange(rec: rec, cursor: Counter())
    let old = BarSeries(symbol: "BTCUSDT", interval: .m1,
                        bars: Array(ex0.history.dropLast(100)))
    _ = try SeriesStore.write(old, in: paths.series)
    let snapLast = old.lastTime

    let deck = ReplayDeck(rec.lines.prefix(200).map { .frame(.text($0)) } + [.hang])
    let pacer = FastPacer()
    let ex = FakeExchange(rec: rec, cursor: deck.cursor)
    let server = FakeServer(pacer: pacer) { ex.reply(for: $0) }
    let rest = BinanceREST(transport: FakeTransport(server), pacer: pacer)
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer)
    let feed = MarketFeed(rest: rest, ws: ws, paths: paths, pacer: pacer,
                          clock: clock(near: ex0.history.last?.openTime ?? snapLast), reconcileMs: 0)

    let firstEvent = Counter()
    let stream = await feed.events()
    let pump = Task { for await _ in stream { firstEvent.bump() } }
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    // 第一帧来自快照，不用等网络。
    #expect(await waitUntil(2) { firstEvent.value >= 1 })
    // 「补缺回来了」的判据不能是「比快照多一根」：WS 推来的实时那根先到，而它落在
    // 100 根缺口的另一头——那一刻序列本来就是断的，断的是**还没补**，不是**补错了**。
    // 要等的是 REST 那一发 `startTime=快照末根` 真的合进来，缺口的 100 根都到位。
    #expect(await waitUntil(10) { await feed.currentSeries.count >= old.count + 100 })

    // 补缺请求带了 startTime=快照末根。
    let urls = await server.urls()
    #expect(urls.contains { $0.query?.contains("startTime=\(snapLast)") == true })
    let s = await feed.currentSeries
    #expect(Set((0..<s.count).map { s.time(at: $0) }).count == s.count)
    for i in 1..<s.count { #expect(s.time(at: i) == s.time(at: i - 1) + 60_000) }
    #expect(s.lastTime > snapLast)                       // 末根被推到最新
    await feed.stop()
    pump.cancel()
  }

  @Test("关掉「启动快照」：文件被删，之后不再写")
  func snapshotDisabled() async throws {
    let rec = Recording.load()
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let deck = ReplayDeck(rec.lines.prefix(100).map { .frame(.text($0)) } + [.hang])
    let pacer = FastPacer()
    let ex = FakeExchange(rec: rec, cursor: deck.cursor)
    let server = FakeServer(pacer: pacer) { ex.reply(for: $0) }
    let rest = BinanceREST(transport: FakeTransport(server), pacer: pacer)
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer)
    let feed = MarketFeed(rest: rest, ws: ws, paths: paths, pacer: pacer, reconcileMs: 0)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    let snap = SeriesStore.url(symbol: "BTCUSDT", interval: .m1, in: paths.series)!
    #expect(await waitUntil(10) { FileManager.default.fileExists(atPath: snap.path) })
    let size = (try? Data(contentsOf: snap).count) ?? 0
    #expect(size <= Snapshot.maxBytes)

    await feed.setSnapshotEnabled(false)
    #expect(!FileManager.default.fileExists(atPath: snap.path))
    #expect(!FileManager.default.fileExists(atPath: paths.series.path))
    await feed.stop()
    #expect(!FileManager.default.fileExists(atPath: snap.path))
  }

  // ---------------------------------------------------------------- A2.12

  @Test("30 品种 × 14 周期切一遍：沙盒里只有 series/ 下封顶的快照和品种表")
  func sandboxStaysClean() async throws {
    let rec = Recording.load()
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let deck = ReplayDeck([.hang])
    let pacer = FastPacer()
    let ex = FakeExchange(rec: rec, cursor: Counter())
    let server = FakeServer(pacer: pacer) { ex.reply(for: $0) }
    let rest = BinanceREST(transport: FakeTransport(server), pacer: pacer)
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer)
    let cache = BarCache()
    let feed = MarketFeed(rest: rest, ws: ws, cache: cache, paths: paths, pacer: pacer, reconcileMs: 0)
    _ = await feed.events()
    await feed.start(symbol: "S0USDT", interval: .m1)
    for i in 0..<30 {
      for iv in Interval.allCases {
        await feed.switchTo(symbol: "S\(i)USDT", interval: iv)
      }
    }
    await feed.stop()

    // 420 对全切过一遍，磁盘上留下的只能是 `series/` 下的快照和品种表，
    // 而且份数和总字节都要在 `SeriesStore` 的上限之内。
    let urls = (FileManager.default.enumerator(at: paths.root, includingPropertiesForKeys: nil)?
      .compactMap { $0 as? URL } ?? []).filter { !$0.hasDirectoryPath }
    let names = urls.map(\.lastPathComponent).sorted()
    #expect(names.allSatisfy { $0.hasSuffix(".kbar") || $0 == "exchangeInfo.json" })
    let snaps = urls.filter { $0.pathExtension == "kbar" }
    #expect(snaps.allSatisfy { $0.deletingLastPathComponent().lastPathComponent == "series" })
    #expect(snaps.count <= SeriesStore.maxEntries)
    let bytes = snaps.reduce(0) { $0 + ((try? Data(contentsOf: $1).count) ?? 0) }
    #expect(bytes <= SeriesStore.maxBytes)
    #expect(snaps.allSatisfy { ((try? Data(contentsOf: $0).count) ?? 0) <= Snapshot.maxBytes })
    #expect(await cache.totalBytes <= BarCache.defaultLimitBytes)

    await feed.memoryWarning()
    #expect(await cache.count <= 1)
  }
}

/// 日志收集器。
final class Waits: @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []
  func note(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
  func all() -> [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
