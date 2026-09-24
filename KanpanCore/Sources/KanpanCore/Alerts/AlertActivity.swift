import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// 提醒「盯一个」的实时活动里会变的那一块（P3.3）。
///
/// 形状和服务端 `Backend/kanpan-api/src/live_activity.rs` 的 `content_state` 一一对应：
/// 七个键每一拍都在（取不到的是 `null`），响了之后另带一个 `firedPrice`。
/// 服务端推来的和 app 前台自己算的是同一个类型，锁屏那一块不分来源。
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

#if canImport(ActivityKit) && os(iOS)
/// 活动的静态那一半：建的时候定死，服务端一个字都不改（`symbol` / `alertID` / `toolLabel`）。
public struct AlertActivityAttributes: ActivityAttributes {
  public typealias ContentState = AlertActivityState

  public var symbol: String
  /// 同步对象 id（`binance/usd_m/<SYM>/<id>`），服务端按它找线、判停。
  public var alertID: String
  /// 「水平线」「趋势线」「价格」这一类，锁屏上说明它盯的是什么。
  public var toolLabel: String
  /// 价格按品种精度排；服务端不用这一格。
  public var decimals: Int?
  /// 发起那一刻的涨跌配色（锁屏上没有皮肤可跟，只跟这一项）。
  public var redUp: Bool

  public init(symbol: String, alertID: String, toolLabel: String, decimals: Int?, redUp: Bool) {
    self.symbol = symbol; self.alertID = alertID; self.toolLabel = toolLabel; self.decimals = decimals
    self.redUp = redUp
  }
}
#endif
