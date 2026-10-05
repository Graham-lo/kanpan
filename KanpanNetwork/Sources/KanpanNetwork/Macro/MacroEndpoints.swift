import Foundation
import KanpanCore

/// 美元指数的地址。
///
/// **唯一来源是看盘自己的 `kanpan-api`**（服务端 `venues::macro_index` 自己采价、存 K 线、推送）：
/// 没有「直连某家交易所」这回事，所以用户选直连还是网关都一样走 `kanpan-api` 的主机
/// （`MarketRoute.apiHosts`，和线路无关）。也不拿别的来源掺着用——币安、OKX 都没有这只，
/// 混进来的数口径对不上（收盘时刻、交易时段都不一样）。
///
/// - REST：`/v1/market/raw/{instruments,klines,ticker/24hr}?source=macro`
/// - 推送：`wss://…/v1/market/stream?source=macro`，连上之后按币安的
///   `SUBSCRIBE` / `UNSUBSCRIBE` 控制帧订 `dxy@ticker`、`dxy@kline_<周期>`。
public struct MacroEndpoints: Sendable, Equatable {
  static let restPrefix = "/v1/market/raw/"
  static let streamPath = "/v1/market/stream"
  static let source = "macro"

  public var route: MarketRoute
  public init(route: MarketRoute) { self.route = route }

  /// 能试的主机，按顺序。两条线路相同。
  var hosts: [String] { route.apiHosts }

  /// `path` 是 `/v1/market/raw/` 之后那一截（`klines`、`ticker/24hr`）。
  func rest(_ path: String, query: [URLQueryItem] = [], host: String) -> URL? {
    guard var c = URLComponents(string: "https://\(host)") else { return nil }
    c.path = Self.restPrefix + path
    c.queryItems = [URLQueryItem(name: "source", value: Self.source)] + query
    return c.url
  }

  var streams: [URL] {
    hosts.compactMap { host in
      guard var c = URLComponents(string: "wss://\(host)") else { return nil }
      c.path = Self.streamPath
      c.queryItems = [URLQueryItem(name: "source", value: Self.source)]
      return c.url
    }
  }
}
