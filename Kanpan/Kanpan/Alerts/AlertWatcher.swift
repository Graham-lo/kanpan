import Combine
import Foundation
import KanpanCore
import UIKit

/// 「响了」这件事，从存档一路到用户眼前。
///
/// **到价判定不在这儿，也不在客户端的任何地方**：谁碰到了线由服务端算（方案第 2 节），
/// 客户端只认存档里那条提醒的 `status` 从 `active` 变成了 `fired`。两边各算一遍的话，
/// 同一条线会在手机上和服务器上得出两个不同的「什么时候算碰到」，用户看到的是
/// 「列表说已触发，图上却什么都没发生」。
///
/// 所以它只做三件事，都是「呈现」：
///
/// 1. 盯着 `AlertStore` 的存档。有提醒**刚**变成已触发，就震一下 + 让宿主说一句，
///    那句话点得动，点了就去那条线上。
/// 2. 同一条只说一次。冷启动时把存档里已经躺着的那些当成「说过了」——它们在提醒页的
///    「已触发」那一堆里等着，不该在开 app 的那一瞬间集体弹一遍。
/// 3. app 不在前台那一下变的（从后台回来拉一次同步就会看到），补一条本地通知。
///    没有 APNs 权限的现在，这是提醒能走到用户眼前的**唯一**一条路。
@MainActor
final class AlertWatcher: ObservableObject {
  /// 说一句。宿主接到主 toast 上（`MainScreen.say`）。
  var onFired: ((Alert) -> Void)?

  private weak var store: AlertStore?
  private var bag: Set<AnyCancellable> = []
  /// 已经报过的那些。只按 id 记，重新上膛（`rearm`）时会被摘掉，所以同一条线
  /// 第二次响照样报。
  private var announced: Set<String> = []
  /// app 此刻在不在前台。不在前台时报法不一样：只发本地通知，不去动界面。
  private var foreground = true

  func attach(_ store: AlertStore) {
    guard self.store !== store else { return }
    bag.removeAll()
    self.store = store
    // 装上的这一刻先把已经躺在存档里的已触发全部记成「说过了」。
    announced = Set(store.all.filter { $0.status == .fired }.map(\.id))
    store.$archive
      .receive(on: RunLoop.main)
      .sink { [weak self] archive in self?.settle(archive) }
      .store(in: &bag)
  }

  /// 前后台。`MainScreen` 那一处 `AppLifecycle` 把话递过来。
  func setForeground(_ value: Bool) { foreground = value }

  private func settle(_ archive: AlertArchive) {
    let fired = Set(archive.alerts.filter { $0.status == .fired }.map(\.id))
    // 重新上膛过的、被删掉的，都从「说过了」里摘掉。
    announced.formIntersection(fired)
    for alert in archive.alerts where alert.status == .fired && !announced.contains(alert.id) {
      announced.insert(alert.id)
      report(alert)
    }
  }

  private func report(_ alert: Alert) {
    // 通知中心里留一条：前台时 `willPresent` 会把横幅压掉（界面上已经有浮条了），
    // 后台回来那一下则是它把人叫住。
    AlertNotifications.present(alert)
    guard foreground else { return }
    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    onFired?(alert)
  }
}
