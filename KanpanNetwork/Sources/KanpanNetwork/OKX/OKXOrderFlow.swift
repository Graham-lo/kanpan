import Foundation
import KanpanCore

// OKX 接进主力订单流：四种产品都有，`books`（400 档滑动窗口）+ `trades`，流内 snapshot，
// 不分线路一律经 kanpan-api 中继 `/v1/market/ws/okx`（国内连不上 OKX）；没有 kanpan-api 主机就不订。
// 品种表查不到时不保底（OKX 的合约代号、面值都要表里给）。

extension OrderFlowExchange {
  static let okx = OrderFlowExchange(
    key: OKXVenue.id, displayName: OKXVenue.displayName, maxBooksPerConnection: OKXBooksAdapter.maxBooks,
    liquidationCode: 1,
    sequenceModel: { _, _ in .previousFinalExact },
    snapshotInBand: { _ in true },
    makeAdapters: { books, context in
      guard !context.route.apiHosts.isEmpty else { return [] }
      return chunks(books, OKXBooksAdapter.maxBooks).map {
        OKXBooksAdapter(books: $0, gateways: context.route.apiHosts, sockets: context.sockets)
      }
    }
  )
}

/// 看 OKX 的永续时主力订单流照样五家聚合（按 base 币找各家的簿），连接与品种表都经 kanpan-api。
extension OKXProvider: OrderFlowSourcing {
  public var orderFlowCatalog: OrderFlowCatalog {
    OrderFlowCatalog(route: route, sockets: sockets, http: transport)
  }
}
