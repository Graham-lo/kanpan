import Foundation
import Testing
import KanpanCore
@testable import Kanpan

/// 深度审查 G 线走查：从搜索点进 1000PEPE / 1000SHIB，顶栏涨跌一行和右侧「额」一排「—」要等二十来秒。
/// 两处根因各一条：
/// 1. 报价簿裁掉一只时只裁了值，「什么时候收到的 / 问过」没裁，重新挂上后补价请求被当成「刚问过」拦掉；
/// 2. 报价簿那一格只有逐笔成交拼出来的价（没有 24h 统计）时，顶栏照用它，把图表行情流手里
///    那份带全套 24h 统计的 @ticker 挡在后面。
@MainActor
@Suite("顶栏不拿一格没有 24h 统计的价挡住手里现成的统计")
struct HeaderTickerFallbackTests {
  private let key = InstrumentID.canonical("1000PEPEUSDT")

  /// 图表行情流那份：带涨跌额、开盘价、成交额。
  private func feed() -> Ticker {
    Ticker(symbol: key, last: 0.00004, changePercent: 5, high: 0.000041, low: 0.000037,
           quoteVolume: 98_916_032, open24h: 0.0000380952, timeMs: 1_000, lastTradeID: 10,
           priceChange: 0.0000019048)
  }

  /// 逐笔成交拼出来的那格：只有价，统计全空。
  private func tradeOnly(last: Double, timeMs: Int64 = 2_000, tradeID: Int64 = 11) -> Ticker {
    Ticker(symbol: key, last: last, changePercent: .nan, high: .nan, low: .nan,
           quoteVolume: .nan, timeMs: timeMs, lastTradeID: tradeID)
  }

  @Test("报价簿只有逐笔价：用行情流的统计垫底、价取最新那笔")
  func tradeOnlyBookBorrowsFeedStatistics() throws {
    let shown = try #require(ChartSession.headerTicker(book: tradeOnly(last: 0.0000423), feed: feed(), seed: nil))
    #expect(shown.last == 0.0000423, "最新价应该是逐笔那一笔")
    #expect(shown.quoteVolume == 98_916_032, "「额」还是空的")
    let change = try #require(shown.priceChange, "涨跌额还是空的")
    #expect(abs(change - (0.0000019048 + 0.0000023)) < 1e-12)
    #expect(abs(shown.changePercent - (0.0000423 - 0.0000380952) / 0.0000380952 * 100) < 1e-6)
  }

  @Test("逐笔价比行情流那份还旧：直接用行情流那份")
  func staleTradeFallsBackToFeed() {
    let shown = ChartSession.headerTicker(book: tradeOnly(last: 0.00003, timeMs: 500, tradeID: 9), feed: feed(), seed: nil)
    #expect(shown == feed())
  }

  @Test("报价簿那格本身有统计：原样用，不掺行情流")
  func bookWithStatisticsWins() {
    var book = feed()
    book.last = 0.0000425; book.priceChange = 0.000004; book.quoteVolume = 1; book.timeMs = 3_000
    #expect(ChartSession.headerTicker(book: book, feed: feed(), seed: nil) == book)
  }

  @Test("行情流是别的品种：不借它的统计")
  func feedOfAnotherSymbolIsIgnored() {
    let other = Ticker(symbol: "BTCUSDT", last: 60_000, changePercent: 1, high: 1, low: 1, quoteVolume: 1,
                       timeMs: 1_000, priceChange: 600)
    let shown = ChartSession.headerTicker(book: tradeOnly(last: 0.0000423), feed: other, seed: nil)
    // 逐笔那格的统计是 NaN，整格比不了相等，逐项看。
    #expect(shown?.symbol == key)
    #expect(shown?.last == 0.0000423)
    #expect(shown?.priceChange == nil)
    #expect(shown?.timeMs == 2_000)
  }

  @Test("报价簿空着：先行情流、再种子")
  func emptyBookFallsBack() {
    let seed = Ticker(symbol: key, last: 0.00004, changePercent: 1, high: 1, low: 1, quoteVolume: 1)
    #expect(ChartSession.headerTicker(book: nil, feed: feed(), seed: seed) == feed())
    #expect(ChartSession.headerTicker(book: nil, feed: nil, seed: seed) == seed)
  }

  @Test("一只被裁出报价范围时，「什么时候收到的」跟着裁，重新挂上不会被当成刚收到过")
  func trimmedSymbolForgetsReceivedTime() {
    let book = QuoteBook()
    book.setChartSymbol("BTCUSDT")
    book.setFavorites([])
    book.setForeground(true)
    book.quoteNow(key)
    book.ingest([feed()])
    #expect(book.receivedTime(key) != nil, "收下的价没记时间，这条验不到东西")
    book.releaseNamed()
    #expect(book.receivedTime(key) == nil, "值裁掉了，收到时间还留着")
    book.shutdown()
  }
}
