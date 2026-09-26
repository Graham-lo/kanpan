import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

// 压测 · 「过了多久」用的钟：设备睡着也要走、改系统时间不能动它。

private final class VirtualSeconds: @unchecked Sendable {
  private let lock = NSLock()
  private var t: TimeInterval = 1_000
  func now() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return t }
  func advance(_ s: TimeInterval) { lock.lock(); t += s; lock.unlock() }
}

private actor Counting503: HTTPTransport {
  private(set) var calls = 0
  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    calls += 1
    return json(#"{"error":"unavailable"}"#, status: 503)
  }
}

@Suite("压测 · 单调时钟与网关冷却账本")
struct StressMonotonicClockTests {
  /// 限流器的封禁、权重窗口、WS 看门狗与网关冷却都读这把钟。它必须是「睡着也走」的那把
  /// （`CLOCK_MONOTONIC_RAW`），不能是睡着就停的 uptime：两者之差就是开机以来睡过的总时长，
  /// 在睡过觉的机器上差几小时。
  @Test("MonoClock 与 SystemPacer 读的是睡着也走的单调钟")
  func clockCountsSleep() async {
    let continuous = Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e6
    let mono = MonoClock.nowMs()
    let pacer = await SystemPacer().nowMs()
    #expect(abs(mono - continuous) < 1_000)
    #expect(abs(pacer - continuous) < 1_000)
  }

  /// 冷却按注进来的单调钟到期：钟不走就一直冷却（和墙上时间怎么拨无关），钟走过冷却期就放行。
  @Test("网关冷却跟着单调钟走，不看墙上时间", .timeLimit(.minutes(1)))
  func cooldownFollowsInjectedClock() async throws {
    let clock = VirtualSeconds()
    let net = Counting503()
    let transport = MarketRESTTransport(
      source: .okx,
      route: MarketRoute(policy: .gateway, endpoints: MarketEndpoints(gateways: ["a.test", "b.test"])),
      transport: net, log: .silent, now: { clock.now() })
    let url = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=300")!

    _ = try? await transport.get(url, timeout: 5)
    let afterFirst = await net.calls
    #expect(afterFirst == 2, "两台都试过、都 503")

    // 钟没走：两台都在冷却里，这一笔不出站。
    _ = try? await transport.get(url, timeout: 5)
    #expect(await net.calls == afterFirst)

    // 钟走过冷却期：两台重新上场。
    clock.advance(61)
    _ = try? await transport.get(url, timeout: 5)
    #expect(await net.calls == afterFirst + 2)
  }
}
