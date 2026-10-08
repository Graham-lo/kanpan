import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 网关档的限流信号（2026-10-08 起网关档是 kanpan-api 的原样透传 `/v1/market/raw/*?source=binance`）。
///
/// 透传把币安的状态码、正文与 `Retry-After` 原样带回来；kanpan-api 自己排不上队时回
/// `429 {"error":"upstream_rate_limited"}` + `Retry-After`。两种都交给 `BinanceREST`：429 按 `Retry-After`
/// 罚网关档那把限流器（`RateLimiter.sharedGateway`，和直连那把分开），418 是封禁、当场收手。
/// 原来那套「网关信封 → 按主机冷却 → 冷却期内按原类别重放」随替身一起删了。
@Suite("网关档透传的限流信号")
struct RateLimitGatewaySignalTests {

  private static let klines = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=300")!

  private func gatewayREST(_ server: FakeServer, limiter: RateLimiter, pacer: Pacer,
                           gateways: [String] = ["one.test"]) -> BinanceREST {
    let transport = MarketRESTTransport(gateways: gateways, transport: FakeTransport(server), policy: .gateway)
    return BinanceREST(transport: transport, limiter: limiter, pacer: pacer)
  }

  @Test("透传回 429 + Retry-After:120：网关档那把限流器记满 120 秒，这一轮只出站一次，类别是限流")
  func passthrough429PenalizesTheGatewayLimiter() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer(pacer: pacer) { _ in
      json(#"{"code":-1003,"msg":"Too many requests"}"#, status: 429, headers: ["Retry-After": "120"])
    }
    let rest = gatewayREST(server, limiter: limiter, pacer: pacer)
    var thrown: BinanceError?
    do { _ = try await rest.klines(symbol: "BTCUSDT", interval: .m1, limit: 300) }
    catch let e as BinanceError { thrown = e }
    let error = try #require(thrown)
    #expect(error.isRateLimited)
    #expect((error.retryAfter ?? 0) > 119)
    let remaining = await limiter.banRemainingMs()
    #expect(remaining > 119_000 && remaining <= 120_000)
    // 429 不换主机（4xx 是这一笔的答案），第二圈开头的 `acquire` 当场拒发。
    #expect(await server.urls().count == 1)
    #expect(await pacer.sleepLog().allSatisfy { $0 <= RateLimiter.waitableBanMs })
  }

  @Test("kanpan-api 自己排不上队（429 upstream_rate_limited + Retry-After:2）：短罚停原地等掉，再发一次就成")
  func serverQueueFullIsAShortWait() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let calls = Counter()
    let server = FakeServer(pacer: pacer) { _ in
      calls.bump() == 1
        ? json(#"{"error":"upstream_rate_limited"}"#, status: 429, headers: ["Retry-After": "2"])
        : json("[]")
    }
    let rest = gatewayREST(server, limiter: limiter, pacer: pacer)
    let bars = try await rest.klines(symbol: "BTCUSDT", interval: .m1, limit: 300)
    #expect(bars.isEmpty)
    #expect(await server.urls().count == 2)
    #expect(await pacer.sleepLog().contains { $0 >= 2000 })
  }

  @Test("透传回 418：IP 级封禁，业务层立刻收手，不叠加重试")
  func passthrough418IsAnIPBan() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer(pacer: pacer) { _ in
      json(#"{"code":-1003,"msg":"IP banned"}"#, status: 418, headers: ["Retry-After": "300"])
    }
    let rest = gatewayREST(server, limiter: limiter, pacer: pacer)
    var thrown: BinanceError?
    do { _ = try await rest.klines(symbol: "BTCUSDT", interval: .m1, limit: 300) }
    catch let e as BinanceError { thrown = e }
    let error = try #require(thrown)
    #expect(error.isIPBan)
    #expect(error.stopsRetrying)
    #expect(await server.urls().count == 1)
    #expect(await limiter.banRemainingMs() > 299_000)
  }

  @Test("主网关 5xx 换备用，429 不换：备用那台回的限流照样进限流器")
  func fiveHundredMovesOnButRateLimitDoesNot() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer(pacer: pacer) { url in
      url.host == "one.test"
        ? json(#"{"error":"upstream_unavailable"}"#, status: 502)
        : json(#"{"code":-1003,"msg":"Too many requests"}"#, status: 429, headers: ["Retry-After": "120"])
    }
    let rest = gatewayREST(server, limiter: limiter, pacer: pacer, gateways: ["one.test", "two.test"])
    await #expect(throws: BinanceError.self) { _ = try await rest.klines(symbol: "BTCUSDT", interval: .m1, limit: 300) }
    #expect(await server.urls().compactMap(\.host) == ["one.test", "two.test"])
    #expect(await limiter.banRemainingMs() > 119_000)
  }

  // ---------------------------------------------------------------- A.2 运行时限额

  @Test("A.2 exchangeInfo 里的 rateLimits 能改写本机的分钟权重预算")
  func runtimeRateLimitsAdjustTheBudget() async throws {
    let body = Data(#"{"timezone":"UTC","serverTime":1,"rateLimits":[{"rateLimitType":"REQUEST_WEIGHT","interval":"MINUTE","intervalNum":1,"limit":1200},{"rateLimitType":"ORDERS","interval":"SECOND","intervalNum":10,"limit":300}],"symbols":[]}"#.utf8)
    let rules = BinanceREST.parseRateLimits(body)
    #expect(rules.count == 2)
    #expect(rules.first?.isRequestWeightPerMinute == true)

    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, budget: RateLimiter.sharedBinanceBudget, minGapMs: 0)
    await limiter.apply(rules: rules)
    // 1200 的 87.5% ＝ 1050：这一笔刚好放行，下一笔就要等窗口滚出去。
    try await limiter.acquire(weight: 1050)
    let t0 = await pacer.nowMs()
    try await limiter.acquire(weight: 1)
    #expect(await pacer.nowMs() - t0 >= 60_000)
  }

  // ---------------------------------------------------------------- A-04 全市场 ticker

  @Test("A-04 网关档的全市场报价走透传的 ticker/24hr（不带 symbol），载荷就是币安那份数组")
  func allMarketTickerGoesThroughTheGateway() async throws {
    let rows = #"[{"symbol":"BTCUSDT","lastPrice":"100","priceChangePercent":"1","highPrice":"101","lowPrice":"99","quoteVolume":"1","closeTime":3000}]"#
    let server = FakeServer { url in
      guard url.path == "/v1/market/raw/fapi/v1/ticker/24hr" else { return json("{}", status: 404) }
      return json(rows)
    }
    let transport = MarketRESTTransport(gateways: ["one.test"], transport: FakeTransport(server), policy: .gateway)
    let rest = BinanceREST(transport: transport, limiter: RateLimiter(minGapMs: 0))
    let tickers = try await rest.tickers24h()
    #expect(tickers.count == 1)
    #expect(tickers.first?.symbol == "binance/usd_m/BTCUSDT")
    let asked = try #require(await server.urls().first)
    #expect(asked.query == "source=binance")     // 多给一个查询键服务端就回 400
  }
}
