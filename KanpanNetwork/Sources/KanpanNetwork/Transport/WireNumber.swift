import Foundation

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
