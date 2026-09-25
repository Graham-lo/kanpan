import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// WS 链路审查（F2 / F3 / F5 / F6 / F8 / F9）的回归用例。

// ---------------------------------------------------------------- 假件

/// 控制帧发不出去的 socket：`heartbeats` 之外的 subscribe 一律抛错（`failing == true` 时）。
/// `receive()` 挂着，只有 `cancel()` 叫得醒——和真 `URLSessionWebSocketTask` 一个脾气。
actor SendFailSocket: WSSocket {
  let failing: Bool
  private var waiters: [CheckedContinuation<WSFrame, Error>] = []
  private(set) var cancelled = false
  private(set) var sent: [String] = []
  init(failing: Bool) { self.failing = failing }

  func send(_ text: String) async throws {
    if cancelled { throw FeedError.badResponse("已关闭") }
    sent.append(text)
    if failing, !text.contains("heartbeats") { throw FeedError.badResponse("写失败") }
  }
  func receive() async throws -> WSFrame {
    if cancelled { throw FeedError.badResponse("已关闭") }
    return try await withCheckedThrowingContinuation { waiters.append($0) }
  }
  func pong() async throws {}
  func cancel() async {
    cancelled = true
    let w = waiters; waiters = []
    for c in w { c.resume(throwing: FeedError.badResponse("被掐断")) }
  }
}

/// 第一条连接发控制帧失败，之后的连接正常。
actor SendFailBench: WSSocketFactory {
  private(set) var made: [SendFailSocket] = []
  func connect(to url: URL) async throws -> any WSSocket {
    let s = SendFailSocket(failing: made.isEmpty)
    made.append(s)
    return s
  }
  var connects: Int { made.count }
  func socket(_ i: Int) -> SendFailSocket? { i >= 1 && i <= made.count ? made[i - 1] : nil }
}

/// 永远连不上的工厂：退避一档一档往上走。
actor RefusingFactory: WSSocketFactory {
  private(set) var attempts = 0
  func connect(to url: URL) async throws -> any WSSocket {
    attempts += 1
    throw FeedError.badResponse("连不上")
  }
}

@Suite("WS 链路加固")
struct WSChainHardeningTests {
  private static let coinbaseURL = URL(string: "wss://advanced-trade-ws.coinbase.com")!

  private struct Control: Decodable { var type: String; var channel: String; var product_ids: [String]? }
  private func controls(_ texts: [String]) -> [Control] {
    texts.compactMap { try? JSONDecoder().decode(Control.self, from: Data($0.utf8)) }
  }
  private static func tickerFrame(_ product: String) -> String {
    #"{"channel":"ticker","timestamp":"2026-09-22T23:19:47Z","events":[{"type":"update","tickers":[{"product_id":""#
      + product + #"","price":"63000","volume_24_h":"1","low_24_h":"1","high_24_h":"2","price_percent_chg_24_h":"0"}]}]}"#
  }

  // ---------------------------------------------------------------- F2

  @Test("F2 Coinbase：订阅控制帧发送失败 → 当场重连，新连接把整套订阅重发", .timeLimit(.minutes(1)))
  func coinbaseSendFailureReconnects() async throws {
    let bench = SendFailBench()
    // 两个静默窗口都拉到天边：能重连只可能是「发送失败」这一路触发的。
    let ws = CoinbaseWS(urls: [Self.coinbaseURL], factory: bench, pacer: FastPacer(scale: 0.0001),
                        silenceMs: 1e12, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "coinbase/spot/BTC-USD")])
    #expect(await waitUntil(5) { await bench.connects >= 2 })
    #expect(await bench.socket(1)?.cancelled == true, "发不出去的那条连接必须被收掉")
    #expect(await waitUntil(5) {
      guard let s = await bench.socket(2) else { return false }
      return self.controls(await s.sent).contains { $0.type == "subscribe" && $0.channel == "ticker" }
    })
    // 第一条连接上 ticker 的 subscribe 只试了一次，不会对着坏连接反复重排。
    let first = controls(await bench.socket(1)?.sent ?? [])
    #expect(first.filter { $0.channel == "ticker" }.count == 1)
    await ws.stop()
  }

  // ---------------------------------------------------------------- F5

  @Test("F5 Coinbase：连接在推之后新增的订阅没有首帧 → 先重发一次 subscribe，再超时才重连", .timeLimit(.minutes(1)))
  func coinbasePendingTopicResubscribesThenReconnects() async throws {
    let bench = GateSocketBench()
    // 20 秒窗口 × 0.01 = 真实 200ms。
    let ws = CoinbaseWS(urls: [Self.coinbaseURL], factory: bench, pacer: FastPacer(scale: 0.01),
                        silenceMs: 20_000, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "coinbase/spot/BTC-USD")])
    #expect(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    await socket.push(.text(Self.tickerFrame("BTC-USD")))
    #expect(await waitUntil(5) { await socket.sent.count >= 2 })

    await ws.replace(topics: [.ticker(symbol: "coinbase/spot/BTC-USD"), .ticker(symbol: "coinbase/spot/ETH-USD")])
    let ethSubs: @Sendable () async -> Int = {
      self.controls(await socket.sent).filter { $0.type == "subscribe" && $0.product_ids == ["ETH-USD"] }.count
    }
    #expect(await waitUntil(5) { await ethSubs() == 1 })
    // 第一个窗口过去：只重发这一个品种的 subscribe，不拆连接。
    #expect(await waitUntil(5) { await ethSubs() == 2 })
    #expect(await bench.connects == 1)
    // 重发后仍然没有：重连。
    #expect(await waitUntil(5) { await bench.connects >= 2 })
    #expect(await socket.closed)
    #expect(await ethSubs() == 2)
    await ws.stop()
  }

  @Test("F5 Coinbase：新增订阅的首帧到了就算生效，不重发也不重连", .timeLimit(.minutes(1)))
  func coinbaseConfirmedTopicStaysPut() async throws {
    let bench = GateSocketBench()
    let ws = CoinbaseWS(urls: [Self.coinbaseURL], factory: bench, pacer: FastPacer(scale: 0.01),
                        silenceMs: 20_000, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "coinbase/spot/BTC-USD")])
    #expect(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    await socket.push(.text(Self.tickerFrame("BTC-USD")))
    await ws.replace(topics: [.ticker(symbol: "coinbase/spot/BTC-USD"), .ticker(symbol: "coinbase/spot/ETH-USD")])
    #expect(await waitUntil(5) {
      self.controls(await socket.sent).contains { $0.type == "subscribe" && $0.product_ids == ["ETH-USD"] }
    })
    await socket.push(.text(Self.tickerFrame("ETH-USD")))
    #expect(await staysFalse(for: 0.6) { await bench.connects >= 2 })
    #expect(controls(await socket.sent).filter { $0.product_ids == ["ETH-USD"] }.count == 1)
    await ws.stop()
  }

  @Test("F5 Coinbase：error 帧按最近一发控制帧记到那个频道 × 品种上，被明确拒掉的不再重发 / 重连", .timeLimit(.minutes(1)))
  func coinbaseErrorFrameIsAttributed() async throws {
    let bench = GateSocketBench()
    let ws = CoinbaseWS(urls: [Self.coinbaseURL], factory: bench, pacer: FastPacer(scale: 0.01),
                        silenceMs: 20_000, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "coinbase/spot/BTC-USD")])
    #expect(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    await socket.push(.text(Self.tickerFrame("BTC-USD")))
    await ws.replace(topics: [.ticker(symbol: "coinbase/spot/BTC-USD"), .ticker(symbol: "coinbase/spot/NOPE-USD")])
    #expect(await waitUntil(5) {
      self.controls(await socket.sent).contains { $0.type == "subscribe" && $0.product_ids == ["NOPE-USD"] }
    })
    await socket.push(.text(#"{"type":"error","message":"Failed to subscribe"}"#))
    #expect(await waitUntil(5) { await ws.topicErrors["ticker NOPE-USD"] == "Failed to subscribe" })
    #expect(await staysFalse(for: 0.6) { await bench.connects >= 2 })
    #expect(controls(await socket.sent).filter { $0.product_ids == ["NOPE-USD"] }.count == 1)
    await ws.stop()
  }

  // ---------------------------------------------------------------- F6

  @Test("F6 币安：再 start 一轮，退避从第一档重新算", .timeLimit(.minutes(1)))
  func binanceStartResetsBackoff() async throws {
    let factory = RefusingFactory()
    let pacer = ManualPacer()
    let ws = BinanceWS(factory: factory, pacer: pacer, silenceMs: 1e12)
    _ = await ws.start(streams: ["btcusdt@kline_1m"])
    for n in 1...4 {
      #expect(await waitUntil(5) {
        let sleeping = await pacer.sleeping, attempts = await factory.attempts
        return sleeping >= 1 && attempts >= n
      })
      if n < 4 { await pacer.advance(1_000_000) }
    }
    #expect(await ws.backoffAttempt >= 4)
    _ = await ws.start(streams: ["ethusdt@kline_1m"])
    #expect(await waitUntil(5) { await factory.attempts >= 5 })
    #expect(await waitUntil(5) { await ws.backoffAttempt == 1 }, "新一轮第一次失败只该在第一档")
    #expect(await ws.backoffAttempt == 1)
    await ws.stop()
    await pacer.drain()
  }

  @Test("F6 Coinbase：再 start 一轮，退避从第一档重新算", .timeLimit(.minutes(1)))
  func coinbaseStartResetsBackoff() async throws {
    let factory = RefusingFactory()
    let pacer = ManualPacer()
    let ws = CoinbaseWS(urls: [Self.coinbaseURL], factory: factory, pacer: pacer,
                        silenceMs: 1e12, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "coinbase/spot/BTC-USD")])
    for n in 1...4 {
      #expect(await waitUntil(5) {
        let sleeping = await pacer.sleeping, attempts = await factory.attempts
        return sleeping >= 1 && attempts >= n
      })
      if n < 4 { await pacer.advance(1_000_000) }
    }
    #expect(await ws.backoffAttempt >= 4)
    _ = await ws.start(topics: [.ticker(symbol: "coinbase/spot/ETH-USD")])
    #expect(await waitUntil(5) { await factory.attempts >= 5 })
    #expect(await waitUntil(5) { await ws.backoffAttempt == 1 })
    await ws.stop()
    await pacer.drain()
  }

  // ---------------------------------------------------------------- F8

  @Test("F8 币安：流名不在当前订阅集里的组合流报文丢掉并计数", .timeLimit(.minutes(1)))
  func binanceDropsForeignStreams() async throws {
    let bench = WireBench()
    let ws = BinanceWS(factory: bench, pacer: FastPacer(), silenceMs: 60_000_000)
    let events = await ws.start(streams: ["btcusdt@kline_1m"])
    #expect(await waitUntil(5) { await bench.count == 1 })
    let seen = SymbolLog()
    let reader = Task {
      for await ev in events { if case .payload(.kline(let k)) = ev { await seen.add(k.symbol) } }
    }
    await bench.wire(1)?.push(.text(klineText("ETHUSDT")))
    await bench.wire(1)?.push(.text(klineText("BTCUSDT")))
    #expect(await waitUntil(5) { await seen.all().contains("BTCUSDT") })
    #expect(!(await seen.all().contains("ETHUSDT")))
    #expect(await ws.droppedForeignFrames == 1)
    await ws.stop()
    reader.cancel()
  }

  // ---------------------------------------------------------------- F9

  @Test("F9 全市场 ticker 批量帧：坏一行只丢那一行，其余照收，并计数")
  func tickerBatchIsLenient() throws {
    let before = StreamPayload.droppedBatchRows
    let text = #"""
    [{"e":"24hrTicker","s":"BTCUSDT","c":"105","P":"1","h":"110","l":"90","q":"1000"},
     {"e":"24hrTicker","c":"1"},
     42,
     {"e":"24hrTicker","s":"ETHUSDT","c":"5","P":"1","h":"6","l":"4","q":"10"}]
    """#
    let payload = try JSONDecoder().decode(StreamPayload.self, from: Data(text.utf8))
    guard case .tickerBatch(let rows) = payload else { Issue.record("不是批量帧：\(payload)"); return }
    #expect(rows.map(\.symbol) == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(StreamPayload.droppedBatchRows - before >= 2)
  }

  // ---------------------------------------------------------------- F3

  @Test("F3 币安 aggTrade / trade / 五档：nan、inf、1e400 整帧丢掉并计数", arguments: ["NaN", "inf", "1e400"])
  func binanceNonFiniteDropsFrame(_ bad: String) throws {
    let decoder = JSONDecoder()
    func decodes(_ s: String) -> Bool { (try? decoder.decode(StreamPayload.self, from: Data(s.utf8))) != nil }
    let before = WireNumber.droppedFrames
    #expect(decodes(#"{"e":"aggTrade","s":"BTCUSDT","p":"100","q":"1","m":false,"T":1}"#))
    #expect(!decodes(#"{"e":"aggTrade","s":"BTCUSDT","p":""# + bad + #"","q":"1","m":false,"T":1}"#))
    #expect(!decodes(#"{"e":"aggTrade","s":"BTCUSDT","p":"100","q":""# + bad + #"","m":false,"T":1}"#))
    #expect(!decodes(#"{"e":"trade","s":"BTCUSDT","t":1,"p":""# + bad + #"","q":"1","T":1}"#))
    #expect(decodes(#"{"e":"depthUpdate","s":"BTCUSDT","T":1,"b":[["100","1"]],"a":[["101","2"]]}"#))
    #expect(!decodes(#"{"e":"depthUpdate","s":"BTCUSDT","T":1,"b":[["100","1"]],"a":[["101",""# + bad + #""]]}"#))
    #expect(WireNumber.droppedFrames - before >= 4)
    // 数字写法（回放文件、镜像）超出 Double 范围的也一样。
    if bad == "1e400" {
      #expect(!decodes(#"{"e":"aggTrade","s":"BTCUSDT","p":1e400,"q":1,"m":false,"T":1}"#))
    }
  }

  @Test("F3 Coinbase market_trades：一笔坏成交整帧丢掉并计数", arguments: ["nan", "inf", "1e400"])
  func coinbaseNonFiniteDropsFrame(_ bad: String) throws {
    func frame(_ size: String) throws -> CoinbaseDTO.Frame {
      let text = #"{"channel":"market_trades","timestamp":"2026-09-22T23:19:47Z","events":[{"type":"update","trades":["#
        + #"{"trade_id":"1","product_id":"BTC-USD","price":"63000","size":"0.1","side":"BUY","time":"2026-09-22T23:19:46.98Z"},"#
        + #"{"trade_id":"2","product_id":"BTC-USD","price":"63001","size":""# + size + #"","side":"BUY","time":"2026-09-22T23:19:46.99Z"}]}]}"#
      return try JSONDecoder().decode(CoinbaseDTO.Frame.self, from: Data(text.utf8))
    }
    #expect(CoinbaseDTO.payloads(try frame("0.2"), candleInterval: .m5).count == 2)
    let before = WireNumber.droppedFrames
    #expect(CoinbaseDTO.payloads(try frame(bad), candleInterval: .m5).isEmpty)
    #expect(WireNumber.droppedFrames > before)
  }

  @Test("F3 订单流适配器：坏数值整帧丢掉（币安 aggTrade、OKX trades、Coinbase l2 与成交）", arguments: ["nan", "inf", "1e400"])
  func orderFlowNonFiniteDropsFrame(_ bad: String) throws {
    let um = OrderFlowAdapterTests.umPerp
    let binance = OrderFlowAdapterTests.binance(.um, [um], .direct)
    let trade = #"{"stream":"btcusdt@aggTrade","data":{"e":"aggTrade","s":"BTCUSDT","p":"78450","q":"X","m":true,"T":1}}"#
    #expect(binance.decode(trade.replacingOccurrences(of: "\"X\"", with: "\"1\"")).count == 1)
    #expect(binance.decode(trade.replacingOccurrences(of: "\"X\"", with: "\"\(bad)\"")).isEmpty)
    let depth = #"{"stream":"btcusdt@depth@100ms","data":{"e":"depthUpdate","E":1,"s":"BTCUSDT","U":1,"u":2,"pu":0,"b":[["100","1"]],"a":[["101","X"]]}}"#
    #expect(binance.decode(depth.replacingOccurrences(of: "\"X\"", with: "\"\(bad)\"")).isEmpty)

    let okx = OrderFlowAdapterTests.okx()
    let okxTrades = #"{"arg":{"channel":"trades","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","tradeId":"1","px":"78450","sz":"30","side":"sell","ts":"1"},{"instId":"BTC-USDT-SWAP","tradeId":"2","px":"X","sz":"5","side":"buy","ts":"2"}]}"#
    #expect(okx.decode(okxTrades.replacingOccurrences(of: "\"X\"", with: "\"78460\"")).count == 2)
    #expect(okx.decode(okxTrades.replacingOccurrences(of: "\"X\"", with: "\"\(bad)\"")).isEmpty)

    let book = OrderFlowAdapterTests.coinbaseBook
    let cb = CoinbaseLevel2Adapter(book: book)
    let l2 = #"{"channel":"l2_data","sequence_num":2,"events":[{"type":"update","product_id":"BTC-USD","updates":[{"side":"bid","event_time":"2026-09-24T01:02:04Z","price_level":"60000","new_quantity":"1"},{"side":"offer","event_time":"2026-09-24T01:02:04Z","price_level":"60010","new_quantity":"X"}]}]}"#
    #expect(cb.decode(l2.replacingOccurrences(of: "\"X\"", with: "\"0\"")).count == 1)
    // 整帧丢：连序号都不推进，下一帧就会发现断档、整本重来。
    #expect(cb.decode(l2.replacingOccurrences(of: "\"X\"", with: "\"\(bad)\"")).isEmpty)
    let trades = #"{"channel":"market_trades","sequence_num":4,"events":[{"type":"update","trades":[{"trade_id":"9","product_id":"BTC-USD","price":"60010","size":"0.25","side":"BUY","time":"2026-09-24T01:02:05Z"},{"trade_id":"10","product_id":"BTC-USD","price":"60000","size":"X","side":"SELL","time":"2026-09-24T01:02:05Z"}]}]}"#
    let advance = VenueMessage(book.id, .delta(BookDelta(firstUpdateID: 4, finalUpdateID: 4, previousFinalUpdateID: nil)))
    #expect(cb.decode(trades.replacingOccurrences(of: "\"X\"", with: "\"0.1\"")).count == 3)
    // 成交帧坏了：成交全不要，但序号照推（成交帧不改簿）。
    #expect(cb.decode(trades.replacingOccurrences(of: "\"X\"", with: "\"\(bad)\"")) == [advance])
  }
}
