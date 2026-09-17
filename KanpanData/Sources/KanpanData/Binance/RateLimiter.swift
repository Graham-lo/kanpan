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

  /// 币安 K 线按请求条数计权重。保留上面的常量兼容旧调用方，
  /// 新请求必须传实际 `limit`，否则 300 根首屏和 3 根健康探测都会被
  /// 按 1500 根计费，造成不必要的分钟窗口等待。
  public static func klinesWeight(for limit: Int) -> Int {
    switch max(1, min(limit, 1500)) {
    case 1..<100: return 1
    case 100..<500: return 2
    case 500...1000: return 5
    default: return 10
    }
  }

  /// 全 app 共用的那把限流器（按上游分）。
  ///
  /// 币安的分钟权重是按 IP 算的，不是按对象算的。以前
  /// `BinanceREST.upstream(_:hosts:)` 每调用一次就配一把新的——行情页、自选、
  /// 复盘、品种目录同时开着就是四五把，每把都以为自己独占整个额度，真正发出去
  /// 的量是限额的好几倍。撞上 418 之后又各罚各的，谁也不知道别人已经被 ban，
  /// 于是一直有请求往枪口上撞。共用一把之后：谁被罚停，所有人一起等。
  ///
  /// 间隔从 120ms 收到 25ms——原来那个数是「每个对象各自限速」时代留下的，
  /// 现在只有一把，再用 120ms 就等于把全 app 卡在 8 次/秒。真正的闸门是
  /// 下面那个分钟权重窗口。
  public static let sharedBinance = RateLimiter(budget: 2100, minGapMs: 25)
  public static let sharedOKX = RateLimiter(budget: 1000, minGapMs: 40)

  private let pacer: Pacer
  /// 见 `MonoClock`：真机上读时刻不必再跨一次 `await`。
  private let systemClock: Bool
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
    self.systemClock = pacer is SystemPacer
    self.budget = budget
    self.minGapMs = minGapMs
  }

  /// 拿到发一次请求的许可。该等就在这儿等够。
  public func acquire(weight: Int) async throws {
    while true {
      let now = await nowMs()
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
    let now = await nowMs()
    blockedUntilMs = max(blockedUntilMs, now + secs * 1000)
  }

  /// 一次成功的请求，清掉罚停的记忆。
  public func succeeded() {
    penaltyCount = 0
  }

  /// 还要等多久才能发（测试和日志用）。
  public func waitMs() async -> Double {
    let now = await nowMs()
    prune(now: now)
    return max(0, max(blockedUntilMs - now, lastSendMs + minGapMs - now))
  }

  public func usedWeight() async -> Int {
    prune(now: await nowMs())
    return spent.reduce(0) { $0 + $1.weight }
  }

  private func prune(now: Double) {
    while let f = spent.first, now - f.at >= windowMs { spent.removeFirst() }
  }

  /// 当前时刻，毫秒。真机上走 `MonoClock`，测试注了虚拟时钟时仍然问 `pacer`。
  private func nowMs() async -> Double {
    systemClock ? MonoClock.nowMs() : await pacer.nowMs()
  }
}
