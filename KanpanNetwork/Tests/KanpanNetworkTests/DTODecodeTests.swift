import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 币安 REST / WS 报文的解码：数字既可以是字符串也可以是数字、坏 OHLC 在进指标之前就被拒、
// REST 与 WS 两边的交易所时钟对得上。
@Suite("币安报文解码")
struct DTODecodeTests {
  @Test("kline 行数字可以是字符串也可以是数字")
  func klineRowDecode() throws {
    let a = Data(#"[[1700000000000,"1.5","2.5","0.5","2.0","10.0",1700003599999,"1",1,"1","1","0"]]"#.utf8)
    let b = Data(#"[[1700000000000,1.5,2.5,0.5,2.0,10.0,1700003599999,1,1,1,1,0]]"#.utf8)
    let ra = try JSONDecoder().decode([KlineRow].self, from: a)
    let rb = try JSONDecoder().decode([KlineRow].self, from: b)
    #expect(ra[0].bar == rb[0].bar)
    #expect(ra[0].bar == Bar(openTime: 1700000000000, open: 1.5, high: 2.5, low: 0.5, close: 2.0, volume: 10.0))
  }

  @Test func invalidOHLCVIsRejectedBeforeIndicators() throws {
    let bad = Data("[[60000,\"100\",\"99\",\"90\",\"105\",\"1\",119999]]".utf8)
    #expect(throws: FeedError.self) { try JSONDecoder().decode([KlineRow].self, from: bad) }
  }

  @Test func decoderRetainsExchangeClock() throws {
    let rest = try JSONDecoder().decode(Ticker24hDTO.self, from: Data(#"{"symbol":"BTCUSDT","lastPrice":"105","priceChangePercent":"1","highPrice":"110","lowPrice":"90","quoteVolume":"1000","closeTime":2000,"lastId":30}"#.utf8)).ticker
    let ws = try JSONDecoder().decode(StreamPayload.self, from: Data(#"{"e":"24hrTicker","s":"BTCUSDT","c":"105","P":"1","h":"110","l":"90","q":"1000","C":2000,"L":30}"#.utf8))
    guard case .ticker(let ticker) = ws else { Issue.record("Expected ticker"); return }
    #expect(ticker.timeMs == rest.timeMs)
    #expect(ticker.lastTradeID == rest.lastTradeID)
    #expect(!LatestQuote.accepts(rest, after: ticker))
  }
}

// ---------------------------------------------------------------- 资金费率

@Suite("单品种资金费率")
struct PremiumIndexTests {

  @Test("premiumIndex 拿得到费率和下一次结算时刻")
  func decodesFundingSnapshot() async throws {
    let pacer = StepPacer()
    let server = FakeServer { _ in
      json("""
      {"symbol":"BTCUSDT","markPrice":"80000.00","indexPrice":"80010.00",
       "lastFundingRate":"0.00010000","nextFundingTime":1700000000000,"time":1699990000000}
      """)
    }
    let rest = BinanceREST(transport: FakeTransport(server),
                           limiter: RateLimiter(pacer: pacer, minGapMs: 0), pacer: pacer)
    let snapshot = try await rest.funding(symbol: "BTCUSDT")
    #expect(snapshot.rate == 0.0001)
    #expect(snapshot.nextFundingTimeMs == 1_700_000_000_000)
    let path = await server.hits.first?.url
    #expect(path?.path == "/fapi/v1/premiumIndex")
    #expect(path?.query == "symbol=BTCUSDT")
  }

  /// 没有资金费率那回事的品种：`nextFundingTime` 是 0，当作「没有下一次」，
  /// 费率本身照旧算数。
  @Test("结算时刻是 0 就当没有")
  func zeroNextFundingTimeBecomesNil() async throws {
    let pacer = StepPacer()
    let server = FakeServer { _ in
      json(#"{"symbol":"XUSDT","lastFundingRate":"-0.00023000","nextFundingTime":0}"#)
    }
    let rest = BinanceREST(transport: FakeTransport(server),
                           limiter: RateLimiter(pacer: pacer, minGapMs: 0), pacer: pacer)
    let snapshot = try await rest.funding(symbol: "XUSDT")
    #expect(snapshot.rate == -0.00023)
    #expect(snapshot.nextFundingTimeMs == nil)
  }
}
