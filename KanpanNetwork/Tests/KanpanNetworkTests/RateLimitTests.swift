import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
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

  /// 板块页冷启动偶发「20 多秒没有气泡、也没有报错」的那一种：出口 IP 的一分钟账
  /// （`X-MBX-USED-WEIGHT-1M`，同一出口上别的设备也记在里面）已经贴着预算，
  /// 全市场 24h（权重 40）在限流器里排队等窗口滑过去——这段等待原来不受 8 秒超时管。
  @Test("全市场 24h 的超时是总时限：限流器里排队也算")
  func fullMarketTimeoutCoversLimiterQueue() async throws {
    let limiter = RateLimiter(pacer: SystemPacer(), budget: 100, minGapMs: 0)
    await limiter.observe(usedWeight: 90)
    let server = FakeServer { _ in json("[]") }
    let rest = BinanceREST(transport: FakeTransport(server), limiter: limiter, pacer: SystemPacer())
    let began = ContinuousClock.now
    await #expect(throws: URLError.self) { _ = try await rest.tickers24h(timeout: 0.3) }
    #expect(ContinuousClock.now - began < .seconds(3))
    #expect(await server.hits.isEmpty)
  }

  /// 连上了、却迟迟收不完（空闲超时只在「一个字节都不来」时才触发）。
  @Test("全市场 24h 的超时是总时限：迟迟收不完也会到点")
  func fullMarketTimeoutCoversSlowTransfer() async throws {
    struct Stalled: HTTPTransport {
      func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
        try await Task.sleep(for: .seconds(30))
        return json("[]")
      }
    }
    let rest = BinanceREST(transport: Stalled(), limiter: RateLimiter(pacer: SystemPacer(), minGapMs: 0),
                           pacer: SystemPacer())
    let began = ContinuousClock.now
    await #expect(throws: URLError.self) { _ = try await rest.tickers24h(timeout: 0.3) }
    #expect(ContinuousClock.now - began < .seconds(3))
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

  /// 首屏小页被取消时（完整那发先回来了），这一笔不许再出站。`minGapMs == 0` 的
  /// 限流器放行时一次都不睡，所以取消不会在排队那一步被顺手拦下，得在出站前自己看。
  @Test("已取消的请求不出站")
  func cancelledRequestNeverLeaves() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer { _ in json("[]") }
    let rest = BinanceREST(transport: FakeTransport(server), limiter: limiter, pacer: pacer)
    let request = Task { () -> Result<[Bar], Error> in
      withUnsafeCurrentTask { $0?.cancel() }
      do { return .success(try await rest.klines(symbol: "BTCUSDT", interval: .m1, limit: 300)) }
      catch { return .failure(error) }
    }
    guard case .failure(let error) = await request.value else {
      Issue.record("已取消的请求照样拿回了数据"); return
    }
    #expect(error is CancellationError, "\(error)")
    #expect(await server.urls().isEmpty)
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
    // 名义序列（不抖）：文档和日志对的就是这一串。
    #expect(Backoff.sequence(10) == [1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000, 30000, 30000])
    var b = Backoff(jitter: .none)
    #expect(b.peek() == 1000)
    #expect(b.next() == 1000)
    #expect(b.attempt == 1)
    b.reset()
    #expect(b.attempt == 0)
  }

  /// 抖动是为了别让所有客户端在同一毫秒一起回来把刚缓过来的上游再撞一次（A.2）。
  @Test("每一档再抖 ±20%，档位与上限不变")
  func backoffJitter() {
    #expect(Backoff.sequence(4, jitter: .fixed(1)) == [1200, 2400, 4800, 9600])
    #expect(Backoff.sequence(4, jitter: .fixed(-1)) == [800, 1600, 3200, 6400])
    // 上限那一档抖完也不许越过 30 秒。
    #expect(Backoff.sequence(6, jitter: .fixed(1)).last == 30_000)
    // 随机源：每一档都落在名义值的 ±20% 之内，而且不会退化成常数。
    var b = Backoff()
    var seen: Set<Double> = []
    for nominal in [1000.0, 2000, 4000, 8000] {
      let d = b.next()
      #expect(d >= nominal * 0.8 && d <= nominal * 1.2)
      seen.insert(d / nominal)
    }
    #expect(seen.count > 1)
  }
}
