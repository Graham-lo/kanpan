import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 压测（2026-09-26）：WS 重连风暴。
//
// 服务器几百次地「连上 → 推一两帧 → 掐掉」，看三件事：
// 1. 退避收不收敛——不能因为每条连接都「收到过帧」就永远按 1 秒一次地重连；
// 2. 连接数收敛到 1——任何时刻最多一条没人要关的连接，旧 socket 都被 cancel；
// 3. 不泄漏——被换下来的 socket 在风暴结束后都被释放（弱引用探针），出口流的事件数与连接数成正比。
// 判据全是计数与最终状态，不看墙钟。

// ---------------------------------------------------------------- 假件

/// 风暴用的 socket：`receive()` 挂着、不理会任务取消，只有 `push` 或 `cancel()` 叫得醒。
actor StormSocket: WSSocket {
  nonisolated let id: Int
  private var frames: [WSFrame] = []
  private var waiters: [CheckedContinuation<WSFrame, Error>] = []
  private(set) var cancelCalls = 0
  private(set) var closed = false
  private(set) var sent: [String] = []
  init(id: Int) { self.id = id }

  func receive() async throws -> WSFrame {
    if closed { throw FeedError.badResponse("#\(id) 已关闭") }
    if !frames.isEmpty { return frames.removeFirst() }
    return try await withCheckedThrowingContinuation { waiters.append($0) }
  }
  func push(_ f: WSFrame) {
    guard !closed else { return }
    if !waiters.isEmpty { waiters.removeFirst().resume(returning: f) } else { frames.append(f) }
  }
  var receiving: Int { waiters.count }
  func send(_ text: String) async throws {
    if closed { throw FeedError.badResponse("#\(id) 已关闭") }
    sent.append(text)
  }
  func pong() async throws {}
  func cancel() async {
    cancelCalls += 1
    guard !closed else { return }
    closed = true
    let w = waiters; waiters = []
    for c in w { c.resume(throwing: FeedError.badResponse("#\(id) 被掐断")) }
  }
}

/// 只弱持有造出来的 socket：风暴过后还活着几条，就是有谁还攥着它们。
actor StormBench: WSSocketFactory {
  private final class WeakBox: @unchecked Sendable { weak var socket: StormSocket?; init(_ s: StormSocket) { socket = s } }
  private var made: [WeakBox] = []
  private var latestStrong: StormSocket?
  private(set) var urls: [URL] = []

  func connect(to url: URL) async throws -> any WSSocket {
    let s = StormSocket(id: made.count + 1)
    made.append(WeakBox(s))
    urls.append(url)
    latestStrong = s
    return s
  }
  var connects: Int { made.count }
  /// 最新那条（测试要往它身上推帧）。
  func latest() -> StormSocket? { latestStrong }
  /// 放掉工厂自己对最新那条的强引用，只剩被测对象的。
  func releaseLatest() { latestStrong = nil }
  /// 还活着（没被释放）的 socket 编号。
  func alive() -> [Int] { made.compactMap { $0.socket?.id } }
  /// 活着且从没被 cancel 过的：没有人打算关它、会一直占一条服务器连接的。
  func liveUncancelled() async -> Int {
    var n = 0
    for box in made { if let s = box.socket, await s.cancelCalls == 0 { n += 1 } }
    return n
  }
}

enum StormFrames {
  static func binanceKline(_ symbol: String, interval: String = "1m", openTime: Int64 = 1_700_000_040_000,
                           close: String = "90200") -> String {
    let s = symbol.lowercased()
    return #"{"stream":"\#(s)@kline_\#(interval)","data":{"e":"kline","E":1700000123456,"s":"\#(symbol.uppercased())","k":{"t":\#(openTime),"T":\#(openTime + 59_999),"s":"\#(symbol.uppercased())","i":"\#(interval)","o":"90000","c":"\#(close)","h":"90500","l":"89500","v":"1","q":"100000","x":false}}}"#
  }
}

/// 一边读出口流一边计数（读者不读的话 `.unbounded` 的出口会一直攒着）。
final class EventTally: @unchecked Sendable {
  private let lock = NSLock()
  private var counts: [String: Int] = [:]
  private var lastStatus: FeedStatus?
  private var klineCloses: [String] = []
  func note(_ e: WSEvent) {
    lock.withLock {
      switch e {
      case .connected: counts["connected", default: 0] += 1
      case .status(let s): counts["status", default: 0] += 1; lastStatus = s
      case .payload(let p):
        counts["payload", default: 0] += 1
        if case .kline(let k) = p { klineCloses.append(k.symbol) }
      }
    }
  }
  func count(_ k: String) -> Int { lock.withLock { counts[k, default: 0] } }
  var status: FeedStatus? { lock.withLock { lastStatus } }
  var klineSymbols: [String] { lock.withLock { klineCloses } }
}

@Suite("压测 · WS 重连风暴")
struct StressWSStormTests {

  /// 服务器每条连接只推一帧就掐：几百轮之后退避必须已经涨上去，而不是每次都从 1 秒起跳。
  /// 用手拨的钟：连接从连上到被掐没走过一毫秒，退避睡多久就拨多久，于是「虚拟的前 5 分钟里连了几次」是确定的数。
  @Test("币安：每条连接推一帧就被掐 × 300 → 退避收敛到上限、5 分钟内的连接数有界、只剩一条活连接、旧 socket 全部释放",
        .timeLimit(.minutes(2)))
  func binanceOneFrameThenDropStorm() async throws {
    let bench = StormBench()
    let pacer = ManualPacer()
    let ws = BinanceWS(factory: bench, pacer: pacer,
                       silenceMs: 1e12, transportSilenceMs: 1e12, baseBackoffMs: 1000, capBackoffMs: 30_000)
    let tally = EventTally()
    let events = await ws.start(streams: ["btcusdt@kline_1m"])
    let reader = Task { for await e in events { tally.note(e) } }
    let t0 = await pacer.nowMs()

    let rounds = 300
    var attempts: [Int] = []
    var connectTimes: [Double] = [t0]
    for n in 1...rounds {
      #expect(await waitUntil(10) { await bench.connects >= n })
      let s = try #require(await bench.latest())
      #expect(await waitUntil(10) { await s.receiving > 0 })
      await s.push(.text(StormFrames.binanceKline("BTCUSDT")))
      await s.push(.closed("服务器踢线 #\(n)"))
      // 等退避那一觉排上（看门狗睡的是 1e12，醒点在一分钟以内的只可能是退避），正好拨到它醒。
      #expect(await waitUntil(10) { (await pacer.nextWakeIn ?? .infinity) < 60_000 })
      var spins = 0
      while await bench.connects < n + 1, spins < 50 {
        await pacer.advance(max(1, await pacer.nextWakeIn ?? 1))
        spins += 1
      }
      attempts.append(await ws.backoffAttempt)
      connectTimes.append(await pacer.nowMs())
    }
    let firstFiveMinutes = connectTimes.filter { $0 - t0 <= 300_000 }.count
    let spanMinutes = (connectTimes.last! - t0) / 60_000
    print("压测数据 WS风暴 rounds=\(rounds) 前5分钟连接=\(firstFiveMinutes) 总虚拟时长=\(Int(spanMinutes))分钟 尾段档位=\(Array(attempts.suffix(5)))")
    // 一连三百条连接都活不过一秒：退避不许一直停在第 1 档（1 秒一次地重连，5 分钟正好 300 条，
    // 顶满币安单 IP 的连接额度）。档位要涨到上限那一档，前 5 分钟只该有十来条。
    let tailAttempts = attempts.suffix(20)
    #expect(tailAttempts.allSatisfy { $0 >= 5 }, "尾段退避档位：\(Array(tailAttempts))")
    #expect(firstFiveMinutes <= 20, "虚拟前 5 分钟的连接数：\(firstFiveMinutes)")

    await bench.releaseLatest()
    #expect(await bench.liveUncancelled() <= 1)
    await ws.stop()
    reader.cancel()
    await pacer.drain()
    let released = await waitUntil(5) { await bench.alive().isEmpty }
    let held = await bench.alive()
    #expect(released, "还攥着的 socket：\(held)")
    #expect(tally.count("connected") >= rounds && tally.count("connected") <= rounds + 1)
    #expect(tally.count("payload") == rounds)
  }

  /// 同一场风暴放到 Coinbase：原来也是「第一帧行情就把退避清零」，一样会 1 秒一次地重连。
  @Test("Coinbase：每条连接推一帧 ticker 就被掐 × 120 → 退避收敛、5 分钟内的连接数有界、旧 socket 全部释放",
        .timeLimit(.minutes(2)))
  func coinbaseOneFrameThenDropStorm() async throws {
    let bench = StormBench()
    let pacer = ManualPacer()
    let ws = CoinbaseWS(urls: [URL(string: "wss://advanced-trade-ws.coinbase.com")!], factory: bench, pacer: pacer,
                        silenceMs: 1e12, transportSilenceMs: 1e12)
    let tally = EventTally()
    let events = await ws.start(topics: [.ticker(symbol: "coinbase/spot/BTC-USD")])
    let reader = Task { for await e in events { tally.note(e) } }
    let t0 = await pacer.nowMs()
    let ticker = #"{"channel":"ticker","timestamp":"2026-09-22T23:19:47Z","events":[{"type":"snapshot","tickers":[{"product_id":"BTC-USD","price":"63000","volume_24_h":"1","low_24_h":"1","high_24_h":"2","price_percent_chg_24_h":"0"}]}]}"#

    let rounds = 120
    var attempts: [Int] = []
    var connectTimes: [Double] = [t0]
    for n in 1...rounds {
      #expect(await waitUntil(10) { await bench.connects >= n })
      let s = try #require(await bench.latest())
      #expect(await waitUntil(10) { await s.receiving > 0 })
      await s.push(.text(ticker))
      #expect(await waitUntil(10) { tally.count("payload") >= n })
      await s.push(.closed("服务器踢线 #\(n)"))
      var spins = 0
      while await bench.connects < n + 1, spins < 200 {
        if let wake = await pacer.nextWakeIn, wake < 60_000 { await pacer.advance(max(1, wake)) }
        else { await Task.yield() }
        spins += 1
      }
      attempts.append(await ws.backoffAttempt)
      connectTimes.append(await pacer.nowMs())
    }
    let firstFiveMinutes = connectTimes.filter { $0 - t0 <= 300_000 }.count
    print("压测数据 Coinbase风暴 rounds=\(rounds) 前5分钟连接=\(firstFiveMinutes) 尾段档位=\(Array(attempts.suffix(5)))")
    let tailAttempts = attempts.suffix(20)
    #expect(tailAttempts.allSatisfy { $0 >= 5 }, "尾段退避档位：\(Array(tailAttempts))")
    #expect(firstFiveMinutes <= 20, "虚拟前 5 分钟的连接数：\(firstFiveMinutes)")

    await bench.releaseLatest()
    #expect(await bench.liveUncancelled() <= 1)
    await ws.stop()
    reader.cancel()
    await pacer.drain()
    let released = await waitUntil(5) { await bench.alive().isEmpty }
    let held = await bench.alive()
    #expect(released, "还攥着的 socket：\(held)")
    #expect(tally.count("payload") == rounds)
  }

  /// 长命的连接断掉，下一次仍然从第 1 档（1 秒）起跳：收敛不能以「好连接断了也要等 30 秒」为代价。
  @Test("币安：稳定跑过一段的连接断了 → 退避归零", .timeLimit(.minutes(1)))
  func binanceStableConnectionResetsBackoff() async throws {
    let bench = StormBench()
    let pacer = ManualPacer()
    let ws = BinanceWS(factory: bench, pacer: pacer, silenceMs: 1e12, transportSilenceMs: 1e12,
                       baseBackoffMs: 1000, capBackoffMs: 30_000)
    let events = await ws.start(streams: ["btcusdt@kline_1m"])
    let reader = Task { for await _ in events {} }
    // 先打出几次失败，把档位抬起来。
    for n in 1...4 {
      #expect(await waitUntil(10) { await bench.connects >= n })
      let s = try #require(await bench.latest())
      #expect(await waitUntil(10) { await s.receiving > 0 })
      await s.push(.text(StormFrames.binanceKline("BTCUSDT")))
      await s.push(.closed("抖 #\(n)"))
      #expect(await waitUntil(10) { await ws.backoffAttempt >= n })
      await pacer.advance(40_000)
    }
    #expect(await waitUntil(10) { await bench.connects >= 5 })
    let s = try #require(await bench.latest())
    #expect(await waitUntil(10) { await s.receiving > 0 })
    await s.push(.text(StormFrames.binanceKline("BTCUSDT")))
    #expect(await waitUntil(10) { await s.receiving > 0 })
    // 这条连接稳定跑了十分钟。
    for _ in 0..<10 {
      await pacer.advance(60_000)
      await s.push(.text(StormFrames.binanceKline("BTCUSDT")))
      #expect(await waitUntil(10) { await s.receiving > 0 })
    }
    await s.push(.closed("每日换线"))
    let reset = await waitUntil(10) { await ws.backoffAttempt == 1 }
    let attempt = await ws.backoffAttempt
    #expect(reset, "档位：\(attempt)")
    await ws.stop()
    reader.cancel()
    await pacer.drain()
  }
}
