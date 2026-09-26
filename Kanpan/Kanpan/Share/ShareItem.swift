import Foundation
import KanpanCore
import os

struct ShareWindow: Codable, Equatable, Sendable {
  var from: Double
  var to: Double
  var window: ViewWindow { ViewWindow(to: to, span: max(1, to - from)) }
}
struct ShareItem: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var from: String
  var symbol: String
  var market: String
  var interval: Interval
  var view: ShareWindow
  var drawings: [Drawing]
  var alerted: [String]
  // 服务端的 RFC3339 原串也是游标；保留微秒精度，不经 Date 往返削成毫秒。
  var createdAt: String
  var openedAt: String?
  var keptAt: String?
  /// 这封是回信：指向我先前发给他的那一封（P3.5）。卡上写「XX 回了你」。
  var replyTo: String?
  var key: String { InstrumentID.canonical(symbol.contains("/") ? symbol : market + "/" + symbol) }
  var shortSymbol: String {
    SymbolInfo.placeholder(symbol: symbol).base
  }
  var createdDate: Date? { Self.date(createdAt) }
  static func date(_ raw: String) -> Date? { ShareDates.parse(raw) }
  /// 原顺序与样式保留，只换身份。偏好的提醒按旧 / 新 id 映射。
  func copies(ids: [String]? = nil) -> [Drawing] {
    drawings.enumerated().map { index, drawing in
      var copy = drawing
      copy.id = ids.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? Drawing.newID()
      return copy
    }
  }
  func preferred(in copies: [Drawing]) -> Set<String> {
    Set(zip(drawings, copies).filter { alerted.contains($0.0.id) }.map { $0.1.id })
  }
}
struct ShareOutbound: Encodable, Sendable {
  var to: String
  var symbol: String
  var interval: Interval
  var view: ShareWindow
  var drawings: [Drawing]
  var alerted: [String]
  /// 「回给他」时带上他发来的那一封的 id；服务端只认我收到的、正是他发的那封。
  var replyTo: String? = nil
}
struct ShareFriend: Codable, Hashable, Identifiable, Sendable {
  var username: String
  var id: String { username }
}
/// 程序切换的周期不进 Prefs；人的换档（包括换走又换回来）不替他撤销。
struct SharePreviewInterval {
  let before: Interval
  let shared: Interval
  private(set) var changedByUser = false
  mutating func userPicked() { changedByUser = true }
  func restore(current: Interval) -> Interval? {
    !changedByUser && current == shared && before != shared ? before : nil
  }
}

/// 分享里那几个 RFC3339 时间串的解析与盖戳。
///
/// 以前每解析一次就新建一个 `ISO8601DateFormatter`（带小数秒的那个认不出，再建第二个），
/// 朋友页每一行的 body、每次拉收件箱按留存期过滤都逐条走这一步；一个格式器建出来要几十微秒，
/// 三百封信一趟就是十几毫秒全压在主线程上（压测 M3）。现在整个进程只有这两个，
/// 格式器不保证跨线程同时用安全，所以一律在同一把锁里用。
enum ShareDates {
  private struct Formatters {
    /// 服务端的原串带小数秒（微秒）。
    let fractional: ISO8601DateFormatter
    /// 不带小数秒的；本机「已读 / 留下」盖的戳也是这一种。
    let plain: ISO8601DateFormatter
  }
  private static let formatters = OSAllocatedUnfairLock(uncheckedState: Formatters(
    fractional: {
      let parser = ISO8601DateFormatter()
      parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return parser
    }(),
    plain: ISO8601DateFormatter()))

  static func parse(_ raw: String) -> Date? {
    formatters.withLockUnchecked { $0.fractional.date(from: raw) ?? $0.plain.date(from: raw) }
  }
  /// 本机「已读 / 留下」的时间戳，和原来 `ISO8601DateFormatter().string(from:)` 同一格式。
  static func stamp(_ date: Date = Date()) -> String {
    formatters.withLockUnchecked { $0.plain.string(from: date) }
  }
  /// 两个格式器是谁。给用例核对「整个进程只建了这一份」。
  static var identities: [ObjectIdentifier] {
    formatters.withLockUnchecked { [ObjectIdentifier($0.fractional), ObjectIdentifier($0.plain)] }
  }
}
