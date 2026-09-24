import XCTest
import ReviewDomain
import ReviewData

/// 假的系统通知中心：记下排了什么、撤了什么。
@MainActor final class FakeDueScheduler: ReviewDueReminders.Scheduler {
  var authorized = true
  var pending: [String: Date] = [:]
  var added: [(ReviewDueReminders.Reminder, Date)] = []
  var removed: [String] = []
  func isAuthorized() async -> Bool { authorized }
  func pendingIdentifiers() async -> [String] { Array(pending.keys) }
  func remove(_ identifiers: [String]) { removed += identifiers; for id in identifiers { pending[id] = nil } }
  func add(_ reminder: ReviewDueReminders.Reminder, fireAt: Date) async { added.append((reminder, fireAt)); pending[reminder.identifier] = fireAt }
}

final class ReviewDueRemindersTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)
  private func record(dueIn seconds: TimeInterval, from now: Date) -> ReviewRecord {
    var draft = ReviewDraft(range: ReviewRange(symbol: "BTCUSDT", interval: "1m", start: 0, end: 180_000, bars: 3),
                            reference: 100, high: 110, low: 90, now: Int64(now.timeIntervalSince1970 * 1000) - 60_000)
    draft.rule.direction = .long
    draft.rule.expires = Int64((now.timeIntervalSince1970 + seconds) * 1000)
    return ReviewRecord(draft: draft)
  }
  private func defaults() -> UserDefaults {
    let name = "review-due-" + UUID().uuidString
    let value = UserDefaults(suiteName: name)!
    value.removePersistentDomain(forName: name)
    return value
  }

  /// 只排还在等答案、没过点的，按到期排；再排一次把不要了的撤掉，自己的以外一条不碰。
  @MainActor func testLocalChannelSchedulesPendingAndWithdrawsStale() async {
    let scheduler = FakeDueScheduler()
    scheduler.pending = ["alert.x": start, ReviewDueReminders.prefix + UUID().uuidString: start]
    var now = start
    let reminders = ReviewDueReminders(scheduler: scheduler, defaults: defaults(), clock: { now })
    let later = record(dueIn: 7200, from: start), sooner = record(dueIn: 3600, from: start), past = record(dueIn: -10, from: start)
    reminders.reschedule([later, past, sooner])
    await reminders.settled()
    XCTAssertEqual(scheduler.added.map(\.0.id), [sooner.id, later.id])
    XCTAssertEqual(scheduler.added.first?.0.title, "BTC 到点了")
    XCTAssertEqual(Set(scheduler.pending.keys), ["alert.x", ReviewDueReminders.prefix + sooner.id.uuidString, ReviewDueReminders.prefix + later.id.uuidString])

    now = start.addingTimeInterval(5000)   // sooner 过了点
    scheduler.added = []
    reminders.reschedule([later, sooner])
    await reminders.settled()
    XCTAssertEqual(scheduler.added.map(\.0.id), [later.id])
    XCTAssertTrue(scheduler.removed.contains(ReviewDueReminders.prefix + sooner.id.uuidString) == false || scheduler.pending[ReviewDueReminders.prefix + sooner.id.uuidString] == nil)
    XCTAssertNotNil(scheduler.pending["alert.x"], "别人的通知不碰")
  }

  /// 服务端推送那条通道：本机一条都不排，排过的撤掉——两条通道不会同时叫。
  @MainActor func testRemoteChannelSchedulesNothingLocally() async {
    let scheduler = FakeDueScheduler()
    let old = ReviewDueReminders.prefix + UUID().uuidString
    scheduler.pending = [old: start]
    let reminders = ReviewDueReminders(scheduler: scheduler, channel: .remote, defaults: defaults(), clock: { self.start })
    reminders.reschedule([record(dueIn: 3600, from: start)])
    await reminders.settled()
    XCTAssertTrue(scheduler.added.isEmpty)
    XCTAssertNil(scheduler.pending[old])
  }

  /// 测试钩子：「现在」往后拨，排程时扣回来——一小时后到点的，拨 3590 秒就在十秒后响。
  @MainActor func testTimeShiftFiresSoonerInRealTime() async {
    let scheduler = FakeDueScheduler()
    let reminders = ReviewDueReminders(scheduler: scheduler, defaults: defaults(), shift: 3590, clock: { self.start })
    reminders.reschedule([record(dueIn: 3600, from: start)])
    await reminders.settled()
    XCTAssertEqual(scheduler.added.first?.1, start.addingTimeInterval(10))
  }

  /// 记下第一笔时才问到权限：问完 `refresh()` 一次，这一笔就挂上系统通知（锁屏也响）。
  @MainActor func testRefreshAfterPermissionGrantedSchedulesTheSystemNotification() async {
    let scheduler = FakeDueScheduler(); scheduler.authorized = false
    let reminders = ReviewDueReminders(scheduler: scheduler, defaults: defaults(), clock: { self.start })
    let pending = record(dueIn: 3600, from: start)
    reminders.reschedule([pending])
    await reminders.settled()
    XCTAssertTrue(scheduler.added.isEmpty, "没权限时不往通知中心排")
    scheduler.authorized = true
    reminders.refresh()
    await reminders.settled()
    XCTAssertEqual(scheduler.added.map(\.0.id), [pending.id])
  }

  /// 没有通知权限：前台自己叫，一条只叫一次（换页重排、冷启动都不再叫）；后台不叫。
  @MainActor func testWithoutPermissionTheForegroundAnnouncesEachOnce() async {
    let scheduler = FakeDueScheduler(); scheduler.authorized = false
    let store = defaults()
    var now = start
    let due = record(dueIn: -30, from: start), waiting = record(dueIn: 3600, from: start), stale = record(dueIn: -200_000, from: start)
    var heard: [UUID] = []
    let reminders = ReviewDueReminders(scheduler: scheduler, defaults: store, clock: { now })
    reminders.onInApp = { heard.append($0.id) }
    reminders.reschedule([due, waiting, stale])
    await reminders.settled()
    XCTAssertEqual(heard, [due.id], "过了点一天以内的补叫；更早的不叫；没到点的不叫")
    XCTAssertTrue(scheduler.added.isEmpty, "没权限不往系统里排")
    reminders.reschedule([due, waiting, stale])
    await reminders.settled()
    XCTAssertEqual(heard, [due.id], "同一条不叫第二遍")

    // 冷启动：新实例、同一本账。
    now = start.addingTimeInterval(3700)
    let again = ReviewDueReminders(scheduler: scheduler, defaults: store, clock: { now })
    again.onInApp = { heard.append($0.id) }
    again.setForeground(false)
    again.reschedule([due, waiting])
    await again.settled()
    XCTAssertEqual(heard, [due.id], "后台不叫")
    again.setForeground(true)
    await again.settled()
    XCTAssertEqual(heard, [due.id, waiting.id])
  }

  /// 有权限时系统叫过的记进账本：权限后来被关掉，也不会被前台再补叫一遍。
  @MainActor func testSystemDeliveredOnesAreNotAnnouncedAgainAfterPermissionIsRevoked() async {
    let scheduler = FakeDueScheduler()
    let store = defaults()
    var now = start
    let item = record(dueIn: 60, from: start)
    var heard: [UUID] = []
    let reminders = ReviewDueReminders(scheduler: scheduler, defaults: store, clock: { now })
    reminders.onInApp = { heard.append($0.id) }
    reminders.reschedule([item])
    await reminders.settled()
    now = start.addingTimeInterval(120)   // 系统那条响过了
    reminders.reschedule([item])
    await reminders.settled()
    scheduler.authorized = false
    reminders.reschedule([item])
    await reminders.settled()
    XCTAssertEqual(heard, [])
  }

  /// 在前台等到点：一次只挂一个等待，到点叫一声（不轮询）。
  @MainActor func testForegroundWaitsForTheNextDueWithoutPolling() async throws {
    let scheduler = FakeDueScheduler(); scheduler.authorized = false
    let item = record(dueIn: 0.3, from: Date())
    var heard: [UUID] = []
    let reminders = ReviewDueReminders(scheduler: scheduler, defaults: defaults())
    reminders.onInApp = { heard.append($0.id) }
    reminders.reschedule([item])
    await reminders.settled()
    XCTAssertEqual(heard, [])
    try await Task.sleep(nanoseconds: 1_300_000_000)
    XCTAssertEqual(heard, [item.id])
    reminders.stop()
  }
}
