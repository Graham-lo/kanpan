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
}
