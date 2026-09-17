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
  /// 大请求的直连超时。1500 根 K 线是 250KB、品种表几百 KB，移动网络上光收包
  /// 就能超过 3 秒——一刀切 3 秒等于每次都在快收完的时候把它砍掉，再去网关
  /// 从头收一遍，反而更慢。只有这两类放宽，小请求照旧 3 秒快速让位。
  private static let directBulkTimeout: TimeInterval = 8
  /// 网关被按下去之后歇多久。网关自己在 429 / 503 上给了 `Retry-After` 就听它的，
  /// 但不超过这个上限——更长的退避该由整条线路的切换来做，不是把一台网关按死。
  private static let gatewayCooldownSeconds: TimeInterval = 10
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
  /// 行情线路策略。`.auto` 是原来的行为，另外两档见 `MarketRoutePolicy`。
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
              log: FeedLog = .silent, policy: MarketRoutePolicy = .auto) {
    self.source = source; self.gateways = gateways; self.transport = transport; self.log = log
    self.policy = policy
  }

  /// 换线路策略。顺手把两种冷却都清掉：策略是用户刚按下的，
  /// 上一档留下的「这条路先歇着」的账不该拖累新的选择。
  public func setPolicy(_ policy: MarketRoutePolicy) {
    self.policy = policy
    resetRouteCooldowns()
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
    // 「只走直连」只对币安成立：OKX 本来就没有直连这条路（网关才有），
    // 所以 `.direct` 下 OKX 的行为一个字都不改。
    let directOnly = policy == .direct && source == .binance
    let plan = directOnly ? nil : gatewayPlan(for: url)
    let directAllowed: Bool
    if policy == .gateway { directAllowed = false }          // 跳过直连，只剩网关竞速
    else if directOnly { directAllowed = true }              // 冷却也不认：用户说了这条网能走
    else { directAllowed = source == .binance && Date() >= directRetry }

    // 网关代理不了这条路线（`/futures/data/openInterestHist` 就是这种），而直连
    // 又还在冷却里：这一笔没有任何能走的路。立刻认输，别再去发一发注定要等满
    // 超时才失败的请求。直连的冷却是整条 transport 共享的——刚被黑洞吃过、
    // 或者刚在竞速里输给网关，都会置上。
    if plan == nil, !directAllowed {
      log("\(url.path) 没有网关路线且直连不可用（\(policy.rawValue)），直接跳过")
      throw failure
    }

    // 两条路都能走：对冲。直连先发，`hedgeDelay` 之后网关跟上，谁先回用谁。
    if directAllowed, let plan, !plan.candidates.isEmpty {
      if let reply = try await hedged(url, timeout: timeout, plan: plan, failure: &failure) { return reply }
      throw failure
    }

    if directAllowed {
      do {
        let began = Date()
        // 「只走直连」时不做 3/8 秒的快速让位：那个短超时是为了尽快把机会让给
        // 网关，而此刻根本没有网关可让——砍掉只会把一笔本来会成功的慢请求砍死。
        let deadline = directOnly ? timeout : min(timeout, Self.directTimeout(for: url))
        let reply = try await transport.get(url, timeout: deadline)
        log("直连 \(url.host ?? "") \(url.path) HTTP \(reply.status) \(Int(-began.timeIntervalSinceNow * 1000))ms")
        try Task.checkCancellation()
        if !Self.fallsBack(reply.status) { return reply }
        if !directOnly { directRetry = Self.directCooldown(for: reply.status) }
        // 上游的状态码到这儿就被吞掉了。留一份带状态码的错误：两条路都没成的时候
        // 抛的是它，`BinanceREST` 才认得出 418/429，才会去按住限流器。
        failure = BinanceError(status: reply.status, url: url.absoluteString)
      } catch is CancellationError { throw CancellationError() }
      catch {
        try Task.checkCancellation()
        if (error as? URLError)?.code == .cancelled { throw CancellationError() }
        // 只走直连时不记冷却：冷却的意义是「先去走网关」，没有网关可走的时候
        // 它只会让下一笔连试都不试就直接失败。
        if directOnly {
          log("直连失败 \(url.host ?? "")（行情线路=直连，不退网关）：\(error)")
        } else {
          directRetry = Date().addingTimeInterval(Self.directCooldownSeconds)
          log("直连失败 \(url.host ?? "")，\(Int(Self.directCooldownSeconds))s 内优先走网关：\(error)")
        }
        failure = error }
    }

    guard let plan, !plan.candidates.isEmpty else { throw failure }
    let raced = await Self.race(plan)
    guard let winner = raced.winner else {
      for candidate in plan.candidates {
        let seconds = raced.retryAfter[candidate.host] ?? Self.gatewayCooldownSeconds
        gatewayRetry[candidate.host] = Date().addingTimeInterval(seconds)
      }
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
    case gateway(GatewayOutcome)
  }

  /// 「直连那一腿已经没戏了」这个消息的传话筒。
  ///
  /// 原来网关腿是死等 `hedgeDelay` 才发。可直连快速失败（DNS 解不开、连接被拒、
  /// 证书不对）往往几十毫秒就有结论——那 0.7 秒纯属白等。现在直连一失败就举旗，
  /// 网关腿最多 20ms 后就看见并立刻出发。
  private final class HedgeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func raise() { lock.lock(); flag = true; lock.unlock() }
    var raised: Bool { lock.lock(); defer { lock.unlock() }; return flag }
  }

  private struct HedgeOutcome: Sendable {
    var direct: DirectLeg?
    var gateway: GatewaySuccess?
    var gatewayRetryAfter: [String: TimeInterval] = [:]
    /// 网关那一腿是自己跑完的，还是被我们取消掉的。只有跑完了才记它的冷却。
    var gatewayFinished = false
  }

  /// 直连与网关并行，返回先到的那份；两边都没成就返回 nil（`failure` 里带着原因）。
  private func hedged(_ url: URL, timeout: TimeInterval, plan: GatewayPlan,
                      failure: inout Error) async throws -> HTTPReply? {
    let transport = self.transport
    let directTimeout = min(timeout, Self.directTimeout(for: url))
    let delay = Self.hedgeDelay
    let began = Date()

    let flag = HedgeFlag()

    let outcome = await withTaskGroup(of: HedgeLeg.self) { group -> HedgeOutcome in
      group.addTask {
        do {
          let reply = try await transport.get(url, timeout: directTimeout)
          // 200（或者退了也没用的 4xx）不举旗：这一腿已经赢了，网关不必出发。
          if MarketRESTTransport.fallsBack(reply.status) { flag.raise() }
          return .direct(DirectLeg(reply: reply, error: nil))
        } catch {
          // 取消不算「直连坏了」，整轮都要作废，别把网关叫起来。
          if !MarketRESTTransport.isCancellation(error) { flag.raise() }
          return .direct(DirectLeg(reply: nil, error: error))
        }
      }
      group.addTask {
        guard await MarketRESTTransport.waitToHedge(delay, flag: flag) else { return .gateway(GatewayOutcome()) }
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
        case .gateway(let raced):
          result.gatewayFinished = true
          result.gateway = raced.winner
          result.gatewayRetryAfter = raced.retryAfter
          if raced.winner != nil {
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
        failure = BinanceError(status: reply.status, url: url.absoluteString)
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
      for candidate in plan.candidates {
        let seconds = outcome.gatewayRetryAfter[candidate.host] ?? Self.gatewayCooldownSeconds
        gatewayRetry[candidate.host] = Date().addingTimeInterval(seconds)
      }
    }
    return nil
  }

  /// 等到该叫网关了。返回 false 表示这一轮被取消，网关腿不必出发。
  ///
  /// 分片轮询而不是一觉睡到底：这样直连举旗之后最多 20ms 就能被看见。
  /// 用轮询而不是 continuation，是因为 continuation 在这个 task group 被
  /// `cancelAll()` 的时候没人去 resume，会把整组挂死。
  private static func waitToHedge(_ delay: TimeInterval, flag: HedgeFlag) async -> Bool {
    var waited: TimeInterval = 0
    while waited < delay {
      if flag.raised { break }
      let slice = min(0.02, delay - waited)
      do { try await Task.sleep(nanoseconds: UInt64(slice * 1_000_000_000)) }
      catch { return false }
      waited += slice
    }
    return !Task.isCancelled
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
      gatewayRetry[candidate.host] = Date().addingTimeInterval(Self.gatewayCooldownSeconds)
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

  /// 这一笔直连该等多久。见 `directBulkTimeout`。
  static func directTimeout(for url: URL) -> TimeInterval {
    switch url.path {
    case "/fapi/v1/exchangeInfo":
      return directBulkTimeout
    case "/fapi/v1/klines":
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      // 没写 limit 就是币安的默认 500；写了就按写的算。1000 根往上算大页。
      let limit = items.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 500
      return limit >= 1000 ? directBulkTimeout : directAttemptTimeout
    default:
      return directAttemptTimeout
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
  /// 币安的 WS 也有直连（`fstream.binance.com`）与网关（`streamFallbacks`，
  /// 就是那两台 VPS）两条路，`MarketSocketRouter` 平时让它们赛跑。
  /// 策略在这儿同样管用；OKX 只有网关这一条路，不受影响。
  let policy: MarketRoutePolicy
  public init(source: MarketSource, hosts: BinanceHosts, factory: any WSSocketFactory = URLSessionSocketFactory(),
              policy: MarketRoutePolicy = .auto) {
    self.source = source; self.hosts = hosts; self.factory = factory; self.policy = policy
  }
  public func connect(to url: URL) async throws -> any WSSocket {
    if source == .binance {
      switch policy {
      case .auto:
        return try await MarketSocketRouter(factory: factory, fallbacks: hosts.streamFallbacks).connect(to: url)
      case .direct:
        // 不带退路：只连币安自己的域名。
        return try await MarketSocketRouter(factory: factory, fallbacks: []).connect(to: url)
      case .gateway:
        // 把首选也换成网关，`MarketSocketRouter` 才不会仍旧把直连塞进候选里。
        // `streamFallbacks` 里可能混着直连域名本身（app 侧把 `fstream.binance.com`
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
        guard let target = parts.url else { throw FeedError.badResponse("行情地址无效") }
        return try await MarketSocketRouter(factory: factory,
                                            fallbacks: Array(gateways.dropFirst())).connect(to: target)
      }
    }
    guard let first = hosts.oiProxies.first, var parts = URLComponents(string: "wss://" + first),
          parts.host != nil, parts.user == nil, parts.password == nil else { throw FeedError.badResponse("行情服务暂不可用") }
    parts.path = "/market/okx/stream"; parts.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    guard let target = parts.url else { throw FeedError.badResponse("行情地址无效") }
    return try await MarketSocketRouter(factory: factory, fallbacks: Array(hosts.oiProxies.dropFirst())).connect(to: target)
  }
}

public extension BinanceREST {
  static func upstream(_ source: MarketSource, hosts: BinanceHosts, log: FeedLog = .silent,
                       policy: MarketRoutePolicy = .auto) -> BinanceREST {
    BinanceREST(hosts: hosts,
                transport: MarketRESTTransport(source: source, gateways: hosts.oiProxies, log: log, policy: policy),
                limiter: source == .binance ? .sharedBinance : .sharedOKX, log: log)
  }

}
