import Foundation

// 主力订单流 · 分桶。
//
// 照原项目「站立墙之前」的主力墙版本：桶是固定美元步长，价位落桶 = floor(价 / 步长)，
// 桶覆盖 [桶号 × 步长, (桶号 + 1) × 步长)。步长是用户可改的指标设置，默认值按品种查表
// （`OrderFlowDefaults`，表和来源见 OrderFlowSettings.swift）；表里没有的品种按前一 UTC 日收盘 × 0.1% 取最接近的
// 1 / 2 / 5 × 10ⁿ 档位（`derivedStep`），且不小于该品种的最小价格步长。
// 几家交易所的价位都落进同一组桶号，所以聚合、成交归因、跟踪都按同一个步长。

public struct BucketScheme: Sendable, Equatable {
  /// 表里没有的品种：步长取收盘价的这个比例附近。
  public static let derivedFraction = 0.001

  /// 桶宽（美元）。
  public let step: Double

  public var width: Double { step }

  public init?(step: Double) {
    guard step.isFinite, step > 0 else { return nil }
    self.step = step
  }

  /// 价位所在的桶号。步长常是 0.1 这类浮点里不精确的数，150.3 / 0.1 会得 1502.9999…，
  /// 离整数 1e-9 以内的先吸到整数再向下取整。
  public func index(of price: Double) -> Int64 {
    let x = price / step
    let r = x.rounded()
    let q = abs(x - r) <= 1e-9 * max(1, abs(r)) ? r : x.rounded(.down)
    guard q.isFinite, abs(q) < Double(Int64.max / 4) else { return 0 }
    return Int64(q)
  }

  /// 桶的下沿价。
  public func low(of index: Int64) -> Double { Double(index) * step }

  /// 表里没有的品种：收盘 × 0.1% 最接近的 1 / 2 / 5 × 10ⁿ，且不小于最小价格步长。
  public static func derivedStep(referenceClose: Double, tick: Double?) -> Double? {
    guard referenceClose.isFinite, referenceClose > 0 else { return nil }
    let target = referenceClose * derivedFraction
    let decade = pow(10, (log10(target)).rounded(.down))
    let candidates = [0.5, 1, 2, 5, 10].map { $0 * decade }
    guard var best = candidates.min(by: { abs($0 - target) < abs($1 - target) }) else { return nil }
    if let tick, tick.isFinite, tick > 0, best < tick { best = tick }
    return best.isFinite && best > 0 ? best : nil
  }

  /// 前一个 UTC 日的零点（毫秒）：推导步长用这一天的收盘。
  public static func referenceDay(nowMs: Int64) -> Int64 {
    let day: Int64 = 86_400_000
    let today = nowMs >= 0 ? nowMs / day * day : ((nowMs - day + 1) / day) * day
    return today - day
  }
}
