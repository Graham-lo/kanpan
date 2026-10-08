import Foundation
import KanpanCore

/// 币安 REST 的线路：直连就只打币安自己的域名，网关就只打 kanpan-api 的原样透传。
/// 一笔请求永远不换交易所、不换线路（2026-10-08 起网关档不再有 OKX 替身，新加坡那台直通币安）。
///
/// 网关档把 `https://fapi.binance.com/<path>?<query>`（`futures/data/*` 与 `dapi.binance.com` 同理）
/// 改写成 `https://<kanpan-api>/v1/market/raw/<path>?<query>&source=binance`（服务端
/// `Backend/kanpan-api/src/venues/binance/mod.rs`，网页版同一条）：状态码、正文、`Retry-After` 原样回，
/// 不包信封，所以 `BinanceREST` 的解析与限流两条线路共用一份。
/// - kanpan-api 主机（`MarketRoute.apiHosts`）按顺序试：连不上 / 5xx 换下一台；
/// - 4xx（含 429 / 418）原样交回 `BinanceREST`：429 由它按 `Retry-After` 进网关档那把限流器冷却；
/// - 透传白名单之外的地址（`data.binance.vision` 的归档这类）在网关档没有路线，直接报错，不偷偷直连。
public actor MarketRESTTransport: HTTPTransport {
  private let log: FeedLog
  private let transport: any HTTPTransport
  /// 行情线路（`RouteResolver` 给的决策）：直连就只直连，网关就只网关。
  private var route: MarketRoute

  /// 透传的来源名与前缀（`/v1/market/raw/<path>?source=binance`）。
  static let source = BinanceProvider.venue
  /// 服务端透传放行的路径（与 `venues/binance/mod.rs` 的 `upstream_of` 同一张表）。
  static let rawPaths: Set<String> = [
    "fapi/v1/exchangeInfo", "fapi/v1/ticker/24hr", "fapi/v1/premiumIndex", "fapi/v1/klines",
    "fapi/v1/openInterest", "fapi/v1/depth",
    "futures/data/openInterestHist", "futures/data/globalLongShortAccountRatio",
    "futures/data/topLongShortPositionRatio", "futures/data/takerlongshortRatio", "futures/data/basis",
    "dapi/v1/klines", "dapi/v1/depth", "dapi/v1/premiumIndex",
  ]
  /// 透传只认这两台币安 REST 主机发出的地址（U 本位与币本位）。
  static let rawHosts: Set<String> = [BinanceProvider.defaultRestHost, "dapi.binance.com"]

  public init(route: MarketRoute, transport: any HTTPTransport = URLSessionTransport(), log: FeedLog = .silent) {
    self.route = route; self.transport = transport; self.log = log
  }

  /// 测试用：线路档位 + 网关表（网关表同时当 kanpan-api 主机用）。
  public init(gateways: [String], transport: any HTTPTransport = URLSessionTransport(),
              log: FeedLog = .silent, policy: MarketRoutePolicy = .direct) {
    self.init(route: MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: gateways, api: gateways)),
              transport: transport, log: log)
  }

  /// 换线路。
  public func setPolicy(_ policy: MarketRoutePolicy) {
    route = MarketRoute(policy: policy, endpoints: route.endpoints)
  }

  /// 用户显式点「点此重试」。线路这一层已经没有自己记的冷却（主机按顺序试、每笔从头试），
  /// 所以这里什么都不清；**不动限流器上的封禁**（上游对出口下的判决，点一下不会提前结束）。
  public func resetRouteCooldowns() {}

  public func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    try Task.checkCancellation()
    #if DEBUG
    if ProcessInfo.processInfo.environment["KANPAN_TEST_BINANCE_REST_DOWN"] == "1" {
      throw FeedError.badResponse("Test: Binance REST unavailable")
    }
    #endif
    return route.viaGateway ? try await gateway(url, timeout: timeout) : try await direct(url, timeout: timeout)
  }

  // ------------------------------------------------------------------ 直连

  /// 只走直连：一发到底，用满请求超时，不记冷却、不退网关。
  private func direct(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    let began = Date()
    do {
      let reply = try await transport.get(url, timeout: timeout)
      log("直连 \(url.host ?? "") \(url.path) HTTP \(reply.status) \(Int(-began.timeIntervalSinceNow * 1000))ms")
      try Task.checkCancellation()
      if !Self.fallsBack(reply.status) { return reply }
      // 留一份**完整**的错误：状态码之外还有 `Retry-After`（秒数或 HTTP-date）、
      // body 里的 `code`/`msg`、以及 418/429/451 的类别。只留状态码的话，
      // 上游说「歇 120 秒」就在这儿丢了，限流器只能按自己的秒级退避接着撞（A-03）。
      throw Self.upstreamError(reply, url: url)
    } catch is CancellationError { throw CancellationError() }
    catch let error as BinanceError { throw error }
    catch {
      try Task.checkCancellation()
      if (error as? URLError)?.code == .cancelled { throw CancellationError() }
      log("直连失败 \(url.host ?? "")（行情线路=直连，不退网关）：\(error)")
      throw error
    }
  }

  /// 这个状态码在直连上要不要当成上游的信号抛上去（限流、封禁、地域拒绝、5xx）。
  static func fallsBack(_ status: Int) -> Bool {
    status != 200 && [403, 408, 418, 429, 451, 500, 502, 503, 504].contains(status)
  }

  /// 直连回的失败响应 → 带齐上游信号的错误（`Retry-After` / `code` / 类别）。
  static func upstreamError(_ reply: HTTPReply, url: URL) -> BinanceError {
    struct Body: Decodable { var code: Int?; var msg: String? }
    let body = try? JSONDecoder().decode(Body.self, from: reply.body)
    return BinanceError(status: reply.status, code: body?.code, msg: body?.msg,
                        url: url.absoluteString,
                        retryAfter: BinanceError.retryAfterSeconds(reply.header("Retry-After")))
  }

  // ------------------------------------------------------------------ 网关（原样透传）

  private func gateway(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    let targets = route.apiHosts.compactMap { Self.rawURL(for: url, host: $0) }
    guard !targets.isEmpty else {
      // 这条地址网关不透传（归档站），或者根本没有 kanpan-api 主机：用户选的是网关，这一笔就没有路可走。
      log("\(url.host ?? "") \(url.path) 没有网关路线（行情线路=\(route.policy.rawValue)），直接跳过")
      throw FeedError.badResponse("行情暂不可用，请重试")
    }
    var outcome: Result<HTTPReply, any Error> = .failure(FeedError.badResponse("行情暂不可用，请重试"))
    for target in targets {
      let began = Date()
      do {
        let reply = try await transport.get(target, timeout: timeout)
        try Task.checkCancellation()
        log("网关 \(target.host ?? "") \(url.path) HTTP \(reply.status) \(Int(-began.timeIntervalSinceNow * 1000))ms")
        // 5xx 是那台主机或它的上游一时不行：换下一台。其余（200、4xx）就是这一笔的答案。
        guard (500..<600).contains(reply.status) else { return reply }
        outcome = .success(reply)
      } catch is CancellationError { throw CancellationError() }
      catch {
        try Task.checkCancellation()
        if (error as? URLError)?.code == .cancelled { throw CancellationError() }
        log("网关 \(target.host ?? "") \(url.path) 传输失败（\(Self.transportKind(error))）：\(error.localizedDescription)")
        outcome = .failure(error)
      }
    }
    return try outcome.get()
  }

  /// 币安地址 → kanpan-api 透传地址。不在白名单里（主机或路径）就是 nil。
  static func rawURL(for url: URL, host: String) -> URL? {
    guard let from = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let upstream = from.host, rawHosts.contains(upstream) else { return nil }
    let path = String(from.path.drop { $0 == "/" })
    guard rawPaths.contains(path), var to = VenueEndpoints.origin("https", host) else { return nil }
    to.path = VenueEndpoints.rawPrefix + path
    to.queryItems = (from.queryItems ?? []) + [URLQueryItem(name: "source", value: source)]
    return to.url
  }

  /// 传输层失败的类别，只用来写日志（不改变行为）。
  static func transportKind(_ error: Error) -> String {
    guard let url = error as? URLError else { return "其他" }
    switch url.code {
    case .timedOut: return "超时"
    case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return "断网"
    case .cannotFindHost, .dnsLookupFailed: return "域名解析"
    case .cannotConnectToHost: return "连不上"
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
         .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
      return "TLS"
    default: return "URLError \(url.code.rawValue)"
    }
  }
}

/// 币安行情 WS 的拨号：线路决策来自 `MarketRoute`，这里只把它翻成具体的地址。
///
/// - 直连：连币安自己的流域名（`hosts.stream` 的 `/stream`），不带任何退路。
/// - 网关：连 Python 网关的共享 hub `wss://<gateway>/market/stream?streams=…`
///   （`Backend/kanpan-gateway/stream_hub.py`，和币安 `/stream` 同形的组合流协议），主、备按 `route.gateways`。
///   hub 只放行 `ticker` / `markPrice@1s` / `aggTrade` / `kline_*`，`@trade` 与 `@depth5@100ms` 订了会被它
///   当场断开——所以网关档的能力位里没有盘口与逐笔方向（`hasMicrostructure == false`），
///   `BinanceProvider.makeStream` 也只把 hub 认的流交给它（`BinanceProvider.gatewayAllows`）。
public struct SourceSocketFactory: WSSocketFactory {
  /// 网关 hub 的路径。不能拿它当直连的默认值：币安自己只有 `/stream`。
  public static let gatewayStreamPath = "/market/stream"
  let factory: any WSSocketFactory
  let route: MarketRoute
  let log: FeedLog

  public init(factory: any WSSocketFactory = URLSessionSocketFactory(), route: MarketRoute, log: FeedLog = .silent) {
    self.factory = factory; self.route = route; self.log = log
  }

  /// 测试用：线路档位 + 网关表。
  public init(gateways: [String], factory: any WSSocketFactory = URLSessionSocketFactory(),
              policy: MarketRoutePolicy, log: FeedLog = .silent) {
    self.init(factory: factory, route: MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: gateways)),
              log: log)
  }

  public func connect(to url: URL) async throws -> any WSSocket {
    guard route.viaGateway else {
      // 不带退路：只连币安自己的域名。
      return try await MarketSocketRouter(factory: factory, fallbacks: [], log: log).connect(to: url)
    }
    let gateways = route.gateways
    guard let first = gateways.first, var parts = VenueEndpoints.origin("wss", first) else {
      log("行情流：网关线路下没有可用的网关")
      throw FeedError.badResponse("行情服务暂不可用")
    }
    parts.path = Self.gatewayStreamPath
    parts.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    guard let target = parts.url else { throw FeedError.badResponse("行情地址无效") }
    return try await MarketSocketRouter(factory: factory, fallbacks: Array(gateways.dropFirst()), log: log)
      .connect(to: target)
  }
}

public extension BinanceREST {
  /// 某条线路上的 REST 客户端。线路由 `RouteResolver` 定好传进来（`MarketRoute`）。
  /// 直连与网关各用一把共享限流器：币安按出口 IP 记权重，直连的出口是这台手机，网关的出口是新加坡那台。
  static func routed(hosts: BinanceHosts, route: MarketRoute, log: FeedLog = .silent) -> BinanceREST {
    BinanceREST(hosts: hosts,
                transport: MarketRESTTransport(route: route, log: log),
                limiter: route.viaGateway ? .sharedGateway : .sharedBinance, log: log)
  }
}
