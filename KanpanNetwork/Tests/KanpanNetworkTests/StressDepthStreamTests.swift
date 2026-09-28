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
