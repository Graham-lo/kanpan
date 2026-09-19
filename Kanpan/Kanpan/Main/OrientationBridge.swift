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
    refreshSupportedOrientations()
    scene.requestGeometryUpdate(
      .iOS(interfaceOrientations: landscape ? .landscape : .portrait)
    ) { _ in }
    scheduleRelease()
  }

  /// 正排着的那次「放开方向锁」。见 `scheduleRelease(after:)`。
  private static var release: Task<Void, Never>?
  /// 第几次转屏。任务已经醒了、取消标记来不及生效的那一小段里，靠它认人。
  private static var intent = 0

  /// 下一拍放开方向锁。放得太早系统还没转完就会被自动方向拽回去，太晚用户会觉得手机卡住。
  ///
  /// 这一拍必须**只认最后一次意图**。画线工作台正是连着转两次的场景（点「画线」进横屏、
  /// 画完自动回竖屏），两次之间往往不到 600ms。原来这个复位任务没人拿着、也没人取消：
  /// 它会在新意图刚把 mask 设成 `.portrait` 之后，把 mask 抹回 `.allButUpsideDown`，
  /// 于是手一斜，系统按自动方向又把人转回横屏——用户看到的是「转回去了又自己转回来」。
  ///
  /// 所以留一个句柄：新的一次转屏先取消上一次的复位；再加一个序号兜底，任务已经醒来
  /// 但还没跑完那一小段里，也只有最后一次说了算。600ms 这个值本身不动。
  static func scheduleRelease(after milliseconds: Int = 600) {
    release?.cancel()
    intent &+= 1
    let mine = intent
    release = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(milliseconds))
      guard !Task.isCancelled, mine == intent else { return }
      release = nil
      OrientationBridge.mask = .allButUpsideDown
      refreshSupportedOrientations()
    }
  }

  /// 改完 `OrientationBridge.mask` 必须叫这一下，否则 UIKit 不会回来问。
  private static func refreshSupportedOrientations() {
    for window in scene?.windows ?? [] {
      window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
  }

  /// 还排着复位吗。给用例看的。
  static var hasPendingRelease: Bool { release != nil }

  /// 丢掉排着的复位（不动 mask）。用例收尾用，免得它跨用例醒来。
  static func cancelPendingRelease() { release?.cancel(); release = nil }
}
