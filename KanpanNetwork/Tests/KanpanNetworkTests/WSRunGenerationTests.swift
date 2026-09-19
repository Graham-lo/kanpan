import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

// 一条 `BinanceWS` 上可能先后跑过好几轮 run（`start` 被再叫一次、重连、回前台重启）。
// 这套用例守的是同一件事：**每一轮只许动自己的东西**——自己的 continuation、
// 自己的 socket、自己那份订阅账。旧一轮醒来时世界已经换过了，它必须安静地退场，
// 而不是把新一轮的连接掐掉、把新一轮的订阅账清空、或者把旧连接的帧塞进新流里。

// ---------------------------------------------------------------- 假件

/// 一条可以由测试逐帧喂数据的线。`receive()` 没帧时挂着，**不理会任务取消**——
/// 真 `URLSessionWebSocketTask.receive()` 就是这个脾气，只有 `cancel()` 叫得醒。
actor Wire {
  let id: Int
  private var frames: [WSFrame] = []
  private var waiters: [CheckedContinuation<WSFrame?, Never>] = []
  private(set) var cancelled = false
  private(set) var sent: [String] = []

  init(id: Int) { self.id = id }

  func push(_ f: WSFrame) {
    if !waiters.isEmpty { waiters.removeFirst().resume(returning: f); return }
    frames.append(f)
  }
  func receive() async -> WSFrame? {
    if cancelled { return nil }
    if !frames.isEmpty { return frames.removeFirst() }
    return await withCheckedContinuation { waiters.append($0) }
  }
  func cancel() {
    cancelled = true
    let w = waiters; waiters = []
    for c in w { c.resume(returning: nil) }
  }
  func note(_ text: String) { sent.append(text) }
  func sentTexts() -> [String] { sent }
}

struct WireSocket: WSSocket {
  let wire: Wire
  /// 挡住这条线上的控制帧，模拟「发出去了，回执还在路上」。
  let sendGate: Gate?
  /// 挡住 `cancel()`，模拟「善后跨了一个 await，这中间世界变了」。
  let cancelGate: Gate?

  func send(_ text: String) async throws {
    if let sendGate { await sendGate.wait() }
    await wire.note(text)
  }
  func receive() async throws -> WSFrame {
    guard let f = await wire.receive() else { throw FeedError.badResponse("连接已取消") }
    return f
  }
  func pong() async throws {}
  func cancel() async {
    if let cancelGate { await cancelGate.wait() }
    await wire.cancel()
  }
}

actor WireBench: WSSocketFactory {
  private(set) var wires: [Wire] = []
  private(set) var urls: [URL] = []
  private var sendGates: [Int: Gate] = [:]
  private var cancelGates: [Int: Gate] = [:]

  func holdSends(on id: Int) -> Gate { let g = Gate(); sendGates[id] = g; return g }
  func holdCancel(on id: Int) -> Gate { let g = Gate(); cancelGates[id] = g; return g }

  func connect(to url: URL) async throws -> WSSocket {
    urls.append(url)
    let wire = Wire(id: wires.count + 1)
    wires.append(wire)
    return WireSocket(wire: wire, sendGate: sendGates[wire.id], cancelGate: cancelGates[wire.id])
  }
  var count: Int { wires.count }
  func wire(_ i: Int) -> Wire? { i >= 1 && i <= wires.count ? wires[i - 1] : nil }
}

/// 一条能解出来的 kline 报文。
func klineText(_ symbol: String, openTime: Int64 = 1_789_371_600_000, close: Double = 100) -> String {
  """
  {"stream":"\(symbol.lowercased())@kline_1m","data":{"e":"kline","E":\(openTime + 1000),"s":"\(symbol)",\
  "k":{"t":\(openTime),"T":\(openTime + 59_999),"s":"\(symbol)","i":"1m","f":1,"L":2,"o":"\(close)",\
  "c":"\(close)","h":"\(close)","l":"\(close)","v":"1","n":2,"x":false,"q":"1","V":"1","Q":"1","B":"0"}}}
  """
}

actor SymbolLog {
  private(set) var symbols: [String] = []
  func add(_ s: String) { symbols.append(s) }
  func all() -> [String] { symbols }
}

@Suite("WS 一轮 run 只动自己的东西")
struct WSRunGenerationTests {

  @Test("BT-04 再 start 一轮：旧连接的帧不许进新流，旧 socket 必须被收走", .timeLimit(.minutes(1)))
  func secondStartTakesOverOldRun() async throws {
    let bench = WireBench()
    let ws = BinanceWS(factory: bench, pacer: FastPacer(), silenceMs: 60_000_000)

    let first = await ws.start(streams: ["btcusdt@kline_1m"])
    #expect(await waitUntil(5) { await bench.count == 1 })
    let second = await ws.start(streams: ["ethusdt@kline_1m"])
    #expect(await waitUntil(5) { await bench.count == 2 })

    let seen = SymbolLog()
    let reader = Task {
      for await ev in second {
        if case .payload(.kline(let k)) = ev { await seen.add(k.symbol) }
      }
    }
    let oldDone = Counter()
    let oldReader = Task { for await _ in first {}; oldDone.bump() }

    // 旧连接这会儿才把一帧推上来：真机上就是旧连接还没被收掉、又来了一帧。
    await bench.wire(1)?.push(.text(klineText("BTCUSDT")))
    await bench.wire(2)?.push(.text(klineText("ETHUSDT")))

    #expect(await waitUntil(5) { await seen.all().contains("ETHUSDT") })
    // 先推的是旧连接那条；它要是进得来，一定排在 ETHUSDT 前面。
    #expect(!(await seen.all().contains("BTCUSDT")))
    // 旧连接必须被收走，不然它会一直挂在那儿收帧、也一直占着一条真连接。
    #expect(await waitUntil(5) { await bench.wire(1)?.cancelled == true })
    // 旧流要收口：订阅它的人才知道「这一轮结束了」。
    #expect(await waitUntil(5) { oldDone.value == 1 })

    await ws.stop()
    reader.cancel(); oldReader.cancel()
  }

  @Test("BT-03 旧一轮卡住的控制帧醒来：不许发到新连接上，也不许改新一轮的订阅账", .timeLimit(.minutes(1)))
  func staleControlFrameCannotTouchNewRun() async throws {
    let bench = WireBench()
    let gate = await bench.holdSends(on: 1)
    let ws = BinanceWS(factory: bench, pacer: FastPacer(), silenceMs: 60_000_000)

    _ = await ws.start(streams: ["aaausdt@kline_1m", "bbbusdt@kline_1m"])
    #expect(await waitUntil(5) { await bench.count == 1 })

    // 切走 aaa：要发一条 UNSUBSCRIBE，卡在闸门上（真机上就是帧发出去了没回执）。
    await ws.replaceStreams(["bbbusdt@kline_1m"])
    #expect(await waitUntil(5) { await gate.arrived > 0 })

    // 这一轮整个被换掉：新连接的 URL 自带 aaa，服务器已经知道这条流了。
    _ = await ws.start(streams: ["aaausdt@kline_1m"])
    #expect(await waitUntil(5) { await bench.count == 2 })

    await gate.open()                      // 旧控制帧这时候才醒过来
    try await Task.sleep(for: .milliseconds(300))

    // 新连接上不该出现任何控制帧：它该订的流 URL 里已经带了。
    #expect(await bench.wire(2)?.sentTexts().isEmpty == true)
    // 新一轮的订阅账也不许被旧一轮减掉。
    #expect(await ws.streamsInSync)
    await ws.stop()
  }

  @Test("BT-03b 旧一轮断线善后不许把新一轮的连接清掉", .timeLimit(.minutes(1)))
  func staleTeardownCannotClearNewRun() async throws {
    let bench = WireBench()
    let cancelGate = await bench.holdCancel(on: 1)
    let ws = BinanceWS(factory: bench, pacer: FastPacer(), silenceMs: 60_000_000)

    _ = await ws.start(streams: ["aaausdt@kline_1m"])
    #expect(await waitUntil(5) { await bench.count == 1 })

    // 服务器掐了：旧一轮进入善后，卡在 `socket.cancel()` 这个 await 上。
    await bench.wire(1)?.push(.closed("服务器掐了"))
    #expect(await waitUntil(5) { await cancelGate.arrived > 0 })

    // 善后还没做完，新的一轮已经起来了（回前台重启 WS 就是这个时序）。
    _ = await ws.start(streams: ["aaausdt@kline_1m"])
    #expect(await waitUntil(5) { await bench.count == 2 })

    await cancelGate.open()
    try await Task.sleep(for: .milliseconds(200))

    // 新一轮必须还活着：换流还发得出去，连接也没被旧一轮掐掉。
    await ws.replaceStreams(["zzzusdt@kline_1m"])
    #expect(await waitUntil(5) { await ws.streamsInSync })
    #expect(await bench.wire(2)?.cancelled == false)
    await ws.stop()
  }
}
