import Foundation
import Testing
import KanpanCore
@testable import KanpanNetwork
import KanpanNetworkTestSupport

/// 网关线路上替身（OKX）自己的 24h 行情与持仓量历史：走 kanpan-api，不落到币安本家，
/// 数全是替身自己的。
@Suite("网关替身：24h 行情与持仓量历史")
struct GatewaySubstituteTests {

  @Test("替身推送帧不带涨跌额时，用同一帧的最新价减开盘价补上；成交额留空")
  func okxStreamFrameFillsPriceChange() throws {
    let frame = #"{"e":"24hrTicker","E":1790163254373,"s":"BTCUSDT","o":"85896.9","c":"85509.7","P":"-0.45","h":"87245","l":"85406","v":"73948.48","q":"","C":1790163254373}"#
    guard case .ticker(let t) = try JSONDecoder().decode(StreamPayload.self, from: Data(frame.utf8)) else {
      Issue.record("不是行情帧"); return
    }
    #expect(abs((t.priceChange ?? .nan) - (-387.2)) < 1e-6)
    #expect(t.open24h == 85896.9)
    #expect(t.quoteVolume.isNaN)
    #expect(t.amplitude24h != nil)
  }

  @Test("替身 24h 行情问 kanpan-api（主 503 换备），带 USDT 成交额；不打到币安本家")
  func substituteTickerAsksKanpanAPI() async throws {
    let pacer = StepPacer()
    let binance = FakeServer { _ in json("{}", status: 500) }
    let rest = BinanceREST(transport: FakeTransport(binance),
                           limiter: RateLimiter(pacer: pacer, minGapMs: 0), pacer: pacer)
    let gateway = FakeServer { url in
      if url.host == "gw-a.example" { return json("{}", status: 503) }
      return json(#"{"ok":true,"data":{"source":"okx","ticker":{"symbol":"BTCUSDT","lastPrice":"85509.7","openPrice":"85896.9","highPrice":"87245","lowPrice":"85406","priceChange":"-387.2","priceChangePercent":"-0.451","volume":"73948.4807","quoteVolume":"6378415174.86","closeTime":1790163254373}}}"#)
    }
    let hosts = BinanceHosts(oiProxy: "gw-a.example", oiProxyFallbacks: ["gw-b.example:8443"])
    let okx = BinanceProvider(upstream: .okx, hosts: hosts, policy: .gateway, rest: rest,
                              http: FakeTransport(gateway))
    let t = try await okx.ticker24h(symbol: "BTCUSDT", timeout: 5)
    #expect(t.quoteVolume == 6_378_415_174.86)
    #expect(t.priceChange == -387.2)
    #expect(t.open24h == 85896.9)
    #expect(t.timeMs == 1_790_163_254_373)
    let asked = await gateway.hits.map(\.url)
    #expect(asked.map { $0.host ?? "" } == ["gw-a.example", "gw-b.example"])
    #expect(asked.allSatisfy { $0.path == "/v1/market/ticker" && $0.query == "source=okx&symbol=BTCUSDT" })
    #expect(await binance.hits.isEmpty)
  }

  @Test("网关替身行情来源或品种对不上就不收")
  func substituteTickerRejectsForeignRows() {
    let foreign = Data(#"{"data":{"source":"binance","ticker":{"symbol":"BTCUSDT","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1"}}}"#.utf8)
    #expect(throws: (any Error).self) { try GatewayTicker.decode(foreign, source: "okx", symbol: "BTCUSDT") }
    let other = Data(#"{"data":{"source":"okx","ticker":{"symbol":"ETHUSDT","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1"}}}"#.utf8)
    #expect(throws: (any Error).self) { try GatewayTicker.decode(other, source: "okx", symbol: "BTCUSDT") }
  }

  @Test("替身持仓量历史问 kanpan-api：币数、升序，参数照币安那套，4xx 不换主机")
  func substituteOIHistory() async throws {
    let pacer = StepPacer()
    let binance = FakeServer { _ in json("[]", status: 500) }
    let rest = BinanceREST(transport: FakeTransport(binance),
                           limiter: RateLimiter(pacer: pacer, minGapMs: 0), pacer: pacer)
    let gateway = FakeServer { url in
      if url.query?.contains("period=3m") == true { return json(#"{"ok":false,"error":{"code":"unsupported_period"}}"#, status: 400) }
      return json(#"{"ok":true,"data":{"source":"okx","symbol":"BTCUSDT","period":"1h","rows":[[1790150400000,26000.5,2.2e9],[1790154000000,26100.25,null],[1790157600000,null,1]]}}"#)
    }
    let hosts = BinanceHosts(oiProxy: "gw-a.example", oiProxyFallbacks: ["gw-b.example:8443"])
    let okx = BinanceProvider(upstream: .okx, hosts: hosts, policy: .gateway, rest: rest,
                              http: FakeTransport(gateway))
    let points = try await okx.openInterestHist(symbol: "binance/usd_m/BTCUSDT", period: "1h", limit: 500,
                                                startTime: nil, endTime: 1_790_160_000_000)
    #expect(points == [OIPoint(time: 1_790_150_400_000, value: 26000.5), OIPoint(time: 1_790_154_000_000, value: 26100.25)])
    let first = await gateway.hits.first?.url
    #expect(first?.host == "gw-a.example" && first?.path == "/v1/market/open-interest/history")
    #expect(first?.query == "source=okx&symbol=BTCUSDT&period=1h&limit=500&endTime=1790160000000")
    await #expect(throws: (any Error).self) {
      _ = try await okx.openInterestHist(symbol: "BTCUSDT", period: "3m", limit: 10, startTime: nil, endTime: nil)
    }
    #expect(await gateway.hits.count == 2)
    #expect(await binance.hits.isEmpty)
  }

  @Test("持仓量历史来源不符整页不收")
  func substituteOIHistoryRejectsForeignSource() {
    let body = Data(#"{"data":{"source":"binance","symbol":"BTCUSDT","rows":[[1,2,3]]}}"#.utf8)
    #expect(throws: (any Error).self) { try GatewayOIHistory.decode(body, source: "okx", symbol: "BTCUSDT") }
  }
}
