import Foundation
import KanpanCore

// Hyperliquid 接进主力订单流：只有 USDC 永续（按 U 本位永续记），`l2Book`（nSigFigs 4，每侧 20 档）+ `trades`。
// `l2Book` 每一帧都是整本簿、没有序号 → `snapshotOnly`。不分线路一律经 kanpan-api 中继
// `/v1/market/ws/hyperliquid`；没有 kanpan-api 主机就不订。一条连接最多 8 本。
// 合约代号就是币名（`BTC`、`kPEPE`），价格缩放由服务端品种表给（`kPEPE` 1000），客户端照用。
// 品种表查不到时保底订 `<BASE>`（去掉缩放前缀的币名，价格乘回图上的缩放）。

extension OrderFlowExchange {
  static let hyperliquid = OrderFlowExchange(
    key: HyperliquidVenue.id, displayName: HyperliquidVenue.displayName, maxBooksPerConnection: HyperliquidBookAdapter.maxBooks,
    liquidationCode: nil,
    sequenceModel: { _, _ in .snapshotOnly },
    snapshotInBand: { _ in true },
    fallback: { _, base, chartScale in
      [OrderFlowFallbackBook(product: .usdtPerp, instrument: base, priceFactor: chartScale)]
    },
    makeAdapters: { books, context in
      guard !context.route.apiHosts.isEmpty else { return [] }
      return chunks(books.filter { $0.venue.product == .usdtPerp }, HyperliquidBookAdapter.maxBooks).map {
        HyperliquidBookAdapter(books: $0, gateways: context.route.apiHosts, sockets: context.sockets)
      }
    }
  )
}

extension HyperliquidProvider: OrderFlowSourcing {
  public var orderFlowCatalog: OrderFlowCatalog {
    OrderFlowCatalog(route: endpoints.route, sockets: sockets, http: transport)
  }
}
