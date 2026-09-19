import Foundation
import KanpanCore

public enum MarketSource: String, Codable, Sendable { case binance, okx }

/// REST adaptation is confined to the upstream boundary. A request never changes exchange.
public actor MarketRESTTransport: HTTPTransport {
  /// 网关被按下去之后歇多久。网关自己在 429 / 503 上给了 `Retry-After` 就听它的，
  /// 但不超过这个上限——更长的退避该由用户换线路来做，不是把一台网关按死。
  private static let gatewayCooldownSeconds: TimeInterval = 10
  private let source: MarketSource
  private let log: FeedLog
  private let gateways: [String]
  private let transport: any HTTPTransport
  private var gatewayRetry: [String: Date] = [:]
  private var preferred: String?
  /// 路由账本的版本号。换线路、清冷却都会把它 +1。
  /// 一场竞速要等好几秒，赢家回来的时候用户可能已经换了线路、或者刚按过重试，
  /// 那份结果就是上一档的旧账，不能再写进来。
  private var routeEpoch = 0
  /// 行情线路。用户定的，见 `MarketRoutePolicy`：直连就只直连，网关就只网关。
  private var policy: MarketRoutePolicy

  private struct GatewayCandidate: Sendable {
    let host: String
    let target: URL
    let timeout: TimeInterval
  }

  private struct GatewaySuccess: Sendable {
    let host: String
    let payload: Data
  }

  /// 一轮竞速的结果：赢家（可能没有），外加各台网关自己报的 `Retry-After`。
  private struct GatewayOutcome: Sendable {
    var winner: GatewaySuccess?
    var retryAfter: [String: TimeInterval] = [:]
  }

  public init(source: MarketSource, gateways: [String], transport: any HTTPTransport = URLSessionTransport(),
              log: FeedLog = .silent, policy: MarketRoutePolicy = .direct) {
    self.source = source; self.gateways = gateways; self.transport = transport; self.log = log
    self.policy = policy
  }

  /// 换线路。顺手把网关冷却清掉：线路是用户刚按下的，
  /// 上一档留下的「这台网关先歇着」的账不该拖累新的选择。
  public func setPolicy(_ policy: MarketRoutePolicy) {
    self.policy = policy
    resetRouteCooldowns()
  }

  /// 把在飞的那些竞速结果作废：从这一刻起回来的赢家/输家都不许再改路由账本。
  private func invalidateRoutes() { routeEpoch &+= 1 }

  /// A user-requested retry may bypass a gateway cooldown once. Automatic
  /// monitoring still observes the cooldowns; this is only for an explicit
  /// tap on the visible retry affordance.
  public func resetRouteCooldowns() {
    gatewayRetry.removeAll()
    invalidateRoutes()
  }

  public func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    try Task.checkCancellation()
    #if DEBUG
    if source == .binance, ProcessInfo.processInfo.environment["KANPAN_TEST_BINANCE_REST_DOWN"] == "1" {
      throw FeedError.badResponse("Test: Binance REST unavailable")
    }
    #endif
    // 「直连」只对币安成立：OKX 本来就没有直连这条路（网关才有），
    // 所以 OKX 无论哪条线路都走网关竞速。
    if policy == .direct, source == .binance { return try await direct(url, timeout: timeout) }

    let failure = FeedError.badResponse("行情暂不可用，请重试")
    // 网关代理不了这条路线（`/futures/data/openInterestHist` 就是这种）：
    // 用户选的是网关，那这一笔就没有路可走，立刻认输。
    guard let plan = gatewayPlan(for: url), !plan.candidates.isEmpty else {
      log("\(url.path) 没有网关路线（行情线路=\(policy.rawValue)），直接跳过")
      throw failure
    }
    // 竞速前记下路由账本的版本。竞速要等好几秒，这中间用户完全可能换了线路
    // 或者按了重试（两者都会清冷却），那时这一场的输赢属于上一档，不能再记账。
    let epoch = routeEpoch
    let raced = await Self.race(plan)
    guard let winner = raced.winner else {
      // 是这一笔自己被取消了（换品种、换线路把上一份 feed 停掉），不是网关不行：
      // 不能给网关记冷却，不然紧接着的新一份 feed 首屏会「没有网关路线」白等 10 秒。
      try Task.checkCancellation()
      guard epoch == routeEpoch else { throw failure }
      for candidate in plan.candidates {
        let seconds = raced.retryAfter[candidate.host] ?? Self.gatewayCooldownSeconds
        gatewayRetry[candidate.host] = Date().addingTimeInterval(seconds)
      }
      throw failure
    }
    // 赢家这条路原来既不查取消也不查版本：一笔在取消窗口里回来的成功，会把两台
    // 网关里的输家按 10 秒冷却，紧接着重开的那份 feed 于是只剩一台可用；换线路
    // 那一下更糟——刚清干净的冷却被上一档的旧结果重新写满。
    try Task.checkCancellation()
    guard epoch == routeEpoch else { return HTTPReply(status: 200, body: winner.payload) }
    settle(winner, plan: plan)
    return HTTPReply(status: 200, body: winner.payload)
  }

  // ------------------------------------------------------------------ 直连

  /// 只走直连：一发到底，用满请求超时，不记冷却、不退网关。
  ///
  /// 没有 3/8 秒的「快速让位」——那个短超时是为了尽快把机会让给网关，
  /// 而此刻根本没有网关可让，砍掉只会把一笔本来会成功的慢请求砍死。
  /// 失败也不记冷却：冷却的意义是「先去走网关」，没有网关可走的时候
  /// 它只会让下一笔连试都不试就直接失败。
  private func direct(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    let began = Date()
    do {
      let reply = try await transport.get(url, timeout: timeout)
      log("直连 \(url.host ?? "") \(url.path) HTTP \(reply.status) \(Int(-began.timeIntervalSinceNow * 1000))ms")
      try Task.checkCancellation()
      if !Self.fallsBack(reply.status) { return reply }
      // 留一份带状态码的错误：`BinanceREST` 才认得出 418/429，才会去按住限流器。
      throw BinanceError(status: reply.status, url: url.absoluteString)
    } catch is CancellationError { throw CancellationError() }
    catch let error as BinanceError { throw error }
    catch {
      try Task.checkCancellation()
      if (error as? URLError)?.code == .cancelled { throw CancellationError() }
      log("直连失败 \(url.host ?? "")（行情线路=直连，不退网关）：\(error)")
      throw error
    }
  }

  /// 网关赢了之后的记账。
  private func settle(_ winner: GatewaySuccess, plan: GatewayPlan) {
    preferred = winner.host
    // 这一轮输掉的网关先歇一会儿：它可能只是慢或者被黑洞吃了，
    // 别让每一行都去把同一场竞速重开一遍。
    for candidate in plan.candidates where candidate.host != winner.host {
      gatewayRetry[candidate.host] = Date().addingTimeInterval(Self.gatewayCooldownSeconds)
    }
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
  private static func race(_ plan: GatewayPlan) async -> GatewayOutcome {
    typealias Leg = (host: String, success: GatewaySuccess?, retryAfter: TimeInterval?)
    return await withTaskGroup(of: Leg.self) { group -> GatewayOutcome in
      for candidate in plan.candidates {
        group.addTask {
          do {
            let reply = try await plan.transport.get(candidate.target, timeout: candidate.timeout)
            guard reply.status == 200 else {
              // 网关自己说了过多久再来就听它的，比一刀切 10 秒恢复得快。
              return (candidate.host, nil, MarketRESTTransport.gatewayCooldown(reply))
            }
            guard let data = MarketRESTTransport.payload(of: reply.body, plan: plan) else {
              return (candidate.host, nil, nil)
            }
            return (candidate.host, GatewaySuccess(host: candidate.host, payload: data), nil)
          } catch is CancellationError {
            return (candidate.host, nil, nil)
          } catch {
            return (candidate.host, nil, nil)
          }
        }
      }
      var result = GatewayOutcome()
      while let leg = await group.next() {
        if let success = leg.success {
          result.winner = success
          group.cancelAll()
          break
        }
        if let hint = leg.retryAfter { result.retryAfter[leg.host] = hint }
      }
      group.cancelAll()
      while await group.next() != nil {}
      return result
    }
  }

  /// 网关这一台歇多久：优先听它自己说的 `Retry-After`（秒），封顶 10 秒。
  static func gatewayCooldown(_ reply: HTTPReply) -> TimeInterval {
    guard reply.status == 429 || reply.status == 503,
          let raw = reply.header("Retry-After")?.trimmingCharacters(in: .whitespaces),
          let seconds = Double(raw), seconds > 0 else { return gatewayCooldownSeconds }
    return min(seconds, gatewayCooldownSeconds)
  }

  /// 从网关信封里取出载荷，顺手把同源校验做掉。
  ///
  /// 先走 `GatewayEnvelope` 的一趟式扫描（不建对象图、不重新序列化）；
  /// 扫不动才退回原来那条 `JSONSerialization` 的路，保证行为不回退。
  private static func payload(of body: Data, plan: GatewayPlan) -> Data? {
    if let scanned = GatewayEnvelope.parse(body, field: plan.field), let payload = scanned.payload {
      guard scanned.source == plan.sourceRawValue else { return nil }
      if plan.endpoint == "klines" {
        guard scanned.symbol == plan.expectedSymbol,
              scanned.interval == plan.expectedInterval else { return nil }
      }
      return payload
    }
    guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          object["source"] as? String == plan.sourceRawValue,
          let field = object[plan.field] else { return nil }
    if plan.endpoint == "klines" {
      guard object["symbol"] as? String == plan.expectedSymbol,
            object["interval"] as? String == plan.expectedInterval else { return nil }
    }
    return try? JSONSerialization.data(withJSONObject: field)
  }

}

/// Both gateways expose the existing candle wire format, with a source-specific URL.
public struct SourceSocketFactory: WSSocketFactory {
  let source: MarketSource
  let hosts: BinanceHosts
  let factory: any WSSocketFactory
  /// 币安的 WS 也有直连（`hosts.stream`，默认 `dstream.binance.me`）与网关（`streamFallbacks`，
  /// 就是那两台 VPS）两条路，用户选了哪条就只拨哪条；OKX 只有网关这一条路，不受影响。
  let policy: MarketRoutePolicy
  let log: FeedLog
  public init(source: MarketSource, hosts: BinanceHosts, factory: any WSSocketFactory = URLSessionSocketFactory(),
              policy: MarketRoutePolicy = .direct, log: FeedLog = .silent) {
    self.source = source; self.hosts = hosts; self.factory = factory; self.policy = policy; self.log = log
  }
  public func connect(to url: URL) async throws -> any WSSocket {
    if source == .binance {
      switch policy {
      case .direct:
        // 不带退路：只连币安自己的域名。
        return try await MarketSocketRouter(factory: factory, fallbacks: [], log: log).connect(to: url)
      case .gateway:
        // 把首选也换成网关，`MarketSocketRouter` 才不会仍旧把直连塞进候选里。
        // `streamFallbacks` 里可能混着直连域名本身（app 侧把 `APIHost.defaultStream`
        // 也列在第一位），先把它剔掉，剩下的才是真正的网关。
        let direct = [hosts.stream.lowercased(), (url.host ?? "").lowercased()]
        let gateways = hosts.streamFallbacks.filter { host in
          guard let name = URLComponents(string: "wss://" + host)?.host?.lowercased() else { return false }
          return !direct.contains(name)
        }
        guard let first = gateways.first,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let endpoint = URLComponents(string: "wss://" + first), let name = endpoint.host,
              endpoint.user == nil, endpoint.password == nil else {
          throw FeedError.badResponse("行情服务暂不可用")
        }
        parts.host = name; parts.port = endpoint.port
        // 网关的组合流挂在它自己的 `/market/stream` 上，不是币安的 `/stream`。
        parts.path = "/market/stream"
        guard let target = parts.url else { throw FeedError.badResponse("行情地址无效") }
        return try await MarketSocketRouter(factory: factory,
                                            fallbacks: Array(gateways.dropFirst()), log: log).connect(to: target)
      }
    }
    guard let first = hosts.oiProxies.first, var parts = URLComponents(string: "wss://" + first),
          parts.host != nil, parts.user == nil, parts.password == nil else { throw FeedError.badResponse("行情服务暂不可用") }
    parts.path = "/market/okx/stream"; parts.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    guard let target = parts.url else { throw FeedError.badResponse("行情地址无效") }
    return try await MarketSocketRouter(factory: factory, fallbacks: Array(hosts.oiProxies.dropFirst()), log: log).connect(to: target)
  }
}

public extension BinanceREST {
  /// 某条线路上的 REST 客户端。`policy` 不传就用用户当前选的线路（`MarketRoutePolicyStore`），
  /// 这样 app 里顺手建的目录 / 历史 OI / 报价簿客户端都跟设置走，不会「行情走网关、
  /// OI 却还在直连」。测试要钉死线路时显式传。
  static func upstream(_ source: MarketSource, hosts: BinanceHosts, log: FeedLog = .silent,
                       policy: MarketRoutePolicy = MarketRoutePolicyStore.current) -> BinanceREST {
    BinanceREST(hosts: hosts,
                transport: MarketRESTTransport(source: source, gateways: hosts.oiProxies, log: log, policy: policy),
                limiter: source == .binance ? .sharedBinance : .sharedOKX, log: log)
  }

}
