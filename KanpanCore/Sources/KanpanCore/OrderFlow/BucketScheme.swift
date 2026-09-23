import Foundation

// 主力订单流 · 分桶。
//
// 移植 send-tradfi `crates/bit-orderbook-signal-policy/src/policy.rs` 的 BucketDerivation::derive：
// 桶宽 = max(ceil(收盘 × 8 bps / tick), 1) × tick，收盘取前一 UTC 日；价位落桶 = floor(价 / 桶宽)。
// 全程按整数 tick 算，避免 0.1 这类 tick 在浮点里取整取偏。

public struct BucketScheme: Sendable, Equatable {
  public static let targetBps = 8.0

  public let tick: Double
  public let widthTicks: Int64
  /// 用哪一天的收盘派生的（UTC 日零点，毫秒）；每日重算时拿它比。
  public let referenceDayMs: Int64

  public var width: Double { Double(widthTicks) * tick }

  public init?(referenceClose: Double, tick: Double, referenceDayMs: Int64 = 0, bps: Double = BucketScheme.targetBps) {
    guard referenceClose.isFinite, tick.isFinite, bps.isFinite, referenceClose > 0, tick > 0, bps > 0 else { return nil }
    let ticks = Self.ceilTolerant(referenceClose * bps / 10_000 / tick)
    guard ticks.isFinite, ticks < Double(Int64.max / 4) else { return nil }
    self.tick = tick
    self.widthTicks = max(Int64(ticks), 1)
    self.referenceDayMs = referenceDayMs
  }

  /// 价位所在的桶号。
  public func index(of price: Double) -> Int64 {
    let ticks = (price / tick).rounded()
    return Int64((ticks / Double(widthTicks)).rounded(.down))
  }

  /// 桶的下沿价。
  public func low(of index: Int64) -> Double { Double(index &* widthTicks) * tick }

  /// 前一个 UTC 日的零点（毫秒）：桶宽用这一天的收盘。
  public static func referenceDay(nowMs: Int64) -> Int64 {
    let day: Int64 = 86_400_000
    let today = nowMs >= 0 ? nowMs / day * day : ((nowMs - day + 1) / day) * day
    return today - day
  }

  /// 恰好整除时浮点会冒出 800.0000000001，按原项目 Decimal 的语义应得 800。
  static func ceilTolerant(_ x: Double) -> Double {
    let r = x.rounded()
    return abs(x - r) <= 1e-9 * max(1, abs(r)) ? r : x.rounded(.up)
  }
}
