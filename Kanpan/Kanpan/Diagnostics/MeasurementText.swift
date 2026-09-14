import Foundation

// ============================================================ MetricKit 的「带单位字符串」
//
// `MXMetricPayload.jsonRepresentation()` 里所有物理量都是**带单位的字符串**，
// 不是数字：`"500 ms"`、`"2.5 s"`、`"12 kB"`、`"3.4 MB"`、`"1200 mWh"`。
// 这是 `MXUnit*` 走 `Measurement.description` 出来的结果，Apple 没有给结构化版本。
//
// 所以要拿到数，只能自己解析。写在这里而不是散在各处，是因为：
//   1. 这是**唯一**会因为系统版本改文案而碎掉的地方，出问题一眼知道去哪儿改；
//   2. 它是纯函数，模拟器 / mac 上都能直接单测，不需要真机攒一天的 payload。
//
// 解析失败一律返回 nil，**不返回 0**：0 会被当成「这项指标很好」写进证据表，
// 那是在说谎。nil 会让上层把这项标成「缺」。

enum MeasurementText {

  /// 支持的时间单位 → 换算成毫秒的系数。
  private static let timeUnits: [(String, Double)] = [
    ("ns", 1e-6), ("µs", 1e-3), ("us", 1e-3), ("ms", 1), ("sec", 1000), ("s", 1000),
    ("min", 60_000), ("hr", 3_600_000), ("h", 3_600_000),
  ]

  /// 支持的字节单位 → 换算成 KB（1000 进制，和 `MXUnitStorage` 一致，不是 1024）的系数。
  ///
  /// MetricKit 输出过小写 `mB` / `gB` 这种怪拼写（`MXUnitStorage` 自定义符号），
  /// 所以比对一律 case-insensitive。
  private static let byteUnits: [(String, Double)] = [
    ("kb", 1), ("mb", 1000), ("gb", 1_000_000), ("tb", 1_000_000_000), ("b", 0.001),
  ]

  /// `"500 ms"` → 500。纯数字（没单位）按毫秒处理——真机上见过这种。
  static func milliseconds(_ text: String?) -> Double? {
    convert(text, units: timeUnits, bareFactor: 1)
  }

  /// `"12 kB"` → 12。纯数字按 KB 处理。
  static func kilobytes(_ text: String?) -> Double? {
    convert(text, units: byteUnits, bareFactor: 1)
  }

  /// JSON 里这一项有可能已经是数字（`NSNumber`）而不是字符串，两种都收。
  static func milliseconds(any value: Any?) -> Double? {
    if let n = value as? NSNumber { return n.doubleValue }
    return milliseconds(value as? String)
  }

  static func kilobytes(any value: Any?) -> Double? {
    if let n = value as? NSNumber { return n.doubleValue }
    return kilobytes(value as? String)
  }

  // ---------------------------------------------------------------- 实现

  private static func convert(
    _ text: String?, units: [(String, Double)], bareFactor: Double
  ) -> Double? {
    guard let raw = text?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }

    // 先切出开头那段数字（允许负号、小数点、科学计数法）。
    var digits = ""
    var rest = Substring(raw)
    while let c = rest.first,
      c.isNumber || c == "." || c == "-" || c == "+" || c == "e" || c == "E"
    {
      // `e` 只有当它真的是指数（后面跟数字或正负号）时才算数字的一部分，
      // 否则 `"3 exabytes"` 这种会把 e 吞掉。
      if c == "e" || c == "E" {
        let after = rest.dropFirst().first
        guard let after, after.isNumber || after == "-" || after == "+" else { break }
      }
      digits.append(c)
      rest = rest.dropFirst()
    }
    guard let value = Double(digits) else { return nil }

    let suffix = rest.trimmingCharacters(in: .whitespaces).lowercased()
    if suffix.isEmpty { return value * bareFactor }

    // 长后缀优先匹配，否则 `"2 ms"` 会先被 `"s"` 命中。
    for (symbol, factor) in units.sorted(by: { $0.0.count > $1.0.count })
    where suffix == symbol || suffix.hasPrefix(symbol) {
      return value * factor
    }
    return nil
  }
}

// ============================================================ 直方图
//
// `MXHistogram` 的 JSON 形如：
//
//   { "histogramNumBuckets": 2,
//     "histogramValue": {
//       "0": { "bucketCount": 3, "bucketStart": "100 ms", "bucketEnd": "200 ms" },
//       "1": { "bucketCount": 1, "bucketStart": "200 ms", "bucketEnd": "300 ms" } } }
//
// 注意 `histogramValue` 的键是**字符串下标**且顺序不保证（JSON 对象无序），
// 必须自己按数值排。

/// 一个桶。`start` / `end` 已经换算到统一单位（时间→ms，存储→KB）。
struct HistogramBucket: Sendable, Equatable {
  var start: Double
  var end: Double
  var count: Int

  /// 取中点做代表值。桶内分布未知，中点是唯一无偏的选择；
  /// 用 start 会系统性低估，用 end 会系统性高估。
  var midpoint: Double { (start + end) / 2 }
}

/// 解析后的直方图。样本总数为 0 时 `isEmpty`，上层据此把这项标成「缺」。
struct ParsedHistogram: Sendable, Equatable {
  var buckets: [HistogramBucket]

  var totalCount: Int { buckets.reduce(0) { $0 + $1.count } }
  var isEmpty: Bool { totalCount == 0 }

  /// 分位数。**桶粒度的近似**：落在哪个桶就报那个桶的中点，
  /// 所以精度不会高于 MetricKit 给的桶宽（启动耗时那档通常 100ms 一桶）。
  /// 写进证据时必须带上这句话，否则「p50 = 250ms」看着像精确值。
  func percentile(_ p: Double) -> Double? {
    let total = totalCount
    guard total > 0 else { return nil }
    let target = Double(total) * min(max(p, 0), 1)
    var seen = 0
    for b in buckets {
      seen += b.count
      if Double(seen) >= target { return b.midpoint }
    }
    return buckets.last?.midpoint
  }

  /// 加权平均。桶中点 × 桶内样本数 ÷ 总数。
  var mean: Double? {
    let total = totalCount
    guard total > 0 else { return nil }
    let sum = buckets.reduce(0.0) { $0 + $1.midpoint * Double($1.count) }
    return sum / Double(total)
  }

  var maximum: Double? { buckets.last(where: { $0.count > 0 })?.end }

  /// `unit` 决定桶边界按时间还是按存储解析。
  static func parse(_ raw: Any?, unit: Unit) -> ParsedHistogram {
    guard let dict = raw as? [String: Any],
      let values = dict["histogramValue"] as? [String: Any]
    else { return ParsedHistogram(buckets: []) }

    func convert(_ v: Any?) -> Double? {
      unit == .milliseconds
        ? MeasurementText.milliseconds(any: v) : MeasurementText.kilobytes(any: v)
    }

    var buckets: [HistogramBucket] = []
    for key in values.keys.sorted(by: { (Int($0) ?? 0) < (Int($1) ?? 0) }) {
      guard let b = values[key] as? [String: Any],
        let start = convert(b["bucketStart"]),
        let end = convert(b["bucketEnd"])
      else { continue }
      let count = (b["bucketCount"] as? NSNumber)?.intValue ?? 0
      buckets.append(HistogramBucket(start: start, end: end, count: count))
    }
    // 按 start 再排一次：万一 JSON 的数字键顺序和桶顺序对不上（没保证过），
    // 分位数算法依赖递增序，这里兜住。
    buckets.sort { $0.start < $1.start }
    return ParsedHistogram(buckets: buckets)
  }

  enum Unit: Sendable { case milliseconds, kilobytes }
}
