import Foundation

/// 时钟 + 睡眠。抽出来是为了限流和退避能在虚拟时间里跑，测试不用真等。
public protocol Pacer: Sendable {
  /// 单调递增的毫秒。只用来算间隔，绝对值没有意义。
  func nowMs() async -> Double
  func sleep(ms: Double) async throws
}

public struct SystemPacer: Pacer {
  public init() {}
  public func nowMs() async -> Double { MonoClock.nowMs() }
  public func sleep(ms: Double) async throws {
    guard ms > 0 else { return }
    // `UInt64(inf)`、`UInt64(≥ 1.8e19)` 会直接崩。一年以上的睡眠在这个 app 里不存在，
    // 真碰上就当它睡一年（照样认取消）。
    try await Task.sleep(nanoseconds: UInt64(min(ms, 365 * 86_400_000) * 1e6))
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
///
/// **手机睡着的时间也要算进去。** 原来读的是 `DispatchTime.now().uptimeNanoseconds`
/// （`mach_absolute_time`），它在设备睡眠时是停的：锁屏一小时、CPU 真睡着的那几十分钟
/// 这把钟一格不走。于是锁屏前挨的 418 / 429 封禁、一分钟权重窗口、网关冷却，解锁回来
/// 在这把钟上都还「没过去」——上游早解禁了，限流器还当场拒发、界面挂着「点此重试」。
/// `CLOCK_MONOTONIC_RAW`（`mach_continuous_time`）睡着也走、也不受改系统时间影响，
/// 这才是「过了多久」该用的那把。`SystemPacer.nowMs()`、`MarketFeed` 的节流钟都读这里，
/// 三处必须是同一个量。
public enum MonoClock {
  public static func nowMs() -> Double { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e6 }
}
