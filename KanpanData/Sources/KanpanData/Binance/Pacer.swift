import Foundation

/// 时钟 + 睡眠。抽出来是为了限流和退避能在虚拟时间里跑，测试不用真等。
public protocol Pacer: Sendable {
  /// 单调递增的毫秒。只用来算间隔，绝对值没有意义。
  func nowMs() async -> Double
  func sleep(ms: Double) async throws
}

public struct SystemPacer: Pacer {
  public init() {}
  public func nowMs() async -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1e6
  }
  public func sleep(ms: Double) async throws {
    guard ms > 0 else { return }
    try await Task.sleep(nanoseconds: UInt64(ms * 1e6))
  }
}
