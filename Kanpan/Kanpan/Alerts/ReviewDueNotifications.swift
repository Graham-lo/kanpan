import Foundation
import KanpanCore
import ReviewDomain
import UserNotifications

/// 复盘那条「到点提醒我」（方案 2.3 最后一条）。
///
/// 复盘的待办**本来就有到期时间**——记一笔的时候必填的那个「到期」
/// （`ReviewRule.expires`，校验在 `ReviewContract`：晚于记录时间、最远一年）。
/// 所以这儿不再往编辑器里加第二个时间，只是把已有的那个兑现成一条本地通知：
/// 到点了叫一声，点开直接进那条记录。
///
/// 全程**本地**：`UNCalendarNotificationTrigger` 排在系统里，app 关着、没网、
/// 没有 APNs 都照响。没有通知权限时一条都不排（系统也不会收），提醒本身不受影响。
@MainActor
enum ReviewDueNotifications {
  /// 排程 id 的前缀。撤销时靠它认出「哪些是我排的」，别人的一条都不碰。
  static let prefix = "review.due."
  /// 系统给每个 app 的待发通知上限是 64 条。留出余量给提醒那一侧，这儿只排最近的 32 条。
  static let limit = 32

  /// 按当前这批记录重排一次。
  ///
  /// **整批重排，不做增量**：待办的到期会被改（用户编辑、服务端裁决），记录会作废、
  /// 会被判对判错，增量对账比重排复杂得多而收益为零——一共也就几十条。
  static func reschedule(_ records: [ReviewRecord]) {
    let now = Date().timeIntervalSince1970 * 1000
    let due = records
      .filter { $0.outcome == .waiting && Double($0.draft.rule.expires) > now }
      .sorted { $0.draft.rule.expires < $1.draft.rule.expires }
      .prefix(limit)
      .map { $0 }

    Task { @MainActor in
      let center = UNUserNotificationCenter.current()
      let pending = await center.pendingNotificationRequests()
      let wanted = Set(due.map { prefix + $0.id.uuidString })
      let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) && !wanted.contains($0) }
      if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
      guard await AlertNotifications.isAuthorized() else { return }
      for record in due { schedule(record, on: center) }
    }
  }

  /// 全撤。退登 / 换号时叫——别人的待办不该在这台机器上继续响。
  static func cancelAll() {
    Task { @MainActor in
      let center = UNUserNotificationCenter.current()
      let mine = await center.pendingNotificationRequests()
        .map(\.identifier).filter { $0.hasPrefix(prefix) }
      guard !mine.isEmpty else { return }
      center.removePendingNotificationRequests(withIdentifiers: mine)
    }
  }

  private static func schedule(_ record: ReviewRecord, on center: UNUserNotificationCenter) {
    let date = Date(timeIntervalSince1970: Double(record.draft.rule.expires) / 1000)
    guard date > Date() else { return }
    let content = UNMutableNotificationContent()
    content.title = record.draft.range.shortSymbol + " 到点了"
    content.body = "去看看这一笔判对了没有"
    content.sound = .default
    content.categoryIdentifier = AlertNotifications.category
    content.userInfo = [AlertNotifications.linkKey: "\(DeepLink.scheme)://review/\(record.id.uuidString)"]
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    center.add(UNNotificationRequest(identifier: prefix + record.id.uuidString,
                                     content: content, trigger: trigger))
  }
}

extension ReviewDueAlerts.Item {
  /// 一条复盘记录折成提醒要的那几样（`ReviewDueAlerts` 不链复盘那一摊，折在这儿）。
  init(record: ReviewRecord) {
    let range = record.draft.range
    self.init(id: record.id.uuidString,
              symbol: range.symbol.uppercased(),
              dueAt: Double(record.draft.rule.expires),
              short: range.shortSymbol,
              waiting: record.outcome == .waiting,
              eligible: range.venue == "binance" && range.market == "usd_m" && !range.symbol.isEmpty)
  }
}
