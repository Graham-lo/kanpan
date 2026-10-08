import Foundation

/// 一家交易所的 REST 客户端。**不认识任何一家**：地址来自那一家的 `VenueEndpoints`，
/// 限速来自那一家的 `VenueRateLimiter.shared`，错误体怎么读由 `message` 说。
///
/// 规矩（两条线路一样）：
/// - 主机按 `endpoints.restHosts` 的顺序试：连不上 / 5xx 换下一台（网关主 → 备）；
/// - 4xx 是这一笔本身的问题（品种不存在、参数不对），换主机也一样，直接报；
/// - 429 按 `Retry-After`（没有就 1 秒）罚那一家的限速器，整把歇够了在同一台上再试，最多 3 次；
/// - 每一次出站都先在限速器上排队（按权重计的交易所报这一笔的权重），被取消就不出站。
///
/// GET 与 POST JSON 都走这一套（Hyperliquid 的 `info` 查询是 POST）。
public struct VenueREST: Sendable {
  public let endpoints: VenueEndpoints
  let transport: any HTTPTransport
  let limiter: VenueRateLimiter
  let log: FeedLog
  /// 错误体 → 给人看的一句话（各家字段名不同）。
  let message: @Sendable (Data) -> String?

  /// 429 在同一台主机上最多试几次（含第一次）。
  static let rateLimitAttempts = 3

  public init(endpoints: VenueEndpoints, transport: any HTTPTransport, limiter: VenueRateLimiter,
              log: FeedLog = .silent, message: @escaping @Sendable (Data) -> String? = VenueREST.defaultMessage) {
    self.endpoints = endpoints; self.transport = transport; self.limiter = limiter
    self.log = log; self.message = message
  }

  /// GET `<前缀><path>?<query>`。`weight` 是这一笔在限速器上记多少（按次数的限速器上一笔就是一笔）。
  public func get(_ path: String, query: [URLQueryItem] = [], weight: Double = 1,
                  timeout: TimeInterval = 15) async throws -> Data {
    try await send(path, query: query, weight: weight, timeout: timeout) { url in
      try await transport.get(url, timeout: timeout)
    }
  }

  /// POST `<前缀><path>?<query>`，正文是一段 JSON。
  public func post(_ path: String, query: [URLQueryItem] = [], json body: Data, weight: Double = 1,
                   timeout: TimeInterval = 15) async throws -> Data {
    try await send(path, query: query, weight: weight, timeout: timeout) { url in
      try await transport.post(url, json: body, timeout: timeout)
    }
  }

  private func send(_ path: String, query: [URLQueryItem], weight: Double, timeout: TimeInterval,
                    _ request: @Sendable (URL) async throws -> HTTPReply) async throws -> Data {
    let hosts = endpoints.restHosts
    guard !hosts.isEmpty else { throw FeedError.badResponse("行情暂不可用，请重试") }
    var failure: any Error = FeedError.badResponse("行情暂不可用，请重试")
    for host in hosts {
      guard let url = endpoints.rest(path, query: query, host: host) else { continue }
      var attempt = 0
      while true {
        attempt += 1
        try await limiter.acquire(weight: weight)
        let reply: HTTPReply
        do { reply = try await request(url) }
        catch {
          if error is CancellationError || Task.isCancelled { throw CancellationError() }
          log("\(endpoints.spec.source) \(url.path) 失败：\(error)")
          failure = error
          break
        }
        log("\(endpoints.spec.source) \(url.path)\(url.query.map { "?\($0)" } ?? "") → \(reply.status) \(reply.body.count)B")
        if reply.status == 200 { return reply.body }
        let retry = UpstreamError.retryAfterSeconds(reply.header("Retry-After"))
        let error = UpstreamError(status: reply.status, msg: message(reply.body),
                                  url: url.absoluteString, retryAfter: retry,
                                  proxied: endpoints.viaGateway)
        if reply.status == 429 {
          await limiter.penalize(seconds: retry ?? 1)
          failure = error
          if attempt < Self.rateLimitAttempts { continue }
          throw error
        }
        if (400..<500).contains(reply.status) { throw error }
        failure = error
        break
      }
    }
    throw failure
  }

  /// 常见的几种错误体：`{"message":…}`、`{"error":…}`、`{"msg":…}`。
  public static let defaultMessage: @Sendable (Data) -> String? = { body in
    struct E: Decodable { var message: String?; var error: String?; var msg: String? }
    let e = try? JSONDecoder().decode(E.self, from: body)
    return e?.message ?? e?.error ?? e?.msg
  }
}
