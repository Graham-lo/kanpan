import Foundation

// 交易复盘里的数字一律用十进制（`Decimal`），线上一律是十进制字符串。
//
// 为什么不用 Double：回合的盈亏是几十笔成交的已实现盈亏、手续费、资金费一路加出来的，
// 交易所给的就是十进制字符串（"0.00012345"），用 Double 加几十次会在第八位上出零头，
// 两台手机拼同一个回合、服务端再拿 Rust 的 decimal 核一遍时就对不上。
// 协议见 `docs/交易复盘-协议-2026-09-27.md` 第 1 节。

public enum TradeDecimal {
  /// 价格、数量、金额的小数位。
  public static let amountScale = 8
  /// 比值（胜率、占比、涨跌幅）的小数位。
  public static let ratioScale = 6
  /// 盈亏比的小数位。
  public static let rewardRiskScale = 4

  private static let posix = Locale(identifier: "en_US_POSIX")

  /// 解析交易所给的十进制字符串。空串、非数字、科学计数法之外的怪东西一律 nil。
  public static func parse(_ text: String) -> Decimal? {
    let t = text.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty, let d = Decimal(string: t, locale: posix), !d.isNaN else { return nil }
    return d
  }

  /// 线上格式：不带科学计数法、不带千分位、去掉尾随 0，零写 "0"。
  public static func format(_ value: Decimal) -> String {
    // `Decimal.description` 本身就是朴素写法（不出科学计数法、不带尾随 0、不看地区设置），
    // 零单独写成 "0"，免得带符号或带小数位的零漏出去。
    value.isZero ? "0" : value.description
  }

  /// 四舍六入五成双（和服务端 `rust_decimal::round_dp` 同口径）。
  public static func round(_ value: Decimal, scale: Int) -> Decimal {
    var v = value
    var out = Decimal()
    NSDecimalRound(&out, &v, scale, .bankers)
    return out
  }
}

public extension Decimal {
  /// 金额口径（8 位）舍入。
  var amountRounded: Decimal { TradeDecimal.round(self, scale: TradeDecimal.amountScale) }
  var magnitudeValue: Decimal { self < 0 ? -self : self }
}

// MARK: - Codable 辅助：十进制一律编成字符串，可空字段一律写 null（协议第 1 节）

extension KeyedDecodingContainer {
  func decimal(_ key: Key) throws -> Decimal {
    let text = try decode(String.self, forKey: key)
    guard let d = TradeDecimal.parse(text) else {
      throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "不是十进制字符串：\(text)")
    }
    return d
  }

  func decimalIfPresent(_ key: Key) throws -> Decimal? {
    guard let text = try decodeIfPresent(String.self, forKey: key) else { return nil }
    guard let d = TradeDecimal.parse(text) else {
      throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "不是十进制字符串：\(text)")
    }
    return d
  }
}

extension KeyedEncodingContainer {
  mutating func encodeDecimal(_ value: Decimal, _ key: Key) throws {
    try encode(TradeDecimal.format(value), forKey: key)
  }

  mutating func encodeDecimalOrNull(_ value: Decimal?, _ key: Key) throws {
    if let value { try encode(TradeDecimal.format(value), forKey: key) } else { try encodeNil(forKey: key) }
  }

  mutating func encodeOrNull<T: Encodable>(_ value: T?, _ key: Key) throws {
    if let value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) }
  }
}
