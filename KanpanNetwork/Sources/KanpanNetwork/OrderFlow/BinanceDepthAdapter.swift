import Foundation
import KanpanCore

/// 币安 U 本位永续的增量深度（`<sym>@depth@100ms`，U / u / pu 链）+ REST 快照。
///
/// - 直连：推送走 `hosts.stream` 的组合流（默认 `dstream.binance.me`，2026-09-24 实测同一条连接上
///   `@depth@100ms` 与 `@aggTrade` 都发），快照打 `hosts.fapi` 的 `/fapi/v1/depth?limit=1000`。
/// - 网关：推送走网关 `/market/stream`（stream_hub 经币安 `/public` 上游逐帧转发，不合并），主备两台；
///   成交同样订 `@aggTrade`（网关原样转发）。快照打 kanpan-api `GET /v1/market/depth`
///   （美国机房打 fapi 回 451，由 kanpan-api 经 `www.binance.com` 取），只有主节点有，按网关表逐台试。
///
/// 解码对应原项目 `bit-orderbook-binance/src/lib.rs:519 decode_depth_snapshot`、`:548 decode_depth_delta`。
public struct BinanceDepthAdapter: DepthFeedAdapter {
  public static let snapshotLevels = 1000
  static let gatewaySnapshotPath = "/v1/market/depth"

  public let symbol: String
  public var upstream: String { BinanceUpstream.binance.rawValue }
  public var sequenceModel: DepthSequenceModel { .previousFinalOverlap }
  public var snapshotInBand: Bool { false }

  let hosts: BinanceHosts
  let policy: MarketRoutePolicy
  let sockets: any WSSocketFactory
  let http: any HTTPTransport

  public init(symbol: String, hosts: BinanceHosts, policy: MarketRoutePolicy,
              sockets: any WSSocketFactory = URLSessionSocketFactory(),
              http: any HTTPTransport = URLSessionTransport()) {
    self.symbol = InstrumentID(symbol).symbol.uppercased()
    self.hosts = hosts; self.policy = policy; self.sockets = sockets; self.http = http
  }

  var depthStream: String { "\(symbol.lowercased())@depth@100ms" }
  var tradeStream: String { BinanceHosts.aggTradeStream(symbol: symbol) }
  var streams: [String] { [depthStream, tradeStream] }

  public var streamURLs: [URL] {
    policy == .direct ? [hosts.combinedStream(streams)]
                      : Self.gatewayStreams(hosts, path: "/market/stream", streams: streams)
  }

  public func connect(candidate: Int) async throws -> any WSSocket {
    try await sockets.connect(to: try url(candidate))
  }

  // ------------------------------------------------------------------ 推送

  public func decode(_ text: String) -> [DepthMessage] {
    guard let outer = DepthWire.object(text) else { return [] }
    let body = (outer["data"] as? [String: Any]) ?? outer
    switch body["e"] as? String {
    case "depthUpdate":
      guard (body["s"] as? String)?.uppercased() == symbol,
            let first = DepthWire.integer(body["U"]), let final = DepthWire.integer(body["u"]),
            let bids = DepthWire.levels(body["b"]), let asks = DepthWire.levels(body["a"]) else { return [] }
      return [.delta(BookDelta(firstUpdateID: first, finalUpdateID: final,
                               previousFinalUpdateID: DepthWire.integer(body["pu"]),
                               bids: bids, asks: asks, eventTimeMs: DepthWire.integer(body["E"]) ?? 0))]
    case "aggTrade":
      guard (body["s"] as? String)?.uppercased() == symbol,
            let p = DepthWire.number(body["p"]), let q = DepthWire.number(body["q"]), p > 0, q > 0 else { return [] }
      // m = 买方是挂单方 → 这笔是主动卖，吃的是买盘。
      let hit: BookSide = (body["m"] as? Bool ?? false) ? .bid : .ask
      return [.trade(OrderFlowTrade(price: p, quantity: q, hitSide: hit,
                                    timeMs: DepthWire.integer(body["T"]) ?? 0))]
    default:
      return []
    }
  }

  // ------------------------------------------------------------------ 快照

  public func fetchSnapshot() async throws -> BookSnapshot {
    switch policy {
    case .direct:
      let url = hosts.url("/fapi/v1/depth", ["symbol": symbol, "limit": String(Self.snapshotLevels)])
      return try Self.snapshot(try await Self.body(http.get(url, timeout: 10)))
    case .gateway:
      var lastError: Error = FeedError.badResponse("行情服务暂不可用")
      for host in hosts.oiProxies {
        guard var c = URLComponents(string: "https://\(host)") else { continue }
        c.path = Self.gatewaySnapshotPath
        c.queryItems = [URLQueryItem(name: "symbol", value: symbol),
                        URLQueryItem(name: "limit", value: String(Self.snapshotLevels))]
        guard let url = c.url else { continue }
        do {
          return try Self.snapshot(try await Self.body(http.get(url, timeout: 10)))
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

  static func body(_ reply: HTTPReply) throws -> Data {
    guard (200..<300).contains(reply.status) else {
      throw DepthSnapshotError(status: reply.status,
                               retryAfterMs: reply.header("Retry-After").flatMap(Double.init).map { $0 * 1000 })
    }
    return reply.body
  }

  static func snapshot(_ data: Data) throws -> BookSnapshot {
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let last = DepthWire.integer(obj["lastUpdateId"]),
          let bids = DepthWire.levels(obj["bids"]), let asks = DepthWire.levels(obj["asks"]) else {
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
