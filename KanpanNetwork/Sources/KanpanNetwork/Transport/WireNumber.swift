import Foundation
import KanpanCore

/// 报文里的数值只收有限值。
///
/// `Double("nan")`、`Double("inf")`、`Double("1e400")` 都解得开（后两个是 `+inf`），
/// 解码层要是只问「是不是数字」，这些值就一路流进主动买卖桶、订单簿、K 线末根，
/// 一笔坏成交能把整根的成交量、整本簿的累计量都变成 NaN。所以推送解码一律经这里：
/// 解不开的照旧当缺失；**解得开但不是有限值**的，调用方丢掉整帧，并在这里记一笔。
public enum WireNumber {
  private static let counter = DropCounter()

  /// 因为数值不是有限值（或超出合法范围）被整帧丢掉的推送帧数。进程级累计，诊断用。
  public static var droppedFrames: Int { counter.value }

  /// 记一帧因坏数值被丢掉。
  public static func noteDropped() { counter.bump() }

  /// 测试用：清零。
  public static func resetDropped() { counter.reset() }
}

/// 字符串 → 有限的 `Double`。解不开给 nil；解得开但不是有限值也给 nil（并不计数，
/// 丢不丢整帧由调用方决定，丢了再 `WireNumber.noteDropped()`）。
@inline(__always)
func finiteDouble(_ text: String) -> Double? {
  guard let v = Double(text), v.isFinite else { return nil }
  return v
}

/// 数字 → 有限的 `Double`。
@inline(__always)
func finiteDouble(_ value: Double) -> Double? { value.isFinite ? value : nil }

private final class DropCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var n = 0
  var value: Int { lock.lock(); defer { lock.unlock() }; return n }
  func bump() { lock.lock(); n += 1; lock.unlock() }
  func reset() { lock.lock(); n = 0; lock.unlock() }
}

// ---------------------------------------------------------------- 交易所报文的共用口径（2026-10-08 压测）

/// 交易所给的时刻（毫秒）合不合理：正数、早于 1e14 毫秒（公元 5000 年前后）。
///
/// 不只是好看：开盘时刻是要拿来做加减的（翻页游标 `cursor - startTime`、`now - cursor`、秒 × 1000），
/// `-9223372036854775808` 这种值一进来，下一步整数运算就溢出闪退。
enum WireTime {
  static let maxMs: Int64 = 100_000_000_000_000

  @inline(__always)
  static func plausible(_ ms: Int64) -> Bool { ms > 0 && ms < maxMs }

  /// 秒 → 毫秒；不合理（含乘了会溢出）给 nil。
  static func ms(seconds: Int64) -> Int64? {
    guard seconds > 0, seconds < maxMs / 1000 else { return nil }
    return seconds * 1000
  }
}

/// 一根交易所 K 线收不收：数值有效（`Bar.isValidMarketBar`）、价格为正（零价的 K 线只会是坏数据，
/// 画上去整张图的纵轴就塌了）、开盘时刻合理。OKX / Bybit / Hyperliquid / Coinbase 的 REST 与推送同一口径。
func isPlausibleVenueBar(_ bar: Bar) -> Bool {
  bar.isValidMarketBar && bar.low > 0 && WireTime.plausible(bar.openTime)
}

/// 价格类字段（24h 高低、开盘、标记价、指数价）：有限正数，否则「不知道」（NaN）。
@inline(__always)
func positiveOrNaN(_ v: Double?) -> Double {
  guard let v, v.isFinite, v > 0 else { return .nan }
  return v
}

/// 量、额类字段：有限非负数，否则「不知道」（NaN）。
@inline(__always)
func nonNegativeOrNaN(_ v: Double?) -> Double {
  guard let v, v.isFinite, v >= 0 else { return .nan }
  return v
}

/// 交易所写的步长 / 精度串（`0.25`、`1e-7`、`0.10`）要几位小数才写得下：按字面数，末尾的 0 不算，
/// 科学计数法按指数折算，封顶 12 位。指数大得离谱（`1e-9223372036854775808`）也不溢出。
/// OKX / Bybit / Coinbase 原来各写一份，`decimals(...) - exponent` 碰上 `Int.min` 当场溢出闪退。
func venueDecimals(_ text: String) -> Int {
  let t = text.trimmingCharacters(in: .whitespaces).lowercased()
  if let e = t.firstIndex(of: "e") {
    let exponent = max(-100, min(100, Int(t[t.index(after: e)...]) ?? 0))
    return max(0, min(12, venueDecimals(String(t[..<e])) - exponent))
  }
  guard let dot = t.firstIndex(of: ".") else { return 0 }
  let fraction = t[t.index(after: dot)...].reversed().drop { $0 == "0" }
  return max(0, min(12, fraction.count))
}
