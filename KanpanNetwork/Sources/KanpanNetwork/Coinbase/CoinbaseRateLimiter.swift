import Foundation

/// Coinbase 公开行情的限速：按 IP 10 次/秒（官方公开端点的保守值）。
///
/// 做法是最简单的「两次出站之间至少隔 100 毫秒」，整个进程共用一把——Coinbase 按
/// 出口 IP 记账，同一台手机上开几份提供者也是同一个 IP。被回了 429 就整把歇一会儿
/// （有 `Retry-After` 听它的，没有就 1 秒），不是哪一个调用自己歇。
actor CoinbaseRateLimiter {
  static let shared = CoinbaseRateLimiter()

  private let gapMs: Double
  private let pacer: Pacer
  private var nextSlotMs: Double = 0

  init(perSecond: Double = 10, pacer: Pacer = SystemPacer()) {
    self.gapMs = 1000 / max(1, perSecond)
    self.pacer = pacer
  }

  /// 排一个出站的位置。排到了才返回。
  func acquire() async throws {
    let now = await pacer.nowMs()
    let slot = max(now, nextSlotMs)
    nextSlotMs = slot + gapMs
    let wait = slot - now
    if wait > 0 { try await pacer.sleep(ms: wait) }
    try Task.checkCancellation()
  }

  /// 被限流了：从现在起这么久谁都不许再发。
  func penalize(seconds: TimeInterval) async {
    let now = await pacer.nowMs()
    nextSlotMs = max(nextSlotMs, now + max(0.1, seconds) * 1000)
  }
}
