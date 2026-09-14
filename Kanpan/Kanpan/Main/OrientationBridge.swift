import SwiftUI
import UIKit

/// 转屏这件事 SwiftUI 自己说了不算——`supportedInterfaceOrientations` 是 UIKit 问
/// app delegate 的（§10.7「跟随系统转屏，或点底栏『横屏』强制横屏」）。
///
/// 所以这里留一个最小的 delegate：平时报「随便转」，点了横屏就临时只报横屏、逼系统
/// 转过去，转完立刻放开——一直锁着的话用户自己转回竖屏就转不动了，那不是「强制横屏」
/// 是「卡在横屏」。
final class OrientationBridge: NSObject, UIApplicationDelegate {
  /// 当前允许的方向。改完必须叫 `setNeedsUpdateOfSupportedInterfaceOrientations()`，
  /// 否则 UIKit 不会回来问。
  static var mask: UIInterfaceOrientationMask = .allButUpsideDown

  func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    Self.mask
  }
}

@MainActor
enum Orientation {
  private static var scene: UIWindowScene? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
      ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
  }

  static var isLandscape: Bool { scene?.interfaceOrientation.isLandscape ?? false }

  /// 转到横屏 / 竖屏。
  ///
  /// 系统开了方向锁的时候 `requestGeometryUpdate` 照样转得动——锁的是「跟着重力转」，
  /// 不是「app 不许指定方向」。转完把 mask 放回 `.allButUpsideDown`，手转就又生效了。
  static func rotate(to landscape: Bool) {
    guard let scene else { return }
    OrientationBridge.mask = landscape ? .landscape : .portrait
    for window in scene.windows {
      window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
    scene.requestGeometryUpdate(
      .iOS(interfaceOrientations: landscape ? .landscape : .portrait)
    ) { _ in }
    // 下一拍放开。放得太早系统还没转完就会被自动方向拽回去，太晚用户会觉得手机卡住。
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(600))
      OrientationBridge.mask = .allButUpsideDown
      for window in scene.windows {
        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
      }
    }
  }
}
