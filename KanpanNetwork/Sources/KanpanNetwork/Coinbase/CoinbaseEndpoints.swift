import Foundation
import KanpanCore

/// Coinbase Advanced Trade 公开行情的地址。
///
/// 直连打 Coinbase 自己的域名；网关线路走看盘自己的 `kanpan-api`
/// （`Backend/kanpan-api/src/venues/coinbase.rs`）：REST 原样透传，推送是一条上游
/// 共享给所有手机的 hub，报文格式和 Coinbase 原生的一字不差——所以下面的解析、
/// 订阅协议两条线路共用一份，差别只在 URL。
public struct CoinbaseEndpoints: Sendable, Equatable {
  public static let restHost = "api.coinbase.com"
  public static let streamHost = "advanced-trade-ws.coinbase.com"
  /// REST 在 Coinbase 上的公共前缀（公开行情，无鉴权）。
  static let restPrefix = "/api/v3/brokerage/market/"
  /// 网关上的透传前缀与推送入口（`kanpan-api`）。`/market/*` 在 Caddy 上归 Python 网关，
  /// 所以这里挂在 `/v1/market/` 下面。
  static let gatewayRestPrefix = "/v1/market/raw/"
  static let gatewayStreamPath = "/v1/market/stream"
  static let gatewaySource = "coinbase"

  public var policy: MarketRoutePolicy
  /// 看盘自己的网关，主在前、备在后。直连线路不用。
  public var gateways: [String]

  public init(policy: MarketRoutePolicy, gateways: [String]) {
    self.policy = policy; self.gateways = gateways
  }

  /// 这条线路上能试的 REST 主机，按顺序。直连只有 Coinbase 一家；网关按主、备。
  var restHosts: [String] { policy == .gateway ? gateways : [Self.restHost] }

  /// `path` 是 Coinbase 公开行情前缀之后的那一截（`products`、`products/BTC-USD/candles`）。
  func rest(_ path: String, query: [URLQueryItem] = [], host: String) -> URL? {
    guard var c = Self.origin("https", host) else { return nil }
    if policy == .gateway {
      c.path = Self.gatewayRestPrefix + path
      c.queryItems = [URLQueryItem(name: "source", value: Self.gatewaySource)] + query
    } else {
      c.path = Self.restPrefix + path
      c.queryItems = query.isEmpty ? nil : query
    }
    return c.url
  }

  /// 推送地址。网关线路上按主、备顺序给候选。
  var streams: [URL] {
    if policy == .gateway {
      return gateways.compactMap { host in
        guard var c = Self.origin("wss", host) else { return nil }
        c.path = Self.gatewayStreamPath
        c.queryItems = [URLQueryItem(name: "source", value: Self.gatewaySource)]
        return c.url
      }
    }
    return [URL(string: "wss://\(Self.streamHost)")!]
  }

  /// `host` 可能带端口（备用网关是 `…:8443`），不能直接塞进 `URLComponents.host`。
  static func origin(_ scheme: String, _ host: String) -> URLComponents? {
    URLComponents(string: "\(scheme)://\(host)")
  }

  /// Coinbase 的 `granularity`。只有这 9 档是原生的。
  static func granularity(_ interval: Interval) -> String? {
    switch interval {
    case .m1: "ONE_MINUTE"
    case .m5: "FIVE_MINUTE"
    case .m15: "FIFTEEN_MINUTE"
    case .m30: "THIRTY_MINUTE"
    case .h1: "ONE_HOUR"
    case .h2: "TWO_HOUR"
    case .h4: "FOUR_HOUR"
    case .h6: "SIX_HOUR"
    case .d1: "ONE_DAY"
    default: nil
    }
  }
}
