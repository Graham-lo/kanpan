import Foundation
import UIKit

/// 内存告警的分发点。
///
/// `MarketModel.memoryWarning()`（`Kanpan/Kanpan/Main/MarketModel.swift:168`）一直
/// 存在但**全工程没有一个调用者**：系统发 `didReceiveMemoryWarning` 的时候，K 线
/// 缓存该放的那一批没人去放。
///
/// 通知只能在 app 入口挂（`KanpanApp`），而 `MarketModel` 只在 `MainScreen` 里被
/// 创建，两头碰不上，所以中间放这么一个转接：入口负责听，谁想收谁自己登记。
///
/// 登记方式（在 `MainScreen` 里加一行即可）：
/// ```swift
/// MemoryWarningRelay.shared.register(id: "market") { [weak market] in market?.memoryWarning() }
/// ```
@MainActor
final class MemoryWarningRelay {
  static let shared = MemoryWarningRelay()

  private var handlers: [String: () -> Void] = [:]
  private var observer: NSObjectProtocol?

  private init() {}

  /// 挂上系统通知。幂等，`KanpanApp.init()` 调一次就够。
  func start() {
    guard observer == nil else { return }
    observer = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { MemoryWarningRelay.shared.fire() }
      }
  }

  /// 登记一个处理器。同一个 `id` 再登记会替换掉上一个，`MainScreen` 重建时不会叠加。
  func register(id: String, _ handler: @escaping () -> Void) { handlers[id] = handler }
  func unregister(id: String) { handlers.removeValue(forKey: id) }

  /// 直接触发。单测和「手动放一次缓存」用。
  func fire() { for handler in handlers.values { handler() } }
}
