import Foundation
import KanpanCore

/// 指标参数的合法区间（A6.5：0、负数、> 500 一律拒绝）。
///
/// **上限取 400，不是 500**：原型 `stepper.bump` 写死 `Math.max(1, Math.min(400, …))`，
/// 「原型即规格」，所以能按出来的最大值是 400。A6.5 要的是「> 500 拒绝」——400 封顶
/// 天然满足，验收时那三种非法值走的是 `reject(_:)` 这条路。
enum IndicatorParamRule {
  /// 能存下来的闭区间。
  static let range: ClosedRange<Int> = 1...400
  /// 任务书写死的硬上限，只用来出拒绝理由。
  static let hardMax = 500

  /// 为什么这个值不能要；合法就是 nil。
  static func reject(_ value: Int) -> String? {
    if value <= 0 { return "参数要大于 0" }
    if value > hardMax { return "参数不能超过 \(hardMax)" }
    if value > range.upperBound { return "参数最大 \(range.upperBound)" }
    return nil
  }

  static func isValid(_ value: Int) -> Bool { reject(value) == nil }

  /// 夹到合法区间。步进器按这个走，按不出非法值。
  static func clamp(_ value: Int) -> Int { min(range.upperBound, max(range.lowerBound, value)) }

  /// 把一串存档里的参数修成这个指标能用的样子：
  /// 个数不对就按默认值补齐 / 截断，越界的逐个夹回来。
  static func sanitize(_ raw: [Int], for id: IndicatorID) -> [Int] {
    let fallback = id.defaultParams
    guard !fallback.isEmpty else { return [] }
    var out = (id == .ma || id == .ema || id == .vol) && !raw.isEmpty
      ? Array(raw.prefix(20)) : fallback
    for i in out.indices where raw.indices.contains(i) {
      out[i] = clamp(raw[i])
    }
    return out
  }
}
