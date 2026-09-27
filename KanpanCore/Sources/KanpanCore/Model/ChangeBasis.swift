import Foundation

/// 全项目涨跌幅口径；和时间轴显示时区、百分比坐标基准分开。
///
/// 2026-09-28 起口径不再由用户选（原来设置里的「涨跌幅起点」三档），而是按品种类型自动定，
/// 见 `automatic(for:)`。`shanghaiMidnight` 这一档留着只是枚举完整，app 里不再有人用它。
public enum ChangeBasis: String, Codable, Sendable, CaseIterable {
  case rolling24h, shanghaiMidnight, utcMidnight

  /// 这只品种的涨跌幅从哪儿算起。
  ///
  /// - 加密（交易所 `underlyingType: COIN`，以及币安那种按 `PERPETUAL` 挂的币指数）全天候交易、
  ///   没有「一天的开盘」，看的就是交易所给的**滚动 24 小时**。
  /// - 美股、ETF、港韩 A 股、贵金属、大宗、TradFi 指数有交易日：周末休市时滚动 24 小时会把
  ///   周五的行情挪到周六周日慢慢「涨完跌完」，读起来不对，所以看 **UTC 0 点起**（上海 08:00，
  ///   和交易所日线的边界同一个时刻）。
  /// - 分类说不上来的（目录没到、`underlyingType` 缺、Pre-IPO 这类 24 小时交易的盘前合约）
  ///   一律滚动 24 小时：那是交易所原样给的数，不会错。
  ///
  /// 分类只认 `SymbolClassifier`（审查 B-04 那一份），这里不另起一套判据。
  public static func automatic(for info: SymbolInfo) -> ChangeBasis {
    let category = SymbolClassifier.classify(info)
    switch category.asset {
    case .equity, .preciousMetal, .commodity: return .utcMidnight
    case .index: return info.contractType == "PERPETUAL" ? .rolling24h : .utcMidnight
    case .crypto, .preMarket, .other: return .rolling24h
    }
  }
  public func boundary(now: Int64) -> Int64? {
    guard self != .rolling24h else { return nil }
    let offset: Int64 = self == .shanghaiMidnight ? 8 * 3_600_000 : 0
    return Int64(floor(Double(now + offset) / 86_400_000)) * 86_400_000 - offset
  }
  public func percent(last: Double, rolling: Double, open: Double?) -> Double {
    if self == .rolling24h { return rolling }
    guard last.isFinite, let open, open.isFinite, open > 0 else { return .nan }
    return (last / open - 1) * 100
  }
}
