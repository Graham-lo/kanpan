import Foundation
import Testing
@testable import KanpanNetwork
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
