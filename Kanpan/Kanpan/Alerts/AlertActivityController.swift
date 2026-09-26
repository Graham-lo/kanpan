import ActivityKit
import Foundation
import KanpanCore

/// 提醒「盯一个」的实时活动（P3.3）：锁屏与灵动岛上挂一块，写着品种、现价、24 小时涨跌、
/// 离提醒价还差多少。
///
/// - **一台设备只挂一块。** 盯另一条就先把手上那块收掉；再点同一条就是不盯了。
/// - **谁来更新。** app 在前台时自己拿报价簿的价更新（最多五秒一拍，不要 APNs 密钥）；
///   不在前台时由服务端按心跳推（`Backend/kanpan-api/src/live_activity.rs`）——推送 token
///   交到 `POST /v1/devices/push-token`（`kind=liveActivity`，带 `activityId` 与 `alertId`）。
///   没开 APNs 的包拿不到 token（`pushType: .token` 被拒就退回不带推送的活动），那时它只在
///   前台跟价，过了 `staleDate` 系统把它标成过期，锁屏那块写「价格已停更」。
/// - **什么时候结束。** 提醒被删、被暂停：立刻收掉并告诉服务端；提醒响了：最后一拍写上
///   「已触发」再收（锁屏上按系统默认留一会儿）。
@MainActor
final class AlertActivityController: ObservableObject {
  /// 正在盯的那条提醒的本地 id。
  @Published private(set) var watching: String?

  /// 账号桥交进来：推送 token 上传与「用户划掉了」的通知。没登录就是 nil。
  var submitToken: ((_ token: String, _ activityID: String, _ alertID: String) -> Void)?
  var submitEnd: ((_ activityID: String) -> Void)?

  static let updateEvery: TimeInterval = 5
  /// 和服务端 `STALE_AFTER` 同一个数：这么久没新的一拍就算停更。
  static let staleAfter: TimeInterval = 150

  private var activity: Activity<AlertActivityAttributes>?
  private var alert: KanpanCore.Alert?
  private var lastState: AlertActivityState?
  private var lastUpdate = Date.distantPast
  private var watchers: [Task<Void, Never>] = []

  /// 这台设备允许实时活动吗（设置里能关）。
  var available: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

  /// 同步对象 id（`<完整品种 key>/<提醒 id>`，如 `binance/usd_m/BTCUSDT/<id>`），服务端按它认线。
  /// 和 `PersonalSyncCodec` 里 alerts 那一份同一个拼法：`alert.symbol` 已经是完整 key，不能再前缀一次。
  static func syncID(_ alert: KanpanCore.Alert) -> String { InstrumentID.canonical(alert.symbol) + "/" + alert.id }

  /// 活动标题里说它盯的是什么：裸价格提醒写「价格」，画线提醒写线种。
  static func toolLabel(_ alert: KanpanCore.Alert) -> String {
    alert.kind == .price ? "价格" : alert.lineName ?? "画线"
  }

  /// 现在这一刻离现价最近的那条线的价。
  static func linePrice(_ alert: KanpanCore.Alert, price: Double?, at t: Double) -> Double? {
    let prices = alert.lines.compactMap { $0.price(at: t) }.filter(\.isFinite)
    guard let price, price.isFinite else { return prices.first }
    return prices.min { abs($0 - price) < abs($1 - price) }
  }

  static func state(for alert: KanpanCore.Alert, price: Double?, change: Double?, now: Date = Date()) -> AlertActivityState {
    let t = now.timeIntervalSince1970 * 1000
    let fired = alert.status == .fired
    return AlertActivityState(price: price, change: change, line: linePrice(alert, price: price, at: t),
                              fired: fired, firedAt: fired ? alert.firedAt.map { Int64($0) } : nil,
                              updatedAt: Int64(t), firedPrice: fired ? alert.firedPrice : nil)
  }

  /// 接回锁屏上挂着的那几块，谁留谁收（纯函数，`adopt` 按它办）。
  ///
  /// - 挨个看**所有**活动，不只看第一个：系统里可能挂着不止一块（上一个版本、换号前留下的）。
  /// - 对得上一条生效中的提醒、手上又还没挂着一块的，接回来（一台设备只挂一块）；
  ///   已经接着一块时，别的对得上的也收掉。
  /// - 对不上的：档案**已经落定**（`settled`，账号核完了）才收；还没落定就先放着——
  ///   冷启动那一刻手上可能还是设备级那份访客提醒表，登录用户的提醒要等账号桥把他的档案
  ///   装进来才看得见，那时候收就是把他的活动当场结束（整机压测 2026-09-26）。
  struct AdoptPlan: Equatable {
    /// 要接回来的那一块：（活动 id，提醒 id）。
    var attach: (activityID: String, alertID: String)?
    /// 要收掉的活动 id。
    var end: [String] = []

    static func == (l: Self, r: Self) -> Bool {
      l.attach?.activityID == r.attach?.activityID && l.attach?.alertID == r.attach?.alertID && l.end == r.end
    }
  }

  static func adoptPlan(activities: [(id: String, alertID: String)], alerts: [KanpanCore.Alert],
                        attachedID: String?, settled: Bool) -> AdoptPlan {
    var byID: [String: KanpanCore.Alert] = [:]
    for alert in alerts where alert.isActive { byID[syncID(alert)] = byID[syncID(alert)] ?? alert }
    var plan = AdoptPlan()
    var holding = attachedID != nil
    for existing in activities where existing.id != attachedID {
      if let alert = byID[existing.alertID] {
        if holding { plan.end.append(existing.id) }
        else { plan.attach = (existing.id, alert.id); holding = true }
      } else if settled {
        plan.end.append(existing.id)
      }
    }
    return plan
  }

  /// 把上一次留下的那几块接回来（app 被杀过，活动还挂在锁屏上）。
  ///
  /// 宿主在**档案到货**时调（`MainScreen.honorProfile()`：冷启动装上次那个人的档案、
  /// 账号核完、登录 / 退登 / 换号），`alerts` 永远是那一刻档案主人的提醒表；
  /// `settled` 为假（还在等 `account.restore()`）时对不上的先不收。
  func adopt(alerts: [KanpanCore.Alert], settled: Bool) {
    let live = Activity<AlertActivityAttributes>.activities
    guard !live.isEmpty else { return }
    let plan = Self.adoptPlan(activities: live.map { ($0.id, $0.attributes.alertID) }, alerts: alerts,
                              attachedID: activity?.id, settled: settled)
    for id in plan.end { Task.detached { await Self.end(id: id, nil, policy: .immediate) } }
    if let pick = plan.attach, let existing = live.first(where: { $0.id == pick.activityID }),
       let alert = alerts.first(where: { $0.id == pick.alertID }) {
      attach(existing, alert: alert)
    }
  }

  /// 行上那颗「盯一个」。已经在盯这条就是不盯了。
  @discardableResult
  func toggle(_ alert: KanpanCore.Alert, price: Double?, change: Double?, decimals: Int?, redUp: Bool) -> Bool {
    if watching == alert.id { stop(); return false }
    stop()
    guard alert.isActive, alert.kind != .reviewDue, available else { return false }
    let attributes = AlertActivityAttributes(symbol: alert.symbol, alertID: Self.syncID(alert),
                                             toolLabel: Self.toolLabel(alert), decimals: decimals, redUp: redUp)
    let state = Self.state(for: alert, price: price, change: change)
    let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))
    let started: Activity<AlertActivityAttributes>
    do {
      started = try Activity.request(attributes: attributes, content: content, pushType: .token)
    } catch {
      // 没有推送能力的包（没开 APNs）会被拒：退回只在前台跟价的那种。
      guard let plain = try? Activity.request(attributes: attributes, content: content, pushType: nil) else { return false }
      started = plain
    }
    lastState = state
    lastUpdate = Date()
    attach(started, alert: alert)
    return true
  }

  private func attach(_ activity: Activity<AlertActivityAttributes>, alert: KanpanCore.Alert) {
    self.activity = activity
    self.alert = alert
    watching = alert.id
    let alertID = Self.syncID(alert)
    let activityID = activity.id
    watchers.forEach { $0.cancel() }
    watchers = [
      Task { @MainActor [weak self] in
        for await data in activity.pushTokenUpdates {
          let hex = data.map { String(format: "%02x", $0) }.joined()
          self?.submitToken?(hex, activityID, alertID)
        }
      },
      Task { @MainActor [weak self] in
        for await state in activity.activityStateUpdates where state == .dismissed || state == .ended {
          guard let self, self.activity?.id == activityID else { return }
          if state == .dismissed { self.submitEnd?(activityID) }
          self.forget()
          return
        }
      },
    ]
  }

  /// 前台的一批价。只认正在盯的那一只。
  func observe(symbol: String, price: Double, change: Double?) {
    guard let activity, let alert, alert.symbol == symbol, price.isFinite, price > 0 else { return }
    guard Date().timeIntervalSince(lastUpdate) >= Self.updateEvery else { return }
    let state = Self.state(for: alert, price: price, change: change ?? lastState?.change)
    lastState = state
    lastUpdate = Date()
    let id = activity.id
    let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))
    Task.detached { await Self.update(id: id, content) }
  }

  /// 提醒表变了：盯着的那条被删 / 暂停就收掉；响了就写上「已触发」再收。
  ///
  /// v3 触发即删：响了的那条先以「已触发」发布（这里同步收到，写最后一拍再收），
  /// 下一拍 `AlertWatcher` 才把它从存档删掉——那时活动已经收了，走不到 `stop()`；
  /// 万一先看到的是删除（比如同步一次拉到删除后的状态），走 `stop()` 立即收，不会挂着不结束。
  func reconcile(_ alerts: [KanpanCore.Alert]) {
    guard let current = alert, let activity else { return }
    guard let next = alerts.first(where: { $0.id == current.id }), next.status != .paused else {
      stop(); return
    }
    alert = next
    if next.status == .fired {
      let state = Self.state(for: next, price: next.firedPrice ?? lastState?.price, change: lastState?.change)
      let id = activity.id
      Task.detached { await Self.end(id: id, ActivityContent(state: state, staleDate: nil), policy: .default) }
      submitEnd?(activity.id)
      forget()
    }
  }

  /// 不盯了。
  func stop() {
    guard let activity else { forget(); return }
    let id = activity.id
    Task.detached { await Self.end(id: id, nil, policy: .immediate) }
    submitEnd?(id)
    forget()
  }

  // `Activity` 不是 Sendable：主线程上不能把它本身交给异步的 end / update，
  // 只交 id，到非隔离的地方按 id 再找一次。
  nonisolated private static func find(_ id: String) -> Activity<AlertActivityAttributes>? {
    Activity<AlertActivityAttributes>.activities.first { $0.id == id }
  }
  nonisolated private static func update(id: String, _ content: ActivityContent<AlertActivityState>) async {
    await find(id)?.update(content)
  }
  nonisolated private static func end(id: String, _ content: ActivityContent<AlertActivityState>?,
                                      policy: ActivityUIDismissalPolicy) async {
    await find(id)?.end(content, dismissalPolicy: policy)
  }

  private func forget() {
    watchers.forEach { $0.cancel() }
    watchers = []
    activity = nil
    alert = nil
    lastState = nil
    watching = nil
  }
}
