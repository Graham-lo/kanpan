import Foundation
import KanpanCore

/// 币安这一家在两条线路上实际由谁供数：直连是币安本家，网关上币安被封（451），
/// 服务端换成 OKX 的同名永续顶上。只在币安这一支内部使用，上层看不见。
public enum BinanceUpstream: String, Codable, Sendable { case binance, okx }

/// REST adaptation is confined to the upstream boundary. A request never changes exchange.
public actor MarketRESTTransport: HTTPTransport {
  /// 网关被按下去之后歇多久。网关自己在 429 / 503 上给了 `Retry-After` 就听它的，
  /// 但不超过这个上限——更长的退避该由用户换线路来做，不是把一台网关按死。
  private static let gatewayCooldownSeconds: TimeInterval = 10
  /// 上游地域拒绝（451）时这台网关歇多久。它不是「忙一下」：网关那边自己记的是
  /// 60 秒，客户端跟着走，别用 10 秒的短冷却去反复撞同一堵墙。有 `Retry-After`
  /// 或 body 的 `retry_after` 就听上游的。
  private static let gatewayGeoCooldownSeconds: TimeInterval = 60
  private let source: BinanceUpstream
  private let log: FeedLog
  private let transport: any HTTPTransport
  private var gatewayRetry: [String: Date] = [:]
  /// 因为**上游限流**而歇的那些网关：截止时间 + 上游当时给的状态码。
  ///
  /// 和 `gatewayRetry` 分开记是为了别把类别丢掉：冷却期内再来的请求仍然是「限流」，
  /// 不是「行情暂不可用」——压扁成后者，业务层就会当成普通故障接着重试（A-05 / A.10）。
  ///
  /// 状态码也必须记：418 / 403 是 IP 级封禁，429 只是超频，业务层对两者的处理不一样。
  /// 只留截止时间的话，冷却期内重放出去的错误一律变成 429，封禁就被降级成超频了。
  private struct GatewayLimit: Sendable {
    let until: Date
    /// 上游当时回的状态码（网关 `upstream_status`：418 / 429 / 403）。
    let upstreamStatus: Int
  }
  private var gatewayLimited: [String: GatewayLimit] = [:]
  private var preferred: String?
  /// 路由账本的版本号。换线路、清冷却都会把它 +1。
  /// 一场竞速要等好几秒，赢家回来的时候用户可能已经换了线路、或者刚按过重试，
  /// 那份结果就是上一档的旧账，不能再写进来。
  private var routeEpoch = 0
  /// 行情线路（`RouteResolver` 给的决策）：直连就只直连，网关就只网关。
  private var route: MarketRoute
  private var gateways: [String] { route.gateways }

  private struct GatewayCandidate: Sendable {
    let host: String
    let target: URL
    let timeout: TimeInterval
  }

  private struct GatewaySuccess: Sendable {
    let host: String
    let payload: Data
  }

  /// 一轮竞速的结果：赢家（可能没有），外加各台网关自己报的 `Retry-After`
  /// 与它转述的上游语义（限流 / 地域拒绝）。
  private struct GatewayOutcome: Sendable {
    var winner: GatewaySuccess?
    var retryAfter: [String: TimeInterval] = [:]
    var errors: [String: BinanceError] = [:]
    /// 因为**上游限流**而失败的那几台，以及上游当时回的状态码（418 / 429 / 403）。
    var limits: [String: Int] = [:]
  }

  /// 一条腿失败之后怎么记账：这台网关歇多久，以及要不要把上游的语义带给业务层。
  struct GatewayFailure: Sendable {
    var cooldown: TimeInterval
    var error: BinanceError?
    /// 上游限流时那个状态码（418 / 429 / 403）；不是限流就留 nil。
    var upstreamStatus: Int?
  }

  public init(source: BinanceUpstream, route: MarketRoute, transport: any HTTPTransport = URLSessionTransport(),
              log: FeedLog = .silent) {
    self.source = source; self.route = route; self.transport = transport; self.log = log
  }

  /// 测试用的旧写法：线路 + 网关表。
  public init(source: BinanceUpstream, gateways: [String], transport: any HTTPTransport = URLSessionTransport(),
              log: FeedLog = .silent, policy: MarketRoutePolicy = .direct) {
    self.init(source: source, route: MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: gateways)),
              transport: transport, log: log)
  }

  /// 换线路。顺手把网关冷却清掉：线路是用户刚按下的，
  /// 上一档留下的「这台网关先歇着」的账不该拖累新的选择。
  public func setPolicy(_ policy: MarketRoutePolicy) {
    route = MarketRoute(policy: policy, endpoints: route.endpoints)
    resetRouteCooldowns()
  }

  /// 把在飞的那些竞速结果作废：从这一刻起回来的赢家/输家都不许再改路由账本。
  private func invalidateRoutes() { routeEpoch &+= 1 }

  /// 用户显式点「点此重试」时，允许绕过一次网关冷却；自动监控仍然照冷却办事。
  ///
  /// 只清路由冷却。
  ///
  /// **不动限流器上的 IP 封禁**：那是上游对我们整个出口下的判决，用户点一下
  /// 「点此重试」并不能让它提前结束；封禁期内再点，仍然当场失败（A-03 第 4 点）。
  public func resetRouteCooldowns() {
    gatewayRetry.removeAll()
    gatewayLimited.removeAll()
    invalidateRoutes()
  }

  public func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    try Task.checkCancellation()
    #if DEBUG
    if source == .binance, ProcessInfo.processInfo.environment["KANPAN_TEST_BINANCE_REST_DOWN"] == "1" {
      throw FeedError.badResponse("Test: Binance REST unavailable")
    }
    #endif
    // 「直连」只对币安本家成立：替身（OKX）只在网关上有，它那一支永远走网关竞速。
    if !route.viaGateway, source == .binance { return try await direct(url, timeout: timeout) }

    let failure = FeedError.badResponse("行情暂不可用，请重试")
    // 网关代理不了这条路线（`/futures/data/openInterestHist` 就是这种）：
    // 用户选的是网关，那这一笔就没有路可走，立刻认输。
    // 这条 URL 网关根本不代理（`/futures/data/openInterestHist` 就是这种）：和限流
    // 毫无关系，不许借用下面那条「网关在冷却」的判定——否则任一网关正被上游限流时，
    // 一笔本来没有网关路线的 OI 请求也会被报成 429 限流，业务层于是当成出口被按住。
    guard let plan = gatewayPlan(for: url) else {
      log("\(url.path) 没有网关路线（行情线路=\(route.policy.rawValue)），直接跳过")
      throw failure
    }
    guard !plan.candidates.isEmpty else {
      // 有网关路线、但候选一台不剩：如果是上游限流按下去的，这一笔的类别就是「限流」，
      // 剩多少秒、原来是 418 还是 429 都照实说。压扁成「行情暂不可用」的话，
      // 业务层会当成普通故障接着往枪口上撞（A-05 / A.10）。
      if let limit = gatewayLimitRemaining() {
        let banned = limit.upstreamStatus == 418 || limit.upstreamStatus == 403
        log("网关上游限流未解除（上游 \(limit.upstreamStatus)，还剩 \(Int(limit.remaining.rounded(.up))) 秒），\(url.path) 这一笔不发")
        throw BinanceError(status: banned ? 418 : 429,
                           msg: "网关上游限流未解除（上游 \(limit.upstreamStatus)）",
                           url: url.absoluteString, retryAfter: limit.remaining,
                           reason: banned ? .ipBanned : .rateLimited, proxied: true)
      }
      log("\(url.path) 的网关都在冷却里（行情线路=\(route.policy.rawValue)），直接跳过")
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
        let deadline = Date().addingTimeInterval(seconds)
        gatewayRetry[candidate.host] = deadline
        // 上游限流是「这台网关的出口被按住了」：冷却按它自己报的秒数走（可以是 120 秒），
        // 两台各记各的——一台被限不代表另一台也被限。上游那个状态码也一起记下来，
        // 冷却期内要按原类别（418/403 封禁、429 超频）重放，不能一律降级成 429。
        if let upstream = raced.limits[candidate.host] {
          gatewayLimited[candidate.host] = GatewayLimit(until: deadline, upstreamStatus: upstream)
          log("网关 \(candidate.host) 上游限流（\(upstream)），歇 \(Int(seconds.rounded(.up))) 秒")
        } else {
          gatewayLimited[candidate.host] = nil
        }
      }
      // 把上游说的话带上去：限流、地域拒绝、还是普通不可用，业务层要分得清。
      if let signal = Self.mostInformative(raced.errors) {
        throw BinanceError(status: signal.status, code: signal.code, msg: signal.msg,
                           url: url.absoluteString, retryAfter: signal.retryAfter,
                           reason: signal.reason, proxied: true)
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

  /// 网关赢了之后的记账。
  private func settle(_ winner: GatewaySuccess, plan: GatewayPlan) {
    preferred = winner.host
    // 这一轮输掉的网关先歇一会儿：它可能只是慢或者被黑洞吃了，
    // 别让每一行都去把同一场竞速重开一遍。
    for candidate in plan.candidates where candidate.host != winner.host {
      gatewayRetry[candidate.host] = Date().addingTimeInterval(Self.gatewayCooldownSeconds)
    }
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
    let log: FeedLog
  }

  /// 把这条 URL 能走的网关路线算出来。网关代理不了就返回 nil，调用方只能走直连。
  private func gatewayPlan(for url: URL) -> GatewayPlan? {
    var endpoint: String
    let field: String
    switch url.path {
    case "/fapi/v1/klines": endpoint = "klines"; field = "bars"
    case "/fapi/v1/ticker/24hr": endpoint = "ticker"; field = "ticker"
    case "/fapi/v1/exchangeInfo": endpoint = "instruments"; field = "instruments"
    default: return nil
    }
    let ordered = gateways.sorted { $0 == preferred && $1 != preferred }
    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let expectedSymbol = queryItems.first(where: { $0.name == "symbol" })?.value ?? ""
    // 全市场 ticker 没有 symbol，走网关自己的 `/market/v1/tickers`：信封和单品种
    // 一样（`source` + `ticker`），`symbol` 是空串，载荷是币安 `ticker/24hr` 形状的数组。
    // 以前这里直接 `return nil`，于是「网关」这一档下板块页永久取不到全市场报价（A-04）。
    if endpoint == "ticker", expectedSymbol.isEmpty { endpoint = "tickers" }
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
      // 全市场 ticker 是几百个品种的一整份数组，比单品种大得多，给它和历史一样的 8 秒。
      let deadline: TimeInterval = endpoint == "instruments" || endpoint == "ticker"
        ? 5 : (endpoint == "tickers" ? 8 : (source == .binance || smallProbe ? 5 : 8))
      candidates.append(GatewayCandidate(host: host, target: target, timeout: deadline))
    }
    return GatewayPlan(endpoint: endpoint, field: field, expectedSymbol: expectedSymbol,
                       expectedInterval: expectedInterval, sourceRawValue: source.rawValue,
                       candidates: candidates, transport: transport, log: log)
  }

  /// 几台网关一起发，谁先回一份校验得过的同源载荷就用谁。
  private static func race(_ plan: GatewayPlan) async -> GatewayOutcome {
    typealias Leg = (host: String, success: GatewaySuccess?, failure: GatewayFailure?)
    return await withTaskGroup(of: Leg.self) { group -> GatewayOutcome in
      for candidate in plan.candidates {
        group.addTask {
          do {
            let reply = try await plan.transport.get(candidate.target, timeout: candidate.timeout)
            guard reply.status == 200 else {
              // 网关自己说了过多久再来就听它的，比一刀切 10 秒恢复得快；
              // 而且要看 body 的 `error`——同一个 429 可能是「本机忙两秒」，
              // 也可能是「上游把我们按了 120 秒」。
              return (candidate.host,
                      nil,
                      MarketRESTTransport.gatewayFailure(reply, url: candidate.target))
            }
            guard let data = MarketRESTTransport.payload(of: reply.body, plan: plan) else {
              // 回了 200 但信封不对（来源、品种或周期对不上、字段缺失）：这台网关给的是
              // 别人的数据，按普通不可用记冷却，并留一行日志说清楚是哪一种。
              plan.log("网关 \(candidate.host) \(plan.endpoint) 载荷校验不过（期望 source=\(plan.sourceRawValue) symbol=\(plan.expectedSymbol)）")
              return (candidate.host, nil,
                      GatewayFailure(cooldown: MarketRESTTransport.gatewayCooldownSeconds, error: nil))
            }
            return (candidate.host, GatewaySuccess(host: candidate.host, payload: data), nil)
          } catch is CancellationError {
            // 竞速里被取消的一支：要么是别的网关先赢了，要么是整笔被上层取消。都不是这台的错。
            return (candidate.host, nil, nil)
          } catch let error as URLError where error.code == .cancelled {
            return (candidate.host, nil, nil)
          } catch {
            // 传输层失败（超时、断网、TLS、连不上）：以前在这里一声不吭地吞掉，
            // 两台都失败时上层只看得到一句笼统的「行情服务暂不可用」。现在按类记一行。
            plan.log("网关 \(candidate.host) \(plan.endpoint) 传输失败（\(MarketRESTTransport.transportKind(error))）：\(error.localizedDescription)")
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
        if let hint = leg.failure {
          result.retryAfter[leg.host] = hint.cooldown
          if let error = hint.error { result.errors[leg.host] = error }
          if let upstream = hint.upstreamStatus { result.limits[leg.host] = upstream }
        }
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

  /// 网关 `/market/v1/*` 的失败信封（`Backend/kanpan-gateway/README.md`「失败线契约」）。
  ///
  /// `upstreamStatus` 是 **JSON 字符串**（`"429"` / `"418"` / `"403"` / `"50011"`），
  /// 别按 Int 解；`retryAfter` 是 JSON 数字（整数秒）。
  struct GatewayFailureBody: Decodable {
    var error: String?
    var source: String?
    var code: Int?
    var retryAfter: Double?
    var upstreamStatus: String?
  }

  /// 网关的失败响应 → 「这台歇多久」+「要不要把上游的语义带给业务层」。
  ///
  /// 同一个 429 可能是两件相反的事，所以看 body 的 `error`：
  /// - `upstream_rate_limited`：上游把网关按住了。冷却**不夹 10 秒**，头与 body 取更大者；
  ///   错误类别是「限流」（`upstreamStatus == "418"` 时是 IP 级封禁），一路带给业务层。
  /// - `upstream_blocked`：上游地域拒绝（451），类别是「地域拒绝」，和限流分得开。
  /// - `busy`：本机准入/队列满，几秒的事，按原来的短冷却，不算上游限流。
  /// - 其他：普通不可用，短冷却，不给业务层额外语义。
  static func gatewayFailure(_ reply: HTTPReply, url: URL) -> GatewayFailure {
    let body = try? JSONDecoder().decode(GatewayFailureBody.self, from: reply.body)
    let header = BinanceError.retryAfterSeconds(reply.header("Retry-After"))
    switch body?.error {
    case "upstream_rate_limited":
      let upstream = body?.upstreamStatus ?? ""
      let code = Int(upstream) ?? 429
      // 418（IP ban）和 403（币安对被封出口也会回这个）都是 IP 级封禁，起步 2 分钟；
      // 429 只是超频，起步 10 秒。
      let banned = code == 418 || code == 403
      let said = max(body?.retryAfter ?? 0, header ?? 0)
      let seconds = said > 0 ? said
        : (banned ? RateLimiter.ipBanFloorSeconds : RateLimiter.rateLimitFloorSeconds)
      let who = [body?.source, upstream.isEmpty ? nil : upstream].compactMap { $0 }.joined(separator: " ")
      return GatewayFailure(cooldown: seconds,
                            error: BinanceError(status: banned ? 418 : 429, code: body?.code,
                                                msg: "网关上游限流（\(who)）", url: url.absoluteString,
                                                retryAfter: seconds,
                                                reason: banned ? .ipBanned : .rateLimited,
                                                proxied: true),
                            upstreamStatus: code)
    case "upstream_blocked":
      // 地域拒绝不是「忙一下」：这台网关的出口被上游按地区拒了，10 秒后再问还是同一堵墙。
      // 上游说了多久就听它的，没说按 60 秒（和网关自己记的那一档一致）。
      let said = max(body?.retryAfter ?? 0, header ?? 0)
      let geoSeconds = said > 0 ? said : gatewayGeoCooldownSeconds
      return GatewayFailure(cooldown: geoSeconds,
                            error: BinanceError(status: 451, code: body?.code,
                                                msg: "网关上游地域拒绝（\(body?.source ?? "")）",
                                                url: url.absoluteString,
                                                retryAfter: geoSeconds,
                                                reason: .geoBlocked, proxied: true))
    default:
      // `busy`（本机准入/队列满）和其他失败都走这条：短冷却，不带上游语义。
      return GatewayFailure(cooldown: gatewayCooldown(reply), error: nil)
    }
  }

  /// 直连回的失败响应 → 带齐上游信号的错误（`Retry-After` / `code` / 类别）。
  static func upstreamError(_ reply: HTTPReply, url: URL) -> BinanceError {
    struct Body: Decodable { var code: Int?; var msg: String? }
    let body = try? JSONDecoder().decode(Body.self, from: reply.body)
    return BinanceError(status: reply.status, code: body?.code, msg: body?.msg,
                        url: url.absoluteString,
                        retryAfter: BinanceError.retryAfterSeconds(reply.header("Retry-After")))
  }

  /// 一轮竞速里几台网关各报了一种失败，挑最该让业务层知道的那个：
  /// IP 封禁 > 限流 > 地域拒绝 > 其他。
  private static func mostInformative(_ errors: [String: BinanceError]) -> BinanceError? {
    func rank(_ e: BinanceError) -> Int {
      switch e.reason {
      case .ipBanned: return 3
      case .rateLimited, .blocked: return 2
      case .geoBlocked: return 1
      case .http: return 0
      }
    }
    return errors.values.max { a, b in
      rank(a) != rank(b) ? rank(a) < rank(b) : (a.retryAfter ?? 0) < (b.retryAfter ?? 0)
    }
  }

  /// 还在上游限流冷却里的网关中，最早能用的那台还要等多少秒、以及它是被什么按下的。
  /// 全都不在冷却里就返回 nil。
  ///
  /// 取「最早能用的那台」：它就是这一笔最快的出路，剩余秒数和类别都该按它说。
  private func gatewayLimitRemaining() -> (remaining: TimeInterval, upstreamStatus: Int)? {
    let now = Date()
    gatewayLimited = gatewayLimited.filter { $0.value.until > now }
    guard let earliest = gatewayLimited.values.min(by: { $0.until < $1.until }) else { return nil }
    return (max(0, earliest.until.timeIntervalSince(now)), earliest.upstreamStatus)
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

/// 行情 WS 的拨号：线路决策来自 `MarketRoute`，这里只把它翻成具体的地址。
///
/// 只有两条生产上真走得到的路：
/// - 币安本家 + 直连：连币安自己的流域名（`hosts.stream`），不带任何退路。
/// - 替身（OKX）：只在网关上有，连网关的 `/market/okx/stream`，主备两台按顺序拨。
///
/// 「币安本家 + 网关」这一格以前有一段拨 `/market/stream` 的代码，但生产上没有人走得到：
/// 选了网关，`BinanceProvider.upstream(for:)` 给的就是替身；唯一在网关线路下还拿币安本家的
/// 是复盘的 `makeOwn`，它只取 REST K 线、从不开流。所以这一格现在明确抛错，不再留一条
/// 没人验证过的暗路（也不许悄悄退回直连——线路选了网关就只走网关）。
public struct SourceSocketFactory: WSSocketFactory {
  let source: BinanceUpstream
  let hosts: BinanceHosts
  let factory: any WSSocketFactory
  let viaGateway: Bool
  let log: FeedLog
  public init(source: BinanceUpstream, hosts: BinanceHosts, factory: any WSSocketFactory = URLSessionSocketFactory(),
              route: MarketRoute, log: FeedLog = .silent) {
    self.source = source; self.hosts = hosts; self.factory = factory; self.viaGateway = route.viaGateway; self.log = log
  }
  /// 测试用：只给线路档位，网关表取 `hosts.oiProxies`。
  public init(source: BinanceUpstream, hosts: BinanceHosts, factory: any WSSocketFactory = URLSessionSocketFactory(),
              policy: MarketRoutePolicy, log: FeedLog = .silent) {
    self.init(source: source, hosts: hosts, factory: factory,
              route: MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: hosts.oiProxies)), log: log)
  }
  public func connect(to url: URL) async throws -> any WSSocket {
    switch (source, viaGateway) {
    case (.binance, false):
      // 不带退路：只连币安自己的域名。
      return try await MarketSocketRouter(factory: factory, fallbacks: [], log: log).connect(to: url)
    case (.binance, true):
      log("行情流：网关线路下不开币安本家的流（没有这条生产路径）")
      throw FeedError.badResponse("行情服务暂不可用")
    case (.okx, _):
      guard let first = hosts.oiProxies.first, var parts = URLComponents(string: "wss://" + first),
            parts.host != nil, parts.user == nil, parts.password == nil else { throw FeedError.badResponse("行情服务暂不可用") }
      parts.path = "/market/okx/stream"; parts.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
      guard let target = parts.url else { throw FeedError.badResponse("行情地址无效") }
      return try await MarketSocketRouter(factory: factory, fallbacks: Array(hosts.oiProxies.dropFirst()), log: log).connect(to: target)
    }
  }
}

public extension BinanceREST {
  /// 某条线路上的 REST 客户端。线路由 `RouteResolver` 定好传进来（`MarketRoute`），
  /// 这里不再自己去读设置。
  static func upstream(_ source: BinanceUpstream, hosts: BinanceHosts, route: MarketRoute,
                       log: FeedLog = .silent) -> BinanceREST {
    BinanceREST(hosts: hosts,
                transport: MarketRESTTransport(source: source, route: route, log: log),
                limiter: source == .binance ? .sharedBinance : .sharedOKX, log: log)
  }

}
