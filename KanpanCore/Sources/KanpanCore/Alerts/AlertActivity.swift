import Foundation

/// 提醒「盯一个」的实时活动里会变的那一块（P3.3）。
///
/// 形状和服务端 `Backend/kanpan-api/src/live_activity.rs` 的 `content_state` 一一对应：
/// 七个键每一拍都在（取不到的是 `null`），响了之后另带一个 `firedPrice`。
/// 服务端推来的和 app 前台自己算的是同一个类型，锁屏那一块不分来源。
///
/// 这一半是纯值，留在 Core（和服务端契约对得上、在 `make core-test` 里测）；
/// 带 `ActivityKit` 的静态那一半（`AlertActivityAttributes`）在 app 与小组件共用的
/// `Kanpan/KanpanShared/AlertActivityAttributes.swift`（审查 24：Core 不碰系统框架）。
public struct AlertActivityState: Codable, Hashable, Sendable {
  public var price: Double?
  /// 24 小时涨跌幅，**小数**（-0.0123 = -1.23%），和服务端同口径。
  public var change: Double?
  /// 线在此刻的价。
  public var line: Double?
  /// 现价到线的相对距离 `(price - line) / line`。
  public var distance: Double?
  /// `watching` / `fired`。
  public var state: String
  public var firedAt: Int64?
  public var updatedAt: Int64
  public var firedPrice: Double?

  public init(price: Double?, change: Double?, line: Double?, fired: Bool = false, firedAt: Int64? = nil,
              updatedAt: Int64, firedPrice: Double? = nil) {
    self.price = Self.finite(price)
    self.change = Self.finite(change)
    self.line = Self.finite(line)
    self.distance = Self.distance(price: self.price, line: self.line)
    self.state = fired ? "fired" : "watching"
    self.firedAt = firedAt
    self.updatedAt = updatedAt
    self.firedPrice = Self.finite(firedPrice)
  }

  public var fired: Bool { state == "fired" }

  public static func distance(price: Double?, line: Double?) -> Double? {
    guard let price, let line, price.isFinite, line.isFinite, line != 0 else { return nil }
    return (price - line) / line
  }

  private static func finite(_ v: Double?) -> Double? { v.flatMap { $0.isFinite ? $0 : nil } }

  /// 「离提醒价 +1.23%」里那个数。取不到写「--」（和实时活动上缺价的写法一样）。
  /// 和 app 里所有涨跌幅同一把写法（审查 U9）。
  public var distanceLabel: String { changePercentText(distance.map { $0 * 100 }, missing: "--") }

  public var changeLabel: String {
    changePercentText(change.map { $0 * 100 }, missing: "--")
  }
}
