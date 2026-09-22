import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 第四轮 A-03：418/429 之后「不许再撞」这件事，从线上响应一直到共享限流器。
///
/// 这一套盯的是**出站次数**，不只是等待时长：原来的实现里 418 只是让本方法再退避
/// 四次，而 `MarketFeed` 外面还有三发 fill，同一个封禁最后撞成 3×4＝12 次，
/// 把 2 分钟的封禁续成几个小时（A.3.4）。
///
/// 时钟是注进去的（`StepPacer`），所以 120 秒的封禁在测试里不占真实时间：
/// `pacer.nowMs()` 只在有人真的 `sleep` 时才前进，这也让「有没有人在偷偷睡两分钟」
/// 变成可断言的事。
@Suite("A-03 限流与 IP 封禁")
struct RateLimitBanTests {

  /// 空 K 线响应。`[]` 解得开，够判「这一笔成功了」。
  private static let empty = Data("[]".utf8)

  /// 真 `MarketRESTTransport`（直连档）套一台假服务器：A-T01 要的就是
  /// 「上游的 `Retry-After` 经过 transport 这一层没有被压扁」。
  private func directREST(_ server: FakeServer, limiter: RateLimiter, pacer: Pacer) -> BinanceREST {
    let routed = MarketRESTTransport(source: .binance, gateways: ["gw.example.com"],
                                     transport: FakeTransport(server), policy: .direct)
    return BinanceREST(transport: routed, limiter: limiter, pacer: pacer)
  }

  // ---------------------------------------------------------------- A-T01

  @Test("A-T01 直连收到 429 + Retry-After:120：本机记满 120 秒，这一轮只出站一次")
  func retryAfterHonoredOnDirectRoute() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer(pacer: pacer) { _ in
      json(#"{"code":-1003,"msg":"Too many requests"}"#, status: 429,
           headers: ["Retry-After": "120"])
    }
    let rest = directREST(server, limiter: limiter, pacer: pacer)

    var thrown: BinanceError?
    do { _ = try await rest.klines(symbol: "BTCUSDT", interval: .h1, limit: 300) }
    catch let e as BinanceError { thrown = e }
    let error = try #require(thrown)
    // 上游说的 120 秒记进了限流器，而不是退回到我们自己那点秒级退避。
    let remaining = await limiter.banRemainingMs()
    #expect(remaining > 119_000 && remaining <= 120_000)
    // 只出站一次：第二圈开头的 `acquire` 当场拒发，没有第二个请求。
    #expect(await server.urls().count == 1)
    #expect(error.isBlocked)
    #expect(error.isRateLimited)        // 类别仍然是「限流」，不是「行情暂不可用」
    #expect((error.retryAfter ?? 0) > 119)
    // 没有人在这儿睡两分钟——`acquire` 对长封禁是拒发，不是等。
    #expect(await pacer.sleepLog().allSatisfy { $0 <= RateLimiter.waitableBanMs })
  }

  // ---------------------------------------------------------------- A-T02

  /// A-T02 要的就是 418 这一档：收到 IP 级封禁之后，到截止时刻之前，**新的业务调用
  /// 一个都不许出站**——哪怕换了端点、换了品种，因为封禁停的是整个出口 IP。
  @Test("A-T02 收到 418：2 分钟起步，只发一次，截止前的新调用一律不出站")
  func ipBanFloorIsTwoMinutes() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer(pacer: pacer) { _ in
      json(#"{"code":-1003,"msg":"IP banned"}"#, status: 418)
    }
    let rest = directREST(server, limiter: limiter, pacer: pacer)
    await #expect(throws: BinanceError.self) {
      _ = try await rest.klines(symbol: "BTCUSDT", interval: .h1, limit: 300)
    }
    // 418 不占 `attempts`：秒级重试正是把 2 分钟滚成几天的做法。
    #expect(await server.urls().count == 1)
    let remaining = await limiter.banRemainingMs()
    #expect(remaining > 119_000 && remaining <= RateLimiter.ipBanFloorSeconds * 1000)

    // 截止前再来一笔，换个端点也一样：当场拒发，出站次数还是 1。
    var refused: BinanceError?
    do { _ = try await rest.ticker24h(symbol: "ETHUSDT") }
    catch let e as BinanceError { refused = e }
    let blocked = try #require(refused)
    #expect(blocked.isBlocked)            // 被本机限流器挡下的，连包都没出去
    #expect(blocked.isRateLimited)        // 类别仍是「限流」，不是「行情暂不可用」
    #expect(await server.urls().count == 1)
    // 也没有人替调用方睡到封禁结束。
    #expect(await pacer.sleepLog().allSatisfy { $0 <= RateLimiter.waitableBanMs })
  }

  @Test("429 没给 Retry-After 时也至少停 10 秒")
  func rateLimitFloorIsTenSeconds() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    await limiter.penalize(status: 429, retryAfterSeconds: nil)
    #expect(await limiter.banRemainingMs() >= RateLimiter.rateLimitFloorSeconds * 1000)
  }

  // ---------------------------------------------------------------- 多调用方

  /// 429 + `Retry-After: 120` 落在**共用的**那把限流器上：行情页与自选页各持一份
  /// `BinanceREST`，一份被罚停，另一份也一起停。24 份报价 + 两页历史全被当场拒。
  @Test("封禁期内所有调用方共用一把限流器：26 笔新调用全被当场拒，出站次数 == 1")
  func bannedWindowSendsNothing() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer(pacer: pacer) { _ in
      json(#"{"code":-1003,"msg":"Too many requests"}"#, status: 429,
           headers: ["Retry-After": "120"])
    }
    // 两份 REST（行情页和自选页各一份）共用同一把限流器——币安的额度是按 IP 算的。
    let chart = directREST(server, limiter: limiter, pacer: pacer)
    let list = directREST(server, limiter: limiter, pacer: pacer)

    await #expect(throws: BinanceError.self) {
      _ = try await chart.klines(symbol: "BTCUSDT", interval: .h1, limit: 300)
    }
    #expect(await server.urls().count == 1)

    // 封禁期内再来一堆：24 份报价 + 两页历史，一个都不许出站。
    var blocked = 0
    for i in 0..<24 {
      do { _ = try await list.ticker24h(symbol: "SYM\(i)USDT") }
      catch let e as BinanceError where e.isBlocked { blocked += 1 }
      catch { Issue.record("报价应当被限流器当场挡下，实际抛的是 \(error)") }
    }
    for _ in 0..<2 {
      do { _ = try await chart.klines(symbol: "BTCUSDT", interval: .h1, limit: 1500) }
      catch let e as BinanceError where e.isBlocked { blocked += 1 }
      catch { Issue.record("历史应当被限流器当场挡下，实际抛的是 \(error)") }
    }
    #expect(blocked == 26)
    #expect(await server.urls().count == 1)      // 全程只有最初那一发出站
    #expect(await pacer.sleepLog().allSatisfy { $0 <= RateLimiter.waitableBanMs })
  }

  // ---------------------------------------------------------------- A-T03

  /// A-T03：封禁落下的那一刻，请求分两种，处理方式不同。
  ///
  /// - **在途的**（已经拿到许可、包已经出站）：不撤回、不取消，该收到的响应照收。
  ///   网络上的包本来也追不回来，把它判成失败只是白扔一笔已经付过权重的数据。
  /// - **新许可**：从 418 记进限流器那一刻起，全部当场拒发，一个包都不再出站。
  ///
  /// 先后靠闸门钉死，不靠 sleep 去赌机器够快：两笔都出站了才让 418 回来。
  @Test("A-T03 首个 418 之后：在途请求照收响应，新许可全部拒绝")
  func inFlightSurvivesWhileNewPermitsAreRefused() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let history = Gate()      // 放行那笔要回 418 的历史
    let quote = Gate()        // 放行那笔抢在封禁之前出站、回来得晚的报价
    let bothOut = Gate()      // 「两笔都已出站」这个事件本身
    let upstream = HeldUpstream(history: history, quote: quote, bothOut: bothOut)
    let rest = BinanceREST(transport: upstream, limiter: limiter, pacer: pacer)

    let page = Task { () -> BinanceError? in
      do { _ = try await rest.klines(symbol: "BTCUSDT", interval: .m1, limit: 300); return nil }
      catch let e as BinanceError { return e }
      catch { return nil }
    }
    let inFlight = Task { () -> Ticker? in try? await rest.ticker24h(symbol: "ETHUSDT") }
    await bothOut.wait()                  // 等事件，不等时间
    #expect(upstream.count == 2)

    // 现在才让 418 回来：两笔许可都是在封禁之前拿到的。
    await history.open()
    let banned = try #require(await page.value)
    #expect(banned.isIPBan)
    #expect(banned.isRateLimited)
    #expect((banned.retryAfter ?? 0) > 119)
    #expect(await limiter.banRemainingMs() > 119_000)

    // 在途那一笔照旧收到它的 200——没有人去撤它，也没有把它判成失败。
    await quote.open()
    let late = try #require(await inFlight.value)
    #expect(late.symbol == "ETHUSDT")
    // 而这个晚到的 200 不解封（和 A-T04 同一条判据）。
    #expect(await limiter.banRemainingMs() > 119_000)

    // 新许可：24 份报价 + 两页历史，全部当场拒发，出站次数还是那两笔在途的。
    var refused = 0
    for i in 0..<24 {
      do { _ = try await rest.ticker24h(symbol: "SYM\(i)USDT") }
      catch let e as BinanceError where e.isBlocked { refused += 1 }
      catch { Issue.record("新许可应当被限流器当场挡下，实际抛的是 \(error)") }
    }
    for _ in 0..<2 {
      do { _ = try await rest.klines(symbol: "BTCUSDT", interval: .m1, limit: 1500) }
      catch let e as BinanceError where e.isBlocked { refused += 1 }
      catch { Issue.record("新许可应当被限流器当场挡下，实际抛的是 \(error)") }
    }
    #expect(refused == 26)
    #expect(upstream.count == 2)
    #expect(await pacer.sleepLog().allSatisfy { $0 <= RateLimiter.waitableBanMs })
  }

  // ---------------------------------------------------------------- 封禁到期

  @Test("封禁到点自动放行：同一把限流器上的报价与历史都恢复")
  func banExpiresAndTrafficResumes() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let banned = Counter()
    let server = FakeServer(pacer: pacer) { url in
      // 第一发触发 418，之后一律正常发货。
      if banned.bump() == 1 {
        return json(#"{"code":-1003,"msg":"IP banned"}"#, status: 418, headers: ["Retry-After": "120"])
      }
      guard url.path.contains("ticker") else { return HTTPReply(status: 200, body: Self.empty) }
      let symbol = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "symbol" }?.value ?? "BTCUSDT"
      return json(#"{"symbol":"\#(symbol)","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
    }
    let rest = directREST(server, limiter: limiter, pacer: pacer)
    await #expect(throws: BinanceError.self) {
      _ = try await rest.klines(symbol: "BTCUSDT", interval: .h1, limit: 300)
    }
    #expect(await server.urls().count == 1)

    // 把注进去的钟往前拨过封禁截止时间：没有真实等待，行为和线上一致。
    await pacer.advance(120_001)
    #expect(await limiter.banRemainingMs() == 0)
    for i in 0..<24 { _ = try await rest.ticker24h(symbol: "SYM\(i)USDT") }
    _ = try await rest.klines(symbol: "BTCUSDT", interval: .h1, limit: 1500)
    _ = try await rest.klines(symbol: "BTCUSDT", interval: .h1, limit: 1500)
    #expect(await server.urls().count == 27)
  }

  // ---------------------------------------------------------------- A-T04

  @Test("A-T04 封禁期间晚到的 200 不解封")
  func lateSuccessDoesNotClearTheBan() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    await limiter.penalize(status: 418, retryAfterSeconds: 120)
    // 抢在 418 之前出站、回来得晚的那一笔 200：它只说明「刚才那一笔成了」，
    // 不说明上游解禁了。
    await limiter.succeeded()
    #expect(await limiter.penaltyCount == 0)     // 退避级数确实清了
    #expect(await limiter.banRemainingMs() > 119_000)   // 封禁没有被清
    await #expect(throws: BinanceError.self) { try await limiter.acquire(weight: 1) }
  }

  // ---------------------------------------------------------------- A-T19

  @Test("A-T19 X-MBX-USED-WEIGHT-1M 比本地账高就以上游为准")
  func usedWeightHeaderCorrectsLocalLedger() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, budget: RateLimiter.sharedBinanceBudget, minGapMs: 0)
    let server = FakeServer(pacer: pacer) { _ in
      HTTPReply(status: 200, headers: ["X-MBX-USED-WEIGHT-1M": "1800"], body: Self.empty)
    }
    let rest = BinanceREST(transport: FakeTransport(server), limiter: limiter, pacer: pacer)
    _ = try await rest.klines(symbol: "BTCUSDT", interval: .h1, limit: 300)   // 本地只记 2
    #expect(await limiter.usedWeight() == 1800)

    // 于是本地知道额度快见底了，下一笔大请求会等窗口滚出去，而不是撞 429。
    let t0 = await pacer.nowMs()
    try await limiter.acquire(weight: 400)
    #expect(await pacer.nowMs() - t0 >= 60_000)
  }

  /// A-T19 的另一半：额度是按**出口 IP** 算的，本地的账却是按进程算的。
  /// 两把限流器各记 1200，各自都在 2100 的预算以内，合起来 2400 才越线——
  /// 只有上游回的 `X-MBX-USED-WEIGHT-1M` 能把这件事告诉我们。第二把读到合计 2400
  /// 之后当场停下等窗口滚出去，而不是接着发到撞 429。
  @Test("A-T19 两把限流器各记 1200：靠响应头看见合计 2400，第二把当场停下")
  func usedWeightHeaderReconcilesTwoLimiters() async throws {
    let pacer = StepPacer()
    let budget = RateLimiter.sharedBinanceBudget                    // 2100
    let first = RateLimiter(pacer: pacer, budget: budget, minGapMs: 0)
    let second = RateLimiter(pacer: pacer, budget: budget, minGapMs: 0)
    // 同一台假服务器＝同一个出口 IP：它按两边加起来的量记账。
    let upstreamUsed = Counter()
    let server = FakeServer(pacer: pacer) { _ in
      HTTPReply(status: 200,
                headers: ["X-MBX-USED-WEIGHT-1M": "\(upstreamUsed.bump() * 1200)"],
                body: Self.empty)
    }
    let a = BinanceREST(transport: FakeTransport(server), limiter: first, pacer: pacer)
    let b = BinanceREST(transport: FakeTransport(server), limiter: second, pacer: pacer)

    // 两边各自烧掉 1198 的本地账，谁都没到 2100。
    try await first.acquire(weight: 1198)
    try await second.acquire(weight: 1198)
    #expect(await first.usedWeight() < budget)
    #expect(await second.usedWeight() < budget)

    _ = try await a.klines(symbol: "BTCUSDT", interval: .h1, limit: 300)    // 本地 +2 → 1200
    #expect(await first.usedWeight() == 1200)     // 上游也说 1200，本地账不动
    _ = try await b.klines(symbol: "BTCUSDT", interval: .h1, limit: 300)
    #expect(await second.usedWeight() == 2400)    // 上游说合计 2400：以上游为准

    // 于是第二把知道额度已经越线，下一笔在 `acquire` 里就等窗口滚出去，
    // 不是等撞上 429 才知道。
    let t0 = await pacer.nowMs()
    try await second.acquire(weight: 1)
    #expect(await pacer.nowMs() - t0 >= 60_000)
  }

  @Test("上游报的权重比本地低就不动本地账")
  func usedWeightHeaderNeverLowersTheLedger() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    try await limiter.acquire(weight: 100)
    await limiter.observe(usedWeight: 5)
    #expect(await limiter.usedWeight() == 100)
  }

  // ---------------------------------------------------------------- A.2 端点配额

  @Test("持仓量走 /futures/data 那条 1000 次 / 5 分钟的配额，权重仍然算 1")
  func openInterestHistHasItsOwnQuota() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let rows = #"[{"symbol":"BTCUSDT","sumOpenInterest":"50.0","sumOpenInterestValue":"1","timestamp":1700000000000}]"#
    let server = FakeServer(pacer: pacer) { _ in json(rows) }
    let rest = BinanceREST(transport: FakeTransport(server), limiter: limiter, pacer: pacer)
    _ = try await rest.openInterestHist(symbol: "BTCUSDT", period: "5m", limit: 500)
    #expect(await limiter.usedRequests(.futuresData) == 1)
    #expect(await limiter.usedWeight() == 1)     // 权重照旧算 1，不占 K 线那一档

    // 配额本身：打满 1000 次之后，第 1001 次要等 5 分钟的窗口滚出去。
    for _ in 1..<1000 { try await limiter.acquire(weight: 0, quota: .futuresData) }
    #expect(await limiter.usedRequests(.futuresData) == 1000)
    let t0 = await pacer.nowMs()
    try await limiter.acquire(weight: 0, quota: .futuresData)
    #expect(await pacer.nowMs() - t0 >= 300_000)
    // 分钟权重窗口没有被这 1000 次顶满——它们各算各的。
    #expect(await limiter.usedWeight() <= 1)
  }

  // ---------------------------------------------------------------- A-03 第 4 点

  /// 「点此重试」只清线路冷却。IP 封禁是上游对我们整个出口下的判决，
  /// 用户点一下并不能让它提前结束——封禁期内再点，当场失败，一个包都不出站。
  @Test("A-03④ 清线路冷却不解 IP 封禁：重试当场失败且不出站")
  func routeCooldownResetKeepsTheIPBan() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer(pacer: pacer) { _ in
      json(#"{"code":-1003,"msg":"IP banned until 1700000120000"}"#, status: 418,
           headers: ["Retry-After": "120"])
    }
    let routed = MarketRESTTransport(source: .binance, gateways: ["gw.example.com"],
                                     transport: FakeTransport(server), policy: .direct)
    let rest = BinanceREST(transport: routed, limiter: limiter, pacer: pacer)
    await #expect(throws: BinanceError.self) {
      _ = try await rest.klines(symbol: "BTCUSDT", interval: .m1, limit: 300)
    }
    #expect(await server.urls().count == 1)
    let banned = await limiter.banRemainingMs()
    #expect(banned > 119_000)

    // 用户点「点此重试」：`RoutedMarketFeed.retry()` 走的就是这一句。
    await rest.resetRouteCooldowns()
    #expect(await limiter.banRemainingMs() == banned)   // 封禁一秒都没被清掉

    var thrown: BinanceError?
    do { _ = try await rest.klines(symbol: "BTCUSDT", interval: .m1, limit: 300) }
    catch let e as BinanceError { thrown = e }
    let error = try #require(thrown)
    #expect(error.isBlocked)                            // 「还在封禁里」，不是「行情暂不可用」
    #expect(error.isRateLimited)
    #expect(await server.urls().count == 1)             // 这一笔没有出站
    // 也没人替用户睡到封禁结束。
    #expect(await pacer.sleepLog().allSatisfy { $0 <= RateLimiter.waitableBanMs })
  }
}

/// A-T03 用的假上游：两笔请求先在各自的闸门上挂住，等测试放行才回包。
/// 这样「封禁落下时那两笔已经在途」就是确定的事，不用拿 sleep 去赌。
private final class HeldUpstream: HTTPTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var seen: [URL] = []
  private let history: Gate
  private let quote: Gate
  private let bothOut: Gate

  init(history: Gate, quote: Gate, bothOut: Gate) {
    self.history = history; self.quote = quote; self.bothOut = bothOut
  }

  /// 一共出站了几笔。
  var count: Int { lock.lock(); defer { lock.unlock() }; return seen.count }

  /// 记一笔出站，返回这是第几笔。锁不能在 async 上下文里直接拿，所以单独一个同步方法。
  private func record(_ url: URL) -> Int {
    lock.lock(); defer { lock.unlock() }
    seen.append(url)
    return seen.count
  }

  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    let n = record(url)
    let isQuote = url.path.contains("ticker")
    if n >= 2 { await bothOut.open() }
    // 第三笔起不该存在（限流器该拒发）；万一真出站了就立刻回包，别把用例吊死——
    // 断言看的是 `count`。
    guard n <= 2 else { return json("[]") }
    if isQuote {
      await quote.wait()
      return json(#"{"symbol":"ETHUSDT","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
    }
    await history.wait()
    return json(#"{"code":-1003,"msg":"IP banned"}"#, status: 418, headers: ["Retry-After": "120"])
  }
}
