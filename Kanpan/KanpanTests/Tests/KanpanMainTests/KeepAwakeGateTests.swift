import SwiftUI
import Testing
@testable import KanpanMain

// P2.10：「盯盘时不锁屏」只在前台、且不是低电量快没电的时候才真的撑住屏幕。
@Suite("常亮开关")
struct KeepAwakeGateTests {
  private func wants(
    _ enabled: Bool = true, _ phase: ScenePhase = .active, lowPower: Bool = false, battery: Float = 0.8
  ) -> Bool {
    KeepAwakeGate.wantsIdleTimerDisabled(enabled: enabled, phase: phase, lowPower: lowPower, battery: battery)
  }

  @Test("设置关着就不撑")
  func off() { #expect(!wants(false)) }

  @Test("前台按设置撑住，退后台放手，回前台再撑")
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
