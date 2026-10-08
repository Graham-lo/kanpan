import Foundation

/// 一家交易所的出站限速。两种记账口径，按那一家官方文档的说法选：
/// - **按次数**（`init(perSecond:)`）：两次出站之间至少隔 `1000 / perSecond` 毫秒（Coinbase、OKX、Bybit）。
/// - **按权重**（`init(weightPerMinute:)`）：任意 60 秒里放行的权重合计不超过预算（Hyperliquid：官方按 IP
///   每分钟 1200 权重，各接口权重不同）。每一笔 `acquire(weight:)` 报自己的权重，滑动窗口记账——
///   官方按自然分钟还是滚动 60 秒算都不会超（任一自然分钟都落在某个 60 秒窗口里）。
///
/// 被 429 就整把歇一会儿（有 `Retry-After` 听它的，没有就 1 秒），不是哪一个调用自己歇。
///
/// **一家一个 `static let`**（写在 `<X>Venue.swift` 里）：交易所按出口 IP 记账，同一台手机上
/// 开几份提供者、订单流适配器拉快照、小组件补价、探测都是同一个 IP，所以全经同一把。
/// 参数按官方公开限额取保守值，写在那一家的 `Venue` 里，这里不认识任何一家。
public actor VenueRateLimiter {
  private let gapMs: Double
  /// 按权重时每 60 秒的预算；nil = 按次数。
  private let weightBudget: Double?
  private let pacer: Pacer
  /// 上一笔真正放行的时刻。
  private var lastSendMs: Double = -.infinity
  /// 按权重：最近 60 秒里放行过的（时刻, 权重），时刻升序。
  private var granted: [(atMs: Double, weight: Double)] = []
  /// 被 429 罚停到这个时刻。
  private var blockedUntilMs: Double = -.infinity
  /// 按权重：还在排队、没放行的那几笔（到达序号 → 这一笔替它预留的权重，超过整个预算的按整个预算记）。
  /// 只在排队期间存在：放行、被取消、抛错都当场摘掉（`defer`），不是预订。
  private var queued: [Int: Double] = [:]
  private var nextTicket = 0
  /// 排在别人后面的那一笔最多睡多久就醒来重算一次：前面的人被撤掉了，它要能及时补上，不按旧的排队长度睡满。
  static let queuedRecheckMs: Double = 5_000

  /// 罚停还剩多久以内就原地等掉；再长就当场抛 `.blocked`，把「点此重试」交回用户。
  /// 和币安那把 `RateLimiter.waitableBanMs` 同一个数、同一个道理。
  private let waitableBanMs: Double

  /// 权重预算的窗口。
  static let weightWindowMs: Double = 60_000

  /// 按次数：每秒最多 `perSecond` 笔，均匀错开。
  public init(perSecond: Double, pacer: Pacer = SystemPacer(),
              waitableBanMs: Double = RateLimiter.waitableBanMs) {
    self.gapMs = 1000 / max(0.001, perSecond)
    self.weightBudget = nil
    self.pacer = pacer
    self.waitableBanMs = waitableBanMs
  }

  /// 按权重：任意 60 秒里放行的权重合计不超过 `weightPerMinute`。不额外错开（预算够就立刻放）。
  public init(weightPerMinute: Double, pacer: Pacer = SystemPacer(),
              waitableBanMs: Double = RateLimiter.waitableBanMs) {
    self.gapMs = 0
    self.weightBudget = max(1, weightPerMinute)
    self.pacer = pacer
    self.waitableBanMs = waitableBanMs
  }

  /// 按权重时最近 60 秒已经花掉多少（测试与诊断用）。
  public func spentWeight() async -> Double {
    prune(now: await pacer.nowMs())
    return granted.reduce(0) { $0 + $1.weight }
  }

  private func prune(now: Double) {
    let cut = now - Self.weightWindowMs
    if let keep = granted.firstIndex(where: { $0.atMs > cut }) {
      if keep > 0 { granted.removeFirst(keep) }
    } else {
      granted.removeAll()
    }
  }

  /// 按权重：这一笔还要等多久才放得进预算（0 = 现在就行）。
  ///
  /// `ahead` 是排在它前面、还没放行的那几笔要的权重：后来的只有在**连前面那几笔一起**都放得下时才能先走，
  /// 不许把前面那笔等着的空位一点点抢走。原来轻的一笔只要挤得进剩下的预算就放，重的那笔要等「够它一整笔」
  /// 的空位，可每空出一点就被后来的轻请求抢走——轻请求川流不息时重的那笔永远等不到
  /// （Hyperliquid 一页 5000 根 K 线 ≈ 104 权重，被 `meta` / `allMids` 这类轻查询饿死）。
  ///
  /// 比整个预算还重的一笔：排在最前面时，窗口空着就放（之后谁都得等它出窗口）；排在它后面的一律让它。
  private func weightWait(_ weight: Double, ahead: Double, now: Double) -> Double {
    guard let budget = weightBudget else { return 0 }
    prune(now: now)
    var spent = granted.reduce(0) { $0 + $1.weight }
    let need = ahead + weight
    if spent + need <= budget { return 0 }
    // 窗口空了还放不下：排在最前的（超重的那一笔）现在就走；后面的让它先走——它走了之后
    // 窗口里就有它那一大笔，后面的反正还得等它出窗口，隔一会儿再看就行，不用打转。
    if granted.isEmpty { return ahead > 0 ? Self.queuedRecheckMs : 0 }
    var wait = 1.0
    for entry in granted {
      spent -= entry.weight
      if spent + need <= budget || spent <= 0 { wait = max(1, entry.atMs + Self.weightWindowMs - now); break }
    }
    return ahead > 0 ? min(wait, Self.queuedRecheckMs) : wait
  }

  /// 按次数的那一把：一笔算一次（按权重的那一把：一笔算权重 1）。
  public func acquire() async throws { try await acquire(weight: 1) }

  /// 排一个出站的位置。排到了才返回。`weight` 只在按权重的那一把上有意义。
  ///
  /// **放行的那一刻才记账**，不预订：睡着的那一笔被取消（换品种、离开页面整批撤掉的取数），
  /// 它什么也没留下；每一圈醒来都按「上一笔真出站的时刻 / 窗口里已花的权重」和「罚停截止」重算。
  /// 原来进门就把下一格往后推，撤掉二十笔，下一笔真请求就平白多等两秒。
  ///
  /// 按权重的那一把按到达先后排队（见 `weightWait`）：排队期间替自己预留的权重在 `queued` 里，
  /// 放行、取消、抛错的那一刻摘掉。
  public func acquire(weight: Double) async throws {
    let weight = max(0, weight)
    let ticket = nextTicket
    nextTicket &+= 1
    if let budget = weightBudget { queued[ticket] = min(weight, budget) }
    defer { queued[ticket] = nil }
    while true {
      try Task.checkCancellation()
      let now = await pacer.nowMs()
      // 罚停太长就不静默地睡：`Retry-After: 60` 会让首屏、补缺挂一分钟，界面上既没有错误也没有重试。
      let banRemaining = blockedUntilMs - now
      if banRemaining > waitableBanMs {
        throw UpstreamError.blocked(seconds: banRemaining / 1000)
      }
      let ahead = weightBudget == nil ? 0 : queued.reduce(0) { $1.key < ticket ? $0 + $1.value : $0 }
      let wait = max(banRemaining, lastSendMs + gapMs - now, weightWait(weight, ahead: ahead, now: now))
      if wait <= 0 {
        lastSendMs = now
        if weightBudget != nil { granted.append((now, weight)) }
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
