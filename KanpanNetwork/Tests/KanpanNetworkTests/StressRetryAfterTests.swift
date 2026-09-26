import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 压测（2026-09-26）：畸形 / 极端的 `Retry-After`。
//
// 代理、强制门户、配错的网关都可能吐出 `inf`、`1e400`、二十位整数、年份 9999 的 HTTP-date。
// 原来这些值一路原样传到 `Int(x.rounded(.up))`（日志与错误文案）和 `UInt64(ms * 1e6)`
// （`SystemPacer.sleep`），整个 app 当场闪退；有限但巨大的值则把进程共用的限流器封到几十年后。
// 判据：不崩、抛出来的错误秒数有限且不超过 3 天、限流器的封禁剩余有限且不超过 3 天。

@Suite("压测 · 极端 Retry-After")
struct StressRetryAfterTests {

  static let hostile = ["inf", "+inf", "1e400", "1e30", "99999999999999999999", "9.3e18",
                        "Fri, 31 Dec 9999 23:59:59 GMT", "nan", "-5", "0"]
  static let cap = UpstreamError.maxRetryAfterSeconds

  @Test("解析：非有限 / 非正一律当没给，过大封顶 3 天")
  func parseIsFiniteAndCapped() {
    for raw in Self.hostile {
      let v = UpstreamError.retryAfterSeconds(raw)
      if let v { #expect(v.isFinite && v > 0 && v <= Self.cap, "\(raw) → \(v)") }
    }
    #expect(UpstreamError.retryAfterSeconds("120") == 120)
    #expect(UpstreamError.retryAfterSeconds("inf") == nil)
    #expect(UpstreamError.retryAfterSeconds("1e30") == Self.cap)
    // 错误文案对任何秒数都能求值（原来 `Int(inf)` 在这里崩）。
    for s in [Double.infinity, -.infinity, .nan, 1e30, -1e30] {
      _ = String(describing: UpstreamError.blocked(seconds: s))
      _ = String(describing: UpstreamError(status: 429, retryAfter: s))
    }
  }

  @Test("币安直连回 429 + 极端 Retry-After：不崩，封禁有限且 ≤ 3 天，只出站一次")
  func directRouteSurvivesHostileHeaders() async throws {
    for raw in Self.hostile {
      let pacer = StepPacer()
      let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
      let server = FakeServer(pacer: pacer) { _ in
        json(#"{"code":-1003,"msg":"Too many requests"}"#, status: 429, headers: ["Retry-After": raw])
      }
      let routed = MarketRESTTransport(source: .binance, gateways: ["gw.example.com"],
                                       transport: FakeTransport(server), policy: .direct)
      let rest = BinanceREST(transport: routed, limiter: limiter, pacer: pacer)
      var thrown: BinanceError?
      do { _ = try await rest.klines(symbol: "BTCUSDT", interval: .h1, limit: 300) }
      catch let e as BinanceError { thrown = e }
      let error = try #require(thrown, "\(raw)")
      _ = String(describing: error)
      #expect((error.retryAfter ?? 0).isFinite && (error.retryAfter ?? 0) <= Self.cap, "\(raw)")
      let remaining = await limiter.banRemainingMs()
      #expect(remaining.isFinite && remaining <= Self.cap * 1000, "\(raw) → \(remaining)")
      #expect(await pacer.sleepLog().allSatisfy { $0.isFinite && $0 <= RateLimiter.waitableBanMs })
    }
  }

  @Test("网关转述上游限流，头与 body 都是极端值：不崩，冷却与错误秒数有限且 ≤ 3 天")
  func gatewaySurvivesHostileEnvelope() async throws {
    for (header, body) in [("inf", "1e30"), ("1e400", "1e300"), ("Fri, 31 Dec 9999 23:59:59 GMT", "99999999999999999999")] {
      let server = FakeServer { _ in
        json(#"{"error":"upstream_rate_limited","source":"binance","code":418,"retryAfter":\#(body),"upstreamStatus":"418"}"#,
             status: 429, headers: ["Retry-After": header])
      }
      let transport = MarketRESTTransport(source: .binance, gateways: ["one.test"],
                                          transport: FakeTransport(server), policy: .gateway)
      let url = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=300")!
      for _ in 0..<2 {   // 第二笔走「冷却里按原类别重放」那条路，秒数同样要有限
        var thrown: BinanceError?
        do { _ = try await transport.get(url, timeout: 10) } catch let e as BinanceError { thrown = e }
        let error = try #require(thrown)
        _ = String(describing: error)
        #expect(error.reason == .ipBanned)
        #expect((error.retryAfter ?? 0).isFinite && (error.retryAfter ?? 0) <= Self.cap, "\(header)/\(body)")
      }
    }
  }

  @Test("Coinbase 被罚停得比可等上限还久：当场抛 blocked，不静默挂着；inf 也不崩", .timeLimit(.minutes(1)))
  func coinbaseLongBanThrowsInsteadOfHanging() async throws {
    for seconds in [60.0, 1e30] {
      let pacer = StepPacer()
      let limiter = CoinbaseRateLimiter(perSecond: 10, pacer: pacer)
      await limiter.penalize(seconds: seconds)
      var thrown: UpstreamError?
      do { try await limiter.acquire() } catch let e as UpstreamError { thrown = e }
      // 原来这里会一声不吭地睡上 60 秒（1e30 时等于永远）。
      #expect(await pacer.sleepLog().isEmpty, "罚 \(seconds) 秒：挂着睡了")
      let error = try #require(thrown, "罚 \(seconds) 秒却没抛")
      #expect(error.isBlocked && error.isRateLimited)
      #expect((error.retryAfter ?? 0).isFinite && (error.retryAfter ?? 0) <= Self.cap)
    }
    // inf / NaN 等于没给：按 1 秒罚，短到可以原地等掉（原来 inf 会在 `UInt64(inf)` 上崩）。
    for seconds in [Double.infinity, .nan] {
      let pacer = StepPacer()
      let limiter = CoinbaseRateLimiter(perSecond: 10, pacer: pacer)
      await limiter.penalize(seconds: seconds)
      try await limiter.acquire()
      #expect(await pacer.sleepLog() == [1000])
    }
    // 短罚停仍然原地等掉（既有语义）。
    let pacer = StepPacer()
    let limiter = CoinbaseRateLimiter(perSecond: 10, pacer: pacer)
    await limiter.penalize(seconds: 2)
    try await limiter.acquire()
    #expect(await pacer.sleepLog() == [2000])
  }

  @Test("SystemPacer 睡 inf 毫秒不崩，照样认取消")
  func systemPacerInfiniteSleepIsCancellable() async {
    let task = Task { try await SystemPacer().sleep(ms: .infinity) }
    task.cancel()
    let result = await task.result
    if case .success = result { Issue.record("inf 毫秒的睡眠不该正常醒来") }
  }

  @Test("预算被调得比单笔权重还小：空窗口时放行，不永远挂着", .timeLimit(.minutes(1)))
  func budgetBelowWeightDoesNotLivelock() async throws {
    let pacer = ManualPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    await limiter.apply(rules: [BinanceRateLimitRule(rateLimitType: "REQUEST_WEIGHT", interval: "MINUTE",
                                                     intervalNum: 1, limit: 10)])
    let first = Task { try await limiter.acquire(weight: 40) }
    // 原来这里会挂进 60 秒一觉、醒来还是不够、再睡……
    let done = await waitUntil(5) {
      guard await pacer.sleeping == 0 else { return false }
      return await limiter.spentWeightForTests == 40
    }
    #expect(done)
    if !done { first.cancel(); await pacer.drain() }
    _ = try? await first.value
    // 窗口里已有这一笔：下一笔得等它滑出窗口（一分钟），拨过去就放行。
    let second = Task { try await limiter.acquire(weight: 40) }
    #expect(await waitUntil(5) { await pacer.sleeping == 1 })
    await pacer.advance(61_000)
    try await second.value
    await pacer.drain()
  }
}
