import Foundation
import Testing
@testable import KanpanData
import KanpanCore

@Suite("限流与退避")
struct RateLimitTests {

  @Test("K 线权重按 limit 分档")
  func klineWeights() {
    #expect(RateLimiter.klinesWeight(for: 1) == 1)
    #expect(RateLimiter.klinesWeight(for: 99) == 1)
    #expect(RateLimiter.klinesWeight(for: 100) == 2)
    #expect(RateLimiter.klinesWeight(for: 499) == 2)
    #expect(RateLimiter.klinesWeight(for: 500) == 5)
    #expect(RateLimiter.klinesWeight(for: 1000) == 5)
    #expect(RateLimiter.klinesWeight(for: 1001) == 10)
    #expect(RateLimiter.klinesWeight(for: 1500) == 10)
    #expect(RateLimiter.klinesWeight(for: 5000) == 10)
  }

  @Test("K 线请求按实际 limit 消耗权重")
  func klineRequestUsesActualWeight() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer { _ in json("[]") }
    let rest = BinanceREST(transport: FakeTransport(server), limiter: limiter, pacer: pacer)
    _ = try await rest.klines(symbol: "BTCUSDT", interval: .h1, limit: 300)
    #expect(await limiter.usedWeight() == 2)
  }

  // ---------------------------------------------------------------- A2.10

  @Test("连发要隔 120ms")
  func minGap() async throws {
    let pacer = StepPacer()
    let lim = RateLimiter(pacer: pacer, minGapMs: 120)
    let t0 = await pacer.nowMs()
    for _ in 0..<5 { try await lim.acquire(weight: 10) }
    #expect(await pacer.nowMs() - t0 >= 480)     // 5 次至少 4 个间隔
    #expect(await lim.usedWeight() == 50)
  }

  @Test("撞到分钟权重上限就等到窗口滚出去")
  func budget() async throws {
    let pacer = StepPacer()
    // 预算 30，一次 10：第 4 次必须等满一分钟。
    let lim = RateLimiter(pacer: pacer, budget: 30, minGapMs: 0)
    let t0 = await pacer.nowMs()
    for _ in 0..<3 { try await lim.acquire(weight: 10) }
    #expect(await pacer.nowMs() - t0 < 60_000)
    try await lim.acquire(weight: 10)
    #expect(await pacer.nowMs() - t0 >= 60_000)
  }

  @Test("429 带 Retry-After：停够秒数再发，然后成功")
  func retryAfter() async throws {
    let pacer = StepPacer()
    let hits = Counter()
    let body = Data("[]".utf8)
    let server = FakeServer(pacer: pacer) { _ in
      // 头两次 429，第三次放行。
      if hits.bump() <= 2 {
        return json(#"{"code":-1003,"msg":"Too many requests"}"#, status: 429,
                    headers: ["Retry-After": "7"])
      }
      return HTTPReply(status: 200, body: body)
    }
    let rest = BinanceREST(transport: FakeTransport(server), pacer: pacer)
    let bars = try await rest.klines(symbol: "BTCUSDT", interval: .h1, limit: 10)
    #expect(bars.isEmpty)
    #expect(await server.urls().count == 3)
    // 两次罚停各 7 秒，必须真的出现在 sleep 日志里。
    let slept = await pacer.sleepLog()
    #expect(slept.filter { $0 >= 6_900 && $0 <= 7_100 }.count == 2)
  }

  @Test("429 不带 Retry-After：退避 1s、2s")
  func penaltyBackoff() async throws {
    let pacer = StepPacer()
    let lim = RateLimiter(pacer: pacer, minGapMs: 0)
    await lim.penalize(retryAfterSeconds: nil)
    try await lim.acquire(weight: 1)
    await lim.penalize(retryAfterSeconds: nil)
    try await lim.acquire(weight: 1)
    let slept = await pacer.sleepLog()
    #expect(slept == [1000, 2000])
    #expect(await lim.penaltyCount == 2)
  }

  @Test("罚停后成功一次，计数清零")
  func penaltyReset() async throws {
    let pacer = StepPacer()
    let lim = RateLimiter(pacer: pacer, minGapMs: 0)
    await lim.penalize(retryAfterSeconds: nil)
    await lim.succeeded()
    #expect(await lim.penaltyCount == 0)
  }

  @Test("重试到上限还是 429 就把错误抛出来")
  func giveUp() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer(pacer: pacer) { _ in
      json(#"{"code":-1003,"msg":"Way too many requests"}"#, status: 429, headers: ["Retry-After": "1"])
    }
    let rest = BinanceREST(transport: FakeTransport(server), limiter: limiter, pacer: pacer)
    await #expect(throws: BinanceError.self) {
      _ = try await rest.klines(symbol: "BTCUSDT", interval: .h1, limit: 10)
    }
    #expect(await server.urls().count == 4)     // attempts 默认 4
    #expect(await limiter.penaltyCount == 4)    // 最后一发也要留下冷却状态
  }

  // ---------------------------------------------------------------- A2.7 退避

  @Test("重连退避 1/2/4/…≤30s")
  func backoffSequence() {
    var b = Backoff()
    #expect(Backoff.sequence(10) == [1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000, 30000, 30000])
    b.reset()
    #expect(b.peek() == 1000)
    #expect(b.next() == 1000)
    #expect(b.attempt == 1)
    b.reset()
    #expect(b.attempt == 0)
  }

  @Test("60 秒没帧就算断了")
  func silenceWatch() {
    var w = SilenceWatch()
    w.sawFrame(at: 1_000_000)
    #expect(!w.isSilent(at: 1_059_000))
    #expect(w.remainingMs(at: 1_059_000) == 1000)
    #expect(w.isSilent(at: 1_060_001))
  }
}
