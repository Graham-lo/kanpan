import Foundation
import Testing
import ReviewDomain
import ReviewData

/// 假的系统通知中心：`add` 发出去以后卡住，等测试放行才落地——模拟真机上
/// `UNUserNotificationCenter.add` 还在路上时，换号 / 退登已经开始撤了。
@MainActor final class GatedDueScheduler: ReviewDueReminders.Scheduler {
  var pending: [String: Date] = [:]
  private(set) var addsInFlight = 0
  private var gates: [CheckedContinuation<Void, Never>] = []
  func isAuthorized() async -> Bool { true }
  func pendingIdentifiers() async -> [String] { Array(pending.keys) }
  func remove(_ identifiers: [String]) { for id in identifiers { pending[id] = nil } }
  func add(_ reminder: ReviewDueReminders.Reminder, fireAt: Date) async {
    addsInFlight += 1
    await withCheckedContinuation { gates.append($0) }
    pending[reminder.identifier] = fireAt
  }
  func releaseAll() { let open = gates; gates = []; open.forEach { $0.resume() } }
}

@MainActor struct ReviewDueRemindersRaceTests {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)
  private func record(dueIn seconds: TimeInterval) -> ReviewRecord {
    var draft = ReviewDraft(range: ReviewRange(symbol: "BTCUSDT", interval: "1m", start: 0, end: 180_000, bars: 3),
                            reference: 100, high: 110, low: 90, now: Int64(start.timeIntervalSince1970 * 1000) - 60_000)
    draft.rule.direction = .long
    draft.rule.expires = Int64((start.timeIntervalSince1970 + seconds) * 1000)
    return ReviewRecord(draft: draft)
  }
  private func defaults() -> UserDefaults {
    let name = "review-due-race-" + UUID().uuidString
    let value = UserDefaults(suiteName: name)!
    value.removePersistentDomain(forName: name)
    return value
  }
  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<1_000 where !condition() { await Task.yield() }
  }

  /// 审查 R21：上一个人的那条 `add` 还在路上时退登 `stop()`，它落地在 stop 拍快照之后，
  /// 以前就永远留在系统里、到点照响。现在 stop 先等它落地再撤。
  @Test func stopWithdrawsReminderWhoseAddLandsLate() async {
    let scheduler = GatedDueScheduler()
    let reminders = ReviewDueReminders(scheduler: scheduler, defaults: defaults(), clock: { self.start })
    reminders.reschedule([record(dueIn: 3600)])
    await waitUntil { scheduler.addsInFlight == 1 }
    #expect(scheduler.addsInFlight == 1)
    reminders.stop()
    for _ in 0..<50 { await Task.yield() }   // 让 stop 那一轮先跑到能跑的地方
    scheduler.releaseAll()
    await reminders.settled()
    for _ in 0..<50 { await Task.yield() }
    #expect(scheduler.pending.isEmpty, "上一个人的提醒不许留在系统里")
  }

  /// 同一个竞态换成「换号后整批重排成另一个人的记录」：旧的那条落地晚了也要被这一轮撤掉。
  @Test func rescheduleWithdrawsPreviousRoundsLateAdd() async {
    let scheduler = GatedDueScheduler()
    let reminders = ReviewDueReminders(scheduler: scheduler, defaults: defaults(), clock: { self.start })
    let old = record(dueIn: 3600)
    reminders.reschedule([old])
    await waitUntil { scheduler.addsInFlight == 1 }
    reminders.reschedule([])
    for _ in 0..<50 { await Task.yield() }
    scheduler.releaseAll()
    await reminders.settled()
    for _ in 0..<50 { await Task.yield() }
    #expect(scheduler.pending[ReviewDueReminders.prefix + old.id.uuidString] == nil)
  }
}
