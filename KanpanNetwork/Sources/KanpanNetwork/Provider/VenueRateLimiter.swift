import Foundation

/// 一家交易所的出站限速：两次出站之间至少隔 `1000 / perSecond` 毫秒，被 429 就整把歇一会儿。
///
/// **一家一个 `static let shared`**（写在 `<X>Venue.swift` 里）：交易所按出口 IP 记账，同一台手机上
/// 开几份提供者、订单流适配器拉快照、小组件补价、探测都是同一个 IP，所以全经同一把。
/// 被回了 429 就整把歇（有 `Retry-After` 听它的，没有就 1 秒），不是哪一个调用自己歇。
/// 参数按官方公开限额取保守值，写在那一家的 `Venue` 里，这里不认识任何一家。
public actor VenueRateLimiter {
  private let gapMs: Double
  private let pacer: Pacer
  /// 上一笔真正放行的时刻。
  private var lastSendMs: Double = -.infinity
  /// 被 429 罚停到这个时刻。
  private var blockedUntilMs: Double = -.infinity

  /// 罚停还剩多久以内就原地等掉；再长就当场抛 `.blocked`，把「点此重试」交回用户。
  /// 和币安那把 `RateLimiter.waitableBanMs` 同一个数、同一个道理。
  private let waitableBanMs: Double

  public init(perSecond: Double, pacer: Pacer = SystemPacer(),
              waitableBanMs: Double = RateLimiter.waitableBanMs) {
    self.gapMs = 1000 / max(0.001, perSecond)
    self.pacer = pacer
    self.waitableBanMs = waitableBanMs
  }

  /// 排一个出站的位置。排到了才返回。
  ///
  /// **放行的那一刻才记账**，不预订：睡着的那一笔被取消（换品种、离开页面整批撤掉的取数），
  /// 它什么也没留下；每一圈醒来都按「上一笔真出站的时刻」和「罚停截止」重算。
  /// 原来进门就把下一格往后推，撤掉二十笔，下一笔真请求就平白多等两秒。
  public func acquire() async throws {
    while true {
      try Task.checkCancellation()
      let now = await pacer.nowMs()
      // 罚停太长就不静默地睡：`Retry-After: 60` 会让首屏、补缺挂一分钟，界面上既没有错误也没有重试。
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

  /// 被限流了：从现在起这么久谁都不许再发。非有限 / 非正的秒数按 1 秒。
  public func penalize(seconds: TimeInterval) async {
    let now = await pacer.nowMs()
    let secs = UpstreamError.sanitizedRetryAfter(seconds) ?? 1
    blockedUntilMs = max(blockedUntilMs, now + max(0.1, secs) * 1000)
  }
}
