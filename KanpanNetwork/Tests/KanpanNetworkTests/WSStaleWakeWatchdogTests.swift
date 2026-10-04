import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

// 深度审查 2026-10-04 · C 线：换轮之后旧一轮的收帧带着一帧醒来，不许把新一轮的看门狗掐掉；
// Coinbase 想要的订阅全被上游明确拒了，不许每个静默窗口重连一次、永不停。

private let coinbaseURL = URL(string: "wss://advanced-trade-ws.coinbase.com")!

private func coinbaseTicker(_ product: String) -> String {
  #"{"channel":"ticker","timestamp":"2026-10-04T01:00:00Z","events":[{"type":"update","tickers":[{"product_id":""#
    + product + #"","price":"63000","volume_24_h":"1","low_24_h":"1","high_24_h":"2","price_percent_chg_24_h":"0"}]}]}"#
}

/// 按看门狗节拍一拍一拍拨针，直到 `done` 成立或拨满 `budgetMs` 虚拟毫秒。
private func tick(_ pacer: ManualPacer, stepMs: Double, budgetMs: Double,
                  until done: @escaping @Sendable () async -> Bool) async -> Bool {
  var elapsed = 0.0
  while elapsed < budgetMs {
    if await done() { return true }
    _ = await waitUntil(1) { await pacer.sleeping >= 1 }
    await pacer.advance(stepMs)
    elapsed += stepMs
  }
  return await waitUntil(1) { await done() }
}

/// 收尾兜底：别让挂着的收帧把测试进程挂住。
private func unplug(_ bench: GateSocketBench) async {
  for s in await bench.sockets { await s.cancel() }
}

@Suite("换轮后旧收帧醒来不许动新一轮的看门狗", .timeLimit(.minutes(1)))
struct WSStaleWakeWatchdogTests {

  @Test("C-1 币安：换轮后旧连接带一帧醒来，新连接的首帧静默看门狗照样在，满窗口照样重连")
  func binanceStaleWakeKeepsNewWatchdog() async throws {
    let bench = GateSocketBench()
    // 旧 socket 的 cancel 卡在一次往返上：旧一轮的收帧这时候还挂着，能被一帧叫醒。
    let cancelGate = await bench.holdCancel(on: 1)
    let pacer = ManualPacer()
    let ws = BinanceWS(factory: bench, pacer: pacer, silenceMs: 10_000,
                       transportSilenceMs: 30_000, baseBackoffMs: 1000, capBackoffMs: 1000)
    let first = await ws.start(streams: ["aaausdt@kline_1m"])
    let c1 = Task { for await _ in first {} }
    try #require(await waitUntil(5) { await bench.socket(1)?.receiving == 1 })

    let second = await ws.start(streams: ["bbbusdt@kline_1m"])
    let c2 = Task { for await _ in second {} }
    try #require(await waitUntil(5) {
      let receiving = await bench.socket(2)?.receiving
      let sleeping = await pacer.sleeping
      return receiving == 1 && sleeping >= 1
    })
    let old = try #require(await bench.socket(1))
    let fresh = try #require(await bench.socket(2))

    // 旧连接这会儿才推上来一帧：旧一轮的 pump 认出自己过期、正常返回。
    await old.push(.text(klineText("AAAUSDT")))
    #expect(await waitUntil(5) { await old.receiving == 0 })

    // 新连接一帧都没收到：首帧窗口一过必须掐掉重连。看门狗被旧一轮掐掉的话这里永远等不到。
    let cut = await tick(pacer, stepMs: 2_500, budgetMs: 20_000) { await fresh.cancelCalls >= 1 }
    #expect(cut, "新一轮的首帧静默看门狗被旧一轮掐掉了：新连接静默多久都不会重连")

    await cancelGate.open()
    await ws.stop()
    c1.cancel(); c2.cancel()
    await pacer.drain()
    await unplug(bench)
  }

  @Test("C-2 Coinbase：换轮后旧连接带一帧醒来，新连接的看门狗照样在，满窗口照样重连")
  func coinbaseStaleWakeKeepsNewWatchdog() async throws {
    let bench = GateSocketBench()
    let cancelGate = await bench.holdCancel(on: 1)
    let pacer = ManualPacer()
    let ws = CoinbaseWS(urls: [coinbaseURL], factory: bench, pacer: pacer,
                        silenceMs: 10_000, transportSilenceMs: 1e12)
    let first = await ws.start(topics: [.ticker(symbol: "coinbase/spot/BTC-USD")])
    let c1 = Task { for await _ in first {} }
    try #require(await waitUntil(5) { await bench.socket(1)?.receiving == 1 })

    let second = await ws.start(topics: [.ticker(symbol: "coinbase/spot/ETH-USD")])
    let c2 = Task { for await _ in second {} }
    try #require(await waitUntil(5) {
      let receiving = await bench.socket(2)?.receiving
      let sleeping = await pacer.sleeping
      return receiving == 1 && sleeping >= 1
    })
    let old = try #require(await bench.socket(1))
    let fresh = try #require(await bench.socket(2))

    await old.push(.text(coinbaseTicker("BTC-USD")))
    #expect(await waitUntil(5) { await old.receiving == 0 })

    let cut = await tick(pacer, stepMs: 2_500, budgetMs: 20_000) { await fresh.cancelCalls >= 1 }
    #expect(cut, "新一轮的看门狗被旧一轮掐掉了：新连接静默多久都不会重连")

    await cancelGate.open()
    await ws.stop()
    c1.cancel(); c2.cancel()
    await pacer.drain()
    await unplug(bench)
  }

  @Test("C-3 Coinbase：想要的订阅全被上游明确拒了，不再每个静默窗口重连一次")
  func coinbaseAllRejectedDoesNotReconnectForever() async throws {
    let bench = GateSocketBench()
    // 20 秒窗口 × 0.01 = 真实 200ms。
    let ws = CoinbaseWS(urls: [coinbaseURL], factory: bench, pacer: FastPacer(scale: 0.01),
                        silenceMs: 20_000, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "coinbase/spot/NOPE-USD")])
    try #require(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    #expect(await waitUntil(5) { await socket.sent.contains { $0.contains("NOPE-USD") } })
    await socket.push(.text(#"{"type":"error","message":"Failed to subscribe"}"#))
    #expect(await waitUntil(5) { await ws.topicErrors["ticker NOPE-USD"] == "Failed to subscribe" })
    // 原来：200ms 没有行情就重连，重连上再订、再被拒，一轮接一轮。
    #expect(await staysFalse(for: 0.8) { await bench.connects >= 2 })
    await ws.stop()
    await unplug(bench)
  }

  @Test("C-6 Coinbase：新一轮已起、新连接上只发过心跳订阅，这时来的报错不许记到上一轮那批订阅头上")
  func coinbaseErrorAfterNewRunNotPinnedOnOldRunSubs() async throws {
    let bench = GateSocketBench()
    let ws = CoinbaseWS(urls: [coinbaseURL], factory: bench, pacer: FastPacer(scale: 0.01),
                        silenceMs: 1e12, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "coinbase/spot/BTC-USD")])
    try #require(await waitUntil(5) { await bench.socket(1) != nil })
    let first = try #require(await bench.socket(1))
    #expect(await waitUntil(5) { await first.sent.contains { $0.contains("BTC-USD") } })
    // 新一轮：这一轮在 Coinbase 上没有可订的频道，新连接上唯一一发控制帧是心跳订阅。
    _ = await ws.start(topics: [.markPrice(symbol: "coinbase/spot/BTC-USD")])
    try #require(await waitUntil(5) { await bench.socket(2) != nil })
    let second = try #require(await bench.socket(2))
    #expect(await waitUntil(5) { await second.sent.contains { $0.contains("heartbeats") } })
    await second.push(.text(#"{"type":"error","message":"Failed to subscribe"}"#))
    // 原来：最近一发控制帧还是上一轮的 subscribe ticker BTC-USD，报错整条记到它头上。
    #expect(await staysFalse(for: 0.4) { await ws.topicErrors["ticker BTC-USD"] != nil })
    #expect(await ws.topicErrors.isEmpty)
    await ws.stop()
    await unplug(bench)
  }

  @Test("C-6 Coinbase：同一轮里断线重连，新连接上只发过心跳订阅，这时来的报错不许记到旧连接最后那批订阅头上")
  func coinbaseErrorAfterReconnectNotPinnedOnOldConnectionSubs() async throws {
    let bench = GateSocketBench()
    let ws = CoinbaseWS(urls: [coinbaseURL], factory: bench, pacer: FastPacer(scale: 0.01),
                        silenceMs: 1e12, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "coinbase/spot/BTC-USD")])
    try #require(await waitUntil(5) { await bench.socket(1) != nil })
    let first = try #require(await bench.socket(1))
    #expect(await waitUntil(5) { await first.sent.contains { $0.contains("\"subscribe\"") && $0.contains("BTC-USD") } })
    // 退订之后旧连接上最近一发控制帧是 unsubscribe ticker BTC-USD；然后这条连接断了。
    await ws.replace(topics: [])
    #expect(await waitUntil(5) { await first.sent.contains { $0.contains("unsubscribe") } })
    await first.push(.closed("going away"))
    try #require(await waitUntil(5) { await bench.socket(2) != nil })
    let second = try #require(await bench.socket(2))
    #expect(await waitUntil(5) { await second.sent.contains { $0.contains("heartbeats") } })
    await second.push(.text(#"{"type":"error","message":"Failed to subscribe"}"#))
    #expect(await staysFalse(for: 0.4) { await ws.topicErrors["ticker BTC-USD"] != nil })
    #expect(await ws.topicErrors.isEmpty)
    await ws.stop()
    await unplug(bench)
  }
}
