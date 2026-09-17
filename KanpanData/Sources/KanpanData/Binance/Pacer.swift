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

/// 进程内单调时钟，毫秒。
///
/// `Pacer` 是给**可控睡眠**用的协议：测试注一把虚拟时钟，退避和限流就能在
/// 被加速的时间里跑完。但它同时也被当钟表读——而读一次钟就是一次 `async`
/// 调用，在 actor 里每读一次都要挂起、切执行器、再恢复，读到的无非是一个
/// `DispatchTime`。凡是只想知道「两件事之间隔了多久」的地方都改读这里：
/// 不跨 actor、不挂起，也不受系统时间被改动影响。
///
/// 注了虚拟时钟的路径不能绕过 `Pacer`（虚拟时间里这把钟是不动的），
/// 所以各处都按 `pacer is SystemPacer` 分流，只有真机那一路走这里。
enum MonoClock {
  static func nowMs() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }
}
