import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

/// 后端（kanpan-api `/v1/*`）只读接口的取数口：主备顺序、失败分类、日志。
@Suite("后端取数口") struct BackendClientTests {

  final class Recorder: @unchecked Sendable {
    private let lock = NSLock(); private var lines: [String] = []
    func add(_ s: String) { lock.withLock { lines.append(s) } }
    var all: [String] { lock.withLock { lines } }
  }

  actor FailFirst: HTTPTransport {
    var hosts: [String] = []
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      hosts.append(url.host!)
      if hosts.count == 1 { throw URLError(.timedOut) }
      return json(#"{"data":1}"#)
    }
  }

  @Test("主台超时换备台（带端口），并按类记一行日志")
  func fallsToBackupAndLogs() async throws {
    let net = FailFirst(), rec = Recorder()
    let client = BackendClient(hosts: ["a.test", "b.test:8443"], transport: net, log: FeedLog { rec.add($0) })
    let body = try await client.get("/v1/market/sector-history")
    #expect(String(decoding: body, as: UTF8.self) == #"{"data":1}"#)
    #expect(await net.hosts == ["a.test", "b.test"])
    #expect(rec.all.count == 1 && rec.all[0].contains("超时"))
  }

  @Test("4xx 是这一笔自己的问题，不换主机；5xx 换，全失败按最后一台的类别报")
  func classifiesHTTP() async {
    let bad = FakeServer { _ in json("{}", status: 404) }
    let client = BackendClient(hosts: ["a.test", "b.test"], transport: FakeTransport(bad))
    await #expect(throws: BackendClient.Failure.http(404)) { _ = try await client.get("/v1/x") }
    #expect(await bad.urls().count == 1)

    let down = FakeServer { _ in json("{}", status: 503) }
    let both = BackendClient(hosts: ["a.test", "b.test"], transport: FakeTransport(down))
    await #expect(throws: BackendClient.Failure.http(503)) { _ = try await both.get("/v1/x") }
    #expect(await down.urls().count == 2)
  }

  @Test("没有主机就报 noHost，不去拼别的地址")
  func noHost() async {
    let server = FakeServer { _ in json("{}") }
    let client = BackendClient(hosts: [], transport: FakeTransport(server))
    await #expect(throws: BackendClient.Failure.noHost) { _ = try await client.get("/v1/x") }
    #expect(await server.urls().isEmpty)
  }

  @Test("RouteResolver 给的后端是线上两台网关，两档线路都一样")
  func resolverBackend() {
    #expect(RouteResolver(policy: .direct).backend.hosts == MarketEndpoints.production.gateways)
    #expect(RouteResolver(policy: .gateway).backend == RouteResolver(policy: .direct).backend)
  }
}
