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
}
