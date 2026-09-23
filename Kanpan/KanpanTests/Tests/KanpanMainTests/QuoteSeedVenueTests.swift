import Foundation
import Testing
import KanpanCore
import KanpanNetwork
@testable import KanpanMain

// 全市场种子按交易所分份、按上游认主：一家的整表换掉只换这一家那份，
// 别家的品种、别的上游的数一概不收（「不混源」）。
@MainActor
@Suite("全市场种子不混源")
struct QuoteSeedVenueTests {

  private func row(_ key: String, _ last: Double) -> Ticker {
    Ticker(symbol: key, last: last, changePercent: 1, high: last, low: last,
           quoteVolume: 1_000, open24h: last, timeMs: 1_700_000_000_000, lastTradeID: 1)
  }

  private func upstream(_ venue: String) -> String {
    RouteResolver(policy: .direct, endpoints: .default)
      .provider(venue: venue).capabilities.upstream
  }

  @Test("一家换整表不动别家那份，别家的品种和别的上游都不收")
  func seedsStayPerVenue() throws {
    let venues = VenueRegistry.all.map(\.id)
    try #require(venues.count >= 2)
    let a = venues[0], b = venues[1]
    let keyA = "\(a)/x/AAA", keyB = "\(b)/x/BBB"
    let book = QuoteBook()

    book.seed([row(keyB, 2)], upstream: upstream(b), venue: b)
    book.seed([row(keyA, 1), row("\(b)/x/SNEAK", 9)], upstream: upstream(a), venue: a)
    #expect(book.seeded(keyA)?.last == 1)
    #expect(book.seeded(keyB)?.last == 2, "换 \(a) 那份把 \(b) 的种子冲掉了")
    #expect(book.seeded("\(b)/x/SNEAK") == nil, "\(a) 那份整表里夹带的 \(b) 品种被收了")

    book.seed([row(keyA, 5)], upstream: "not-\(upstream(a))", venue: a)
    #expect(book.seeded(keyA)?.last == 1, "别的上游供的数垫进来了")

    book.seed([row(keyA, 0), row("\(a)/x/CCC", 3)], upstream: upstream(a), venue: a)
    #expect(book.seeded(keyA) == nil, "价格为 0 的行不该当种子")
    #expect(book.seeded("\(a)/x/CCC")?.last == 3)
    #expect(book.seeded(keyB)?.last == 2)
    book.shutdown()
  }
}
