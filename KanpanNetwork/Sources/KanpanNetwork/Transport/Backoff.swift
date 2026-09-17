import Foundation

/// 重连退避：1s → 2s → 4s → … ≤ 30s（§4.4）。纯函数，验收时直接对着日志数。
public struct Backoff: Sendable, Equatable {
  public var baseMs: Double
  public var capMs: Double
  public private(set) var attempt: Int = 0

  public init(baseMs: Double = 1000, capMs: Double = 30_000) {
    self.baseMs = baseMs
    self.capMs = capMs
  }

  /// 下一次该等多久，并把次数 +1。
  public mutating func next() -> Double {
    let d = min(capMs, baseMs * pow(2, Double(attempt)))
    attempt += 1
    return d
  }

  /// 只看不动。
  public func peek() -> Double { min(capMs, baseMs * pow(2, Double(attempt))) }

  /// 连上了就归零。
  public mutating func reset() { attempt = 0 }

  /// 前 n 次的完整序列（测试和文档用）。
  public static func sequence(_ n: Int, baseMs: Double = 1000, capMs: Double = 30_000) -> [Double] {
    var b = Backoff(baseMs: baseMs, capMs: capMs)
    return (0..<n).map { _ in b.next() }
  }
}

/// 静默看门狗：60 秒没有任何帧就主动重连（§4.4 / A2.8）。
public struct SilenceWatch: Sendable {
  public var timeoutMs: Double
  public private(set) var lastFrameMs: Double

  public init(timeoutMs: Double = 60_000, nowMs: Double = 0) {
    self.timeoutMs = timeoutMs
    self.lastFrameMs = nowMs
  }

  public mutating func sawFrame(at ms: Double) { lastFrameMs = ms }
  public func isSilent(at ms: Double) -> Bool { ms - lastFrameMs >= timeoutMs }
  public func remainingMs(at ms: Double) -> Double { max(0, timeoutMs - (ms - lastFrameMs)) }
}
