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
  /// 直连发出去之后等这么久还没回音，就并行把网关也叫上，谁先回用谁。
  ///
  /// 原来这两步是串的：直连先干等满 `directAttemptTimeout`，超时了才去开网关
  /// 竞速——移动网络被黑洞吃掉时，第一屏固定多等 3 秒。改成对冲之后，坏网络
  /// 只多等这一档，好网络完全不受影响。
  ///
  /// 不另设次数配额：这个延迟本身就是闸门。直连健康时它几十毫秒就回来了，
  /// 网关那一发根本不会发出去；只有直连真的慢，才会多出一笔网关请求——
  /// 而那正是网关存在的意义。
  private static let hedgeDelay: TimeInterval = 0.7
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
    let plan = gatewayPlan(for: url)
    let directAllowed = source == .binance && Date() >= directRetry

    // 两条路都能走：对冲。直连先发，`hedgeDelay` 之后网关跟上，谁先回用谁。
    if directAllowed, let plan, !plan.candidates.isEmpty {
      if let reply = try await hedged(url, timeout: timeout, plan: plan, failure: &failure) { return reply }
      throw failure
    }

    if directAllowed {
      do {
        let began = Date()
        let reply = try await transport.get(url, timeout: min(timeout, Self.directAttemptTimeout))
        log("直连 \(url.host ?? "") \(url.path) HTTP \(reply.status) \(Int(-began.timeIntervalSinceNow * 1000))ms")
        try Task.checkCancellation()
        if !Self.fallsBack(reply.status) { return reply }
        directRetry = Self.directCooldown(for: reply.status)
      } catch is CancellationError { throw CancellationError() }
      catch {
        try Task.checkCancellation()
        if (error as? URLError)?.code == .cancelled { throw CancellationError() }
        directRetry = Date().addingTimeInterval(Self.directCooldownSeconds)
        log("直连失败 \(url.host ?? "")，\(Int(Self.directCooldownSeconds))s 内优先走网关：\(error)")
        failure = error }
    }

    guard let plan, !plan.candidates.isEmpty else { throw failure }
    guard let winner = await Self.race(plan) else {
      for candidate in plan.candidates { gatewayRetry[candidate.host] = Date().addingTimeInterval(10) }
      throw failure
    }
    settle(winner, plan: plan, hedged: false)
    return HTTPReply(status: 200, body: winner.payload)
  }

  // ------------------------------------------------------------------ 对冲

  private struct DirectLeg: Sendable {
    var reply: HTTPReply?
    var error: (any Error)?
  }

  private enum HedgeLeg: Sendable {
    case direct(DirectLeg)
    case gateway(GatewaySuccess?)
  }

  private struct HedgeOutcome: Sendable {
    var direct: DirectLeg?
    var gateway: GatewaySuccess?
    /// 网关那一腿是自己跑完的，还是被我们取消掉的。只有跑完了才记它的冷却。
    var gatewayFinished = false
  }

  /// 直连与网关并行，返回先到的那份；两边都没成就返回 nil（`failure` 里带着原因）。
  private func hedged(_ url: URL, timeout: TimeInterval, plan: GatewayPlan,
                      failure: inout Error) async throws -> HTTPReply? {
    let transport = self.transport
    let directTimeout = min(timeout, Self.directAttemptTimeout)
    let delay = Self.hedgeDelay
    let began = Date()

    let outcome = await withTaskGroup(of: HedgeLeg.self) { group -> HedgeOutcome in
      group.addTask {
        do { return .direct(DirectLeg(reply: try await transport.get(url, timeout: directTimeout), error: nil)) }
        catch { return .direct(DirectLeg(reply: nil, error: error)) }
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled else { return .gateway(nil) }
        return .gateway(await MarketRESTTransport.race(plan))
      }

      var result = HedgeOutcome()
      while let leg = await group.next() {
        switch leg {
        case .direct(let direct):
          result.direct = direct
          // 直连回了一个不需要退路的应答（200，或者退了也没用的 4xx），它说了算。
          if let reply = direct.reply, !MarketRESTTransport.fallsBack(reply.status) {
            group.cancelAll()
            while await group.next() != nil {}
            return result
          }
          // 这一笔是被取消的（换了品种/周期）：整轮作废，网关那一腿也不用跑完。
          // 取消不是「直连坏了」，外层会原样把 `CancellationError` 抛出去。
          if let error = direct.error, MarketRESTTransport.isCancellation(error) {
            group.cancelAll()
            while await group.next() != nil {}
            return result
          }
        case .gateway(let winner):
          result.gatewayFinished = true
          result.gateway = winner
          if winner != nil {
            // 网关先到，用它的结果。直连那一腿要是还在飞，取消掉、也不记它的账——
            // 它只是比 `hedgeDelay` 慢，未必是坏的，下一笔还让它先跑。
            // （已经跑完的那种不一样：`result.direct` 里存着真实结果，照记不误。）
            group.cancelAll()
            while await group.next() != nil {}
            return result
          }
        }
        if result.direct != nil, result.gatewayFinished { break }
      }
      group.cancelAll()
      while await group.next() != nil {}
      return result
    }

    try Task.checkCancellation()

    if let direct = outcome.direct {
      if let reply = direct.reply {
        log("直连 \(url.host ?? "") \(url.path) HTTP \(reply.status) \(Int(-began.timeIntervalSinceNow * 1000))ms")
        if !Self.fallsBack(reply.status) { return reply }
        directRetry = Self.directCooldown(for: reply.status)
      } else if let error = direct.error {
        if Self.isCancellation(error) { throw CancellationError() }
        directRetry = Date().addingTimeInterval(Self.directCooldownSeconds)
        log("直连失败 \(url.host ?? "")，\(Int(Self.directCooldownSeconds))s 内优先走网关：\(error)")
        failure = error
      }
    }

    if let winner = outcome.gateway {
      settle(winner, plan: plan, hedged: true)
      return HTTPReply(status: 200, body: winner.payload)
    }
    if outcome.gatewayFinished {
      for candidate in plan.candidates { gatewayRetry[candidate.host] = Date().addingTimeInterval(10) }
    }
    return nil
  }

  /// 网关赢了之后的记账。
  ///
  /// `hedged` 时**不**把直连按进 `preferredGatewaySeconds` 的长冷却：对冲只说明
  /// 直连比 `hedgeDelay` 慢，没说明它坏了。串行退下来的那次不一样——那是直连
  /// 真的超时或报错，长冷却才是对的。
  private func settle(_ winner: GatewaySuccess, plan: GatewayPlan, hedged: Bool) {
    preferred = winner.host
    // 这一轮输掉的网关先歇一会儿：它可能只是慢或者被黑洞吃了，
    // 别让每一行都去把同一场竞速重开一遍。
    for candidate in plan.candidates where candidate.host != winner.host {
      gatewayRetry[candidate.host] = Date().addingTimeInterval(10)
    }
    if !hedged { directRetry = max(directRetry, Date().addingTimeInterval(Self.preferredGatewaySeconds)) }
  }

  /// 这个错误是不是「这一笔被取消了」。取消不算线路故障，不记冷却。
  static func isCancellation(_ error: any Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }

  /// 这个状态码要不要退到另一条路上。
  static func fallsBack(_ status: Int) -> Bool {
    status != 200 && [403, 408, 418, 429, 451, 500, 502, 503, 504].contains(status)
  }

  // ------------------------------------------------------------------ 网关竞速

  private struct GatewayPlan: Sendable {
    let endpoint: String
    let field: String
    let expectedSymbol: String
    let expectedInterval: String
    let sourceRawValue: String
    let candidates: [GatewayCandidate]
    let transport: any HTTPTransport
  }

  /// 把这条 URL 能走的网关路线算出来。网关代理不了就返回 nil，调用方只能走直连。
  private func gatewayPlan(for url: URL) -> GatewayPlan? {
    let endpoint: String, field: String
    switch url.path {
    case "/fapi/v1/klines": endpoint = "klines"; field = "bars"
    case "/fapi/v1/ticker/24hr": endpoint = "ticker"; field = "ticker"
    case "/fapi/v1/exchangeInfo": endpoint = "instruments"; field = "instruments"
    default: return nil
    }
    let ordered = gateways.sorted { $0 == preferred && $1 != preferred }
    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let expectedSymbol = queryItems.first(where: { $0.name == "symbol" })?.value ?? ""
    // 全市场 ticker 没有 symbol，网关只代理单品种。别把它转过去换一份
    // 无法校验的载荷回来——直接当没有网关，让调用方退回逐个请求。
    if endpoint == "ticker", expectedSymbol.isEmpty { return nil }
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
        ? 5 : (source == .binance || smallProbe ? 5 : 8)
      candidates.append(GatewayCandidate(host: host, target: target, timeout: deadline))
    }
    return GatewayPlan(endpoint: endpoint, field: field, expectedSymbol: expectedSymbol,
                       expectedInterval: expectedInterval, sourceRawValue: source.rawValue,
                       candidates: candidates, transport: transport)
  }

  /// 几台网关一起发，谁先回一份校验得过的同源载荷就用谁。
  private static func race(_ plan: GatewayPlan) async -> GatewaySuccess? {
    await withTaskGroup(of: GatewaySuccess?.self) { group -> GatewaySuccess? in
      for candidate in plan.candidates {
        group.addTask {
          do {
            let reply = try await plan.transport.get(candidate.target, timeout: candidate.timeout)
            guard reply.status == 200,
                  let body = try JSONSerialization.jsonObject(with: reply.body) as? [String: Any],
                  body["source"] as? String == plan.sourceRawValue,
                  let payload = body[plan.field] else { return nil }
            if plan.endpoint == "klines" {
              guard body["symbol"] as? String == plan.expectedSymbol,
                    body["interval"] as? String == plan.expectedInterval else { return nil }
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
