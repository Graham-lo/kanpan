import SwiftUI
import Testing
@testable import Kanpan

// P2.10：看图时不锁屏——只在图表页在屏幕上、app 在前台、且不是低电量快没电的时候才真的撑住屏幕。
// 2026-09-28 起它不再是设置项，`enabled` 是「图表页在屏幕上」。
@Suite("常亮开关")
struct KeepAwakeGateTests {
  private func wants(
    _ enabled: Bool = true, _ phase: ScenePhase = .active, lowPower: Bool = false, battery: Float = 0.8
  ) -> Bool {
    KeepAwakeGate.wantsIdleTimerDisabled(enabled: enabled, phase: phase, lowPower: lowPower, battery: battery)
  }

  @Test("不在图表页就不撑")
  func off() { #expect(!wants(false)) }

  @Test("图表页在前台撑住，退后台放手，回前台再撑")
  func phases() {
    #expect(wants(true, .active))
    #expect(!wants(true, .background))
    #expect(wants(true, .inactive))
    #expect(wants(true, .active))
  }

  @Test("低电量模式且电量 ≤20% 放手；只满足一条不放")
  func lowBattery() {
    #expect(!wants(lowPower: true, battery: 0.20))
    #expect(!wants(lowPower: true, battery: 0.05))
    #expect(wants(lowPower: true, battery: 0.21))
    #expect(wants(lowPower: false, battery: 0.05))
    // 电量读不到（-1）不算低电。
    #expect(wants(lowPower: true, battery: -1))
  }
}
