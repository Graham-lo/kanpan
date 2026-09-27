import Foundation
import Testing
import KanpanCore
@testable import Kanpan

// 收设置项 A 组（2026-09-28）：「涨跌幅起点」不再是设置项，报价簿按品种类型自己定口径——
// 加密看滚动 24 小时（交易所给的百分比），美股 / 贵金属 / 指数看 UTC 0 点（上海 08:00）起。
@MainActor
@Suite("报价簿按品种定涨跌幅口径")
struct QuoteBasisTests {
  private static func info(_ symbol: String, _ base: String, underlying: String) -> SymbolInfo {
    SymbolInfo(symbol: symbol, base: base, pricePrecision: 2, tickSize: 0.01,
               underlyingType: underlying, contractType: "PERPETUAL")
  }

  @Test("品种表里查得到的按类型走，查不到的按代号占位行判")
  func basisFollowsKind() {
    let book = QuoteBook()
    let table = [
      "BTCUSDT": Self.info("BTCUSDT", "BTC", underlying: "COIN"),
      "TSLAUSDT": Self.info("TSLAUSDT", "TSLA", underlying: "EQUITY"),
    ]
    book.symbolInfo = { table[InstrumentID(InstrumentID.canonical($0)).symbol] }
    #expect(book.basis(for: "BTCUSDT") == .rolling24h)
    #expect(book.basis(for: "TSLAUSDT") == .utcMidnight)
    #expect(book.basis(for: "XAUUSDT") == .utcMidnight, "品种表还没到时，黄金也认得出来")
    #expect(book.basis(for: "NEWCOINUSDT") == .rolling24h)
  }

  @Test("加密直接用交易所的滚动百分比；按日的品种没取到当天开盘价前留空，不拿滚动的数冒充")
  func presentedUsesPerSymbolBasis() {
    let book = QuoteBook()
    let table = [
      "BTCUSDT": Self.info("BTCUSDT", "BTC", underlying: "COIN"),
      "TSLAUSDT": Self.info("TSLAUSDT", "TSLA", underlying: "EQUITY"),
    ]
    book.symbolInfo = { table[InstrumentID(InstrumentID.canonical($0)).symbol] }
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let btc = Ticker(symbol: "BTCUSDT", last: 100, changePercent: 2.5, high: 101, low: 99, quoteVolume: 1, timeMs: now)
    let tsla = Ticker(symbol: "TSLAUSDT", last: 300, changePercent: 4, high: 301, low: 299, quoteVolume: 1, timeMs: now)
    #expect(book.presented(btc).changePercent == 2.5)
    #expect(book.presented(tsla).changePercent.isNaN)
  }
}
