import Foundation

/// 看盘自己的后端（`kanpan-api`，`/v1/*`）上那些免鉴权只读接口的取数口。
///
/// 后端只在主机上（`MarketRoute.apiHosts`；备机是 metrics 模式，这些路径 404），跟行情线路选直连
/// 还是网关无关——直连线路下板块历史、供应量这些也只能问后端。主机表从 `RouteResolver.backend` 拿，
/// 不在各页面自己拼名单、自己建 `URLSession`。
///
/// 规则：
/// - 主机表里的按顺序试；连不上 / 超时 / 5xx / 429 换下一台，4xx（除 429）是这一笔本身的问题，换主机也一样，直接报。
/// - 每一次失败都按类记一行日志（传输类、HTTP 状态），不再一声不吭地吞掉。
/// - 取消就是取消，不当失败记。
public struct BackendClient: Sendable, Equatable {
  public let hosts: [String]
  let transport: any HTTPTransport
  let log: FeedLog

  public init(hosts: [String], transport: any HTTPTransport = URLSessionTransport(), log: FeedLog = .silent) {
    self.hosts = hosts; self.transport = transport; self.log = log
  }

  /// 同一张主机表就是同一个后端（传输与日志只是实现细节）。
  public static func == (a: BackendClient, b: BackendClient) -> Bool { a.hosts == b.hosts }

  /// 失败的类别。调用方多半只关心「有没有」，但日志与测试要分得清。
  public enum Failure: Error, Equatable, Sendable {
    /// 没有可问的主机（主机表空、或都拼不出合法地址）。
    case noHost
    /// 连不上、超时、TLS 这类传输层问题（带上最后那台的类别）。
    case transport(String)
    /// 后端回了非 200。
    case http(Int)
  }

  /// `GET https://<host><path>?<query>`，返回 200 的 body。
  public func get(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval = 8) async throws -> Data {
    var failure: Failure = .noHost
    for host in hosts {
      guard let url = Self.url(host: host, path: path, query: query) else { continue }
      let reply: HTTPReply
      do { reply = try await transport.get(url, timeout: timeout) }
      catch {
        if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled {
          throw CancellationError()
        }
        let kind = MarketRESTTransport.transportKind(error)
        log("后端 \(host) \(path) 传输失败（\(kind)）：\(error.localizedDescription)")
        failure = .transport(kind)
        continue
      }
      if reply.status == 200 { return reply.body }
      log("后端 \(host) \(path) HTTP \(reply.status)")
      failure = .http(reply.status)
      if (400..<500).contains(reply.status), reply.status != 429 { throw failure }
    }
    throw failure
  }

  /// `host` 可能带端口（备用网关是 `…:8443`），不能直接塞进 `URLComponents.host`。
  static func url(host: String, path: String, query: [URLQueryItem]) -> URL? {
    guard var c = URLComponents(string: "https://\(host)"), c.host != nil,
          c.user == nil, c.password == nil, c.path.isEmpty, c.query == nil else { return nil }
    c.path = path
    c.queryItems = query.isEmpty ? nil : query
    return c.url
  }
}
