import Foundation
import Testing
import KanpanCore
import KanpanNetworkTestSupport
@testable import KanpanData
import KanpanNetwork

/// 交叉（2026-10-08）：币安 / OKX / Bybit / Hyperliquid 同一只 BTC 同时在列表里。
/// 三家用各自真的提供者推送（假 socket），币安用一条假连接；合流之后按品种键分得清清楚楚，谁的价都不串到别家头上。
@Suite("列表行情合并推送 · 四家同一只币", .timeLimit(.minutes(1)))
struct MergedMarketStreamVenueCrossTests {
  /// 币安那一家的假连接（真连接要过线路选择那一层，和这里要验的无关）。
  final class BinanceFake: MarketStream, @unchecked Sendable {
    private let lock = NSLock()
    private var sink: AsyncStream<WSEvent>.Continuation?
    private(set) var topics: [[StreamTopic]] = []
    func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
      let (stream, sink) = AsyncStream<WSEvent>.makeStream()
      lock.withLock { self.sink = sink; self.topics.append(topics) }
      sink.yield(.status(.live))
      return stream
    }
    func replace(topics: [StreamTopic]) async { lock.withLock { self.topics.append(topics) } }
    func stop() async { lock.withLock { sink?.finish() } }
    var firstFrameSilenceMs: Double { get async { 60_000 } }
    var currentConnectionID: Int { get async { 1 } }
    func emit(_ last: Double) {
      lock.withLock {
        _ = sink?.yield(.payload(.ticker(Ticker(symbol: "binance/usd_m/BTCUSDT", last: last, changePercent: .nan,
                                                high: .nan, low: .nan, quoteVolume: .nan))))
      }
    }
    var subscribed: [[StreamTopic]] { lock.withLock { topics } }
  }

  final class Prices: @unchecked Sendable {
    private let lock = NSLock()
    private var bySymbol: [String: [Double]] = [:]
    func note(_ e: WSEvent) {
      guard case .payload(.ticker(let t)) = e else { return }
      lock.withLock { bySymbol[t.symbol, default: []].append(t.last) }
    }
    var snapshot: [String: [Double]] { lock.withLock { bySymbol } }
  }

  @Test("四家各开各的连接、各订各的；交替推 4 × 50 帧，合流后每只键只拿到自家的价、顺序不乱")
  func fourVenuesDoNotCross() async throws {
    let route = MarketRoute(policy: .direct, endpoints: MarketEndpoints(gateways: ["gw.example"], api: ["api.example"]))
    let okx = GateSocketBench(), bybit = GateSocketBench(), hl = GateSocketBench()
    let binance = BinanceFake()
    let merged = MergedMarketStream { venue in
      switch venue {
      case "okx": OKXProvider(route: route, sockets: okx).makeStream(silenceMs: 1e12, log: .silent)
      case "bybit": BybitProvider(route: route, sockets: bybit).makeStream(silenceMs: 1e12, log: .silent)
      case "hyperliquid": HyperliquidProvider(route: route, sockets: hl).makeStream(silenceMs: 1e12, log: .silent)
      case "binance": binance
      default: nil
      }
    }
    let keys = ["binance/usd_m/BTCUSDT", "okx/usd_m/BTCUSDT", "bybit/usd_m/BTCUSDT", "hyperliquid/usd_m/BTC"]
    let events = await merged.start(topics: keys.map { .ticker(symbol: $0) })
    let prices = Prices()
    let reader = Task { for await e in events { prices.note(e) } }

    #expect(await waitUntil(10) {
      let a = await okx.socket(1), b = await bybit.socket(1), c = await hl.socket(1)
      return a != nil && b != nil && c != nil
    })
    let okxSocket = try #require(await okx.socket(1))
    let bybitSocket = try #require(await bybit.socket(1))
    let hlSocket = try #require(await hl.socket(1))
    #expect(await waitUntil(10) { await okxSocket.sent.contains { $0.contains("BTC-USDT-SWAP") } })
    #expect(await waitUntil(10) { await bybitSocket.sent.contains { $0.contains("tickers.BTCUSDT") } })
    #expect(await waitUntil(10) { await hlSocket.sent.contains { $0.contains("activeAssetCtx") } })
    // 每条连接上只有自家的订阅。
    let okxSent = await okxSocket.sent.joined(), bybitSent = await bybitSocket.sent.joined(), hlSent = await hlSocket.sent.joined()
    #expect(!okxSent.contains("tickers.BTCUSDT") && !okxSent.contains("activeAssetCtx"))
    #expect(!bybitSent.contains("BTC-USDT-SWAP") && !bybitSent.contains("activeAssetCtx"))
    #expect(!hlSent.contains("BTC-USDT-SWAP") && !hlSent.contains("tickers.BTCUSDT"))
    #expect(binance.subscribed.first?.map(\.symbol) == ["binance/usd_m/BTCUSDT"])

    for i in 0..<50 {
      let base = Double(i)
      binance.emit(10_000 + base)
      await okxSocket.push(.text(#"{"arg":{"channel":"tickers","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","last":"\#(20_000 + base)","open24h":"1","ts":"1700000000000"}]}"#))
      await bybitSocket.push(.text(#"{"topic":"tickers.BTCUSDT","type":"snapshot","ts":1700000000000,"data":{"symbol":"BTCUSDT","lastPrice":"\#(30_000 + base)","turnover24h":"1"}}"#))
      await hlSocket.push(.text(#"{"channel":"activeAssetCtx","data":{"coin":"BTC","ctx":{"midPx":"\#(40_000 + base)","markPx":"\#(40_000 + base)","prevDayPx":"1","dayNtlVlm":"1","funding":"0"}}}"#))
    }
    #expect(await waitUntil(10) { prices.snapshot.values.map(\.count).reduce(0, +) >= 200 })
    let got = prices.snapshot
    #expect(Set(got.keys) == Set(keys))
    for (n, key) in keys.enumerated() {
      let expected = (0..<50).map { Double((n + 1) * 10_000 + $0) }
      #expect(got[key] == expected, "\(key) 拿到了 \(got[key]?.prefix(5) ?? [])…")
    }

    // 只剩 OKX：别家的连接整条收掉，OKX 那条不重连。
    await merged.replace(topics: [.ticker(symbol: "okx/usd_m/BTCUSDT")])
    #expect(await waitUntil(10) { await bybitSocket.closed })
    #expect(await waitUntil(10) { await hlSocket.closed })
    #expect(await okx.connects == 1)
    await merged.stop()
    await reader.value
    #expect(await okxSocket.closed)
  }
}

private extension Array where Element == String {
  func joined() -> String { joined(separator: "\n") }
}
