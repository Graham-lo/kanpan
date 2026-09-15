import Foundation
import KanpanCore

public enum MarketSource: String, Codable, Sendable { case binance, okx }

/// REST adaptation is confined to the upstream boundary. A request never changes exchange.
public actor MarketRESTTransport: HTTPTransport {
  private static let directCooldownSeconds: TimeInterval = 30
  private static let preferredGatewaySeconds: TimeInterval = 300
  /// A blocked mobile route must yield to the VPS quickly. The route race and
  /// the source switch are the recovery mechanism; waiting the full request
  /// timeout here only makes the first screen feel frozen.
  private static let directAttemptTimeout: TimeInterval = 3
  private let source: MarketSource
  private let log: FeedLog
  private let gateways: [String]
  private let transport: any HTTPTransport
  private var directRetry = Date.distantPast
  private var gatewayRetry: [String: Date] = [:]
  private var preferred: String?

  private struct GatewayCandidate: Sendable {
    let host: String
    let target: URL
    let timeout: TimeInterval
  }

  private struct GatewaySuccess: Sendable {
    let host: String
    let payload: Data
  }

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
        let reply = try await transport.get(url, timeout: min(timeout, Self.directAttemptTimeout))
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
    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let expectedSymbol = queryItems.first(where: { $0.name == "symbol" })?.value ?? ""
    let expectedInterval = queryItems.first(where: { $0.name == "interval" })?.value ?? ""
    var candidates: [GatewayCandidate] = []
    for host in ordered where Date() >= (gatewayRetry[host] ?? .distantPast) {
      guard var parts = URLComponents(string: "https://" + host), parts.host != nil,
            parts.user == nil, parts.password == nil, parts.path.isEmpty, parts.query == nil else { continue }
      parts.path = "/market/v1/" + endpoint
      parts.queryItems = queryItems
        + [URLQueryItem(name: "source", value: source.rawValue)]
      guard let target = parts.url else { continue }
      let smallProbe = queryItems.first(where: { $0.name == "limit" })?.value.flatMap(Int.init).map { $0 <= 3 } ?? false
      // Catalog and ticker requests are small and should never wait behind a
      // mobile-network black hole. A first historical page is also bounded:
      // the gateway returns the latest window first, while older pages can be
      // retried in the background instead of blocking the initial screen.
      let deadline: TimeInterval = endpoint == "instruments" || endpoint == "ticker"
        ? min(timeout, 5) : (source == .binance || smallProbe ? 5 : min(timeout, 8))
      candidates.append(GatewayCandidate(host: host, target: target, timeout: deadline))
    }
    guard !candidates.isEmpty else { throw failure }

    let sourceRawValue = source.rawValue
    let transport = self.transport
    let winner = await withTaskGroup(of: GatewaySuccess?.self) { group -> GatewaySuccess? in
      for candidate in candidates {
        group.addTask {
          do {
            let reply = try await transport.get(candidate.target, timeout: candidate.timeout)
            guard reply.status == 200,
                  let body = try JSONSerialization.jsonObject(with: reply.body) as? [String: Any],
                  body["source"] as? String == sourceRawValue,
                  let payload = body[field] else { return nil }
            if endpoint == "klines" {
              guard body["symbol"] as? String == expectedSymbol,
                    body["interval"] as? String == expectedInterval else { return nil }
            }
            return GatewaySuccess(host: candidate.host,
                                  payload: try JSONSerialization.data(withJSONObject: payload))
          } catch is CancellationError {
            return nil
          } catch {
            return nil
          }
        }
      }
      var result: GatewaySuccess?
      while let next = await group.next() {
        if let next {
          result = next
          group.cancelAll()
          break
        }
      }
      group.cancelAll()
      while await group.next() != nil {}
      return result
    }

    if let winner {
      preferred = winner.host
      // Do not immediately race a gateway that lost this round. It may have
      // been a slow or black-holed path; keep the winner hot and give the
      // losers a short retry lease so each row does not reopen the same race.
      for candidate in candidates where candidate.host != winner.host {
        gatewayRetry[candidate.host] = Date().addingTimeInterval(10)
      }
      // Once a gateway has returned a validated same-source payload, keep
      // subsequent requests on that route for a while. This avoids paying
      // the direct black-hole timeout again on every symbol/interval change;
      // the normal recovery path can probe direct after the short lease.
      directRetry = max(directRetry, Date().addingTimeInterval(Self.preferredGatewaySeconds))
      return HTTPReply(status: 200, body: winner.payload)
    }

    for candidate in candidates { gatewayRetry[candidate.host] = Date().addingTimeInterval(10) }
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
