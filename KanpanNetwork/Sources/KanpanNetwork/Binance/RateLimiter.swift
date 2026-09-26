import Foundation

/// 某个端点自己那一份、和分钟权重无关的请求数配额（§4.1 / A.2）。
///
/// 币安 `/futures/data/` 这一族的权重是 0，但它另有一条「1000 次 / 5 分钟」的独立限制。
/// 只按权重算的话这一族等于不受限，翻历史时能一路撞到 429 才知道。
public struct EndpointQuota: Sendable, Equatable {
  public let name: String
  public let limit: Int
  public let windowMs: Double

  public init(name: String, limit: Int, windowMs: Double) {
    self.name = name; self.limit = limit; self.windowMs = windowMs
  }

  /// `/futures/data/` **整族共用**的 1000 次 / 5 分钟，权重单独算。
  ///
  /// 这 1000 次是币安按 IP 记在**路径族**上的，不是每个端点各有 1000。持仓量
  /// （`openInterestHist`）、多空比（`globalLongShortAccountRatio`）、主动买卖比
  /// （`takerlongshortRatio`）、基差（`basis`）四个端点从同一个计数器里扣。
  ///
  /// 所以这里只有一个桶，`name` 也故意写成路径族而不是端点名：拆成四个各自 1000 的桶，
  /// 名义容量就是 4000，真按那个额度发，撞的还是同一条上游限制——429 一来，连带把
  /// 今天工作正常的持仓量一起打挂。以后再加 `/futures/data/*` 的端点，继续共用这一个。
  public static let futuresData = EndpointQuota(name: "futures/data",
                                                limit: 1000, windowMs: 300_000)
}

/// REST 限流（§4.1）。
///
/// 四件事：① 每分钟权重不超 2400；② 连续请求之间至少隔 25ms；
/// ③ 收到 418 / 429 就按 `Retry-After` 停够再发；④ 个别端点还有自己的请求数配额。
///
/// 第③条在第四轮（A-03 / A.3）改过语义：**长封禁不再是「睡到截止再发」，而是当场
/// 拒发**。418 是 IP 级封禁，官方给的范围是 2 分钟到 3 天；把调用方挂在 `acquire`
/// 里睡两分钟，等于首屏、自选、目录全都静静地卡住，而且每个调用方醒来还要各自再撞
/// 一轮。现在 `acquire` 对超过 `waitableBanMs` 的封禁直接抛
/// `BinanceError.blocked(seconds:)`，业务层据此结束本轮、把既有的「点此重试」入口亮出来。
public actor RateLimiter {
  /// 币安 USDT 合约的分钟权重上限。留 10% 余量，撞上限比慢一点难受得多。
  public static let weightPerMinute = 2400
  /// 币安 K 线按请求条数计权重。必须传实际 `limit`，否则 300 根首屏和 3 根健康探测
  /// 都会被按 1500 根计费，造成不必要的分钟窗口等待。
  public static func klinesWeight(for limit: Int) -> Int {
    switch max(1, min(limit, 1500)) {
    case 1..<100: return 1
    case 100..<500: return 2
    case 500...1000: return 5
    default: return 10
    }
  }

  /// 封禁还剩这么久以内就在 `acquire` 里等掉（毫秒）；超过就抛 `blocked`。
  ///
  /// 10 秒这个数是这么来的：既有的 429 + `Retry-After: 7` 那类短罚停，等掉比把一次
  /// 首屏判死要划算；而 418 起步 120 秒、以及 429 没给头时我们自己按至少 10 秒算的
  /// 那种，等下去只会让界面无声地吊住。
  public static let waitableBanMs: Double = 10_000
  /// 418 没给 `Retry-After` 时的起步封禁（秒）。官方文档给的最短就是 2 分钟。
  public static let ipBanFloorSeconds: Double = 120
  /// 429 没给 `Retry-After` 时的封禁下限（秒）。指数退避算出来比这个小就取这个。
  public static let rateLimitFloorSeconds: Double = 10

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
  /// 共享限流器留给自己的分钟权重预算（2400 的 87.5%）。`apply(rules:)` 按同样的
  /// 比例折算上游公布的新限额。
  public static let sharedBinanceBudget = 2100
  public static let sharedBinance = RateLimiter(budget: RateLimiter.sharedBinanceBudget, minGapMs: 25)
  public static let sharedOKX = RateLimiter(budget: 1000, minGapMs: 40)

  private let pacer: Pacer
  /// 见 `MonoClock`：真机上读时刻不必再跨一次 `await`。
  private let systemClock: Bool
  private var budget: Int
  private let minGapMs: Double
  private let windowMs: Double = 60_000
  private let waitableBanMs: Double

  /// (时刻, 权重)，滚动一分钟窗口。
  private var spent: [(at: Double, weight: Int)] = []
  /// 按端点记的请求时刻，服务 `EndpointQuota`。
  private var endpointHits: [String: [Double]] = [:]
  private var lastSendMs: Double = -.infinity
  /// 被 418 / 429 罚停到这个时刻。
  private var blockedUntilMs: Double = -.infinity
  /// 这次封禁是谁给的（418 还是 429），抛 `blocked` 时一起带上去。
  private var blockedStatus: Int = 429
  public private(set) var penaltyCount = 0

  public init(pacer: Pacer = SystemPacer(),
              budget: Int = RateLimiter.weightPerMinute,
              minGapMs: Double = 120,
              waitableBanMs: Double = RateLimiter.waitableBanMs) {
    self.pacer = pacer
    self.systemClock = pacer is SystemPacer
    self.budget = budget
    self.minGapMs = minGapMs
    self.waitableBanMs = waitableBanMs
  }

  /// 拿到发一次请求的许可。该等就在这儿等够；封禁太长就当场拒发。
  ///
  /// - Throws: `BinanceError.blocked(seconds:)`——上游的封禁还剩得比
  ///   `waitableBanMs` 长，这一笔**没有出站**。
  public func acquire(weight: Int, quota: EndpointQuota? = nil) async throws {
    while true {
      // 每一圈都先看一眼取消，而且必须在记账之前：真机时钟读时刻不挂起，一笔已经被
      // 掐掉的请求（换品种时整批撤掉的预取）走到底会照样把权重、端点配额和最小间隔
      // 记上，然后才在调用方那句 `checkCancellation` 里退场——一分钟窗口里凭空多出
      // 一截没出站的账，后面真要发的请求白白排队。
      try Task.checkCancellation()
      let now = await nowMs()
      prune(now: now)

      let banRemaining = blockedUntilMs - now
      if banRemaining > 0 {
        if banRemaining > waitableBanMs {
          throw BinanceError.blocked(seconds: banRemaining / 1000, upstreamStatus: blockedStatus)
        }
        try await pacer.sleep(ms: banRemaining)
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
      if let quota {
        var hits = endpointHits[quota.name] ?? []
        hits.removeAll { now - $0 >= quota.windowMs }
        endpointHits[quota.name] = hits
        if hits.count >= quota.limit {
          let wait = (hits.first.map { $0 + quota.windowMs - now } ?? quota.windowMs) + 1
          try await pacer.sleep(ms: max(1, wait))
          continue
        }
        hits.append(now)
        endpointHits[quota.name] = hits
      }
      spent.append((at: now, weight: weight))
      lastSendMs = now
      return
    }
  }

  /// 收到 418 / 429。`Retry-After` 是秒；没给就按 1 秒起跳翻倍。
  ///
  /// 这个入口不看状态码，留给「只知道被限了、不知道上游说了什么」的老调用方和测试。
  /// 拿到了线上的响应就该走 `penalize(status:retryAfterSeconds:)`。
  public func penalize(retryAfterSeconds: Double?) async {
    penaltyCount += 1
    let secs = retryAfterSeconds ?? min(30, pow(2, Double(penaltyCount - 1)))
    await ban(seconds: secs, status: 429)
  }

  /// 按线上真实的状态码 + `Retry-After` 罚停（A-03）。
  ///
  /// - 418：IP 级封禁。`Retry-After` 有就用，没给按 120 秒起步——绝不能当成
  ///   「秒级退避再试四次」，那正是把 2 分钟的封禁滚成几天的做法。
  /// - 429：按既有的指数退避，但至少 10 秒。
  public func penalize(status: Int, retryAfterSeconds: Double?) async {
    penaltyCount += 1
    let secs: Double
    if let retryAfterSeconds, retryAfterSeconds > 0 {
      secs = retryAfterSeconds
    } else if status == 418 {
      secs = Self.ipBanFloorSeconds
    } else {
      secs = max(Self.rateLimitFloorSeconds, min(30, pow(2, Double(penaltyCount - 1))))
    }
    await ban(seconds: secs, status: status)
  }

  private func ban(seconds: Double, status: Int) async {
    let now = await nowMs()
    let until = now + max(0, seconds) * 1000
    if until >= blockedUntilMs { blockedStatus = status }
    blockedUntilMs = max(blockedUntilMs, until)
  }

  /// 一次成功的请求，清掉罚停的记忆。
  ///
  /// 只清退避的级数，**不动封禁截止时间**：封禁期间发出去的那一笔可能是抢在
  /// 418 之前出站、回来得晚的 200，它不代表上游解禁了（A-T04）。
  public func succeeded() {
    penaltyCount = 0
  }

  /// 按上游公布的 `rateLimits` 调整分钟权重预算（A.2）。
  ///
  /// 硬编码的 2400 是抄文档抄来的；币安真调过限额，我们只能靠撞 429 才发现。
  /// 安全余量按原来的比例折算（2100 / 2400 = 87.5%），解析不到就维持默认。
  public func apply(rules: [BinanceRateLimitRule]) {
    guard let rule = rules.first(where: { $0.isRequestWeightPerMinute }), rule.limit > 0 else { return }
    let margin = Double(RateLimiter.sharedBinanceBudget) / Double(RateLimiter.weightPerMinute)
    let next = max(1, Int((Double(rule.limit) * margin).rounded(.down)))
    guard next != budget else { return }
    budget = next
  }

  /// 读币安回的 `X-MBX-USED-WEIGHT-1M`，把本地的滚动账对齐到上游的账（A.3.2）。
  ///
  /// 本地只数自己发出去的；同一个出口 IP 上可能还有别的进程、或者我们漏算了某个
  /// 端点的权重。上游说用了更多，就以上游的为准，差额按「刚刚花掉」记进窗口。
  public func observe(usedWeight: Int) async {
    guard usedWeight > 0 else { return }
    let now = await nowMs()
    prune(now: now)
    let local = spent.reduce(0) { $0 + $1.weight }
    guard usedWeight > local else { return }
    spent.append((at: now, weight: usedWeight - local))
  }

  /// 封禁还剩多久（毫秒）。0 表示没在封禁期内。
  public func banRemainingMs() async -> Double {
    max(0, blockedUntilMs - (await nowMs()))
  }

  public func usedWeight() async -> Int {
    prune(now: await nowMs())
    return spent.reduce(0) { $0 + $1.weight }
  }

  /// 某个端点在它自己的窗口里已经用掉几次（测试和日志用）。
  public func usedRequests(_ quota: EndpointQuota) async -> Int {
    let now = await nowMs()
    return (endpointHits[quota.name] ?? []).filter { now - $0 < quota.windowMs }.count
  }

  private func prune(now: Double) {
    while let f = spent.first, now - f.at >= windowMs { spent.removeFirst() }
  }

  /// 当前时刻，毫秒。真机上走 `MonoClock`，测试注了虚拟时钟时仍然问 `pacer`。
  private func nowMs() async -> Double {
    systemClock ? MonoClock.nowMs() : await pacer.nowMs()
  }
}
