import Combine
import Foundation
import KanpanCore
import UIKit

/// 「响了」这件事，从存档一路到用户眼前。
///
/// **到价判定不在这儿**：这个类一个价都不看，只认存档里那条提醒的 `status` 从
/// `active` 变成了 `fired`。谁把它改成 `fired` 有两条路，都汇到这同一个口：
/// app 在前台时是 `AlertEngine`（本机按 1 分钟桶判，没有 APNs 密钥，它是用户当场
/// 能收到提醒的唯一一条路），app 不在前台时是服务端 `alerts.rs` 判完写进同步日志、
/// 回前台拉一次同步换下来。两边靠 `status == .active` 这道闸去重，不会响两次
/// （细节在 `AlertEngine` 的头注释里）。
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

  /// 宿主按提醒所属品种查目录，目录缺失才按价格兜底。
  var priceDecimals: (String) -> Int? = { _ in nil }
  /// 触发时读当前账号的选择，不捕获启动时的偏好快照。
  var sound: () -> AlertSound = { .default }

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
    // 后台回来那一下则是它把人叫住。复盘到点不在这儿发：它有一条到点就响的日历
    // 通知（`ReviewDueNotifications`），这儿再发就是同一件事两条。
    if alert.kind != .reviewDue {
      AlertNotifications.present(alert, decimals: priceDecimals(alert.symbol), sound: sound())
    }
    guard foreground else { return }
    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    onFired?(alert)
  }
}
