import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 第四轮 A-05（客户端那一半）：网关替上游转述的限流，必须原样到达业务层。
///
/// 报文取自 `Backend/kanpan-gateway/README.md`「失败线契约」那张表，逐字照抄——
/// 这一套的意义就是钉住两边对同一个信封的理解一致：
///
/// | 情形 | 状态 | 头 | body |
/// | --- | --- | --- | --- |
/// | 上游限流/封禁 | 429 | `Retry-After: <整数秒>`、`X-Kanpan-Upstream: <source>-limited` | `{"error":"upstream_rate_limited",…}` |
/// | 上游地域拒绝 | 451 | `X-Kanpan-Upstream: <source>-blocked` | `{"error":"upstream_blocked",…}` |
/// | 本机准入满 | 429 | `Retry-After: 2` | `{"error":"busy"}` |
/// | 其他失败 | 503 | `Retry-After: 2` | `{"error":"market unavailable"}` |
@Suite("A-05 网关转述的上游限流")
struct RateLimitGatewaySignalTests {

  private static let klines = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=300")!

  private static func limited(_ seconds: Int, upstreamStatus: String = "429",
                              source: String = "binance") -> HTTPReply {
    json(#"{"error":"upstream_rate_limited","source":"\#(source)","code":429,"retryAfter":\#(seconds),"upstreamStatus":"\#(upstreamStatus)"}"#,
         status: 429,
         headers: ["Retry-After": "\(seconds)", "X-Kanpan-Upstream": "\(source)-limited"])
  }
  private static let blocked = json(#"{"error":"upstream_blocked","source":"binance","code":451}"#,
                                    status: 451, headers: ["X-Kanpan-Upstream": "binance-blocked"])
  private static let busy = json(#"{"error":"busy"}"#, status: 429, headers: ["Retry-After": "2"])
  private static let unavailable = json(#"{"error":"market unavailable"}"#, status: 503,
                                        headers: ["Retry-After": "2"])
  private static let goodBars = #"{"source":"binance","symbol":"BTCUSDT","interval":"1m","bars":[]}"#

  // ---------------------------------------------------------------- A-T06

  @Test("A-T06 网关报上游限流 120 秒：类别是限流，秒数不被 10 秒截断，一轮只出站一次")
  func upstreamRateLimitedKeepsCategoryAndSeconds() async throws {
    let server = FakeServer { _ in Self.limited(120) }
    let transport = MarketRESTTransport(source: .binance, gateways: ["one.test"],
                                        transport: FakeTransport(server), policy: .gateway)
    var thrown: BinanceError?
    do { _ = try await transport.get(Self.klines, timeout: 10) }
    catch let e as BinanceError { thrown = e }
    let error = try #require(thrown, "网关的上游限流必须作为 BinanceError 上来，不能压成「行情暂不可用」")
    #expect(error.status == 429)
    #expect(error.reason == .rateLimited)
    #expect(error.proxied)                      // 被限的是网关的出口，不是这台手机
    #expect((error.retryAfter ?? 0) == 120)     // 不夹 10 秒
    #expect(await server.urls().count == 1)     // 不在同一次调用里叠加重试

    // 冷却期内再来一笔：仍然是「限流」，而且一笔都不出站。
    var again: BinanceError?
    do { _ = try await transport.get(Self.klines, timeout: 10) }
    catch let e as BinanceError { again = e }
    #expect(again?.reason == .rateLimited)
    #expect(again?.proxied == true)
    #expect(await server.urls().count == 1)
  }

  @Test("A-T06 本机限流器不为网关的限流罚停：手机自己的账干净，只有那台网关在歇")
  func proxiedLimitDoesNotBanOurOwnLimiter() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer(pacer: pacer) { _ in Self.limited(120) }
    let transport = MarketRESTTransport(source: .binance, gateways: ["one.test"],
                                        transport: FakeTransport(server), policy: .gateway)
    let rest = BinanceREST(transport: transport, limiter: limiter, pacer: pacer)
    await #expect(throws: BinanceError.self) {
      _ = try await rest.klines(symbol: "BTCUSDT", interval: .m1, limit: 300)
    }
    // 网关转述的限流不该把直连和另一台网关一起按住。
    #expect(await limiter.banRemainingMs() == 0)
    #expect(await limiter.penaltyCount == 0)
    // 也不许在同一次调用里改去撞第二发。
    #expect(await server.urls().count == 1)
  }

  @Test("A-T06 两台网关各歇各的：被限的那台停 120 秒，另一台按自己的短冷却回来")
  func gatewaysCoolDownIndependently() async throws {
    let twoCalls = Counter()
    let server = FakeServer { url in
      if url.host == "one.test" { return Self.limited(120) }
      // 第一发本机 busy（0.2 秒的事），之后正常发货。
      if twoCalls.bump() == 1 {
        return json(#"{"error":"busy"}"#, status: 429, headers: ["Retry-After": "0.2"])
      }
      return json(Self.goodBars)
    }
    let transport = MarketRESTTransport(source: .binance, gateways: ["one.test", "two.test"],
                                        transport: FakeTransport(server), policy: .gateway)
    var first: BinanceError?
    do { _ = try await transport.get(Self.klines, timeout: 10) }
    catch let e as BinanceError { first = e }
    // 两条腿都失败：报上去的是信息量最大的那个（上游限流 120 秒）。
    #expect(first?.reason == .rateLimited)
    #expect((first?.retryAfter ?? 0) == 120)

    try await Task.sleep(nanoseconds: 350_000_000)
    _ = try await transport.get(Self.klines, timeout: 10)
    let hosts = await server.urls().compactMap(\.host)
    // one.test 只被问过第一轮那一次（它还在 120 秒的冷却里），two.test 自己的
    // 短冷却过了就回来了。
    #expect(hosts.filter { $0 == "one.test" }.count == 1)
    #expect(hosts.filter { $0 == "two.test" }.count == 2)
  }

  @Test("A-T06 地域拒绝、本机 busy、普通不可用：三种和限流分得清")
  func categoriesStayDistinct() async throws {
    // 451：地域拒绝。类别是 geoBlocked，不是限流。
    let geoServer = FakeServer { _ in Self.blocked }
    let geo = MarketRESTTransport(source: .binance, gateways: ["one.test"],
                                 transport: FakeTransport(geoServer), policy: .gateway)
    var geoError: BinanceError?
    do { _ = try await geo.get(Self.klines, timeout: 10) }
    catch let e as BinanceError { geoError = e }
    #expect(geoError?.status == 451)
    #expect(geoError?.isGeoBlocked == true)
    #expect(geoError?.isRateLimited == false)
    #expect(geoError?.reason == .geoBlocked)

    // busy / market unavailable：普通不可用，不带上游语义，也不算限流。
    for reply in [Self.busy, Self.unavailable] {
      let server = FakeServer { _ in reply }
      let plain = MarketRESTTransport(source: .binance, gateways: ["one.test"],
                                      transport: FakeTransport(server), policy: .gateway)
      do {
        _ = try await plain.get(Self.klines, timeout: 10)
        Issue.record("本机 busy / 不可用也该失败")
      } catch let e as BinanceError {
        Issue.record("本机 busy / 不可用不该被当成上游信号：\(e)")
      } catch {
        // FeedError.badResponse("行情暂不可用，请重试")——原样保留既有行为。
      }
    }
  }

  @Test("A-T06 upstreamStatus 是 418 时算 IP 级封禁，业务层立刻收手")
  func upstreamStatus418IsAnIPBan() async throws {
    let server = FakeServer { _ in Self.limited(300, upstreamStatus: "418") }
    let transport = MarketRESTTransport(source: .binance, gateways: ["one.test"],
                                        transport: FakeTransport(server), policy: .gateway)
    var thrown: BinanceError?
    do { _ = try await transport.get(Self.klines, timeout: 10) }
    catch let e as BinanceError { thrown = e }
    let error = try #require(thrown)
    #expect(error.status == 418)
    #expect(error.isIPBan)
    #expect(error.stopsRetrying)                // 业务层据此结束本轮
    #expect((error.retryAfter ?? 0) == 300)
  }

  @Test("upstream_rate_limited 的冷却取头与 body 的较大者，且不封顶")
  func cooldownTakesTheLongerOfHeaderAndBody() {
    let reply = json(#"{"error":"upstream_rate_limited","source":"okx","code":429,"retryAfter":120,"upstreamStatus":"429"}"#,
                     status: 429, headers: ["Retry-After": "30"])
    let hint = MarketRESTTransport.gatewayFailure(reply, url: Self.klines)
    #expect(hint.cooldown == 120)
    #expect(hint.error?.reason == .rateLimited)
    // 本机 busy 仍然走老路：短冷却，不带上游语义。
    let plain = MarketRESTTransport.gatewayFailure(Self.busy, url: Self.klines)
    #expect(plain.cooldown == 2)
    #expect(plain.error == nil)
    // 上游没给秒数：429 按 10 秒、418 按 120 秒起步。
    let noSeconds = json(#"{"error":"upstream_rate_limited","source":"okx","code":429,"upstreamStatus":"429"}"#, status: 429)
    #expect(MarketRESTTransport.gatewayFailure(noSeconds, url: Self.klines).cooldown == RateLimiter.rateLimitFloorSeconds)
    let banned = json(#"{"error":"upstream_rate_limited","source":"okx","code":418,"upstreamStatus":"418"}"#, status: 429)
    #expect(MarketRESTTransport.gatewayFailure(banned, url: Self.klines).cooldown == RateLimiter.ipBanFloorSeconds)
  }

  // ---------------------------------------------------------------- 冷却的边界

  private static let oiHist = URL(string: "https://fapi.binance.com/futures/data/openInterestHist?symbol=BTCUSDT&period=5m&limit=500")!

  /// 网关在上游限流的冷却里，**不代表**一条网关根本不代理的路线也被限流了。
  ///
  /// `/futures/data/openInterestHist` 就是这种：网关没有这条代理，它的失败原因是
  /// 「这条线路没有路」，和出口被按住是两件事。混成一件事的话，业务层会把一笔
  /// 本来没有网关路线的 OI 请求当成「整个出口被限流」，于是连直连那条路也不敢走了。
  @Test("网关在上游限流冷却里：没有网关路线的 openInterestHist 不被误报成限流，直连照常")
  func openInterestHistIsNotMislabeledWhileGatewaysAreLimited() async throws {
    let server = FakeServer { url in
      url.path.contains("openInterestHist") ? json("[]") : Self.limited(120)
    }
    let gateway = MarketRESTTransport(source: .binance, gateways: ["one.test"],
                                      transport: FakeTransport(server), policy: .gateway)
    // 先让那台网关进上游限流的冷却。
    await #expect(throws: BinanceError.self) { _ = try await gateway.get(Self.klines, timeout: 10) }
    // 同一时刻的 OI：抛的必须是「没有网关路线」那种普通失败，不是 429/限流。
    do {
      _ = try await gateway.get(Self.oiHist, timeout: 10)
      Issue.record("网关档下 OI 没有代理路线，这一笔本来就该失败")
    } catch let e as BinanceError {
      Issue.record("OI 没有网关路线 ≠ 出口被限流，不许报成 \(e)")
    } catch {
      // FeedError.badResponse("行情暂不可用，请重试")
    }
    // 网关那条路本身仍然照实说「还在限流」。
    var again: BinanceError?
    do { _ = try await gateway.get(Self.klines, timeout: 10) }
    catch let e as BinanceError { again = e }
    #expect(again?.reason == .rateLimited)

    // 直连这一档压根不看网关的账本：同一笔 OI 正常出站。
    let direct = MarketRESTTransport(source: .binance, gateways: ["one.test"],
                                     transport: FakeTransport(server), policy: .direct)
    let reply = try await direct.get(Self.oiHist, timeout: 10)
    #expect(reply.status == 200)
    #expect(await server.urls().contains { $0.path.contains("openInterestHist") })
  }

  /// 冷却期内重放出去的错误要保留**原来的类别**：418 是 IP 级封禁，不是超频。
  @Test("418 造成的网关冷却：冷却期内重放仍是 IP 级封禁，带上游状态码")
  func bannedGatewayReplaysTheBanNotAPlainRateLimit() async throws {
    let server = FakeServer { _ in Self.limited(300, upstreamStatus: "418") }
    let transport = MarketRESTTransport(source: .binance, gateways: ["one.test"],
                                       transport: FakeTransport(server), policy: .gateway)
    await #expect(throws: BinanceError.self) { _ = try await transport.get(Self.klines, timeout: 10) }
    #expect(await server.urls().count == 1)
    var replayed: BinanceError?
    do { _ = try await transport.get(Self.klines, timeout: 10) }
    catch let e as BinanceError { replayed = e }
    let error = try #require(replayed)
    #expect(error.status == 418)
    #expect(error.reason == .ipBanned)
    #expect(error.isIPBan)
    #expect(error.proxied)
    #expect(error.stopsRetrying)
    #expect(error.msg?.contains("418") == true)     // 上游那个状态码没丢
    #expect((error.retryAfter ?? 0) > 0)
    #expect(await server.urls().count == 1)         // 冷却期内一笔都不出站
  }

  /// 403 也是 IP 级封禁：币安对被封的出口回的就是这个，不是「忙一下」。
  @Test("upstreamStatus 403 按 IP 级封禁算，起步 2 分钟")
  func upstreamStatus403IsAnIPBan() {
    let reply = json(#"{"error":"upstream_rate_limited","source":"binance","code":403,"upstreamStatus":"403"}"#,
                     status: 429, headers: ["X-Kanpan-Upstream": "binance-limited"])
    let hint = MarketRESTTransport.gatewayFailure(reply, url: Self.klines)
    #expect(hint.cooldown == RateLimiter.ipBanFloorSeconds)
    #expect(hint.error?.reason == .ipBanned)
    #expect(hint.upstreamStatus == 403)
  }

  /// 451 的冷却不能走 `gatewayCooldown` 那条 10 秒的夹子：地域拒绝 10 秒后还是同一堵墙。
  @Test("upstream_blocked 的冷却是 60 秒起，不被 10 秒夹住")
  func geoBlockedCooldownIsSixtySeconds() {
    let hint = MarketRESTTransport.gatewayFailure(Self.blocked, url: Self.klines)
    #expect(hint.cooldown == 60)
    #expect(hint.error?.reason == .geoBlocked)
    #expect(hint.upstreamStatus == nil)             // 地域拒绝不进「限流」那本账
    #expect(hint.error?.stopsRetrying == true)      // 比限流更没救，业务层立刻收手
    // 上游自己说了多久就听它的（头与 body 取较大者），照样不夹。
    let said = json(#"{"error":"upstream_blocked","source":"binance","code":451,"retryAfter":600}"#,
                    status: 451, headers: ["Retry-After": "120"])
    #expect(MarketRESTTransport.gatewayFailure(said, url: Self.klines).cooldown == 600)
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

  @Test("A-04 网关档的全市场报价走 /market/v1/tickers，信封同单品种")
  func allMarketTickerGoesThroughTheGateway() async throws {
    let rows = #"[{"symbol":"BTCUSDT","lastPrice":"100","priceChangePercent":"1","highPrice":"101","lowPrice":"99","quoteVolume":"1","closeTime":3000}]"#
    let server = FakeServer { url in
      guard url.path == "/market/v1/tickers" else { return json("{}", status: 404) }
      return json(#"{"source":"binance","symbol":"","ticker":\#(rows)}"#)
    }
    let transport = MarketRESTTransport(source: .binance, gateways: ["one.test"],
                                        transport: FakeTransport(server), policy: .gateway)
    let rest = BinanceREST(transport: transport, limiter: RateLimiter(minGapMs: 0))
    let tickers = try await rest.tickers24h()
    #expect(tickers.count == 1)
    #expect(tickers.first?.symbol == "BTCUSDT")
    let asked = try #require(await server.urls().first)
    #expect(asked.path == "/market/v1/tickers")
    #expect(asked.query?.contains("source=binance") == true)
    #expect(asked.query?.contains("symbol") != true)     // 多给一个参数网关就回 400
  }

  // ---------------------------------------------------------------- A-03 第 4 点

  /// 「点此重试」清的是**线路冷却**：那台网关的歇工是本机记的账，用户显式点一下
  /// 允许放它出去试一次（而 IP 封禁那一档在 `RateLimitBanTests` 里验，点了也不解）。
  @Test("清线路冷却之后，显式重试允许再拨一次那台网关")
  func resetRouteCooldownsReleasesTheGatewayLimit() async throws {
    let hits = Counter()
    let server = FakeServer { _ in
      hits.bump() == 1 ? Self.limited(120) : json(Self.goodBars)
    }
    let transport = MarketRESTTransport(source: .binance, gateways: ["one.test"],
                                       transport: FakeTransport(server), policy: .gateway)
    await #expect(throws: BinanceError.self) { _ = try await transport.get(Self.klines, timeout: 10) }
    #expect(await server.urls().count == 1)
    // 冷却期内的自动重试：不出站。
    await #expect(throws: BinanceError.self) { _ = try await transport.get(Self.klines, timeout: 10) }
    #expect(await server.urls().count == 1)
    // 用户点了「点此重试」。
    await transport.resetRouteCooldowns()
    _ = try await transport.get(Self.klines, timeout: 10)
    #expect(await server.urls().count == 2)
  }
}
