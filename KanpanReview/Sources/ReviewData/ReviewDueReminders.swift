import Foundation
import ReviewDomain

/// 复盘待办到点，叫人一声（第 25 项：到点提醒收成一个模块、一条通道）。
///
/// 以前「到点」有三条路各自叫人：本机日历通知（`ReviewDueNotifications`）、提醒总表那条
/// `reviewDue` 在前台被 `AlertEngine` 判掉后 `AlertWatcher` 的震动 + 浮条、服务端 APNs。
/// 前台从后台回来那一下，日历通知响过了、同步下来的 fired 又弹一次浮条；APNs 密钥一插上，
/// 锁屏上也是两条。现在：
///
/// - **只有一条通道叫人**。`channel == .local`（今天，没有 APNs 密钥）是本机日历通知：
///   app 关着、没网、锁屏都照响；前台由系统横幅本身呈现（通知的分类不是提醒那一类，
///   `AlertNotifications.willPresent` 给它横幅 + 声音）。`.remote` 是服务端推送：那时本机
///   一条都不排，只注册 `reviewDue` 类 token（服务端只把复盘到点推给这一类，见迁移 0023）。
///   一台设备在哪条通道上，是这一个开关定的，所以重不了。
/// - **去重只在这儿**：系统通知靠固定的 id（`prefix + 记录 id`）去重；没有通知权限时由本模块
///   在前台自己叫一声（`onInApp`），叫过的记在 `ledger` 里，换页、重排、冷启动都不再叫第二遍。
///   提醒总表那条 `reviewDue` 只管进总表和同步，不再叫人。
/// - 排程是一个存着的 `Task`：再排一次先取消上一次，`stop()` 全部收掉。
@MainActor public final class ReviewDueReminders {
  public enum Channel: Sendable, Equatable { case local, remote }
  /// 今天没有 APNs 密钥，只有本地这一条。插上密钥、服务端部署了 0023 之后改成 `.remote`。
  nonisolated public static let channel: Channel = .local
  /// 系统通知 id 的前缀：撤销时靠它认出「哪些是我排的」，别人的一条都不碰。
  nonisolated public static let prefix = "review.due."
  /// 通知的分类号。不是提醒那一类（`kanpan.alert`），前台才会按系统默认弹横幅。
  nonisolated public static let category = "kanpan.review.due"
  /// 系统给每个 app 的待发通知上限是 64 条，留一半给提醒那一侧。
  nonisolated public static let limit = 32
  /// 过了点多久以内、没被叫过的，前台补叫一声（没有通知权限、app 当时关着的那种）。
  nonisolated public static let lateWindow: TimeInterval = 86_400

  /// 一条要叫的。
  public struct Reminder: Equatable, Sendable {
    public var id: UUID
    public var at: Date
    public var title: String
    public var body: String
    public var identifier: String { ReviewDueReminders.prefix + id.uuidString }
  }

  /// 系统通知中心那一侧。测试里换成假的。
  @MainActor public protocol Scheduler: AnyObject {
    func isAuthorized() async -> Bool
    func pendingIdentifiers() async -> [String]
    func remove(_ identifiers: [String])
    /// `fireAt` 是真实时间（已经扣掉测试钩子的时移）。
    func add(_ reminder: Reminder, fireAt: Date) async
  }

  private let scheduler: any Scheduler
  private let channel: Channel
  private let defaults: UserDefaults
  /// 测试钩子：把「现在」往后拨这么多秒（DEBUG 构建里由启动参数给，见 app 侧接线）。
  /// 排程时再扣回来，所以一条一小时后到点的记录，拨 3590 秒就在十秒后真的响。
  public let shift: TimeInterval
  private let clock: () -> Date
  /// 没有通知权限时，前台自己叫一声。
  public var onInApp: (Reminder) -> Void = { _ in }

  private var records: [ReviewRecord] = []
  private var foreground = true
  private var authorized: Bool?
  private var task: Task<Void, Never>?
  private var waiter: Task<Void, Never>?

  nonisolated static let ledgerKey = "review.due.announced"

  public init(scheduler: any Scheduler, channel: Channel = ReviewDueReminders.channel,
              defaults: UserDefaults = .standard, shift: TimeInterval = 0, clock: @escaping () -> Date = Date.init) {
    self.scheduler = scheduler; self.channel = channel; self.defaults = defaults; self.shift = shift; self.clock = clock
  }

  /// 这一刻的「现在」（带时移）。
  public var now: Date { clock().addingTimeInterval(shift) }

  /// 按当前这批记录要叫哪几条：还在等答案、到期还没过，按到期排、最多 `limit` 条。
  public static func plan(_ records: [ReviewRecord], now: Date, limit: Int = ReviewDueReminders.limit) -> [Reminder] {
    let cutoff = Int64(now.timeIntervalSince1970 * 1000)
    return records
      .filter { $0.outcome == .waiting && $0.draft.rule.expires > cutoff }
      .sorted { $0.draft.rule.expires < $1.draft.rule.expires }
      .prefix(limit)
      .map(reminder)
  }
  static func reminder(_ record: ReviewRecord) -> Reminder {
    Reminder(id: record.id, at: Date(timeIntervalSince1970: Double(record.draft.rule.expires) / 1000),
             title: record.draft.range.shortSymbol + " 到点了", body: "去看看这一笔判对了没有")
  }

  /// 记录变了：整批重排（到期会改、记录会作废会被判，增量对账比重排复杂而收益为零）。
  /// 上一次还没排完的先取消。
  public func reschedule(_ records: [ReviewRecord]) {
    self.records = records
    task?.cancel()
    let due = channel == .local ? Self.plan(records, now: now) : []
    let shift = shift
    task = Task { [weak self, scheduler] in
      let wanted = Set(due.map(\.identifier))
      let stale = await scheduler.pendingIdentifiers().filter { $0.hasPrefix(Self.prefix) && !wanted.contains($0) }
      if !stale.isEmpty { scheduler.remove(stale) }
      let authorized = await scheduler.isAuthorized()
      guard !Task.isCancelled, let self else { return }
      self.authorized = authorized
      if authorized {
        for reminder in due {
          guard !Task.isCancelled else { return }
          await scheduler.add(reminder, fireAt: reminder.at.addingTimeInterval(-shift))
        }
      }
      self.armInApp()
    }
  }

  /// 前后台。没有通知权限时，只有前台这一段能叫到人。
  /// 通知权限刚变过（记下第一笔有方向的记录时问的那一次）：按手上这份记录重排一遍。
  /// 不重排的话，问之前那一轮已经按「没权限」只挂了前台补叫，锁屏上就响不了。
  public func refresh() { reschedule(records) }

  public func setForeground(_ value: Bool) {
    foreground = value
    if value { reschedule(records) } else { waiter?.cancel(); waiter = nil }
  }

  /// 全部收掉：取消排程与等待，撤掉排在系统里的那几条。
  public func stop() {
    task?.cancel(); task = nil; waiter?.cancel(); waiter = nil
    records = []
    let scheduler = scheduler
    task = Task {
      let ours = await scheduler.pendingIdentifiers().filter { $0.hasPrefix(Self.prefix) }
      if !ours.isEmpty { scheduler.remove(ours) }
    }
  }

  /// 等排程那一下做完（测试用）。
  public func settled() async { await task?.value }

  // MARK: - 没有通知权限：前台自己叫

  /// 系统叫不到人的时候（没权限）才走这里：先把已经过了点、还在补叫窗口里的叫掉，
  /// 再睡到下一条的点上。一次只挂一个等待，不轮询。
  private func armInApp() {
    waiter?.cancel(); waiter = nil
    // 有权限时系统已经（或将要）叫过：只把过了点的记进账本，不叫。这样权限哪天被关掉，
    // 系统叫过的不会被这里再补叫一遍；还没到点的那几条则会由这里接着叫。
    guard authorized == false else { if authorized == true { announceDue(silently: true) }; return }
    guard foreground else { return }
    announceDue(silently: false)
    let cutoff = Int64(now.timeIntervalSince1970 * 1000)
    guard let next = records.filter({ $0.outcome == .waiting && $0.draft.rule.expires > cutoff })
      .map(\.draft.rule.expires).min() else { return }
    let wait = max(0, Double(next) / 1000 - now.timeIntervalSince1970)
    waiter = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64((wait + 0.5) * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.armInApp()
    }
  }

  private func announceDue(silently: Bool) {
    let at = now
    var ledger = defaults.dictionary(forKey: Self.ledgerKey) as? [String: Double] ?? [:]
    // 账本只留补叫窗口里的：再往前的本来也不会再叫。
    ledger = ledger.filter { at.timeIntervalSince1970 - $0.value < Self.lateWindow * 2 }
    for record in records where record.outcome == .waiting {
      let due = Date(timeIntervalSince1970: Double(record.draft.rule.expires) / 1000)
      let key = record.id.uuidString
      guard due <= at, at.timeIntervalSince(due) < Self.lateWindow, ledger[key] == nil else { continue }
      ledger[key] = due.timeIntervalSince1970
      if !silently { onInApp(Self.reminder(record)) }
    }
    defaults.set(ledger, forKey: Self.ledgerKey)
  }
}
