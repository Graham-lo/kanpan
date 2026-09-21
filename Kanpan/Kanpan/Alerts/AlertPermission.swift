import Combine
import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// 通知权限在提醒总表上的那一行（方案 2.3「权限时机」后半句）。
///
/// 权限**不在这儿申请**——第一次点「加入提醒」那一下才问，问的人是
/// `AlertNotifications.requestAuthorization()`。这个类只管一件事：
/// 用户已经拒过之后，让他在总表上看见「为什么不响」，并且给他一条走得通的路。
///
/// 被拒了提醒照建照同步（方案 2.2），所以这一行是**提示**不是**拦路**：
/// 它不挡住列表，也不改任何东西，点一下只是把他送去系统设置。
@MainActor
final class AlertPermission: ObservableObject {
  /// 这一行到底出不出来。**整条判据就这一句，别在视图里再判第二遍。**
  ///
  /// - `.denied`：真的拒过了，系统不会再弹第二次，只有他自己去设置里开——出。
  /// - `.notDetermined`：还没问过。这时候摆一行「去系统设置」是无中生有：
  ///   他下次点「加入提醒」系统自己会弹，而且在设置里根本找不到这个开关——不出。
  /// - `.authorized` / `.provisional` / 以后系统再添的档：能响，不出。
  /// 纯函数，不碰任何状态，所以 `nonisolated`——用例可以直接一档一档地钉它。
  nonisolated static func needsSystemSettings(_ status: UNAuthorizationStatus) -> Bool {
    status == .denied
  }

  /// 视图观察的就是这一个。默认 `false`：还没查出来之前不闪一行出来。
  @Published private(set) var needsSystemSettings = false

  /// 去系统那儿现问一遍。
  ///
  /// **每次总表出现、以及每次回前台都要叫一次**：用户可能刚在系统设置里把开关
  /// 拨上来，回到这张表这一行就该自己消失，不能等下次冷启动。
  func refresh() async {
    let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    let next = Self.needsSystemSettings(status)
    if next != needsSystemSettings { needsSystemSettings = next }
  }

  /// 把他送到系统设置里这个 app 那一页（通知开关就在那儿）。
  func openSystemSettings() {
    #if canImport(UIKit)
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
    #endif
  }
}
