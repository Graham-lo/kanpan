import Foundation
import KanpanCore

// Bybit 接进主力订单流：现货、U 本位永续 / 交割（linear）、币本位永续 / 交割（inverse），
// `orderbook.1000`（1000 档滑动窗口）+ `publicTrade`，流内 snapshot，序号严格 +1。
// 不分线路一律经 kanpan-api 中继 `/v1/market/ws/bybit?category=…`（国内连不上 Bybit）；
// 没有 kanpan-api 主机就不订。一个 category 一组连接，一条最多 12 本。
// 品种表查不到时保底订 U 本位永续 `<BASE>USDT`（按图上那只的写法，`1000PEPEUSDT` 价格口径一致）。

extension OrderFlowExchange {
  static let bybit = OrderFlowExchange(
    key: BybitVenue.id, displayName: BybitVenue.displayName, maxBooksPerConnection: BybitBooksAdapter.maxBooks,
    liquidationCode: 2,
    sequenceModel: { _, _ in BybitBooksAdapter.sequenceModel },
    snapshotInBand: { _ in true },
    fallback: { viewedBase, _, _ in
      [OrderFlowFallbackBook(product: .usdtPerp, instrument: viewedBase + BybitVenue.quote)]
    },
    makeAdapters: { books, context in
      guard !context.route.apiHosts.isEmpty else { return [] }
      var byCategory: [BybitBooksAdapter.Category: [DepthBook]] = [:]
      for book in books {
        byCategory[BybitBooksAdapter.category(book.venue.product, book.venue.notional), default: []].append(book)
      }
      return BybitBooksAdapter.Category.allCases.flatMap { category in
        chunks(byCategory[category] ?? [], BybitBooksAdapter.maxBooks).map {
          BybitBooksAdapter(category: category, books: $0, gateways: context.route.apiHosts, sockets: context.sockets)
        }
      }
    }
  )
}

extension BybitProvider: OrderFlowSourcing {
  public var orderFlowCatalog: OrderFlowCatalog {
    OrderFlowCatalog(route: endpoints.route, sockets: sockets, http: transport)
  }
}
