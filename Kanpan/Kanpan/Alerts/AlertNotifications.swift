import Foundation
import KanpanCore
import ReviewData
import UIKit
import UserNotifications

/// 通知这一侧的落点：系统把一条通知交回来时，把它翻译成一条深链交给
/// `DeepLinkRouter`，界面那边照常走 `MainScreen` 那一个口。
///
/// 这里**只做翻译和转交**。提醒本身怎么建、怎么排本地通知、权限什么时候要，
/// 都在提醒模块自己那几件里（`AlertStore` / `AlertWatcher`），不要往这儿塞。
/// 见 `71bd340:docs/提醒与体验细节-实施方案-2026-09-20.md` 第 2 节。
///
/// **这儿不申请通知权限**。按方案第一次点「加入提醒」时才问，问的人是提醒模块。
/// `@unchecked Sendable` 是实话：这个类一个存储属性都没有，系统在哪条线程上回调
/// 它都没有可争的状态；真正要在主线程上做的那一下（交给路由）自己跳过去。
final class AlertNotifications: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  static let shared = AlertNotifications()

  /// userInfo 里放深链的那个键。发通知的人（本地排程与服务端推送）都写这一个。
  static let linkKey = "link"
  /// 提醒自己发的那几条通知的分类号。认出「这是我们的」只看它。
  static let category = "kanpan.alert"
  /// 服务端推送里标明「这是哪一种」的键（`apns.rs::alert_payload`）。
  static let kindKey = "kind"
  /// 本机前台自己也会报的那几种推送。
  static let localTwins: Set<String> = ["watchMove"]

  private override init() { super.init() }

  /// 挂成通知中心的代理。要赶在 app 启动完成之前挂上，否则「点通知冷启动」那一下
  /// 系统会找不到人接，`didReceive` 根本不响——所以叫它的地方是 `KanpanApp.init()`。
  /// 幂等，重复叫没事。
  func install() { UNUserNotificationCenter.current().delegate = self }

  // ---------------------------------------------------------------- 代理

  /// 用户点了一条通知。
  ///
  /// 用带完成回调的这一版、并且**在主线程上**回调。以前是 `async` 那一版：系统替它
  /// 包的完成回调落在并发执行器的线程上，UIKit 收尾（更新后台快照）时断言「必须在主线程」
  /// 直接 abort——app 在后台时点任何一条通知，app 都会闪退，冷启动都进不去
  /// （第 25 项端到端验收时抓到，崩溃栈落在 `_performBlockAfterCATransactionCommitSynchronizes`）。
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    let request = response.notification.request
    let link = Self.link(userInfo: request.content.userInfo, identifier: request.identifier)
    nonisolated(unsafe) let done = completionHandler
    DispatchQueue.main.async {
      MainActor.assumeIsolated { if let link { DeepLinkRouter.shared.open(link) } }
      done()
    }
  }

  /// app 在前台时来了一条通知。
  ///
  /// **提醒类的一条都不弹系统横幅**：前台有 `AlertWatcher` 自己的震动 + 浮条，
  /// 上面再压一张系统横幅就是同一件事说两遍（方案 2.3「通知」那一条）。
  /// 别人的通知照旧按系统默认展示。
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    let request = notification.request
    if request.content.categoryIdentifier == AlertSoundPreview.category { return [.sound] }
    // 服务端推下来的自选波动：前台时本机自己那一份（`WatchMoveMonitor` 的浮条）已经
    // 说过了，这一条压掉，免得同一件事在通知中心躺两条。
    let kind = request.content.userInfo[Self.kindKey] as? String
    if let kind, Self.localTwins.contains(kind) { return [] }
    // 复盘到点只走一条通道（`ReviewDueReminders.channel`）：走推送时这就是唯一的一条，
    // 前台照常弹横幅；走本机日历通知时服务端本不该推到这台（它没登记 `reviewDue` 类
    // token），真推来了（服务端还没部署 0023）就压掉，免得和本机那条重复。
    if kind == "reviewDue" { return ReviewDueReminders.channel == .remote ? [.banner, .list, .sound] : [] }
    guard request.content.categoryIdentifier == Self.category else { return [.banner, .list, .sound] }
    // 价格提醒、自选波动保留所选声音与通知中心条目。
    return request.identifier.hasPrefix("alert.") || request.identifier.hasPrefix("move.") ? [.list, .sound] : [.list]
  }

  // ---------------------------------------------------------------- 翻译

  /// 从一条通知身上找出深链：先看 `userInfo["link"]`，没有就把通知自己的
  /// identifier 当链接试一次（本地排程时常常直接拿深链当 id）。
  static func link(userInfo: [AnyHashable: Any], identifier: String) -> DeepLink? {
    if let raw = userInfo[linkKey] as? String, let link = parse(raw) { return link }
    return parse(identifier)
  }

  private static func parse(_ raw: String) -> DeepLink? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let url = URL(string: text) else { return nil }
    return DeepLink.parse(url)
  }
}


// ---------------------------------------------------------------- 权限与排程

extension AlertNotifications {
  /// 现在到底有没有权限。没问过（`.notDetermined`）也算没有。
  static func isAuthorized() async -> Bool {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
  }

  /// 第一次点「加入提醒」时问一次权限。
  ///
  /// **问不到也不挡事**：提醒照建、照同步，只是响的时候只有 app 在前台那一下能看见
  /// （方案 2.2）。所以返回值只给调用方决定「要不要顺便说一句」，不做任何 guard。
  /// 已经问过的（拒了也算问过）不再问第二次——系统本来也不会再弹，只会直接回 false。
  @discardableResult
  static func requestAuthorization() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional: return true
    case .notDetermined:
      let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
      if granted { await MainActor.run { PushRegistration.start() } }
      return granted
    default: return false
    }
  }

  /// 把一条已经触发的提醒摆到用户眼前。
  ///
  /// 服务端判的到价，客户端只负责让它被看见。app 在前台时 `willPresent` 会把横幅压掉，
  /// 留在通知中心里；在后台回来的那一下（`AppLifecycle` 进前台 → 拉一次同步）发出来的，
  /// 用户点开就直接到那条线上。
  static func present(_ alert: Alert, decimals: Int? = nil, sound: AlertSound) {
    let content = UNMutableNotificationContent()
    content.title = alert.title.isEmpty ? "提醒" : alert.title
    if let price = alert.firedPrice { content.body = "现价 " + ReviewLabels.price(price, decimals: decimals) }
    content.sound = sound.fileName.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) } ?? .default
    content.categoryIdentifier = category
    if let link = link(for: alert) { content.userInfo = [linkKey: link] }
    let request = UNNotificationRequest(identifier: "alert." + alert.id, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  /// 自选波动响了：通知中心留一条，点开就是那只品种。id 带窗口，同一个窗口重复 `add`
  /// 只会覆盖同一条。
  static func present(_ event: WatchMove.Event, decimals: Int? = nil, sound: AlertSound) {
    let content = UNMutableNotificationContent()
    content.title = WatchMove.title(for: event)
    content.body = "现价 " + ReviewLabels.price(event.price, decimals: decimals)
    content.sound = sound.fileName.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) } ?? .default
    content.categoryIdentifier = category
    content.userInfo = [linkKey: "\(DeepLink.scheme)://symbol/\(event.symbol)"]
    let id = "move.\(event.symbol).\(event.direction.rawValue).\(event.window)"
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }

  /// 这条提醒点开该去哪儿：复盘到点去那条记录；有画线就去那条线，没有就只开品种。
  static func link(for alert: Alert) -> String? {
    if alert.kind == .reviewDue, let id = alert.reviewID, !id.isEmpty {
      return "\(DeepLink.scheme)://review/\(id)"
    }
    guard !alert.symbol.isEmpty else { return nil }
    if let drawingID = alert.drawingID, !drawingID.isEmpty {
      return "\(DeepLink.scheme)://drawing/\(alert.symbol)/\(drawingID)"
    }
    return "\(DeepLink.scheme)://symbol/\(alert.symbol)"
  }
}
