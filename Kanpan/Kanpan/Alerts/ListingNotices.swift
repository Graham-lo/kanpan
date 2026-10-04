import Foundation
import KanpanAccount
import KanpanCore
import UserNotifications

/// 设置 › 通知「品种上新与停牌下架」（`Prefs.notifyListingChanges`）的拉取端。
///
/// 服务端每 10 分钟对一次品种表，事件记在每个人名下（`docs/条件提醒-协议-2026-09-27.md` 第 6 节）；
/// 有 APNs 密钥时它自己推，没有时就只记着。app 回前台、每一轮同步跑完都来拉一次
/// `GET /v1/alerts/listing-notices`，新的当本地通知出——**每条只出一次**：本机按账号记一个
/// 「看到哪条了」的游标（最大 id），通知 id 也按事件 id 起，重复 `add` 只会覆盖同一条。
///
/// 第一次拉（这台设备上这个账号还没有游标）只出最近 1 小时内的（和服务端「只推刚发生的」一致），
/// 之后出游标以后、24 小时以内的；太旧的只挪游标不打扰。一次最多出 5 条（新的在前）。
@MainActor
enum ListingNotices {
  struct Notice: Decodable, Sendable, Equatable {
    var id: Int64
    var venue: String
    var market: String
    var symbol: String
    var event: String
    var at: Int64
    var title: String
    var body: String
  }

  struct Page: Decodable, Sendable { var notices: [Notice] }

  nonisolated static let firstWindowMs: Int64 = 3_600_000
  nonisolated static let windowMs: Int64 = 24 * 3_600_000
  nonisolated static let maxPerPull = 5
  /// 两次拉取至少隔多久（回前台和同步跑完常常前后脚到）。
  static let minInterval: TimeInterval = 20

  /// 哪几个账号的拉取还在路上、各自上次什么时候拉的。两样都按账号记：原来「在路上」是全局一格，
  /// 切账号恰逢上一个账号那笔没回来，新账号这一轮就被挡掉，要等下一次回前台（深度审查 E-11）。
  private static var inflight: Set<UUID> = []
  private static var lastPull: [UUID: Date] = [:]

  nonisolated static let idPrefix = "listing."

  static func cursorKey(_ owner: UUID) -> String { "listingNotices.cursor." + owner.uuidString.lowercased() }

  /// 这一批里该出哪几条、游标挪到哪儿。纯函数。
  nonisolated static func plan(_ notices: [Notice], cursor: Int64?, now: Int64) -> (show: [Notice], cursor: Int64?) {
    let newest = notices.map(\.id).max()
    let next = [cursor, newest].compactMap { $0 }.max()
    let window = cursor == nil ? firstWindowMs : windowMs
    let fresh = notices.filter { $0.id > (cursor ?? Int64.min) && $0.at >= now - window }
      .sorted { $0.id > $1.id }
    return (Array(fresh.prefix(maxPerPull)), next)
  }

  /// 这个账号现在能不能发一笔：它自己没有在路上的、离它上次拉够久了。能就记上「在路上」。
  static func begin(owner: UUID, now: Date = Date()) -> Bool {
    guard !inflight.contains(owner), now.timeIntervalSince(lastPull[owner] ?? .distantPast) >= minInterval else { return false }
    inflight.insert(owner)
    lastPull[owner] = now
    return true
  }

  static func end(owner: UUID) { inflight.remove(owner) }

  static func pull(api: AccountClient, owner: UUID, sound: AlertSound) {
    guard begin(owner: owner) else { return }
    Task { @MainActor in
      defer { end(owner: owner) }
      guard let page = try? await api.request("v1/alerts/listing-notices", owner: owner, as: Page.self) else { return }
      let key = cursorKey(owner)
      let cursor = (UserDefaults.standard.object(forKey: key) as? NSNumber)?.int64Value
      let result = plan(page.notices, cursor: cursor, now: Int64(Date().timeIntervalSince1970 * 1000))
      if let next = result.cursor { UserDefaults.standard.set(NSNumber(value: next), forKey: key) }
      for notice in result.show { present(notice, sound: sound) }
    }
  }

  static func present(_ notice: Notice, sound: AlertSound) {
    let content = UNMutableNotificationContent()
    content.title = notice.title
    content.body = notice.body
    content.sound = sound.fileName.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) } ?? .default
    content.categoryIdentifier = AlertNotifications.category
    let key = InstrumentID(venue: notice.venue, market: notice.market, symbol: notice.symbol).key
    content.userInfo = [AlertNotifications.linkKey: "\(DeepLink.scheme)://symbol/\(key)"]
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: idPrefix + String(notice.id), content: content, trigger: nil))
  }
}
