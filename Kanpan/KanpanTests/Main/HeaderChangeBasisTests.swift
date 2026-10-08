import Foundation
import Testing
import KanpanCore
import KanpanNetwork
@testable import Kanpan

/// 审查 A 线：顶栏、横屏那行小字、分享成片、「创建提醒」页的品种卡，涨跌幅读同一个数——
/// 交易所 24 小时口径（和涨跌额成对）。原来后三处读的是自选表口径，美股这类按 UTC 0 点
/// 算的品种在当天开盘价到之前是空的，到了之后又和顶栏不是一个数。
@MainActor
@Suite("图上那只的涨跌幅只有一个口径")
struct HeaderChangeBasisTests {
  @Test("美股：自选表口径还空着时，顶栏那一个涨跌幅照样是交易所 24 小时的数")
  func equityUsesRollingLikeHeader() {
    let session = ChartSession(symbol: "TSLAUSDT")
    let key = session.market.symbol
    session.quotes.symbolInfo = { _ in
      SymbolInfo(symbol: key, base: "TSLA", pricePrecision: 2, tickSize: 0.01,
                 underlyingType: "EQUITY", contractType: "PERPETUAL")
    }
    let venue = VenueRegistry.descriptor(forSymbol: key).id
    // 按当前线路取上游（出厂 2026-10-08 起是网关）：`QuoteBook.seed` 只收 `RouteResolver.current` 那家的数
    let upstream = RouteResolver(policy: MarketRoutePolicyStore.current, endpoints: .default).provider(venue: venue).capabilities.upstream
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let row = Ticker(symbol: key, last: 300, changePercent: 4, high: 301, low: 299, quoteVolume: 1, timeMs: now)
    session.quotes.seed([row], upstream: upstream, venue: venue)

    #expect(session.rollingTicker?.changePercent == 4, "种子没垫上，这条验不到东西")
    #expect(session.quotes.presented(row).changePercent.isNaN, "自选表口径这时应该还是空的")
    #expect(session.changePercent == 4, "横屏小字 / 成片 / 提醒页读到的和顶栏不是一个数")
    session.quotes.shutdown()
  }
}
