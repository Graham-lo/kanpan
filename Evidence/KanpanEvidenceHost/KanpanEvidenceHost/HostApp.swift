import UIKit

/// A3.12 取证宿主的入口。
///
/// 纯 UIKit，没有 SwiftUI、没有定时器、没有网络、没有动画——静止时这个进程
/// 除了 `ChartView` 那条 `CADisplayLink` 之外不该有任何东西在跑。
/// 这正是 A3.12 要量的东西：静止 30 秒，CPU 占用 < 1%。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let c = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    c.delegateClass = SceneDelegate.self
    return c
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let ws = scene as? UIWindowScene else { return }
    let w = UIWindow(windowScene: ws)
    w.rootViewController = HostViewController()
    window = w
    w.makeKeyAndVisible()
  }
}
