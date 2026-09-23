import Foundation
import KanpanCore

// 哪一家、哪条线路用哪个适配器。提供者文件本身不动，只在这里各补一个实现。
//
// | 提供者 | 线路 | 适配器 |
// |---|---|---|
// | 币安（直连，upstream = binance） | 直连 | `BinanceDepthAdapter`（快照打 fapi） |
// | 币安（网关，upstream = okx 替身） | 网关 | `OKXBooksAdapter` |
// | 币安本家经网关（upstream = binance, policy = gateway） | 网关 | `BinanceDepthAdapter`（快照打 kanpan-api） |
// | Coinbase | 恒直连 | `CoinbaseLevel2Adapter` |

extension BinanceProvider {
  public func orderFlowAdapter(symbol: String) -> (any DepthFeedAdapter)? {
    switch upstream {
    case .binance: BinanceDepthAdapter(symbol: symbol, hosts: hosts, policy: policy, sockets: sockets, http: http)
    case .okx: hosts.oiProxies.isEmpty ? nil : OKXBooksAdapter(symbol: symbol, hosts: hosts, sockets: sockets)
    }
  }
}

extension CoinbaseProvider {
  /// 网关的 Coinbase hub 不收 level2，所以不管用户选哪条线路，深度都走 Coinbase 直连。
  public func orderFlowAdapter(symbol: String) -> (any DepthFeedAdapter)? {
    CoinbaseLevel2Adapter(symbol: symbol, sockets: sockets)
  }
}
