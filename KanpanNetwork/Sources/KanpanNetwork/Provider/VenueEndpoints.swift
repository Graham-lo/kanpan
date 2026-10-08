import Foundation

/// 一家交易所的地址表：直连打哪儿、网关打哪儿。**不认识任何一家**——每家在自己的
/// `<X>Venue.swift` 里填一份 `VenueEndpoints.Spec`，再按用户选的线路（`MarketRoute`）
/// 取出「这条线路上按顺序试的主机 / URL」。
///
/// 两条线路（`docs/多交易所-接入指南.md` 第 1 节）：
/// - 直连：交易所自己的域名（`Spec.restHost` + `Spec.restPrefix`，推送 `Spec.directStreams`）。
/// - 网关：看盘自己的 kanpan-api。REST 一律是原样透传 `/v1/market/raw/<path>?source=<id>&…`，
///   主机取 `MarketRoute.apiHosts`；推送由那一家选（`Spec.gatewayStream`）：共享 hub
///   `/v1/market/stream?source=<id>`，或者帧原样转发的中继 `/v1/market/ws/<id>`，主机取 `MarketRoute.gateways`。
///
/// 透传与 hub 说的都是交易所原生的报文，所以一家的解码（`<X>DTO`）两条线路共用一份，差别只在 URL。
public struct VenueEndpoints: Sendable, Equatable {
  /// 网关线路上这一家的推送怎么走。
  public enum GatewayStream: Sendable, Equatable {
    /// kanpan-api 的共享 hub：`wss://<gateway>/v1/market/stream?source=<id>`，一条上游给所有手机共用，
    /// 订阅协议与交易所原生一致（Coinbase、美元指数）。
    case hub
    /// kanpan-api 的中继：`wss://<gateway>/v1/market/ws/<id>`，一条手机连接对一条上游连接，帧原样转发；
    /// 上行只放行白名单里的频道（OKX、Bybit、Hyperliquid）。
    case relay
    /// 网关上没有这一家的推送。
    case none
  }

  /// 一家交易所的出厂地址。只在 `<X>Venue.swift` 里写一次。
  public struct Spec: Sendable, Equatable {
    /// 网关上的来源名（`?source=` / 中继路径的最后一段），通常就是 `InstrumentID.venue`。
    public var source: String
    /// 直连 REST 主机（可带端口）。nil = 没有直连（两条线路都走 kanpan-api，美元指数这种）。
    public var restHost: String?
    /// 直连 REST 在交易所上的公共前缀，以 `/` 开头、以 `/` 结尾（`/api/v3/brokerage/market/`）。
    public var restPrefix: String
    /// 直连推送地址，按顺序试（同一个服务的主、备域名；不是不同的服务）。
    public var directStreams: [URL]
    public var gatewayStream: GatewayStream

    public init(source: String, restHost: String?, restPrefix: String = "/",
                directStreams: [URL], gatewayStream: GatewayStream) {
      self.source = source; self.restHost = restHost; self.restPrefix = restPrefix
      self.directStreams = directStreams; self.gatewayStream = gatewayStream
    }
  }

  /// 网关上的 REST 透传前缀、hub 与中继路径。`/market/*` 在 Caddy 上整段归 Python 网关，
  /// 所以 kanpan-api 的这几条都挂在 `/v1/market/` 下面。
  public static let rawPrefix = "/v1/market/raw/"
  public static let hubPath = "/v1/market/stream"
  public static let relayPrefix = "/v1/market/ws/"

  public let spec: Spec
  /// `RouteResolver` 定下的线路（直连 / 网关与网关表）。
  public let route: MarketRoute

  public init(_ spec: Spec, route: MarketRoute) { self.spec = spec; self.route = route }

  public var viaGateway: Bool { route.viaGateway || spec.restHost == nil }

  // ------------------------------------------------------------------ REST

  /// 这条线路上能试的 REST 主机，按顺序。直连只有交易所自己那一台；网关是 kanpan-api（`route.apiHosts`）。
  public var restHosts: [String] {
    if !viaGateway, let host = spec.restHost { return [host] }
    return route.apiHosts
  }

  /// `path` 是交易所 REST 前缀之后的那一截（`products/BTC-USD/candles`、`fapi/v1/klines`），不带开头的 `/`。
  /// 网关线路上 `source` 排在查询的第一个，其余照原样跟在后面。
  public func rest(_ path: String, query: [URLQueryItem] = [], host: String) -> URL? {
    guard var c = Self.origin("https", host) else { return nil }
    if viaGateway {
      c.path = Self.rawPrefix + path
      c.queryItems = [URLQueryItem(name: "source", value: spec.source)] + query
    } else {
      c.path = spec.restPrefix + path
      c.queryItems = query.isEmpty ? nil : query
    }
    return c.url
  }

  /// 同一条地址的「路径?查询」模板（小组件补价用：`{symbol}` 这类占位不能经 `URLComponents` 转义）。
  /// `query` 是已经拼好的查询串（不带 `?`），可以为空。
  public func restTemplate(_ path: String, query: String = "") -> String {
    if viaGateway {
      return Self.rawPrefix + path + "?source=" + spec.source + (query.isEmpty ? "" : "&" + query)
    }
    return spec.restPrefix + path + (query.isEmpty ? "" : "?" + query)
  }

  // ------------------------------------------------------------------ 推送

  /// 这条线路上的推送地址，按顺序试。网关线路按 `gatewayStream` 拼到网关表（`route.gateways`）的每一台上。
  /// hub 与中继都是 kanpan-api 的 `/v1/market/*`；线上网关表与 kanpan-api 主机是同一台（2026-10-02 起只有新加坡），
  /// 测试里网关表可以带端口、给主备两台，所以推送沿用网关表、REST 透传用 `apiHosts`，两张表各有各的用法。
  public var streams: [URL] { streams(query: []) }

  /// 带额外查询的推送地址（中继按类目分上游时用，例如 `category=linear`）。
  public func streams(query: [URLQueryItem]) -> [URL] {
    guard viaGateway else { return spec.directStreams }
    switch spec.gatewayStream {
    case .none: return []
    case .hub:
      return Self.gatewayURLs(route.gateways, path: Self.hubPath,
                              query: [URLQueryItem(name: "source", value: spec.source)] + query)
    case .relay:
      return relayStreams(query: query)
    }
  }

  /// 中继地址（不管线路：有的交易所国内直连不通，订单流两条线路都只走中继）。
  public func relayStreams(query: [URLQueryItem] = []) -> [URL] {
    Self.gatewayURLs(route.gateways, path: Self.relayPrefix + spec.source, query: query)
  }

  // ------------------------------------------------------------------ 小工具

  /// `host` 可能带端口（网关表允许 `host:port` 写法），不能直接塞进 `URLComponents.host`。
  /// 带路径、账号、查询的主机名不收。
  public static func origin(_ scheme: String, _ host: String) -> URLComponents? {
    guard let c = URLComponents(string: "\(scheme)://\(host)"), c.host?.isEmpty == false,
          c.user == nil, c.password == nil, c.path.isEmpty, c.query == nil, c.fragment == nil else { return nil }
    return c
  }

  static func gatewayURLs(_ hosts: [String], path: String, query: [URLQueryItem]) -> [URL] {
    hosts.compactMap { host in
      guard var c = origin("wss", host) else { return nil }
      c.path = path
      c.queryItems = query.isEmpty ? nil : query
      return c.url
    }
  }
}
