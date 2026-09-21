import Foundation
import KanpanCore

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
  var shortSymbol: String {
    for quote in ["FDUSD", "USDT", "USDC", "BUSD", "TUSD", "USD1"] where symbol.hasSuffix(quote) {
      return String(symbol.dropLast(quote.count))
    }
    return symbol
  }
  var createdDate: Date? { Self.date(createdAt) }
  static func date(_ raw: String) -> Date? {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return parser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
  }
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
