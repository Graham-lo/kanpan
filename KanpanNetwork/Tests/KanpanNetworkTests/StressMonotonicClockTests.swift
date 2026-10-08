import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

// 压测 · 「过了多久」用的钟：设备睡着也要走、改系统时间不能动它。

@Suite("压测 · 单调时钟")
struct StressMonotonicClockTests {
  /// 限流器的封禁、权重窗口、WS 看门狗都读这把钟。它必须是「睡着也走」的那把
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
}
