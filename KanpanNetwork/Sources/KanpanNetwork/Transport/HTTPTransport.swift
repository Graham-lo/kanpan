import Foundation

/// 一次 HTTP 往返的结果。测试里的假 server 也只需要造这个。
public struct HTTPReply: Sendable {
  public var status: Int
  public var headers: [String: String]
  public var body: Data
  public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
    self.status = status; self.headers = headers; self.body = body
  }
  public func header(_ name: String) -> String? {
    let k = name.lowercased()
    for (h, v) in headers where h.lowercased() == k { return v }
    return nil
  }
}

/// 把网络抽掉，`RateLimitTests` / `FeedReplayTests` 才能不联网跑。
public protocol HTTPTransport: Sendable {
  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply
}

extension HTTPTransport {
  public func get(_ url: URL) async throws -> HTTPReply { try await get(url, timeout: 15) }
}

/// 真网络。
///
/// `timeout` 是 URLRequest 的空闲超时（两次收到字节之间最多隔多久）；另加一道整笔的总时限
/// `totalSeconds(for:)`。原来只有空闲超时，`URLSession.shared` 的资源超时是 7 天：对方「滴数据」
/// （每隔几秒来一个字节）时这笔请求永远不结束——网关竞速要等每条腿收尾，首屏、补缺、自愈跟着一直挂着，
/// 补缺期间进队的 K 线与成交越攒越多。
public struct URLSessionTransport: HTTPTransport {
  let session: URLSession

  public init(session: URLSession = .shared) { self.session = session }

  public func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    req.httpMethod = "GET"
    // 币安对没有 UA 的请求偶尔更严，带一个固定的，方便对方限流统计。
    req.setValue("kanpan-ios/1.0", forHTTPHeaderField: "User-Agent")
    #if DEBUG
      if SimulatedOutage.active { throw URLError(.notConnectedToInternet) }
    #endif
    let session = self.session, request = req
    let (data, resp) = try await Deadline.run(seconds: Self.totalSeconds(for: timeout)) {
      try await session.data(for: request)
    }
    guard let http = resp as? HTTPURLResponse else {
      throw FeedError.badResponse("非 HTTP 响应 \(url)")
    }
    var headers: [String: String] = [:]
    for (k, v) in http.allHeaderFields {
      if let ks = k as? String, let vs = v as? String { headers[ks] = vs }
    }
    return HTTPReply(status: http.statusCode, headers: headers, body: data)
  }

  /// 整笔请求的总时限：空闲超时的 3 倍（15 秒的 K 线请求最多 45 秒）。正常的大页在慢网上也远用不到。
  public static func totalSeconds(for timeout: TimeInterval) -> TimeInterval { timeout * 3 }
}
