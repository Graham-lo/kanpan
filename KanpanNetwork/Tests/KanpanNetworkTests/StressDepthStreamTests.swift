import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 压测（2026-09-26）：深度流在「调用方跟不上」与「过期的重拨请求」下的行为。
// 判据全是计数与退避序列（手拨的虚拟钟），不看墙钟。

/// 压测用的深度适配器：拨号交给 `StormBench`，每一帧文本解成一条消息。
private struct StormDepthAdapter: DepthFeedAdapter {
  let bench: StormBench
  var name: String { "压测深度" }
  var books: [DepthBook] { [] }
  var streamURLs: [URL] { [URL(string: "wss://depth.invalid/ws")!] }
  func connect(candidate: Int) async throws -> any WSSocket { try await bench.connect(to: streamURLs[0]) }
  func decode(_ text: String) -> [VenueMessage] { [VenueMessage("v", .reset)] }
  func fetchSnapshot(venueID: String) async throws -> BookSnapshot { throw FeedError.badResponse("压测不拉快照") }
  var keepAlive: DepthKeepAlive? { nil }
  func resubscribeMessages(venueID: String) -> [String]? { ["resub \(venueID)"] }
}

/// 退避睡的那几笔（看门狗的窗口设成天文数字，按大小分开）。
private func backoffSleeps(_ pacer: ManualPacer) async -> [Double] {
  await pacer.sleepLog().filter { $0 < 1e9 }
}

/// 等退避那一笔真的挂上钟，再把针拨到它的醒点。
private func advanceThroughBackoff(_ pacer: ManualPacer) async -> Bool {
  let armed = await waitUntil(5) { (await pacer.nextWakeIn).map { $0 < 1e9 } ?? false }
  guard armed, let wait = await pacer.nextWakeIn else { return false }
  await pacer.advance(wait)
  return true
}

@Suite("压测 · 深度流溢出与过期重拨")
struct StressDepthStreamTests {

  @Test("调用方一直跟不上、每条连接一推就溢出 × 20 → 重拨照常退避、涨到上限；活满 60 秒才溢出的算偶发、退避清零",
        .timeLimit(.minutes(1)))
  func overflowEscalatesBackoff() async throws {
    let bench = StormBench()
    let pacer = ManualPacer()
    let stream = DepthStream(adapter: StormDepthAdapter(bench: bench), pacer: pacer, silenceMs: 1e12,
                             backoff: Backoff(baseMs: 1000, capMs: 30_000, jitter: .none), bufferLimit: 1)
    // 故意不读：缓冲 1 条，已经被 `.connected` 占着，第一帧消息进来就挤掉最旧的 → 溢出。
    let events = await stream.start()
    let rounds = 20
    for round in 1...rounds {
      let connected = await waitUntil(5) { await bench.connects == round }
      #expect(connected, "第 \(round) 条连接没拨出来")
      guard connected, let s = await bench.latest() else { break }
      await s.push(.text("x"))
      // 溢出之后必须先退避：旧代码这里零间隔地拨下一条，调用方一直慢就是一条拨号风暴。
      let backedOff = await waitUntil(5) { await backoffSleeps(pacer).count == round }
      let dialed = await bench.connects
      #expect(backedOff, "第 \(round) 次溢出后没有退避（已拨 \(dialed) 条）")
      guard backedOff else { break }
      #expect(await bench.connects == round, "退避期间不许再拨")
      #expect(await advanceThroughBackoff(pacer))
    }
    let sleeps = await backoffSleeps(pacer)
    #expect(sleeps == [1000, 2000, 4000, 8000, 16_000] + Array(repeating: 30_000, count: rounds - 5))
    // 虚拟的前 5 分钟里一共拨了几条（旧代码：只受 CPU 限制，几毫秒一条）。
    var elapsed = 0.0, inFiveMinutes = 1
    for s in sleeps { elapsed += s; if elapsed <= 300_000 { inFiveMinutes += 1 } }
    #expect(inFiveMinutes == 14)

    // 一条连着活满 61 秒才溢出的：偶发，退避清零，下一笔从 1 秒起。
    #expect(await waitUntil(5) { await bench.connects == rounds + 1 })
    await pacer.advance(61_000)
    await bench.latest()?.push(.text("x"))
    #expect(await waitUntil(5) { await backoffSleeps(pacer).count == rounds + 1 })
    #expect(await backoffSleeps(pacer).last == 1000)

    await stream.stop()
    await pacer.drain()
    withExtendedLifetime(events) {}
  }

  @Test("针对旧连接的重拨 / 单本重订到达时新连接已经换上 → 不理会，新连接不被掐；针对当前连接的照常生效",
        .timeLimit(.minutes(1)))
  func staleRequestsLeaveTheNewConnectionAlone() async throws {
    let bench = StormBench()
    let pacer = ManualPacer()
    let stream = DepthStream(adapter: StormDepthAdapter(bench: bench), pacer: pacer, silenceMs: 1e12,
                             backoff: Backoff(baseMs: 1000, capMs: 30_000, jitter: .none))
    let events = await stream.start()
    let reader = Task { for await _ in events {} }

    #expect(await waitUntil(5) { await bench.connects == 1 })
    let first = try #require(await bench.latest())
    await first.push(.text("x"))
    // 服务器掐掉 #1；退避后换上 #2。调用方手里还有 #1 的积压消息，据此做出的判断都是过期的。
    await first.push(.closed("服务器踢了"))
    // #1 被掐之后、#2 连上之前（退避中）到的过期重拨：什么都不做。
    #expect(await waitUntil(5) { (await pacer.nextWakeIn).map { $0 < 1e9 } ?? false })
    await stream.reconnect(connection: 1)
    #expect(await advanceThroughBackoff(pacer))
    #expect(await waitUntil(5) { await bench.connects == 2 })
    let second = try #require(await bench.latest())
    #expect(await waitUntil(5) { await second.receiving == 1 })

    await stream.reconnect(connection: 1)
    #expect(await stream.resubscribe(["v"], connection: 1) == false)
    #expect(await staysFalse(for: 0.2) { await bench.connects > 2 }, "过期的重拨掐掉了新连接")
    #expect(await second.cancelCalls == 0)
    #expect(await second.sent.isEmpty, "过期的单本重订发到了新连接上")

    // 针对当前这条的照常生效：单本重订发出去，整条重拨立刻拨（主动要求，不退避）。
    #expect(await stream.resubscribe(["v"], connection: 2))
    #expect(await second.sent == ["resub v"])
    await stream.reconnect(connection: 2)
    #expect(await waitUntil(5) { await bench.connects == 3 })
    #expect(await second.cancelCalls >= 1)

    await stream.stop()
    reader.cancel()
    await pacer.drain()
  }
}

// MARK: - 订单簿压测（2026-09-28）：连上之后、登记连接之前的那一跳

/// 连上后要问一次钟（`pacer.nowMs()`，actor 跳转）：这一跳里 `stop()` / 再 `start()` 能插进来。
/// 这个钟可以把指定的前 n 次 `nowMs()` 挂住，等测试放行；睡眠走真时钟（保活要真的一拍一拍发）。
private actor GatedClock: Pacer {
  private var armed = 0
  private let gate = Gate()
  private(set) var parked = 0
  func arm(_ n: Int) { armed = n }
  func release() async { await gate.open() }
  func nowMs() async -> Double {
    if armed > 0 {
      armed -= 1
      parked += 1
      await gate.wait()
    }
    return MonoClock.nowMs()
  }
  nonisolated func sleep(ms: Double) async throws {
    try await Task.sleep(nanoseconds: UInt64(max(0, min(ms, 3_600_000)) * 1_000_000))
  }
}

/// 发 `GateSocket` 的深度适配器，带 OKX 那种定时保活（20ms 一句，好观察）。
private struct GatedDepthAdapter: DepthFeedAdapter {
  let bench: GateSocketBench
  var name: String { "压测深度·闸" }
  var books: [DepthBook] { [] }
  var streamURLs: [URL] { [URL(string: "wss://depth.invalid/ws")!] }
  func connect(candidate: Int) async throws -> any WSSocket { try await bench.connect(to: streamURLs[0]) }
  func decode(_ text: String) -> [VenueMessage] { [VenueMessage("v", .reset)] }
  func fetchSnapshot(venueID: String) async throws -> BookSnapshot { throw FeedError.badResponse("不拉快照") }
  var keepAlive: DepthKeepAlive? { DepthKeepAlive(text: "ping", everyMs: 20) }
  func resubscribeMessages(venueID: String) -> [String]? { nil }
}

@Suite("压测 · 深度流连上那一跳里被停 / 被重开")
struct DepthStreamConnectRaceTests {

  @Test("连上后问钟的那一跳里 stop() → 这条 socket 必须被掐、保活不许留下来一直发",
        .timeLimit(.minutes(1)))
  func stopDuringConnectHopCancelsTheSocket() async throws {
    let bench = GateSocketBench()
    let clock = GatedClock()
    await clock.arm(1)
    let stream = DepthStream(adapter: GatedDepthAdapter(bench: bench), pacer: clock, silenceMs: 1e12)
    let events = await stream.start()
    let reader = Task { for await _ in events {} }
    #expect(await waitUntil(5) { await clock.parked == 1 })
    let first = try #require(await bench.socket(1))
    await stream.stop()
    await clock.release()
    // 旧代码：醒来照样 `socket = s`、起保活，再撞上取消直接 return——这条 socket 没人掐，保活每 20ms 发一句。
    #expect(await waitUntil(2) { await first.cancelCalls >= 1 }, "stop 之后连上的那条 socket 没被掐（泄漏）")
    try await Task.sleep(nanoseconds: 150_000_000)
    let sentAfterStop = await first.sent.count
    #expect(await staysFalse(for: 0.2) { await first.sent.count > sentAfterStop }, "stop 之后保活还在发")
    #expect(await bench.live() == 0)
    reader.cancel()
  }

  @Test("连上后问钟的那一跳里又 start() 了一轮 → 旧 socket 被掐、新一轮的连接号 / 保活不被旧一轮改写",
        .timeLimit(.minutes(1)))
  func restartDuringConnectHopLeavesTheNewRunAlone() async throws {
    let bench = GateSocketBench()
    let clock = GatedClock()
    await clock.arm(1)
    let stream = DepthStream(adapter: GatedDepthAdapter(bench: bench), pacer: clock, silenceMs: 1e12)
    let oldEvents = await stream.start()
    let oldReader = Task { for await _ in oldEvents {} }
    #expect(await waitUntil(5) { await clock.parked == 1 })
    let first = try #require(await bench.socket(1))

    // 新一轮：连上 #2、拿到它的连接号。
    let events = await stream.start()
    var iterator = events.makeAsyncIterator()
    guard case .connected(let id)? = await iterator.next() else { Issue.record("新一轮没连上"); return }
    let second = try #require(await bench.socket(2))
    #expect(await waitUntil(5) { await second.receiving == 1 })
    // 前一个迭代器已不在等，换一个接着读（AsyncStream 只禁止同时两个在等）。
    let reader = Task { for await _ in events {} }

    await clock.release()
    #expect(await waitUntil(2) { await first.cancelCalls >= 1 }, "旧一轮连上的 #1 没被掐")
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(await bench.live() == 1, "同时活着不止一条连接")
    // 新一轮的保活还在发（旧代码里旧一轮的 startKeepAlive 把它 cancel 了）。
    let sent = await second.sent.count
    #expect(await waitUntil(2) { await second.sent.count > sent }, "新一轮的保活被旧一轮掐了")
    // 调用方按自己收到的连接号要求重拨：必须生效（旧代码里旧一轮把连接号又加了一，这句被当成过期请求不理）。
    await stream.reconnect(connection: id)
    #expect(await waitUntil(5) { await bench.connects == 3 }, "按当前连接号重拨被当成过期请求")
    #expect(await second.cancelCalls >= 1)

    await stream.stop()
    reader.cancel(); oldReader.cancel()
  }
}

// MARK: - 五家 × 四只、十分钟的帧（2026-10-08，接 Bybit 与 Hyperliquid 后）
//
// 每只币按注册表分连接（`OrderFlowCatalog.adapters`）：币安 U 本位 + 现货、OKX 永续 + 现货（一条）、Coinbase 现货、
// Bybit U 本位 + 现货（两条 category）、Hyperliquid 永续——4 只共 28 条深度流、32 本簿。每条流背后是一盘
// 「边播边生成」的帧带（照各家真帧的格式，播之前不在内存里攒），走真的 `DepthStream`（解码、看门狗、保活、
// 事件缓冲）进真的 `OrderFlowModel` 与 `BigTradeFlow`。模拟时间 10 分钟，时钟按 100 倍快进。

/// 可复现的伪随机（SplitMix64）。
private struct WireRNG {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
  mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
  mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
  mutating func double(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
  mutating func chance(_ p: Double) -> Bool { unit() < p }
}

/// 一本假簿：整数档位，买在中间价档以下、卖在以上。
private struct WireBook {
  let tick: Double, decimals: Int, mid: Int
  let qty: ClosedRange<Double>
  var bids: [Int: Double] = [:], asks: [Int: Double] = [:]

  init(tick: Double, decimals: Int, mid: Int, levels: Int, rng: inout WireRNG) {
    self.tick = tick; self.decimals = decimals; self.mid = mid
    let price = Double(mid) * tick
    qty = (0.5 * 60_000 / price)...(3 * 60_000 / price)
    for k in 1...levels {
      bids[mid - k] = rng.double(qty.lowerBound, qty.upperBound)
      asks[mid + k] = rng.double(qty.lowerBound, qty.upperBound)
    }
  }

  var midPrice: Double { Double(mid) * tick }
  func px(_ t: Int) -> String { String(format: "%.\(decimals)f", Double(t) * tick) }
  static func qs(_ q: Double) -> String { q == 0 ? "0" : String(format: "%.6f", q) }

  /// 每侧离中间价最近的 `n` 档。
  func top(_ n: Int) -> (bids: [(String, String)], asks: [(String, String)]) {
    (bids.keys.sorted(by: >).prefix(n).map { (px($0), Self.qs(bids[$0]!)) },
     asks.keys.sorted().prefix(n).map { (px($0), Self.qs(asks[$0]!)) })
  }

  /// `n` 档变动（两成删档），离中间价最远 `reach` 档。
  mutating func change(_ n: Int, reach: Int, rng: inout WireRNG) -> (bids: [(String, String)], asks: [(String, String)]) {
    var b: [(String, String)] = [], a: [(String, String)] = []
    for _ in 0..<n {
      let off = rng.int(1...reach)
      let q = rng.chance(0.2) ? 0 : rng.double(qty.lowerBound, qty.upperBound)
      if rng.chance(0.5) {
        bids[mid - off] = q == 0 ? nil : q; b.append((px(mid - off), Self.qs(q)))
      } else {
        asks[mid + off] = q == 0 ? nil : q; a.append((px(mid + off), Self.qs(q)))
      }
    }
    return (b, a)
  }
}

private func pairs(_ xs: [(String, String)]) -> String {
  "[" + xs.map { #"[""# + $0.0 + #"",""# + $0.1 + #""]"# }.joined(separator: ",") + "]"
}

/// 一条连接的帧脚本：第 `tick` 拍（100 ms 一拍）这条连接上推哪几帧。顺手记下这些帧会解出几条消息。
private final class WireScript: @unchecked Sendable {
  static let t0: Int64 = 1_800_000_000_000
  let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
  }()
  let exchange: String
  let books: [DepthBook]
  let ticks: Int
  var truths: [WireBook]
  var seq: [Int64]
  var rng: WireRNG
  var connectionSeq: Int64 = 0  // Coinbase：整条连接一个序号
  private(set) var expected = 0
  private(set) var frames = 0

  init(exchange: String, books: [DepthBook], ticks: Int, coin: (tick: Double, decimals: Int, mid: Int), seed: UInt64) {
    self.exchange = exchange; self.books = books; self.ticks = ticks
    rng = WireRNG(state: seed)
    var r = rng
    // Hyperliquid 的格（nSigFigs 4）比各家粗十倍。
    let tick = exchange == "hyperliquid" ? coin.tick * 10 : coin.tick
    let mid = exchange == "hyperliquid" ? coin.mid / 10 : coin.mid
    let made = books.map { _ in WireBook(tick: tick, decimals: coin.decimals, mid: mid, levels: 500, rng: &r) }
    truths = made
    rng = r
    seq = books.map { _ in 9_000 }
    rest = Dictionary(books.indices.map { i -> (String, String) in
      let top = made[i].top(500)
      return (books[i].venue.instrument,
              #"{"lastUpdateId":9003,"E":\#(Self.t0),"bids":"# + pairs(top.bids) + #","asks":"# + pairs(top.asks) + "}")
    }, uniquingKeysWith: { a, _ in a })
  }

  /// 币安 REST 快照（开播前那一刻的簿；`lastUpdateId` 落在第一条增量的区间里）。建好就不变，别的线程读安全。
  let rest: [String: String]
  func restSnapshot(_ symbol: String) -> String? { rest[symbol] }

  func frames(_ tick: Int) -> [String] {
    let now = Self.t0 + Int64(tick) * 100
    var out: [String] = []
    for i in books.indices {
      let sym = books[i].venue.instrument
      switch exchange {
      case "binance":
        let c = truths[i].change(rng.int(10...60), reach: 300, rng: &rng)
        let u = seq[i] + 3
        let pu = books[i].venue.product == .spot ? "" : #","pu":\#(seq[i])"#
        out.append(#"{"stream":"\#(sym.lowercased())@depth@100ms","data":{"e":"depthUpdate","E":\#(now),"T":\#(now),"s":"\#(sym)","U":\#(seq[i] + 1),"u":\#(u)\#(pu),"b":"#
          + pairs(c.bids) + #","a":"# + pairs(c.asks) + "}}")
        seq[i] = u; expected += 1
        for _ in 0..<rng.int(0...2) {
          let (p, q, buy) = trade(i)
          out.append(#"{"stream":"\#(sym.lowercased())@aggTrade","data":{"e":"aggTrade","E":\#(now),"s":"\#(sym)","a":1,"p":"\#(p)","q":"\#(q)","f":1,"l":1,"T":\#(now),"m":\#(!buy)}}"#)
          expected += 1
        }
      case "okx":
        let action: String, levels: (bids: [(String, String)], asks: [(String, String)]), prev: Int64
        if tick == 1 {
          action = "snapshot"; levels = truths[i].top(OKXBooksAdapter.snapshotLevels); prev = -1
        } else {
          action = "update"; levels = truths[i].change(rng.int(10...60), reach: 300, rng: &rng); prev = seq[i]
        }
        seq[i] += 1
        out.append(#"{"arg":{"channel":"books","instId":"\#(sym)"},"action":"\#(action)","data":[{"asks":"# + okxLevels(levels.asks)
          + #","bids":"# + okxLevels(levels.bids) + #","ts":"\#(now)","checksum":0,"prevSeqId":\#(prev),"seqId":\#(seq[i])}]}"#)
        expected += 1
        let n = rng.int(0...3)
        if n > 0 {
          let items = (0..<n).map { _ -> String in
            let (p, q, buy) = trade(i)
            return #"{"instId":"\#(sym)","tradeId":"1","px":"\#(p)","sz":"\#(q)","side":"\#(buy ? "buy" : "sell")","ts":"\#(now)","count":"1"}"#
          }
          out.append(#"{"arg":{"channel":"trades","instId":"\#(sym)"},"data":["# + items.joined(separator: ",") + "]}")
          expected += n
        }
      case "coinbase":
        let time = iso.string(from: Date(timeIntervalSince1970: Double(now) / 1000))
        let snapshot = tick == 1
        let levels = snapshot ? truths[i].top(500) : truths[i].change(rng.int(10...60), reach: 300, rng: &rng)
        let ups = levels.bids.map { ("bid", $0) } + levels.asks.map { ("offer", $0) }
        connectionSeq += 1
        out.append(#"{"channel":"l2_data","timestamp":"\#(time)","sequence_num":\#(connectionSeq),"events":[{"type":"\#(snapshot ? "snapshot" : "update")","product_id":"\#(sym)","updates":["#
          + ups.map { #"{"side":"\#($0.0)","event_time":"\#(time)","price_level":"\#($0.1.0)","new_quantity":"\#($0.1.1)"}"# }.joined(separator: ",")
          + "]}]}")
        expected += 1
        let n = rng.int(0...3)
        if n > 0 {
          let items = (0..<n).map { _ -> String in
            let (p, q, buy) = trade(i)
            return #"{"trade_id":"1","product_id":"\#(sym)","price":"\#(p)","size":"\#(q)","side":"\#(buy ? "BUY" : "SELL")","time":"\#(time)"}"#
          }
          connectionSeq += 1
          out.append(#"{"channel":"market_trades","timestamp":"\#(time)","sequence_num":\#(connectionSeq),"events":[{"type":"update","trades":["#
            + items.joined(separator: ",") + "]}]}")
          expected += 1 + n
        }
      case "bybit":
        // orderbook.1000 每 200 ms 一帧。
        if tick == 1 || tick % 2 == 0 {
          let snapshot = tick == 1
          let levels = snapshot ? truths[i].top(BybitBooksAdapter.snapshotLevels)
                                : truths[i].change(rng.int(10...60), reach: 300, rng: &rng)
          seq[i] += 1
          out.append(#"{"topic":"orderbook.1000.\#(sym)","ts":\#(now),"type":"\#(snapshot ? "snapshot" : "delta")","data":{"s":"\#(sym)","b":"#
            + pairs(levels.bids) + #","a":"# + pairs(levels.asks) + #","u":\#(seq[i]),"seq":\#(seq[i] * 7)},"cts":\#(now)}"#)
          expected += 1
        }
        let n = rng.int(0...3)
        if n > 0 {
          let items = (0..<n).map { _ -> String in
            let (p, q, buy) = trade(i)
            return #"{"T":\#(now),"s":"\#(sym)","S":"\#(buy ? "Buy" : "Sell")","v":"\#(q)","p":"\#(p)","L":"PlusTick","i":"x","BT":false,"RPI":false,"seq":1}"#
          }
          out.append(#"{"topic":"publicTrade.\#(sym)","type":"snapshot","ts":\#(now),"data":["# + items.joined(separator: ",") + "]}")
          expected += n
        }
      case "hyperliquid":
        // l2Book 每 1 秒一份整本 20 档（实测约 2.7 秒一份，这里更密）。
        if tick == 1 || tick % 10 == 0 {
          _ = truths[i].change(rng.int(10...60), reach: 60, rng: &rng)
          let top = truths[i].top(20)
          func side(_ xs: [(String, String)]) -> String {
            "[" + xs.map { #"{"px":"\#($0.0)","sz":"\#($0.1)","n":3}"# }.joined(separator: ",") + "]"
          }
          out.append(#"{"channel":"l2Book","data":{"coin":"\#(sym)","time":\#(now),"levels":["# + side(top.bids) + "," + side(top.asks) + "]}}")
          expected += 1
        }
        let n = rng.int(0...3)
        if n > 0 {
          let items = (0..<n).map { _ -> String in
            let (p, q, buy) = trade(i)
            return #"{"coin":"\#(sym)","side":"\#(buy ? "B" : "A")","px":"\#(p)","sz":"\#(q)","time":\#(now),"hash":"0x0","tid":1}"#
          }
          out.append(#"{"channel":"trades","data":["# + items.joined(separator: ",") + "]}")
          expected += n
        }
      default:
        break
      }
    }
    frames += out.count
    return out
  }

  private func okxLevels(_ xs: [(String, String)]) -> String {
    "[" + xs.map { #"[""# + $0.0 + #"",""# + $0.1 + #"","0","2"]"# }.joined(separator: ",") + "]"
  }

  /// 一笔成交：中间价两侧一档，名义 200 美元到 6 万美元。
  private func trade(_ i: Int) -> (String, String, Bool) {
    let buy = rng.chance(0.5)
    let t = truths[i].mid + (buy ? 1 : -1)
    let p = Double(t) * truths[i].tick
    return (truths[i].px(t), String(format: "%.6f", rng.double(200, 60_000) / p), buy)
  }
}

/// 一盘帧带：每拍现生成、播完挂着。只有一个读者（深度流的收帧循环）。
private actor WireTape: WSSocket {
  let script: WireScript
  let pacer: FastPacer
  private var queue: [String] = []
  private var head = 0
  private(set) var tick = 0
  private(set) var sent: [String] = []

  init(script: WireScript, pacer: FastPacer) { self.script = script; self.pacer = pacer }

  var drained: Bool { tick >= script.ticks && head >= queue.count }

  func receive() async throws -> WSFrame {
    while head >= queue.count {
      if tick >= script.ticks { try await pacer.sleep(ms: 3_600_000); continue }
      // 每 1 秒（10 拍）按快进时钟歇一下：帧按真实节奏的快进倍速到，不是一口气灌完。
      if tick > 0, tick % 10 == 0 { try await pacer.sleep(ms: 1_000) }
      tick += 1
      queue = script.frames(tick); head = 0
    }
    defer { head += 1 }
    return .text(queue[head])
  }

  func send(_ text: String) async throws { sent.append(text) }
  func pong() async throws {}
  func cancel() async {}
}

/// 按 URL 把连接接到各自的帧带上；数每个 URL 拨了几次（> 1 就是重连过）。
private final class WireFactory: WSSocketFactory, @unchecked Sendable {
  private let lock = NSLock()
  private var tapes: [URL: WireTape] = [:]
  private var dials: [URL: Int] = [:]

  func attach(_ url: URL, _ tape: WireTape) { lock.withLock { tapes[url] = tape } }
  var redials: Int { lock.withLock { dials.values.reduce(0) { $0 + max(0, $1 - 1) } } }

  func connect(to url: URL) async throws -> WSSocket {
    let tape: WireTape? = lock.withLock { dials[url, default: 0] += 1; return tapes[url] }
    guard let tape else { throw FeedError.badResponse("没有这条帧带：\(url)") }
    return tape
  }
}

/// 一只币的模型与大单流。
private actor WireDesk {
  var model: OrderFlowModel
  var flow: BigTradeFlow
  let cut: Double?
  var clock: Int64 = WireScript.t0
  var nextEval: Int64 = WireScript.t0 + 500
  var nextBeat: Int64 = WireScript.t0 + 1_000
  var received = 0, deltas = 0, snapshots = 0, trades = 0, bigTrades = 0, fetched = 0
  var problems: [String] = []
  var evalMs: [Double] = []
  var maxLive = 0
  var byExchange: [String: Int] = [:]

  init(symbol: String, thresholds: OrderFlowThresholds, books: [DepthBook]) {
    model = OrderFlowModel(symbol: symbol, thresholds: thresholds)
    for b in books { model.addVenue(b.venue) }
    flow = BigTradeFlow(symbol: symbol)
    cut = BigTradeFlow.threshold(thresholds).map(BigTradeFlow.cut(threshold:))
  }

  /// 新连接：每本换连接号；回要拉 REST 快照的簿（币安）。
  func opened(_ books: [DepthBook]) -> [String] {
    books.filter { model.connectionOpened($0.id) == .fetchSnapshot }.map(\.id)
  }

  /// 吃一批消息；回要拉 REST 快照的簿。
  func ingest(_ ms: [VenueMessage], exchangeOf: [String: String]) -> [String] {
    var need: [String] = []
    for m in ms {
      received += 1
      let t: Int64?
      switch m.message {
      case .delta(let d): deltas += 1; t = d.eventTimeMs > 0 ? d.eventTimeMs : nil
      case .snapshot(let s): snapshots += 1; t = s.eventTimeMs
      case .trade(let tr):
        trades += 1; t = tr.timeMs
        let usd = tr.price * tr.quantity
        if flow.record(timeMs: tr.timeMs, price: tr.price, usd: usd, buy: tr.hitSide == .ask, cut: cut) {
          bigTrades += 1; byExchange[exchangeOf[m.venueID] ?? "?", default: 0] += 1
        }
      case .reset: problems.append("\(m.venueID) 收到重置"); t = nil
      }
      if let t { clock = max(clock, t) }
      switch model.ingest(m.venueID, m.message, nowMs: clock) {
      case .none: break
      case .fetchSnapshot: if !need.contains(m.venueID) { need.append(m.venueID) }
      case .resubscribe: problems.append("\(m.venueID) 要重订")
      }
      while clock >= nextEval {
        var frame = OrderFlowSnapshot.loading("x")
        let t0 = DispatchTime.now().uptimeNanoseconds
        frame = model.evaluate(nowMs: nextEval)
        evalMs.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        maxLive = max(maxLive, frame.orders.count(where: \.isLive))
        nextEval += 500
      }
      while clock >= nextBeat { flow.beat(nowMs: nextBeat, ok: true); nextBeat += 1_000 }
    }
    return need
  }

  func applySnapshot(_ id: String, _ s: BookSnapshot) {
    fetched += 1
    if model.applySnapshot(id, s, nowMs: clock) != .none { problems.append("\(id) REST 快照没接上") }
  }

  func note(_ p: String) { problems.append(p) }
  func ready(_ ids: [String]) -> [String] { ids.filter { !model.isReady($0) } }
  func sum(_ a: Int64, _ b: Int64) -> BigTradeSum { flow.sum(a, b, nowMs: clock) }
}

private func residentMB() -> Double {
  var info = mach_task_basic_info()
  var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
  let kr = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
    }
  }
  return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : .nan
}

@Suite("压测 · 五家交易所 × 四只币、十分钟的深度流")
struct StressFiveVenueStreamTests {
  static let coins: [(base: String, tick: Double, decimals: Int, mid: Int)] = [
    ("BTC", 1, 0, 60_000), ("ETH", 0.1, 1, 30_000), ("SOL", 0.01, 2, 15_000), ("DOGE", 0.00001, 5, 15_000),
  ]

  /// 一只币的 8 本簿（经品种表的 `venue` 拿注册表定的序号模型与快照来路）。
  static func books(_ base: String) -> [DepthBook] {
    let rows: [(String, OrderFlowProduct, String)] = [
      ("binance", .usdtPerp, "\(base)USDT"), ("binance", .spot, "\(base)USDT"),
      ("okx", .usdtPerp, "\(base)-USDT-SWAP"), ("okx", .spot, "\(base)-USDT"),
      ("coinbase", .spot, "\(base)-USD"),
      ("bybit", .usdtPerp, "\(base)USDT"), ("bybit", .spot, "\(base)USDT"),
      ("hyperliquid", .usdtPerp, base),
    ]
    return rows.map {
      DepthBook(venue: OrderFlowCatalog.venue(exchange: $0.0, product: $0.1, instrument: $0.2, notional: .linear(multiplier: 1)))
    }
  }

  private static func fetch(_ id: String, _ adapter: any DepthFeedAdapter, _ desk: WireDesk) async {
    do { await desk.applySnapshot(id, try await adapter.fetchSnapshot(venueID: id)) }
    catch { await desk.note("\(id) 拉快照失败 \(error)") }
  }

  @Test("32 本簿、28 条流、模拟 10 分钟：五家的帧全部解出来进模型，一本都不掉、不重拨、不重订；大单流记到五家",
        .timeLimit(.minutes(5)))
  func fiveExchangesFourCoinsTenMinutes() async throws {
    let ticks = 6_000
    let pacer = FastPacer(scale: 0.1)
    let rssStart = residentMB()
    let wall0 = DispatchTime.now().uptimeNanoseconds

    var desks: [WireDesk] = [], streams: [DepthStream] = [], readers: [Task<Void, Never>] = []
    var tapes: [WireTape] = [], scripts: [WireScript] = [], factories: [WireFactory] = []
    var allBooks: [[DepthBook]] = []
    var adapterCount = 0
    for (c, coin) in Self.coins.enumerated() {
      let books = Self.books(coin.base)
      allBooks.append(books)
      let exchangeOf = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0.venue.exchange) })
      let factory = WireFactory()
      let scriptsBox = WireSnapshots()
      let server = FakeServer { url in
        let symbol = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "symbol" }?.value ?? ""
        return scriptsBox.snapshot(symbol).map { json($0) } ?? json("{}", status: 404)
      }
      let catalog = OrderFlowCatalog(route: MarketRoute(policy: .direct, endpoints: MarketEndpoints(gateways: OrderFlowAdapterTests.gateways)),
                                     sockets: factory, http: FakeTransport(server), cache: OrderFlowCatalogCache())
      let adapters = catalog.adapters(books)
      adapterCount += adapters.count
      let threshold = 1_100_000.0
      let desk = WireDesk(symbol: "\(coin.base)USDT",
                          thresholds: OrderFlowThresholds(spot: threshold, usdtPerp: threshold, coinPerp: threshold,
                                                          delivery: threshold, step: coin.tick * 10),
                          books: books)
      desks.append(desk); factories.append(factory)
      for (k, adapter) in adapters.enumerated() {
        let exchange = adapter.books[0].venue.exchange
        let script = WireScript(exchange: exchange, books: adapter.books, ticks: ticks,
                                coin: (coin.tick, coin.decimals, coin.mid), seed: 0xF1E0 + UInt64(c * 16 + k))
        if exchange == "binance" { scriptsBox.add(script) }
        let tape = WireTape(script: script, pacer: pacer)
        factory.attach(try #require(adapter.streamURLs.first), tape)
        tapes.append(tape); scripts.append(script)
        // 看门狗窗口放宽到模拟 1 小时：机器一忙、快进时钟上的 30 秒只有 3 秒墙钟，别把慢当断。
        // 时钟快进 10 倍，同样多的帧挤在十分之一的墙钟里到，事件缓冲同比放大 10 倍（缓冲满了丢帧另有专测）。
        let stream = DepthStream(adapter: adapter, pacer: pacer, silenceMs: 3_600_000,
                                 bufferLimit: DepthStream.bufferLimit * 10)
        streams.append(stream)
        let events = await stream.start()
        let mine = adapter.books
        readers.append(Task {
          for await e in events {
            switch e {
            case .connected:
              for id in await desk.opened(mine) { await Self.fetch(id, adapter, desk) }
            case .messages(let ms):
              for id in await desk.ingest(ms, exchangeOf: exchangeOf) { await Self.fetch(id, adapter, desk) }
            case .disconnected(let why): await desk.note("断线：\(why)")
            }
          }
        })
      }
    }

    // 等全部帧带播完、消息全部进了模型（期间每 200 ms 量一次常驻内存）。
    var rssPeak = rssStart
    let deadline = DispatchTime.now().uptimeNanoseconds + 240 * 1_000_000_000
    while DispatchTime.now().uptimeNanoseconds < deadline {
      rssPeak = max(rssPeak, residentMB())
      var played = true
      for t in tapes where !(await t.drained) { played = false; break }
      if played {
        let expected = scripts.reduce(0) { $0 + $1.expected }
        var got = 0
        for d in desks { got += await d.received }
        if got >= expected { break }
      }
      try await Task.sleep(nanoseconds: 200_000_000)
    }
    let wallS = Double(DispatchTime.now().uptimeNanoseconds - wall0) / 1e9
    var problems: [String] = []
    for d in desks { problems += await d.problems }
    for s in streams { await s.stop() }
    for r in readers { r.cancel() }

    let expected = scripts.reduce(0) { $0 + $1.expected }
    let frames = scripts.reduce(0) { $0 + $1.frames }
    var received = 0, deltas = 0, snapshots = 0, trades = 0, bigTrades = 0, fetched = 0, maxLive = 0
    var evalMs: [Double] = []
    var byExchange: [String: Int] = [:]
    let end = WireScript.t0 + Int64(ticks) * 100
    for (c, d) in desks.enumerated() {
      received += await d.received; deltas += await d.deltas; snapshots += await d.snapshots
      trades += await d.trades; bigTrades += await d.bigTrades; fetched += await d.fetched
      maxLive = max(maxLive, await d.maxLive); evalMs += await d.evalMs
      for (k, v) in await d.byExchange { byExchange[k, default: 0] += v }
      let notReady = await d.ready(allBooks[c].map(\.id))
      #expect(notReady.isEmpty, "\(Self.coins[c].base) 有簿没就绪：\(notReady)")
      let s = await d.sum(WireScript.t0, end + 1)
      #expect(s.has && s.buyUsd + s.sellUsd > 0, "\(Self.coins[c].base) 大单流没记到成交")
    }
    let redials = factories.reduce(0) { $0 + $1.redials }
    evalMs.sort()
    let p50 = evalMs.isEmpty ? 0 : evalMs[evalMs.count / 2]
    let p95 = evalMs.isEmpty ? 0 : evalMs[min(evalMs.count - 1, Int(Double(evalMs.count - 1) * 0.95))]
    let f = { (x: Double) in String(format: "%.3f", x) }
    print("【订单簿压测】五家深度流 4 只 × 8 本 = 32 本、\(adapterCount) 条流（币安 2、OKX 1、Coinbase 1、Bybit 2、Hyperliquid 1 / 只），"
      + "模拟 10 分钟（\(ticks) 拍 × 100 ms，时钟快进 10 倍）：帧 \(frames) 条 → 消息 \(received)/\(expected) 条"
      + "（增量 \(deltas)、整本 \(snapshots)、成交 \(trades)，大单 \(bigTrades)：\(byExchange.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " / "))）；"
      + "币安 REST 快照 \(fetched) 次；重拨 \(redials) 次；墙钟 \(String(format: "%.2f", wallS)) s")
    print("【订单簿压测】五家深度流 单只 evaluate p50 \(f(p50)) ms / p95 \(f(p95)) ms（\(evalMs.count) 次）；挂着峰值 \(maxLive) 条；"
      + "常驻内存 起 \(String(format: "%.1f", rssStart)) MB / 峰值 \(String(format: "%.1f", rssPeak)) MB")

    #expect(adapterCount == 28)
    #expect(received == expected, "有消息没进模型（被挤掉或没解出来）")
    #expect(problems.isEmpty, "\(problems.prefix(5))")
    #expect(redials == 0, "整场不该重拨")
    #expect(fetched >= 8, "币安 8 本都该拉过快照")
    #expect(Set(byExchange.keys) == ["binance", "okx", "coinbase", "bybit", "hyperliquid"], "大单流要记到五家")
    #expect(rssPeak - rssStart < 512, "十分钟里常驻内存涨了半个 G 以上")
  }
}

/// 币安 REST 快照由帧脚本出（服务端那头只看 symbol）。
private final class WireSnapshots: @unchecked Sendable {
  private let lock = NSLock()
  private var scripts: [WireScript] = []
  func add(_ s: WireScript) { lock.withLock { scripts.append(s) } }
  func snapshot(_ symbol: String) -> String? {
    lock.withLock { scripts.lazy.compactMap { $0.restSnapshot(symbol) }.first }
  }
}
