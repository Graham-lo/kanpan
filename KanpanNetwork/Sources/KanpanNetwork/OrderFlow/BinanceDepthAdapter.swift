import Foundation
import KanpanCore

/// 币安一条组合流上的几本簿：增量深度（`<sym>@depth@100ms`）+ 逐笔聚合成交（`@aggTrade`）+ REST 快照。
///
/// 按市场分三种连接（`Market`），一条连接最多 `maxBooks` 本（网关中继一条最多 8 路流，一本两路）：
///
/// - `um` U 本位（永续 + U 本位交割 `BTCUSDT_260925`）：U / u / pu 链。
/// - `cm` 币本位（永续 `BTCUSD_PERP` + 币本位交割 `BTCUSD_260925`）：同样 U / u / pu 链。
///   数量是张数（反向合约），名义美元 = 张数 × 面值，由 Core 的 `OrderFlowNotional.inverse` 算。
///
///   这两种**不分线路**，一律经 kanpan-api（`MarketRoute.apiHosts`，只有主机）：推送走中继
///   `/v1/market/ws/binance?streams=…`（服务端按产品分上游：币本位 dstream，U 本位深度 fstream `/public`、
///   成交 fstream `/market`），快照打 `GET /v1/market/depth?market=um|cm`（美国机房打 fapi 回 451，
///   由 kanpan-api 经 `www.binance.com` 取）。线路两档只管币安主行情，订单流要三家聚合、OKX 只能走中继，
///   合约这两种也跟着走同一台，免得一只币的几本簿一半直连一半中继。
/// - `spot` 现货：U / u 链（没有 pu）。不分线路一律直连 `data-stream.binance.vision`，快照打
///   `data-api.binance.vision/api/v3/depth`——网关中继只接币安合约的上游。
///
/// 走哪条、网关有哪几台，一律读提供者交进来的 `MarketRoute`（`RouteResolver` 定的那一份）。
/// 解码对应原项目 `bit-orderbook-binance/src/lib.rs:519 decode_depth_snapshot`、`:548 decode_depth_delta`。
public struct BinanceDepthAdapter: DepthFeedAdapter {
  public enum Market: String, Sendable, CaseIterable {
    case um, cm, spot

    var label: String {
      switch self {
      case .um: "U 本位"
      case .cm: "币本位"
      case .spot: "现货"
      }
    }

    public var sequenceModel: DepthSequenceModel { self == .spot ? .rangeOverlap : .previousFinalOverlap }
  }

  public static let snapshotLevels = 1000
  /// 一条连接最多几本簿：网关中继一条最多 8 路流（`market_relay.rs` MAX_STREAMS），一本 depth + aggTrade 两路。
  public static let maxBooks = 4
  static let gatewaySnapshotPath = "/v1/market/depth"
  static let relayPath = "/v1/market/ws/binance"
  static let spotStreamHost = "data-stream.binance.vision"
  static let spotRestHost = "data-api.binance.vision"

  public let market: Market
  public let books: [DepthBook]
  let hosts: BinanceHosts
  let route: MarketRoute
  let sockets: any WSSocketFactory
  let http: any HTTPTransport
  /// 报文里的 `s`（大写合约代号）→ 簿。
  private let byInstrument: [String: DepthBook]

  public init(market: Market, books: [DepthBook], hosts: BinanceHosts, route: MarketRoute,
              sockets: any WSSocketFactory = URLSessionSocketFactory(),
              http: any HTTPTransport = URLSessionTransport()) {
    self.market = market
    self.books = Array(books.prefix(Self.maxBooks))
    self.hosts = hosts; self.route = route; self.sockets = sockets; self.http = http
    var map: [String: DepthBook] = [:]
    for book in self.books { map[book.venue.instrument.uppercased()] = book }
    byInstrument = map
  }

  public var name: String { "币安\(market.label) \(books.map(\.venue.instrument).joined(separator: ","))" }

  var streams: [String] {
    books.flatMap { book -> [String] in
      let s = book.venue.instrument.lowercased()
      return ["\(s)@depth@100ms", "\(s)@aggTrade"]
    }
  }

  public var streamURLs: [URL] {
    switch market {
    case .spot:
      var c = URLComponents()
      c.scheme = "wss"; c.host = Self.spotStreamHost; c.path = "/stream"
      c.queryItems = [URLQueryItem(name: "streams", value: streams.joined(separator: "/"))]
      return c.url.map { [$0] } ?? []
    case .um, .cm:
      return Self.gatewayStreams(route.apiHosts, path: Self.relayPath, streams: streams)
    }
  }

  public func connect(candidate: Int) async throws -> any WSSocket {
    try await sockets.connect(to: try url(candidate))
  }

  // ------------------------------------------------------------------ 推送

  public func decode(_ text: String) -> [VenueMessage] {
    guard let outer = DepthWire.object(text) else { return [] }
    let body = (outer["data"] as? [String: Any]) ?? outer
    guard let symbol = (body["s"] as? String)?.uppercased(), let book = byInstrument[symbol] else { return [] }
    switch body["e"] as? String {
    case "depthUpdate":
      guard let first = DepthWire.integer(body["U"]), let final = DepthWire.integer(body["u"]),
            let bids = book.levels(body["b"]), let asks = book.levels(body["a"]) else { return [] }
      // 现货不带 pu；合约带。现货要是带了 pu 也不用它（rangeOverlap 不许有 pu）。
      let previous = market == .spot ? nil : DepthWire.integer(body["pu"])
      return [VenueMessage(book.id, .delta(BookDelta(firstUpdateID: first, finalUpdateID: final,
                                                    previousFinalUpdateID: previous, bids: bids, asks: asks,
                                                    eventTimeMs: DepthWire.integer(body["E"]) ?? 0)))]
    case "aggTrade":
      guard let p = DepthWire.number(body["p"]), let q = DepthWire.number(body["q"]),
            p > 0, q > 0, p.isFinite, q.isFinite else { return [] }
      // m = 买方是挂单方 → 这笔是主动卖，吃的是买盘。
      let hit: BookSide = (body["m"] as? Bool ?? false) ? .bid : .ask
      return [VenueMessage(book.id, .trade(book.trade(price: p, quantity: q, hit: hit,
                                                      timeMs: DepthWire.integer(body["T"]) ?? 0)))]
    default:
      return []
    }
  }

  // ------------------------------------------------------------------ 快照

  public func fetchSnapshot(venueID: String) async throws -> BookSnapshot {
    guard let book = books.first(where: { $0.id == venueID }) else {
      throw FeedError.badResponse("没有这本簿")
    }
    let symbol = book.venue.instrument.uppercased()
    let query = [URLQueryItem(name: "limit", value: String(Self.snapshotLevels)),
                 URLQueryItem(name: "symbol", value: symbol)]
    switch market {
    case .spot:
      return try await get(host: Self.spotRestHost, path: "/api/v3/depth", query: query, book: book)
    case .um, .cm:
      var lastError: Error = FeedError.badResponse("行情服务暂不可用")
      for host in route.apiHosts {
        do {
          return try await get(host: host, path: Self.gatewaySnapshotPath,
                               query: query + [URLQueryItem(name: "market", value: market.rawValue)], book: book)
        } catch is CancellationError {
          throw CancellationError()
        } catch let error as DepthSnapshotError where error.isClientError {
          throw error
        } catch {
          lastError = error
        }
      }
      throw lastError
    }
  }

  private func get(host: String, path: String, query: [URLQueryItem], book: DepthBook) async throws -> BookSnapshot {
    guard var c = URLComponents(string: "https://\(host)"), c.host != nil else {
      throw FeedError.badResponse("行情服务暂不可用")
    }
    c.path = path
    c.queryItems = query
    guard let url = c.url else { throw FeedError.badResponse("行情服务暂不可用") }
    return try Self.snapshot(try Self.body(await http.get(url, timeout: 10)), book: book)
  }

  static func body(_ reply: HTTPReply) throws -> Data {
    guard (200..<300).contains(reply.status) else {
      throw DepthSnapshotError(status: reply.status,
                               retryAfterMs: reply.header("Retry-After").flatMap(Double.init).map { $0 * 1000 })
    }
    return reply.body
  }

  static func snapshot(_ data: Data, book: DepthBook) throws -> BookSnapshot {
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let last = DepthWire.integer(obj["lastUpdateId"]),
          let bids = book.levels(obj["bids"]), let asks = book.levels(obj["asks"]) else {
      throw FeedError.badResponse("深度快照格式不对")
    }
    return BookSnapshot(lastUpdateID: last, requestedLevels: snapshotLevels, bids: bids, asks: asks,
                        eventTimeMs: DepthWire.integer(obj["E"]))
  }
}

/// 快照接口回了非 2xx。4xx（品种不认、参数不对）换主机也没用，直接报；5xx 带 Retry-After 时照办。
public struct DepthSnapshotError: Error, Sendable, Equatable {
  public var status: Int
  public var retryAfterMs: Double?
  public var isClientError: Bool { (400..<500).contains(status) && status != 429 && status != 418 }
  public init(status: Int, retryAfterMs: Double? = nil) { self.status = status; self.retryAfterMs = retryAfterMs }
}
