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
  /// 上一笔真正放行的时刻。
  private var lastSendMs: Double = -.infinity
  /// 被 429 罚停到这个时刻。
  private var blockedUntilMs: Double = -.infinity

  /// 罚停还剩多久以内就原地等掉；再长就当场抛 `.blocked`，把「点此重试」交回用户。
  /// 和币安那把 `RateLimiter.waitableBanMs` 同一个数、同一个道理。
  private let waitableBanMs: Double

  init(perSecond: Double = 10, pacer: Pacer = SystemPacer(),
       waitableBanMs: Double = RateLimiter.waitableBanMs) {
    self.gapMs = 1000 / max(1, perSecond)
    self.pacer = pacer
    self.waitableBanMs = waitableBanMs
  }

  /// 排一个出站的位置。排到了才返回。
  ///
  /// **放行的那一刻才记账**，不预订。原来是进门就把 `nextSlot` 往后推一格再去睡：
  /// 睡着的那一笔被取消（换品种、离开页面整批撤掉的取数），它订下的那一格照样留着，
  /// 后来的人得把这些没人用的格子一格格等过去——撤掉二十笔，下一笔真请求就平白多等
  /// 两秒。现在每一圈醒来都按「上一笔真出站的时刻」和「罚停截止」重算，
  /// 取消的人什么也没留下。
  func acquire() async throws {
    while true {
      try Task.checkCancellation()
      let now = await pacer.nowMs()
      // 原来罚停多久都一声不吭地睡：`Retry-After: 60` 就让首屏、补缺静默挂一分钟，
      // 界面上既没有错误也没有重试；值再大就等于永远挂住。
      let banRemaining = blockedUntilMs - now
      if banRemaining > waitableBanMs {
        throw UpstreamError.blocked(seconds: banRemaining / 1000)
      }
      let wait = max(banRemaining, lastSendMs + gapMs - now)
      if wait <= 0 {
        lastSendMs = now
        return
      }
      try await pacer.sleep(ms: wait)
    }
  }

  /// 被限流了：从现在起这么久谁都不许再发。
  func penalize(seconds: TimeInterval) async {
    let now = await pacer.nowMs()
    let secs = UpstreamError.sanitizedRetryAfter(seconds) ?? 1
    blockedUntilMs = max(blockedUntilMs, now + max(0.1, secs) * 1000)
  }
}
