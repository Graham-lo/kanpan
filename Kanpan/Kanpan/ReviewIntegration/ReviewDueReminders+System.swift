import Foundation
import KanpanCore
import ReviewData
import ReviewDomain
import UserNotifications

/// `ReviewDueReminders` 落到系统通知中心的那一侧（模块本身在 `ReviewData`，不链 UIKit
/// 与通知中心，单元测试换成假的）。
@MainActor final class ReviewDueSystemScheduler: ReviewDueReminders.Scheduler {
  private let center = UNUserNotificationCenter.current()

  func isAuthorized() async -> Bool { await AlertNotifications.isAuthorized() }

  func pendingIdentifiers() async -> [String] {
    await center.pendingNotificationRequests().map(\.identifier)
  }

  func remove(_ identifiers: [String]) {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  func add(_ reminder: ReviewDueReminders.Reminder, fireAt: Date) async {
    guard fireAt > Date() else { return }
    let content = UNMutableNotificationContent()
    content.title = reminder.title
    content.body = reminder.body
    content.sound = .default
    // 不是提醒那一类：前台由系统横幅呈现（`AlertNotifications.willPresent` 的默认那一支）。
    content.categoryIdentifier = ReviewDueReminders.category
    content.userInfo = [AlertNotifications.linkKey: "\(DeepLink.scheme)://review/\(reminder.id.uuidString)"]
    // 精确到秒：以前只到分钟，一条 10:00:40 到点的会在 10:00:00 提前响。
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireAt)
    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    try? await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
  }
}

extension ReviewDueReminders {
  /// app 里用的那一个：系统通知中心 + 本机账本。
  ///
  /// DEBUG 构建认一个测试钩子 `KANPAN_REVIEW_DUE_SHIFT`（秒）：把「现在」往后拨，
  /// 一小时后到点的记录拨 3590 就在十秒后真的响，端到端验收不必真等一小时。
  static func live() -> ReviewDueReminders {
    var shift: TimeInterval = 0
    #if DEBUG
    if let raw = ProcessInfo.processInfo.environment["KANPAN_REVIEW_DUE_SHIFT"], let value = TimeInterval(raw) {
      shift = value
    }
    #endif
    return ReviewDueReminders(scheduler: ReviewDueSystemScheduler(), shift: shift)
  }
}

extension ReviewDueAlerts.Item {
  /// 一条复盘记录折成提醒总表要的那几样（`ReviewDueAlerts` 不链复盘那一摊，折在这儿）。
  /// 总表那条只管进总表和同步，不叫人——叫人只有 `ReviewDueReminders` 一处。
  init(record: ReviewRecord) {
    let range = record.draft.range
    let instrument = InstrumentID(venue: range.venue, market: range.market, symbol: range.symbol)
    self.init(id: record.id.uuidString,
              symbol: instrument.key,
              dueAt: Double(record.draft.rule.expires),
              short: range.shortSymbol,
              waiting: record.outcome == .waiting,
              // 和捕获入口同一个判定（`ReviewContract.supports`）：能记的市场，到点就能进提醒。
              eligible: ReviewContract.supports(instrument) && !range.symbol.isEmpty)
  }
}
