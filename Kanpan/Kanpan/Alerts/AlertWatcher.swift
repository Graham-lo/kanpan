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
/// 所以它只做五件事，前四件是「呈现」，最后一件是收尾：
///
/// 1. 盯着 `AlertStore` 的存档。有提醒**刚**变成已触发，就震一下 + 让宿主说一句，
///    那句话点得动，点了就去那条线上。
/// 2. 同一条只说一次。冷启动时、换档案（登录 / 切账号，`AlertStore.generation` 变了）时，
///    把存档里已经躺着的已触发当成「说过了」——那是旧包或上一段会话留下的，
///    不该在开 app 的那一瞬间集体弹一遍。
/// 3. app 不在前台那一下变的（从后台回来拉一次同步就会看到），补一条本地通知。
///    没有 APNs 权限的现在，这是提醒能走到用户眼前的**唯一**一条路。
/// 4. 填了 Webhook 的，本机判响的那一次由这里往那个地址 POST（`AlertWebhook`）；
///    服务端判响、同步换下来的那种服务端已经发过，这里不再发第二遍。
/// 5. **触发即删**（2026-09-25 v3，用户：「默认就是触发一次就删除啊，不要搞重复提醒」）：
///    上面几件做完，把这一拍里所有已触发的（复盘到点除外）交给 `AlertStore.purgeFired`
///    从存档里删掉。删走的是 `write`，账号桥照常记一笔，同步推上去的是这几条的删除。
///    「已触发」于是只是一个一拍长的中间态：`AlertActivityController`（`MainScreen` 同步收存档）
///    先看到已触发、写完最后一拍「已触发」再结束锁屏活动，下一拍这里才把它删掉。
///    冷启动与换档案时那些「说过了」的旧已触发也在第一拍一并清掉。
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
  /// 已经报过的那些。只按 id 记；删掉了的、重新布防了的（编辑改了价）会被摘掉，
  /// 所以同一条改了价再响照样报。
  private var announced: Set<String> = []
  /// 上一次看到的档案代次（`AlertStore.generation`）。变了就是换了档案。
  private var generation = 0
  /// app 此刻在不在前台。不在前台时报法不一样：只发本地通知，不去动界面。
  private var foreground = true

  func attach(_ store: AlertStore) {
    guard self.store !== store else { return }
    bag.removeAll()
    self.store = store
    // 装上的这一刻先把已经躺在存档里的已触发全部记成「说过了」。
    announced = Set(store.all.filter { $0.status == .fired }.map(\.id))
    generation = store.generation
    // `@Published` 在 willSet 里发值，这时 `store.generation` 已经是换档案之后的那个
    // （`useStorage` 先加代次再换存档），所以跟着存档一起取出来的代次是配套的。
    store.$archive
      .map { [weak store] archive in (archive, store?.generation ?? 0) }
      .receive(on: RunLoop.main)
      .sink { [weak self] archive, generation in self?.settle(archive, generation: generation) }
      .store(in: &bag)
  }

  /// 前后台。`MainScreen` 那一处 `AppLifecycle` 把话递过来。
  func setForeground(_ value: Bool) { foreground = value }

  private func settle(_ archive: AlertArchive, generation: Int) {
    let firedAlerts = archive.alerts.filter { $0.status == .fired }
    let fired = Set(firedAlerts.map(\.id))
    if generation != self.generation {
      // 换了档案：这份档案里本来就躺着的已触发是旧的，静默记成说过了，下面照样清掉。
      self.generation = generation
      announced = fired
    }
    // 重新布防过的、被删掉的，都从「说过了」里摘掉。
    announced.formIntersection(fired)
    for alert in firedAlerts where !announced.contains(alert.id) {
      announced.insert(alert.id)
      report(alert)
    }
    // 报完就删（复盘到点 `purgeFired` 自己会跳过）。
    let spent = Set(firedAlerts.filter { $0.kind != .reviewDue }.map(\.id))
    guard !spent.isEmpty, let store else { return }
    store.purgeFired(ids: spent)
  }

  private func report(_ alert: Alert) {
    // 复盘到点不在这儿叫人：叫人只有 `ReviewDueReminders` 一处（本机日历通知，没权限时
    // 它自己在前台补叫）。这儿再震一下、再弹一条浮条，就是同一件事说两遍——以前从后台
    // 回来、同步下来一条 fired 时正是这样。总表「复盘到点」那一段里它照常显示为已到点。
    if alert.kind == .reviewDue { return }
    // 通知中心里留一条：前台时 `willPresent` 会把横幅压掉（界面上已经有浮条了），
    // 后台回来那一下则是它把人叫住。
    let decimals = priceDecimals(alert.symbol)
    AlertNotifications.present(alert, decimals: decimals, sound: sound())
    if alert.webhook != nil, let store, store.firedLocally(alert), let price = alert.firedPrice,
       let at = alert.firedAt {
      AlertWebhook.fire(alert, price: price, decimals: decimals, at: at)
    }
    guard foreground else { return }
    Haptics.alarm()
    onFired?(alert)
  }
}
