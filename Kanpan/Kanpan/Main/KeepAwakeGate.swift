import Combine
import SwiftUI
import UIKit

/// 「看图时不锁屏」的真正开关（P2.10）。
///
/// 2026-09-28 起不再是设置项（原来的 `Prefs.keepAwake` 收掉了）：`enabled` 是「图表页在屏幕上」
/// ——底栏停在图表、复盘本没盖着（`MainScreen` 算好传进来）。离开图表页就放手。
/// 屏幕到底常不常亮还要看两件事：
/// - app 退到后台就放手，回到前台、还在图表页再设回去；
/// - 低电量模式下电量掉到 20% 及以下也放手——这时候再替人撑着屏幕是在跟系统抢电。
///
/// 规则收在 `wantsIdleTimerDisabled` 这一个纯函数里，视图只负责把系统信号喂进来。
struct KeepAwakeGate: ViewModifier {
  let enabled: Bool
  let phase: ScenePhase

  @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
  @State private var battery: Float = -1

  /// 电量未知（模拟器、监测没开起来）记作 -1，不算低电。
  static let lowBatteryLevel: Float = 0.20

  static func wantsIdleTimerDisabled(
    enabled: Bool, phase: ScenePhase, lowPower: Bool, battery: Float
  ) -> Bool {
    guard enabled, phase != .background else { return false }
    if lowPower, battery >= 0, battery <= lowBatteryLevel { return false }
    return true
  }

  private var wanted: Bool {
    Self.wantsIdleTimerDisabled(enabled: enabled, phase: phase, lowPower: lowPower, battery: battery)
  }

  func body(content: Content) -> some View {
    content
      .onAppear {
        UIDevice.current.isBatteryMonitoringEnabled = true
        battery = UIDevice.current.batteryLevel
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
      }
      .onReceive(
        // 这条通知是在任意线程发的，先挪回主线程再改状态。
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
          .receive(on: DispatchQueue.main)
      ) { _ in
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
      }
      .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
        battery = UIDevice.current.batteryLevel
      }
      .onChange(of: wanted, initial: true) { _, on in
        UIApplication.shared.isIdleTimerDisabled = on
      }
  }
}
