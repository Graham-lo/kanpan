import Foundation
import KanpanCore

public enum MarketSource: String, Codable, Sendable { case binance, okx }

/// REST adaptation is confined to the upstream boundary. A request never changes exchange.
public actor MarketRESTTransport: HTTPTransport {
  private static let directCooldownSeconds: TimeInterval = 30
  private static let preferredGatewaySeconds: TimeInterval = 300
  private let source: MarketSource
  private let log: FeedLog
  private let gateways: [String]
  private let transport: any HTTPTransport
  private var directRetry = Date.distantPast
  private var gatewayRetry: [String: Date] = [:]
  private var preferred: String?

  public init(source: MarketSource, gateways: [String], transport: any HTTPTransport = URLSessionTransport(), log: FeedLog = .silent) {
    self.source = source; self.gateways = gateways; self.transport = transport; self.log = log
  }

  /// A user-requested retry may bypass a route cooldown once. Automatic
  /// monitoring still observes the cooldowns; this is only for an explicit
  /// tap on the visible retry affordance.
  public func resetRouteCooldowns() {
    directRetry = .distantPast
    gatewayRetry.removeAll()
  }
  public func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    try Task.checkCancellation()
    #if DEBUG
    if source == .binance, ProcessInfo.processInfo.environment["KANPAN_TEST_BINANCE_REST_DOWN"] == "1" {
      throw FeedError.badResponse("Test: Binance REST unavailable")
    }
    #endif
    var failure: Error = FeedError.badResponse("行情暂不可用，请重试")
    if source == .binance, Date() >= directRetry {
      do {
        let began = Date()
        let reply = try await transport.get(url, timeout: min(timeout, 15))
        log("直连 \(url.host ?? "") \(url.path) HTTP \(reply.status) \(Int(-began.timeIntervalSinceNow * 1000))ms")
        try Task.checkCancellation()
        if reply.status == 200 { return reply }
        if ![403, 408, 418, 429, 451, 500, 502, 503, 504].contains(reply.status) { return reply }
        directRetry = Self.directCooldown(for: reply.status)
      } catch is CancellationError { throw CancellationError() }
      catch {
        try Task.checkCancellation()
        if (error as? URLError)?.code == .cancelled { throw CancellationError() }
        directRetry = Date().addingTimeInterval(Self.directCooldownSeconds)
        log("直连失败 \(url.host ?? "")，\(Int(Self.directCooldownSeconds))s 内优先走网关：\(error)")
        failure = error }
    }
    let endpoint: String, field: String
    switch url.path {
    case "/fapi/v1/klines": endpoint = "klines"; field = "bars"
    case "/fapi/v1/ticker/24hr": endpoint = "ticker"; field = "ticker"
    case "/fapi/v1/exchangeInfo": endpoint = "instruments"; field = "instruments"
    default: throw failure
    }
    let ordered = gateways.sorted { $0 == preferred && $1 != preferred }
    for host in ordered where Date() >= (gatewayRetry[host] ?? .distantPast) {
      guard var parts = URLComponents(string: "https://" + host), parts.host != nil,
            parts.user == nil, parts.password == nil, parts.path.isEmpty, parts.query == nil else { continue }
      parts.path = "/market/v1/" + endpoint
      parts.queryItems = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        + [URLQueryItem(name: "source", value: source.rawValue)]
      guard let target = parts.url else { continue }
      do {
        let smallProbe = parts.queryItems?.first(where: { $0.name == "limit" })?.value.flatMap(Int.init).map { $0 <= 3 } ?? false
        let deadline: TimeInterval = source == .binance || smallProbe ? 5 : 30
        let reply = try await transport.get(target, timeout: deadline)
        try Task.checkCancellation()
        guard reply.status == 200 else { throw FeedError.badResponse("行情暂不可用，请重试") }
        guard let body = try JSONSerialization.jsonObject(with: reply.body) as? [String: Any],
              body["source"] as? String == source.rawValue, let payload = body[field] else {
          throw FeedError.badResponse("行情来源不匹配")
        }
        if endpoint == "klines" {
          let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
          guard body["symbol"] as? String == query.first(where: { $0.name == "symbol" })?.value,
                body["interval"] as? String == query.first(where: { $0.name == "interval" })?.value else {
            throw FeedError.badResponse("行情区间不匹配")
          }
        }
        preferred = host
        // Once a gateway has returned a validated same-source payload, keep
        // subsequent requests on that route for a while. This avoids paying
        // the direct black-hole timeout again on every symbol/interval change;
        // the normal recovery path can probe direct after the short lease.
        directRetry = max(directRetry, Date().addingTimeInterval(Self.preferredGatewaySeconds))
        return HTTPReply(status: 200, body: try JSONSerialization.data(withJSONObject: payload))
      } catch is CancellationError { throw CancellationError() }
      catch {
        try Task.checkCancellation()
        if (error as? URLError)?.code == .cancelled { throw CancellationError() }
        failure = error; gatewayRetry[host] = Date().addingTimeInterval(10)
      }
    }
    throw failure
  }

  private static func directCooldown(for status: Int) -> Date {
    let seconds: TimeInterval
    switch status {
    case 403, 451: seconds = 60
    case 418, 429: seconds = 15
    case 408, 500, 502, 503, 504: seconds = directCooldownSeconds
    default: seconds = 0
    }
    return seconds > 0 ? Date().addingTimeInterval(seconds) : .distantPast
  }
}

/// Both gateways expose the existing candle wire format, with a source-specific URL.
public struct SourceSocketFactory: WSSocketFactory {
  let source: MarketSource
  let hosts: BinanceHosts
  let factory: any WSSocketFactory
  public init(source: MarketSource, hosts: BinanceHosts, factory: any WSSocketFactory = URLSessionSocketFactory()) {
    self.source = source; self.hosts = hosts; self.factory = factory
  }
  public func connect(to url: URL) async throws -> any WSSocket {
    if source == .binance {
      return try await MarketSocketRouter(factory: factory, fallbacks: hosts.streamFallbacks).connect(to: url)
    }
    guard let first = hosts.oiProxies.first, var parts = URLComponents(string: "wss://" + first),
          parts.host != nil, parts.user == nil, parts.password == nil else { throw FeedError.badResponse("行情服务暂不可用") }
    parts.path = "/market/okx/stream"; parts.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    guard let target = parts.url else { throw FeedError.badResponse("行情地址无效") }
    return try await MarketSocketRouter(factory: factory, fallbacks: Array(hosts.oiProxies.dropFirst())).connect(to: target)
  }
}

public extension BinanceREST {
  static func upstream(_ source: MarketSource, hosts: BinanceHosts, log: FeedLog = .silent) -> BinanceREST {
    BinanceREST(hosts: hosts, transport: MarketRESTTransport(source: source, gateways: hosts.oiProxies, log: log), log: log)
  }

}
