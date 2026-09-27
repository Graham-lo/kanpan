import Foundation
import KanpanNetwork

/// 哪几家交易所能接只读账户、各自怎么造 provider。
///
/// 这是 `Exchange/` 里唯一允许点交易所名字的非交易所文件（`Tools/check-venue-isolation.sh` 的登记表）；
/// 同步、凭据、协议这些共用层只认 `venue` / `market` 字符串。以后接别家：在 `Exchange/<交易所>/` 写一个
/// `ExchangeAccountProvider`，在这里加一行。
enum ExchangeAccountRegistry {
  struct Venue: Sendable, Hashable {
    let venue: String
    let market: String
    /// 界面上的名字。
    let displayName: String
  }

  /// 第一期只有币安 U 本位合约。
  static let binanceFutures = Venue(venue: BinanceProvider.venue, market: BinanceProvider.market,
                                    displayName: "币安合约")

  static let supported: [Venue] = [binanceFutures]

  /// 拿一把 Key 造出对应交易所的只读账户。
  static func provider(for venue: Venue, credentials: ExchangeCredentials,
                       http: any ExchangeHTTP = URLSessionExchangeHTTP()) -> (any ExchangeAccountProvider)? {
    switch venue {
    case binanceFutures: BinanceFuturesAccount(credentials: credentials, http: http)
    default: nil
    }
  }
}
