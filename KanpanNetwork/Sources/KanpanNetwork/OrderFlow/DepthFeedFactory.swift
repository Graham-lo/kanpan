import Foundation
import KanpanCore

// 哪家提供者能给主力订单流的接入。提供者文件本身不动，只在这里各补一个 `OrderFlowSourcing`。
// 线路与网关表一律是提供者手上那份 `MarketRoute`（`RouteResolver` 建提供者时交进去的），
// 适配器不另判线路。不管图上看的是哪家的品种，订的都是这只币在币安 / OKX / Coinbase 的全部簿
// （`OrderFlowCatalog`），提供者只决定「走哪条线路、用哪套 socket / HTTP」。
//
// | 提供者 | 币安合约 | 币安现货 | OKX | Coinbase |
// |---|---|---|---|---|
// | 币安（直连） | dstream 组合流 + fapi/dapi 快照 | 直连 binance.vision | 网关中继 | 直连 |
// | 币安（网关，本家或 OKX 替身） | 网关中继 + kanpan-api 快照 | 直连 binance.vision | 网关中继 | 直连 |
// | Coinbase | 同它那条线路 | 同上 | 同上 | 直连 |

extension BinanceProvider: OrderFlowSourcing {
  public var orderFlowCatalog: OrderFlowCatalog {
    OrderFlowCatalog(route: route, binanceHosts: hosts, sockets: sockets, http: http)
  }
}

extension CoinbaseProvider: OrderFlowSourcing {
  public var orderFlowCatalog: OrderFlowCatalog {
    OrderFlowCatalog(route: endpoints.route, sockets: sockets, http: transport)
  }
}
