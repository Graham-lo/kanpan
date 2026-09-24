import KanpanCore
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
// 前两条路都经场景代理 `KanpanSceneDelegate` 进来。它和指定它的那段场景配置是
// 整个 app 的入口接线，住在 `App/KanpanSceneDelegate.swift`；这儿只留快捷入口
// 自己的那部分，外加 app 代理（`OrientationBridge`）上那条兜底回调。
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
      return .symbol(InstrumentID.canonical(symbol), interval: nil)
    default:
      return nil
    }
  }
}

// ---------------------------------------------------------------- app 代理兜底

extension OrientationBridge {
  /// 兜底：有些情形下系统把那一下交给 app 代理而不是场景代理。两边落到同一个
  /// `DeepLinkRouter`，重复一次也只是同一条链接覆盖同一条，没有副作用。
  @objc(application:performActionForShortcutItem:completionHandler:)
  func application(_ application: UIApplication,
                   performActionFor shortcutItem: UIApplicationShortcutItem,
                   completionHandler: @escaping (Bool) -> Void) {
    completionHandler(HomeShortcutsBridge.handle(shortcutItem))
  }
}
