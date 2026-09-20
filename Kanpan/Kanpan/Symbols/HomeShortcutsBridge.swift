import UIKit

// ============================================================ 快捷入口的接线
//
// `HomeShortcuts` 只管算「该摆哪几格」（它在品种包里，测试在 macOS 上编，
// 碰不得 UIKit）。真的去写系统那张表、以及接住桌面上按下去的那一下，在这儿。
//
// 桌面那一下从哪儿进来，要看 app 当时是什么状态：
//
// · **app 还活着**（在后台）：`UIWindowSceneDelegate.windowScene(_:performActionFor:)`；
// · **冷启动**：那一下随场景一起过来，在 `scene(_:willConnectTo:options:)` 的
//   `connectionOptions.shortcutItem` 里。晚一步去问就没有了。
//
// SwiftUI 的 app 生命周期没有地方让人挂场景代理，只能从 app 代理那一侧
// 指定（`application(_:configurationForConnecting:options:)` 里设 `delegateClass`）。
// 那个 app 代理就是 `OrientationBridge`（`KanpanApp` 上那一行 `@UIApplicationDelegateAdaptor`），
// 所以这儿给它加一条扩展，而不是新开第二个 app 代理——一个 app 只认一个。
//
// 两条路都通向同一件事：把那一格化成一条 `DeepLink` 交给 `DeepLinkRouter`，
// 界面那边照常由 `MainScreen` 一处消费（方案第 1 节）。

enum HomeShortcutsBridge {
  /// 把「真的去摆」这件事装给 `HomeShortcuts`。`KanpanApp.init()` 叫一次。
  @MainActor static func install() {
    HomeShortcuts.apply = { items in
      UIApplication.shared.shortcutItems = items.map { item in
        var info: [String: NSSecureCoding]?
        if let symbol = item.symbol { info = [HomeShortcuts.symbolKey: symbol as NSString] }
        return UIApplicationShortcutItem(
          type: item.type,
          localizedTitle: item.title,
          // 副标题那一格不放东西：桌面是系统渲染的，摆上去的数字永远停在上次
          // （而且那本来就是状态字段，界面上不许有）。
          localizedSubtitle: nil,
          icon: UIApplicationShortcutIcon(systemImageName: item.icon),
          userInfo: info)
      }
    }
  }

  /// 桌面上点下去的那一格。认不出来就什么都不做。
  @MainActor @discardableResult
  static func handle(_ item: UIApplicationShortcutItem) -> Bool {
    guard let link = link(for: item) else { return false }
    DeepLinkRouter.shared.open(link)
    return true
  }

  static func link(for item: UIApplicationShortcutItem) -> DeepLink? {
    switch item.type {
    case HomeShortcuts.searchType:
      return .search
    case HomeShortcuts.symbolType:
      guard let symbol = item.userInfo?[HomeShortcuts.symbolKey] as? String, !symbol.isEmpty else { return nil }
      return .symbol(symbol.uppercased(), interval: nil)
    default:
      return nil
    }
  }
}

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

  /// 兜底：有些情形下系统把那一下交给 app 代理而不是场景代理。两边落到同一个
  /// `DeepLinkRouter`，重复一次也只是同一条链接覆盖同一条，没有副作用。
  @objc(application:performActionForShortcutItem:completionHandler:)
  func application(_ application: UIApplication,
                   performActionFor shortcutItem: UIApplicationShortcutItem,
                   completionHandler: @escaping (Bool) -> Void) {
    completionHandler(HomeShortcutsBridge.handle(shortcutItem))
  }
}
