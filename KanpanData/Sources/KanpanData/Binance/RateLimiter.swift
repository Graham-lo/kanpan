import Foundation

/// REST 限流（§4.1）。
///
/// 三件事：① 每分钟权重不超 2400；② 连续请求之间至少隔 120ms（翻历史是串行的）；
/// ③ 收到 418 / 429 就按 `Retry-After` 停够再发。
public actor RateLimiter {
  /// 币安 USDT 合约的分钟权重上限。留 10% 余量，撞上限比慢一点难受得多。
  public static let weightPerMinute = 2400
  /// `klines limit=1500` 的权重。
  public static let klinesWeight = 10

  private let pacer: Pacer
  private let budget: Int
  private let minGapMs: Double
  private let windowMs: Double = 60_000

  /// (时刻, 权重)，滚动一分钟窗口。
  private var spent: [(at: Double, weight: Int)] = []
  private var lastSendMs: Double = -.infinity
  /// 被 418 / 429 罚停到这个时刻。
  private var blockedUntilMs: Double = -.infinity
  public private(set) var penaltyCount = 0

  public init(pacer: Pacer = SystemPacer(),
              budget: Int = RateLimiter.weightPerMinute,
              minGapMs: Double = 120) {
    self.pacer = pacer
    self.budget = budget
    self.minGapMs = minGapMs
  }

  /// 拿到发一次请求的许可。该等就在这儿等够。
  public func acquire(weight: Int) async throws {
    while true {
      let now = await pacer.nowMs()
      prune(now: now)

      if now < blockedUntilMs {
        try await pacer.sleep(ms: blockedUntilMs - now)
        continue
      }
      let gap = minGapMs - (now - lastSendMs)
      if gap > 0 {
        try await pacer.sleep(ms: gap)
        continue
      }
      let used = spent.reduce(0) { $0 + $1.weight }
      if used + weight > budget {
        // 等最老的那笔滑出窗口。
        let wait = (spent.first.map { $0.at + windowMs - now } ?? windowMs) + 1
        try await pacer.sleep(ms: max(1, wait))
        continue
      }
      spent.append((at: now, weight: weight))
      lastSendMs = now
      return
    }
  }

  /// 收到 418 / 429。`Retry-After` 是秒；没给就按 1 秒起跳翻倍。
  public func penalize(retryAfterSeconds: Double?) async {
    penaltyCount += 1
    let secs = retryAfterSeconds ?? min(30, pow(2, Double(penaltyCount - 1)))
    let now = await pacer.nowMs()
    blockedUntilMs = max(blockedUntilMs, now + secs * 1000)
  }

  /// 一次成功的请求，清掉罚停的记忆。
  public func succeeded() {
    penaltyCount = 0
  }

  /// 还要等多久才能发（测试和日志用）。
  public func waitMs() async -> Double {
    let now = await pacer.nowMs()
    prune(now: now)
    return max(0, max(blockedUntilMs - now, lastSendMs + minGapMs - now))
  }

  public func usedWeight() async -> Int {
    prune(now: await pacer.nowMs())
    return spent.reduce(0) { $0 + $1.weight }
  }

  private func prune(now: Double) {
    while let f = spent.first, now - f.at >= windowMs { spent.removeFirst() }
  }
}
