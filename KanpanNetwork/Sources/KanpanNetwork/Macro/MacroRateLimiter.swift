import Foundation

/// 美元指数 REST 的出站节拍：两次出站之间至少隔 `1 / perSecond` 秒，整个进程共用一把。
///
/// 服务端是自己的，限得没有交易所那么紧，但切周期、翻历史一口气会发好几页，
/// 照样排一排，别一下子把同一台机器打满。被回了 429 就整把歇一会儿（`Retry-After` 优先）；
/// 罚停太久就当场抛 `.blocked`，把「点此重试」交回用户（和另两家同一个道理）。
actor MacroRateLimiter {
  static let shared = MacroRateLimiter()

  private let gapMs: Double
  private let pacer: Pacer
  private let waitableBanMs: Double
  private var lastSendMs: Double = -.infinity
  private var blockedUntilMs: Double = -.infinity

  init(perSecond: Double = 10, pacer: Pacer = SystemPacer(),
       waitableBanMs: Double = RateLimiter.waitableBanMs) {
    self.gapMs = 1000 / max(1, perSecond)
    self.pacer = pacer
    self.waitableBanMs = waitableBanMs
  }

  /// 排一个出站的位置。放行的那一刻才记账，被取消的人不占格子。
  func acquire() async throws {
    while true {
      try Task.checkCancellation()
      let now = await pacer.nowMs()
      let banRemaining = blockedUntilMs - now
      if banRemaining > waitableBanMs { throw UpstreamError.blocked(seconds: banRemaining / 1000) }
      let wait = max(banRemaining, lastSendMs + gapMs - now)
      if wait <= 0 { lastSendMs = now; return }
      try await pacer.sleep(ms: wait)
    }
  }

  func penalize(seconds: TimeInterval) async {
    let now = await pacer.nowMs()
    let secs = UpstreamError.sanitizedRetryAfter(seconds) ?? 1
    blockedUntilMs = max(blockedUntilMs, now + max(0.1, secs) * 1000)
  }
}
