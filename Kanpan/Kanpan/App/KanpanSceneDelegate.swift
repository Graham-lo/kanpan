import UIKit

// ============================================================ 场景代理与场景配置
//
// SwiftUI 的 app 生命周期没有地方让人挂场景代理，只能从 app 代理那一侧指定
// （`application(_:configurationForConnecting:options:)` 里设 `delegateClass`）。
// 那个 app 代理就是 `OrientationBridge`（`KanpanApp` 上那一行 `@UIApplicationDelegateAdaptor`），
// 所以这儿给它加一条扩展，而不是新开第二个 app 代理——一个 app 只认一个。
//
// 场景代理眼下只接桌面快捷入口；接住之后怎么化成链接，见
// `Symbols/HomeShortcutsBridge.swift`。它和场景配置是整个 app 的入口接线，
// 不属于哪一个功能，所以和 `KanpanApp` 住在一起（审查第 18 项）。

// ---------------------------------------------------------------- 场景代理

/// 只干一件事：接住桌面快捷入口。窗口与界面仍然由 SwiftUI 自己搭
/// （`KanpanApp` 的 `WindowGroup`），这儿一个 window 都不碰。
final class KanpanSceneDelegate: NSObject, UIWindowSceneDelegate {
  /// 冷启动：那一下藏在 `connectionOptions` 里。
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options connectionOptions: UIScene.ConnectionOptions) {
    if let item = connectionOptions.shortcutItem { HomeShortcutsBridge.handle(item) }
  }

  /// app 还活着时点的那一下。
  func windowScene(_ windowScene: UIWindowScene,
                   performActionFor shortcutItem: UIApplicationShortcutItem,
                   completionHandler: @escaping (Bool) -> Void) {
    completionHandler(HomeShortcutsBridge.handle(shortcutItem))
  }
}

extension OrientationBridge {
  /// 给每个新场景指一个我们自己的代理（上面那个）。除了 `delegateClass`，
  /// 这份配置什么都不改，SwiftUI 那套照常。
  @objc(application:configurationForConnectingSceneSession:options:)
  func application(_ application: UIApplication,
                   configurationForConnecting connectingSceneSession: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    config.delegateClass = KanpanSceneDelegate.self
    return config
  }
}
