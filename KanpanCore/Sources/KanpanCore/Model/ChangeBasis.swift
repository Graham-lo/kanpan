import Foundation

/// 全项目涨跌幅口径；和时间轴显示时区、百分比坐标基准分开。
public enum ChangeBasis: String, Codable, Sendable, CaseIterable {
  case rolling24h, shanghaiMidnight, utcMidnight
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
