import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

// §B.10 回归规格 BT-10 / BT-08（网络层那一半）。
//
// 这里全部换成 `GateSocket`：`receive()` 挂在不理会取消的 continuation 上，只有
// 真的有人调 `cancel()` 才回来。旧的假 socket 拿 `Task.sleep` 模拟等待，任务一取消
// 它自己就醒，于是「超时 / 上层取消有没有真的去掐 socket」在那种假件上永远是绿的。

private let streamURL = URL(string: "wss://local.example/market/stream?streams=btcusdt@kline_1m")!

/// 一个 socket 被「真的关掉了」：owner 调过 `cancel()`，而且挂着的收帧已经带错返回。
private func closedForReal(_ s: GateSocket) async -> Bool {
  let calls = await s.cancelCalls
  let closed = await s.closed
  let receiving = await s.receiving
  return calls >= 1 && closed && receiving == 0
}

/// 收尾兜底：断言失败时别让聋 socket 把测试进程挂住。
private func unplug(_ bench: GateSocketBench) async {
  for s in await bench.sockets { await s.cancel() }
}

@Suite("BT-10 聋 socket：超时与上层取消必须真的掐 socket", .timeLimit(.minutes(1)))
struct DeafSocketTimeoutTests {

  @Test("BT-10 选路首帧超时：两条候选都聋，超时那一路必须对每条都调 cancel，connect 才能返回")
  func routerProbeTimeoutCancelsEverySocket() async throws {
    let bench = GateSocketBench()
    let router = MarketSocketRouter(factory: bench, fallbacks: ["vps.example"], timeoutMs: 50)
    let outcome = Task { () -> Error? in
      do { _ = try await router.connect(to: streamURL); return nil } catch { return error }
    }
    // 聋 socket 的 receive 不认取消：超时分支要是不去掐 socket，收帧子任务永远不回来，
    // 任务组退不出去，这里就会一直等不到 `closed`。
    let settled = await waitUntil(5) {
      let all = await bench.sockets
      guard all.count == 2 else { return false }
      for s in all where !(await closedForReal(s)) { return false }
      return true
    }
    #expect(settled, "首帧超时之后两条候选 socket 都必须被 cancel 并真的关掉")
    if !settled { await unplug(bench) }
    let error = await outcome.value
    #expect(error != nil, "两条都没有有效首帧，connect 必须失败")
    #expect(await bench.connects == 2)
    for s in await bench.sockets {
      #expect(await s.cancelCalls >= 1, "socket #\(s.id) 没被 cancel")
      #expect(await s.receiving == 0, "socket #\(s.id) 的收帧还挂着")
    }
  }

  @Test("BT-10 选路时上层任务被取消：cancel handler 必须掐掉每条挂着的候选 socket")
  func routerParentCancelCancelsEverySocket() async throws {
    let bench = GateSocketBench()
    // 超时设得足够长：这条用例里能让聋 socket 回来的只有「上层取消 → socket.cancel」。
    let router = MarketSocketRouter(factory: bench, fallbacks: ["vps.example"], timeoutMs: 600_000)
    let outcome = Task { () -> Error? in
      do { _ = try await router.connect(to: streamURL); return nil } catch { return error }
    }
    let armed = await waitUntil(5) {
      let all = await bench.sockets
      guard all.count == 2 else { return false }
      for s in all where await s.receiving == 0 { return false }
      return true
    }
    try #require(armed, "两条候选都应该已经挂在 receive 上")
    for s in await bench.sockets { #expect(await s.cancelCalls == 0) }

    outcome.cancel()
    let settled = await waitUntil(5) {
      for s in await bench.sockets where !(await closedForReal(s)) { return false }
      return true
    }
    #expect(settled, "上层取消之后两条候选 socket 都必须被 cancel 并真的关掉")
    if !settled { await unplug(bench) }
    let error = await outcome.value
    #expect(error != nil, "被取消的 connect 不许交出一条连接")
    #expect(await bench.connects == 2, "取消之后不许再拨新的候选")
  }

  @Test("BT-10 首帧静默看门狗：超时那一路必须先 cancel 聋 socket，重连只在退避之后")
  func firstFrameSilenceCancelsDeafSocket() async throws {
    let bench = GateSocketBench()
    let pacer = ManualPacer()
    let ws = BinanceWS(factory: bench, pacer: pacer, silenceMs: 10_000,
                       transportSilenceMs: 30_000, baseBackoffMs: 1000, capBackoffMs: 1000)
    let stream = await ws.start(streams: ["btcusdt@kline_1m"])
    let consumer = Task { for await _ in stream {} }

    let armed = await waitUntil(5) {
      guard let s = await bench.socket(1) else { return false }
      let receiving = await s.receiving
      let sleeping = await pacer.sleeping
      return receiving == 1 && sleeping >= 1
    }
    try #require(armed, "1 号连接应该挂在 receive 上、看门狗闹钟已排上")
    let first = try #require(await bench.socket(1))

    await pacer.advance(9_999)
    #expect(await first.cancelCalls == 0, "没到窗口不许掐")

    await pacer.advance(2)
    #expect(await waitUntil(5) { await closedForReal(first) },
            "首帧静默超过窗口：看门狗必须 cancel 聋 socket，挂着的 receive 才能回来")
    // 掐完先退避，不是当场重拨（退避闹钟排上了、连接数还是 1）。
    #expect(await waitUntil(5) { await pacer.sleeping >= 1 })
    #expect(await bench.connects == 1)

    await pacer.advance(1_300)   // 基础退避 1000ms，抖动最多 +20%
    #expect(await waitUntil(5) { await bench.connects == 2 }, "退避过后才重连")

    await ws.stop()
    #expect(await waitUntil(5) { await bench.live() == 0 })
    consumer.cancel()
    await pacer.drain()
    await unplug(bench)
  }

  @Test("BT-10 传输层静默看门狗：首帧之后保活探不通，满 30 秒必须 cancel 聋 socket")
  func transportSilenceCancelsDeafSocket() async throws {
    let bench = GateSocketBench(answersKeepalive: false)
    let pacer = ManualPacer()
    let ws = BinanceWS(factory: bench, pacer: pacer, silenceMs: 10_000,
                       transportSilenceMs: 30_000, keepaliveProbeMs: 1_000,
                       baseBackoffMs: 1000, capBackoffMs: 1000)
    let seen = Counter()
    let stream = await ws.start(streams: ["btcusdt@kline_1m"])
    let consumer = Task { for await e in stream { if case .payload = e { seen.bump() } } }

    try #require(await waitUntil(5) { await bench.socket(1) != nil })
    let first = try #require(await bench.socket(1))
    await first.push(.text(klineText("BTCUSDT")))
    try #require(await waitUntil(5) {
      let receiving = await first.receiving
      return seen.value == 1 && receiving == 1
    })

    // 按探针节拍一拍一拍往前拨，直到看门狗判死；给足 60 秒虚拟时间的上限。
    var elapsed = 0.0
    while elapsed < 60_000, !(await first.closed) {
      _ = await waitUntil(2) { await pacer.sleeping >= 1 }
      await pacer.advance(2_500)
      elapsed += 2_500
    }
    #expect(await closedForReal(first), "传输层静默满窗口必须 cancel 聋 socket")
    #expect(elapsed >= 30_000, "保活窗口没满就掐了（\(elapsed)ms）")

    await ws.stop()
    consumer.cancel()
    await pacer.drain()
    await unplug(bench)
  }

  @Test("BT-10 owner stop() 时收帧正挂在聋 socket 上：stop 必须 cancel 它并且自己能返回")
  func stopCancelsDeafSocket() async throws {
    let bench = GateSocketBench()
    let ws = BinanceWS(factory: bench, pacer: FastPacer(), silenceMs: 60_000_000)
    let stream = await ws.start(streams: ["btcusdt@kline_1m"])
    let consumer = Task { for await _ in stream {} }
    try #require(await waitUntil(5) {
      guard let s = await bench.socket(1) else { return false }
      return await s.receiving == 1
    })
    let first = try #require(await bench.socket(1))

    await ws.stop()
    #expect(await closedForReal(first), "stop() 返回时聋 socket 必须已经被 cancel 并关掉")
    #expect(await bench.live() == 0)
    // 停了就是停了：不许在后台自己再拨一条。
    try await Task.sleep(for: .milliseconds(50))
    #expect(await bench.connects == 1)
    consumer.cancel()
  }
}

@Suite("BT-08 取消唯一消费者：iterator 退出，连接只听 owner 的", .timeLimit(.minutes(1)))
struct ConsumerCancelTests {

  @Test("BT-08 BinanceWS：取消消费者任务 → 迭代当场结束；连接不抖不重连；owner stop() 才掐 socket")
  func cancellingConsumerEndsIteratorOwnerStopsSocket() async throws {
    // 一条健康的连接：保活探针答得上，行情静默也不会被看门狗拆（快进时钟下默认的
    // 30 秒传输窗口只有 30ms 真实时间，不这样就会把看门狗重连误当成「消费者走了引起的抖动」）。
    let bench = GateSocketBench(answersKeepalive: true)
    let ws = BinanceWS(factory: bench, pacer: FastPacer(), silenceMs: 60_000_000,
                       transportSilenceMs: 60_000_000)
    let stream = await ws.start(streams: ["btcusdt@kline_1m"])
    let payloads = Counter()
    let exited = Counter()
    let consumer = Task {
      for await e in stream { if case .payload = e { payloads.bump() } }
      exited.bump()
    }
    try #require(await waitUntil(5) { await bench.socket(1) != nil })
    let first = try #require(await bench.socket(1))
    await first.push(.text(klineText("BTCUSDT")))
    try #require(await waitUntil(5) { payloads.value == 1 })

    // ① 消费者这一侧：取消它自己的任务，iterator 必须返回 nil、循环退出。
    consumer.cancel()
    #expect(await waitUntil(5) { exited.value == 1 }, "取消消费者任务后 for-await 必须退出")

    // ② producer 这一侧：按 owner 契约，消费者走了不等于连接该关——连接的生死只归
    // owner（MarketFeed.stop / MarketModel.stop）。这里既不许悄悄掐掉，也不许因为
    // 出口没人收就抖成重连。
    await first.push(.text(klineText("BTCUSDT", close: 101)))
    #expect(await waitUntil(5) { await first.receiving == 1 }, "producer 应该继续收帧")
    #expect(await first.cancelCalls == 0)
    #expect(await ws.currentConnectionID == 1)
    #expect(await bench.connects == 1)
    #expect(payloads.value == 1, "消费者走了之后不许再有东西投到它手上")

    // ③ owner 收场：stop() 返回时 socket 已被 cancel 并真的关掉，没有任何残留连接。
    await ws.stop()
    #expect(await closedForReal(first))
    #expect(await bench.live() == 0)
    #expect(await bench.connects == 1)
  }
}
