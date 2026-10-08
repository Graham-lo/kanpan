import Foundation
import KanpanCore

// 币安接进主力订单流：注册表条目 + 提供者给出品种表入口。
//
// | 分组 | 产品 | 增量 | 快照 | 连接 |
// |---|---|---|---|---|
// | U 本位 | U 本位永续、U 本位交割 | `@depth@100ms` + `@aggTrade` | kanpan-api `/v1/market/depth?market=um` | 恒走中继 `/v1/market/ws/binance` |
// | 币本位 | 币本位永续、币本位交割 | 同上 | kanpan-api `market=cm` | 恒走中继（服务端连 dstream） |
// | 现货 | 现货 | 同上（无 pu） | REST data-api.binance.vision | 恒直连 data-stream.binance.vision |

extension OrderFlowExchange {
  static let binance = OrderFlowExchange(
    key: "binance", displayName: "币安", maxBooksPerConnection: BinanceDepthAdapter.maxBooks,
    liquidationCode: 0,
    sequenceModel: { product, notional in BinanceDepthAdapter.market(product, notional).sequenceModel },
    snapshotInBand: { _ in false },
    fallback: { viewedBase, base, chartScale in
      // U 本位永续按图上那只的写法（`1000PEPEUSDT`，价格口径一致）；现货没有缩放前缀，价格要乘回去。
      [OrderFlowFallbackBook(product: .usdtPerp, instrument: viewedBase + "USDT"),
       OrderFlowFallbackBook(product: .spot, instrument: base + "USDT", priceFactor: chartScale)]
    },
    makeAdapters: { books, context in
      var byMarket: [BinanceDepthAdapter.Market: [DepthBook]] = [:]
      for book in books { byMarket[BinanceDepthAdapter.market(book.venue.product, book.venue.notional), default: []].append(book) }
      return BinanceDepthAdapter.Market.allCases.flatMap { market in
        chunks(byMarket[market] ?? [], BinanceDepthAdapter.maxBooks).map {
          BinanceDepthAdapter(market: market, books: $0, route: context.route, sockets: context.sockets, http: context.http)
        }
      }
    }
  )
}

extension BinanceDepthAdapter {
  /// 一本簿归哪种连接：交割按面值口径分（反向是币本位交割，正向是 U 本位交割）。
  static func market(_ product: OrderFlowProduct, _ notional: OrderFlowNotional) -> Market {
    switch product {
    case .spot: .spot
    case .usdtPerp: .um
    case .coinPerp: .cm
    case .delivery:
      if case .inverse = notional { .cm } else { .um }
    }
  }
}

extension BinanceProvider: OrderFlowSourcing {
  public var orderFlowCatalog: OrderFlowCatalog {
    OrderFlowCatalog(route: route, sockets: sockets, http: http)
  }
}
