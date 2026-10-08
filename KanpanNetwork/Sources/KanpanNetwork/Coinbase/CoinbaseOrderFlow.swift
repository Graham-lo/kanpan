import Foundation
import KanpanCore

// Coinbase 接进主力订单流：只有现货（USD 计价），`level2` + `market_trades`，流内 snapshot，恒直连；
// `sequence_num` 是整条连接一个序号，所以一本簿一条连接。

extension OrderFlowExchange {
  static let coinbase = OrderFlowExchange(
    key: "coinbase", displayName: "Coinbase", maxBooksPerConnection: 1,
    sequenceModel: { _, _ in .strictIncrementing },
    snapshotInBand: { _ in true },
    fallback: { _, base, chartScale in
      [OrderFlowFallbackBook(product: .spot, instrument: base + "-USD", priceFactor: chartScale)]
    },
    makeAdapters: { books, context in
      books.filter { $0.venue.product == .spot }.map { CoinbaseLevel2Adapter(book: $0, sockets: context.sockets) }
    }
  )
}

extension CoinbaseProvider: OrderFlowSourcing {
  public var orderFlowCatalog: OrderFlowCatalog {
    OrderFlowCatalog(route: endpoints.route, sockets: sockets, http: transport)
  }
}
