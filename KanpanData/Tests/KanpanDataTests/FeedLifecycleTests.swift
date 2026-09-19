import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

// 「并发与生命周期」在行情流水线这一侧的回归用例（GPT Pro 第三轮 B-01 / B-02 / B-04）。
//
// 这几条全是时序题，所以一条 `sleep` 都不用：要卡住哪一步就在那一步上挂一道闸门
// （`Gate`，它刻意不理会任务取消，跟真 socket、真回包一个脾气），等闸门前真的有人
// 报到了再往下走。这样「旧任务醒来时世界已经变了」这个瞬间是摆出来的，不是碰出来的。
@Suite("行情流水线：生命周期与并发")
struct FeedLifecycleTests {

  // ---------------------------------------------------------------- 假件

  private static let lastOpen: Int64 = 1_700_000_000_000
  private static let step: Int64 = 60_000

  /// 按 `limit` 给等距 1m K 线，末根固定落在 `lastOpen`。
  private static func klines(_ count: Int) -> HTTPReply {
    let rows = (0..<count).map { i -> String in
      let t = lastOpen - Int64(count - 1 - i) * step
      return "[\(t),\"1\",\"1\",\"1\",\"1\",\"1\",\(t + step - 1),\"1\",1,\"1\",\"1\",\"0\"]"
    }
    return json("[" + rows.joined(separator: ",") + "]")
  }

  /// 可以按住的历史接口。`hold` 打开时每一笔都挂在闸门上，`release()` 之后
  /// 挂着的和后来的都照常走。闸门不理会取消——真网络回包就是这样，上层把任务掐了，
  /// 回包该来还是会来，这正是「首屏那一发被取消之后还得有人补发」这件事的前提。
  private actor HeldHistory: HTTPTransport {
    private let gate = Gate()
    private let hold: Bool
    private(set) var urls: [URL] = []
    init(hold: Bool) { self.hold = hold }

    var klineCalls: Int { urls.filter { $0.path.contains("klines") }.count }
    var backfillCalls: Int {
      urls.filter { ($0.query ?? "").contains("startTime") }.count
    }
    func release() async { await gate.open() }
    func arrived() async -> Int { await gate.arrived }

    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      urls.append(url)
      if hold { await gate.wait() }
      guard url.path.contains("klines") else {
        return json(#"{"symbol":"X","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
      }
      let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let limit = q.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 300
      return FeedLifecycleTests.klines(min(limit, 1500))
    }
  }

  /// 关得很慢的 socket：`cancel()` 卡在闸门上。用来把「上一份 feed 正在收摊」
  /// 这个窗口拉开，好让切品种正正落在里面。
  ///
  /// 开头先吐一帧真 K 线：线路择优（`MarketSocketRouter`）要收到一帧真数据才认这条连接，
  /// 不给它就永远连不上，`stop()` 里那一步「关连接」也就没得可关，窗口是空的。
  private final class SlowCloseSocket: WSSocket {
    let closing: Gate
    let alive = Gate()
    let stream: String
    /// 首帧发过没有。发过就一直挂着，等 `cancel()` 来叫醒。
    let greeted = Counter()
    init(closing: Gate, stream: String) { self.closing = closing; self.stream = stream }
    func send(_ text: String) async throws {}
    func pong() async throws {}
    func cancel() async { await closing.wait(); await alive.kill() }
    func receive() async throws -> WSFrame {
      if greeted.bump() == 1 { return .text(Self.kline(stream: stream)) }
      await alive.wait()
      throw FeedError.badResponse("连接已取消")
    }
    static func kline(stream: String) -> String {
      let symbol = stream.split(separator: "@").first.map(String.init)?.uppercased() ?? "BTCUSDT"
      let t = FeedLifecycleTests.lastOpen
      return """
      {"stream":"\(stream)","data":{"e":"kline","E":\(t + 1),"s":"\(symbol)",\
      "k":{"t":\(t),"T":\(t + 59_999),"s":"\(symbol)","i":"1m","f":1,"L":2,\
      "o":"1","c":"1","h":"1","l":"1","v":"1","n":1,"x":false,"q":"1","V":"1","Q":"1","B":"0"}}}
      """
    }
  }

  private struct SlowCloseFactory: WSSocketFactory {
    let closing: Gate
    func connect(to url: URL) async throws -> WSSocket {
      // 组合流地址里第一条流就是 K 线流，照它回帧，线路择优才认。
      let first = (url.query ?? "").split(separator: "/").first.map(String.init)
        ?? "btcusdt@kline_1m"
      return SlowCloseSocket(closing: closing, stream: first)
    }
  }

  private actor Seen {
    private(set) var symbols: [String] = []
    private(set) var live = false
    func add(_ s: String) { symbols.append(s) }
    func has(_ s: String) -> Bool { symbols.contains(s) }
    func noteStatus(_ s: FeedStatus) { if s == .live { live = true } }
  }

  /// 可以拨的墙上时钟。`pendingBars()` 算的是真实时刻的差，总不能真等一分钟。
  private final class MovableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Double
    init(_ t: Double) { self.t = t }
    var date: Date { lock.lock(); defer { lock.unlock() }; return Date(timeIntervalSince1970: t) }
    func set(_ v: Double) { lock.lock(); t = v; lock.unlock() }
  }

  private func tempPaths() -> Paths {
    Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
  }

  // ---------------------------------------------------------------- BT-02

  @Test("BT-02 首屏还在路上就切后台再回前台：必须补发首屏，不能只剩打底那几根",
        .timeLimit(.minutes(1)))
  func foregroundRefillsTheCancelledFirstScreen() async throws {
    let transport = HeldHistory(hold: true)
    let cache = BarCache()
    // 内存里有三根打底（切出去又回来最常见的热启动），末根就是「现在」这一分钟：
    // 按缺口算是「不足一根」，正是原来那条 guard 直接返回的路。
    await cache.put(BarSeries(symbol: "BTCUSDT", interval: .m1,
                              bars: makeBars(t0: Self.lastOpen - 2 * Self.step,
                                             step: Self.step, count: 3)))
    let deck = ReplayDeck([.hang])
    let feed = MarketFeed(rest: BinanceREST(transport: transport),
                          ws: BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer())),
                          cache: cache, paths: tempPaths(),
                          clock: { Date(timeIntervalSince1970: Double(Self.lastOpen) / 1000 + 5) },
                          reconcileMs: 0)
    await feed.setSnapshotEnabled(false)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)

    // 首屏那一发真的卡在网络上了，图上只有打底那三根。
    #expect(await waitUntil(5) { await transport.arrived() > 0 })
    #expect(await feed.currentSeries.count == 3)

    await feed.enterBackground()
    await feed.enterForeground()
    await transport.release()

    // 回前台必须把首屏重开一发。原来这里是 loadTask 被掐掉 + 「缺口不足一根」直接返回，
    // 图就永远停在打底那三根上，直到用户自己再切一次品种。
    #expect(await waitUntil(5) { await feed.currentSeries.count >= MarketFeed.firstScreenLimit })
    await feed.stop()
  }

  // ---------------------------------------------------------------- BT-12

  @Test("BT-12 回前台补不补缺看真实时钟：同一根不补，隔了一根才补", .timeLimit(.minutes(1)))
  func pendingBarsDecidesByTheWallClock() async throws {
    /// 首屏真正落地的那一刻，只能听事件流：`currentSeries` 先于 `emit(.series)` 就满了，
    /// 那会儿 `fillOnce` 还卡在 `cache.put` 上（`filling` 仍是 true），这时候回前台
    /// 走的是「补发首屏」那条路，测不到这儿要测的缺口判定。
    let depth = Counter()
    func rig(_ clock: MovableClock) async -> (MarketFeed, HeldHistory, Task<Void, Never>) {
      let transport = HeldHistory(hold: false)
      let deck = ReplayDeck([.hang])
      let feed = MarketFeed(rest: BinanceREST(transport: transport),
                            ws: BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer())),
                            paths: tempPaths(),
                            clock: { clock.date },
                            reconcileMs: 0)
      await feed.setSnapshotEnabled(false)
      let events = await feed.events()
      depth.setTo(0)
      let collector = Task { [depth] in
        for await update in events {
          if case .series(let s) = update.event, s.count > depth.value { depth.setTo(s.count) }
        }
      }
      await feed.start(symbol: "BTCUSDT", interval: .m1)
      #expect(await waitUntil(5) { depth.value == BinanceREST.maxKlines })
      return (feed, transport, collector)
    }

    // ① 还在末根那一分钟之内：一根都不欠，不许发补缺请求。
    let sameBucket = MovableClock(Double(Self.lastOpen) / 1000 + 5)
    let (feedA, netA, collectorA) = await rig(sameBucket)
    #expect(await netA.backfillCalls == 0)
    await feedA.enterBackground()
    await feedA.enterForeground()
    // 等一秒钟，确认那一笔补缺请求**始终没有**发出来（它是异步派的，光看这一刻不算数）。
    #expect(await waitUntil(1) { await netA.backfillCalls > 0 } == false)
    await feedA.stop(); collectorA.cancel()

    // ② 过了一根：欠两根（末根 + 新开的那根），必须补。
    let nextBucket = MovableClock(Double(Self.lastOpen) / 1000 + 5)
    let (feedB, netB, collectorB) = await rig(nextBucket)
    nextBucket.set(Double(Self.lastOpen) / 1000 + 65)
    await feedB.enterBackground()
    await feedB.enterForeground()
    #expect(await waitUntil(5) { await netB.backfillCalls > 0 })
    await feedB.stop(); collectorB.cancel()
  }

  // ---------------------------------------------------------------- BT-05

  @Test("BT-05 后台那记 25 秒的闹钟醒来时人已回前台：不许掐当前连接", .timeLimit(.minutes(1)))
  func lateBackgroundAlarmKeepsTheLiveConnection() async throws {
    // 25 秒是有意的（宿主那边 27 秒的 BackgroundGrace 兜着它），这条用例顺便把它钉住。
    #expect(MarketFeed.backgroundGraceMs == 25_000)

    let transport = HeldHistory(hold: false)
    let deck = ReplayDeck([.hang])
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer()))
    let feed = MarketFeed(rest: BinanceREST(transport: transport), ws: ws,
                          paths: tempPaths(), reconcileMs: 0)
    await feed.setSnapshotEnabled(false)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(5) { await ws.currentConnectionID == 1 })

    await feed.enterBackground()
    let alarm = await feed.lifecycleEpochForTests   // 这记闹钟属于这一轮后台
    await feed.enterForeground()                    // 人回来了，WS 一直连着

    // 闹钟这时候才醒。它属于上一轮生命周期，只能作废。
    await feed.suspendForTests(lifecycle: alarm)
    #expect(await feed.isWSRunningForTests)
    #expect(await ws.currentConnectionID == 1)      // 同一条连接，没被掐过也没重连
    #expect(await deck.stats().connects == 1)

    // 真的留在后台时照断不误——别把闸门修成「永远不挂起」。
    await feed.enterBackground()
    await feed.suspendForTests(lifecycle: await feed.lifecycleEpochForTests)
    #expect(!(await feed.isWSRunningForTests))
    await feed.stop()
  }

  // ---------------------------------------------------------------- BT-01

  @Test("BT-01 上一份 feed 还在收摊时切品种：新品种的行情必须真的流出来",
        .timeLimit(.minutes(1)))
  func switchDuringActivateStillDeliversTheNewSymbol() async throws {
    let closing = Gate()
    let server = FakeServer { url in
      guard url.path.contains("klines") else {
        return json(#"{"symbol":"X","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
      }
      let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let limit = q.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 300
      return FeedLifecycleTests.klines(min(limit, 1500))
    }
    let hosts = BinanceHosts(streamFallbacks: ["gw.test"], oiProxy: "gw.test")
    let routed = RoutedMarketFeed(
      hosts: hosts, paths: tempPaths(), log: .silent,
      primary: BinanceREST(hosts: hosts, transport: FakeTransport(server), limiter: RateLimiter()),
      backup: BinanceREST(hosts: hosts, transport: FakeTransport(server), limiter: RateLimiter()),
      sockets: SlowCloseFactory(closing: closing), policy: .direct)

    let seen = Seen()
    let events = await routed.events()
    let collector = Task {
      for await update in events {
        if case .series(let s) = update.event { await seen.add(s.symbol) }
        if case .status(let st) = update.event { await seen.noteStatus(st) }
      }
    }
    await routed.start(symbol: "AAAUSDT", interval: .m1)
    #expect(await waitUntil(5) { await seen.has("AAAUSDT") })
    // 等这条连接真的连上：连上了 `stop()` 才会停在「关 socket」那一步，
    // 下面那个窗口才真的存在。不等的话 WS 还没连，停起来一瞬间就完事了。
    #expect(await waitUntil(5) { await seen.live })

    // 用户在设置里换了线路 → 重建一份 feed。旧的那份正卡在关连接上。
    let switching = Task { await routed.setRoutePolicy(.gateway) }
    #expect(await waitUntil(5) { await closing.arrived > 0 })

    // 就在这个窗口里切品种。原来 `feed` 字段还指着正在被拆掉的那份，
    // 这一笔切换会被交给它，然后 `activate` 回来发现 selection 变了就直接返回——
    // 谁也没在跑新品种，图就空在那儿。
    let entering = Gate()
    let switched = Task {
      await entering.open()                 // 我这条任务真的跑起来了
      await routed.switchTo(symbol: "BBBUSDT", interval: .m1)
    }
    await entering.wait()                   // 等它跑起来再让路，不然让的是空
    for _ in 0..<50 { await Task.yield() }
    _ = await routed.currentSeries          // 排在切品种后面，确认它已经进了 actor

    await closing.open()
    await switched.value
    await switching.value

    #expect(await waitUntil(5) { await seen.has("BBBUSDT") })
    collector.cancel()
    await routed.stop()
  }

  // ---------------------------------------------------------------- BT-09

  /// 一条 combined stream 的 kline 报文。`seq` 同时当事件时间与成交 ID，
  /// 保证同一根上的连续报文不会被合成器当成重复/乱序丢掉。
  private static func frame(open t: Int64, close c: Double, closed: Bool, seq: Int64) -> String {
    let px = String(format: "%.2f", c)
    let hi = String(format: "%.2f", max(100, c) + 1)
    return """
    {"stream":"btcusdt@kline_1m","data":{"e":"kline","E":\(t + seq),"s":"BTCUSDT",\
    "k":{"t":\(t),"T":\(t + step - 1),"s":"BTCUSDT","i":"1m","f":1,"L":\(seq),\
    "o":"100.00","c":"\(px)","h":"\(hi)","l":"99.00","v":"\(seq).0","n":7,\
    "x":\(closed),"q":"1000.0","V":"5.0","Q":"500.0","B":"0"}}}
    """
  }

  /// 收下来的事件。`blocked` 打开时每收一条先去闸门前排队——这就是「消费者卡住了」。
  private actor Inbox {
    private(set) var total = 0
    private(set) var bars: [Bar] = []
    func note(_ e: FeedEvent) {
      total += 1
      if case .lastBar(let b) = e { bars.append(b) }
    }
    func has(open: Int64, close: Double) -> Bool {
      bars.contains { $0.openTime == open && $0.close == close }
    }
    func opens() -> [Int64] { bars.map(\.openTime) }
  }

  @Test("BT-09 报文猛灌时消费者被闸门按住：放行后结构性事件一条都不能少",
        .timeLimit(.minutes(1)))
  func blockedConsumerLosesNoStructuralEvent() async throws {
    // 报文先停在闸门后面：REST 首屏没落地就放报文进来，合成器面对的是一张空图，
    // 那测的就不是「积压」而是「冷启动」了。
    let wsGate = Gate()
    let buckets = 6
    let updatesPerBucket = 4
    var steps: [ReplayStep] = [.hold(wsGate)]
    var seq: Int64 = 1
    // 每一根：先来几条半截更新（会被 80ms 合帧闸门攒起来），再来一条 x=true 定盘。
    var settlements: [(open: Int64, close: Double)] = []
    for i in 0..<buckets {
      let t = Self.lastOpen + Int64(i) * Self.step
      for j in 1...updatesPerBucket {
        steps.append(.frame(.text(Self.frame(open: t, close: 100 + Double(j), closed: false, seq: seq))))
        seq += 1
      }
      let settle = 110 + Double(i)
      steps.append(.frame(.text(Self.frame(open: t, close: settle, closed: true, seq: seq))))
      seq += 1
      settlements.append((t, settle))
    }
    steps.append(.hang)
    let sentFrames = steps.count - 2

    let transport = HeldHistory(hold: true)
    let deck = ReplayDeck(steps)
    // 阶梯时钟：合帧闸门那 80ms 在虚拟时间里过，不真的等。
    let feed = MarketFeed(rest: BinanceREST(transport: transport, limiter: RateLimiter(minGapMs: 0)),
                          ws: BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer())),
                          paths: tempPaths(), pacer: StepPacer(),
                          clock: { Date(timeIntervalSince1970: Double(Self.lastOpen) / 1000 + 5) },
                          reconcileMs: 0)
    await feed.setSnapshotEnabled(false)

    let inbox = Inbox()
    let blocking = Counter()
    let consumerGate = Gate()
    let events = await feed.events()
    let consumer = Task { [blocking] in
      for await u in events {
        if blocking.value == 1 { await consumerGate.wait() }
        await inbox.note(u.event)
      }
    }

    await feed.start(symbol: "BTCUSDT", interval: .m1)
    // WS 已经连上并停在闸门前，REST 首屏也已经卡在网络上了。
    #expect(await waitUntil(5) { await wsGate.arrived > 0 })
    #expect(await waitUntil(5) { await transport.arrived() > 0 })
    await transport.release()
    #expect(await waitUntil(5) { await feed.currentSeries.count == BinanceREST.maxKlines })

    // 现在把消费者按住，再把 30 条报文一次性灌进去。
    blocking.setTo(1)
    let beforeBlock = await inbox.total
    await wsGate.open()

    let lastBucket = Self.lastOpen + Int64(buckets - 1) * Self.step
    let lastClose = 110 + Double(buckets - 1)
    // 报文全被合成器吃进去了：序列已经走到最后一根的定盘值，而消费者还一条没收到。
    #expect(await waitUntil(5) {
      let s = await feed.currentSeries
      return s.count == BinanceREST.maxKlines + buckets - 1
        && s.lastTime == lastBucket && s.bar(at: s.count - 1).close == lastClose
    })
    #expect(await inbox.total == beforeBlock)

    // 放行，等最后那条定盘值到岸。
    await consumerGate.open()
    #expect(await waitUntil(5) { await inbox.has(open: lastBucket, close: lastClose) })
    let backlog = await inbox.total - beforeBlock

    // ① 每一根的 x=true 定盘值都必须到过消费者手上。一根只来一条，被闸门攒掉
    //    就再也没有第二条会带上它。
    for s in settlements {
      #expect(await inbox.has(open: s.open, close: s.close),
              "第 \(s.open) 根的收线值 \(s.close) 没到消费者手上")
    }
    // ② 每一次换桶都必须到过：图上少一根就是一个洞。
    let opens = await inbox.opens()
    for s in settlements { #expect(opens.contains(s.open), "换桶 \(s.open) 丢了") }
    // ③ 顺序不许乱。
    #expect(opens == opens.sorted())
    // ④ 观测：阻塞期间真的积压住了（不设阈值，只记录）。
    #expect(backlog > 0)
    print("BT-09 观测：灌入 \(sentFrames) 条报文，放行那一刻流里积压 \(backlog) 条事件，"
          + "其中末根事件 \(opens.count) 条")

    consumer.cancel()
    await feed.stop()
  }

  // ---------------------------------------------------------------- BT-11

  /// 会往前走的假交易所：手上有多少根由测试拨（`setLast`）。`klines` 认 `startTime`，
  /// 所以补缺请求拿回来的正是欠的那一段，不是又一份「到此刻为止」的整屏。
  private actor MovingExchange: HTTPTransport {
    private var last: Int64
    private(set) var urls: [URL] = []
    init(last: Int64) { self.last = last }
    func setLast(_ t: Int64) { last = t }
    /// 带 `startTime` 的才是补缺（首屏和对表都不带）。
    var backfillCalls: Int { urls.filter { ($0.query ?? "").contains("startTime") }.count }
    var klineCalls: Int { urls.filter { $0.path.contains("klines") }.count }

    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      urls.append(url)
      guard url.path.contains("klines") else {
        return json(#"{"symbol":"BTCUSDT","lastPrice":"100","priceChangePercent":"0","highPrice":"101","lowPrice":"99","quoteVolume":"1","closeTime":3000}"#)
      }
      let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      func v(_ n: String) -> String? { q.first { $0.name == n }?.value }
      let limit = min(v("limit").flatMap(Int.init) ?? 500, BinanceREST.maxKlines)
      let step = FeedLifecycleTests.step
      let oldest = last - Int64(BinanceREST.maxKlines - 1) * step
      var t = max(v("startTime").flatMap(Int64.init) ?? (last - Int64(limit - 1) * step), oldest)
      var rows: [String] = []
      while t <= last, rows.count < limit {
        rows.append("[\(t),\"100\",\"101\",\"99\",\"100\",\"1\",\(t + step - 1),\"1\",1,\"1\",\"1\",\"0\"]")
        t += step
      }
      return json("[" + rows.joined(separator: ",") + "]")
    }
  }

  /// 一套起好的 feed：首屏已落地、WS 已连上第一条连接。
  private struct GraceRig: Sendable {
    let feed: MarketFeed
    let ws: BinanceWS
    let deck: ReplayDeck
    let net: MovingExchange
    let pacer: ManualPacer
    let clock: MovableClock
    let collector: Task<Void, Never>
  }

  private func graceRig(enteringBackgroundAt offsetS: Double) async -> GraceRig {
    let clock = MovableClock(Double(Self.lastOpen) / 1000 + offsetS)
    let pacer = ManualPacer()
    let net = MovingExchange(last: Self.lastOpen)
    let deck = ReplayDeck([.hang])
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer()))
    let feed = MarketFeed(rest: BinanceREST(transport: net, limiter: RateLimiter(minGapMs: 0)),
                          ws: ws, paths: tempPaths(), pacer: pacer,
                          clock: { clock.date }, reconcileMs: 0)
    await feed.setSnapshotEnabled(false)
    // 首屏真正落地只能听事件流：`currentSeries` 满了的那会儿 `filling` 可能还挂着，
    // 那时候回前台走的是「补发首屏」而不是这儿要测的宽限判定（见 BT-12）。
    let depth = Counter()
    let events = await feed.events()
    let collector = Task { [depth] in
      for await u in events {
        if case .series(let s) = u.event, s.count > depth.value { depth.setTo(s.count) }
      }
    }
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(5) { depth.value == BinanceREST.maxKlines })
    #expect(await waitUntil(5) { await ws.currentConnectionID == 1 })
    return GraceRig(feed: feed, ws: ws, deck: deck, net: net, pacer: pacer, clock: clock,
                    collector: collector)
  }

  @Test("BT-11 后台 24.9 秒回来复用现有连接；25.1 秒回来才重连并补缺",
        .timeLimit(.minutes(1)))
  func backgroundGraceIsDecidedByTheClock() async throws {
    #expect(MarketFeed.backgroundGraceMs == 25_000)

    // ① 24.9 秒就回来了：闹钟还没响，连接原地复用，一个补缺请求都不许发。
    let a = await graceRig(enteringBackgroundAt: 5)
    let firstScreenCalls = await a.net.klineCalls
    await a.feed.enterBackground()
    // 那记 25 秒的闹钟真的排在钟上了，再拨针，不然拨的是空。
    #expect(await waitUntil(5) { await a.pacer.sleeping == 1 })
    await a.pacer.advance(24_900)
    #expect(await a.pacer.sleeping == 1)          // 差 100ms，没响
    a.clock.set(Double(Self.lastOpen) / 1000 + 29.9)   // 回来的时刻，还在同一根里
    await a.feed.enterForeground()

    #expect(await a.feed.isWSRunningForTests)
    #expect(await a.ws.currentConnectionID == 1)
    #expect(await a.deck.stats().connects == 1)   // 没重连
    #expect(await a.net.backfillCalls == 0)
    // 补缺是异步派的，光看这一刻不算数：确认它**始终**没发出来。
    #expect(await waitUntil(1) { await a.net.backfillCalls > 0 } == false)
    #expect(await a.net.klineCalls == firstScreenCalls)   // 首屏也没白重拉
    await a.feed.stop()
    a.collector.cancel()
    await a.pacer.drain()

    // ② 25.1 秒才回来：闹钟响过了，连接已经挂起，回来必须重连 + 补缺。
    let b = await graceRig(enteringBackgroundAt: 50)
    await b.net.setLast(Self.lastOpen + Self.step)   // 这段时间里市场走出了新的一根
    await b.feed.enterBackground()
    #expect(await waitUntil(5) { await b.pacer.sleeping == 1 })
    await b.pacer.advance(25_100)
    // 闹钟响了：WS 挂起，缺口记下了。
    #expect(await waitUntil(5) { await b.feed.isWSRunningForTests == false })
    b.clock.set(Double(Self.lastOpen) / 1000 + 75.1)
    await b.feed.enterForeground()

    #expect(await waitUntil(5) { await b.ws.currentConnectionID == 2 })
    #expect(await b.deck.stats().connects == 2)          // 连接数 +1
    #expect(await waitUntil(5) { await b.net.backfillCalls > 0 })
    // 补缺回来之后序列必须是完整的：新的一根接上了，中间没有洞。
    #expect(await waitUntil(5) { await b.feed.currentSeries.lastTime == Self.lastOpen + Self.step })
    let series = await b.feed.currentSeries
    #expect(series.count == BinanceREST.maxKlines + 1)
    #expect(Self.contiguous(series))
    await b.feed.stop()
    b.collector.cancel()
    await b.pacer.drain()
  }

  /// 一根不缺、一根不重。
  private static func contiguous(_ s: BarSeries) -> Bool {
    guard s.count > 1 else { return s.count == 1 }
    for i in 1..<s.count where s.time(at: i) - s.time(at: i - 1) != step { return false }
    return true
  }
}
