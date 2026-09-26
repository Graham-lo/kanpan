import Foundation
import Testing
@testable import KanpanNetwork

// 压测 · 「滴数据」的对端：每隔一小段来一个字节、永远不收尾。空闲超时一直不触发，
// 原来这笔请求永远挂着（URLSession.shared 的资源超时是 7 天）；现在整笔到总时限就报超时。
// 对端是本进程里的 URLProtocol，不联网。

/// 回 200 之后每 50 ms 滴一个字节，直到被停。
private final class DripProtocol: URLProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var stopped = false

  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "drip.test" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let url = request.url!
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                                          headerFields: ["Content-Length": "100000000"])!,
                        cacheStoragePolicy: .notAllowed)
    Thread.detachNewThread { [self] in
      while !lock.withLock({ stopped }) {
        client?.urlProtocol(self, didLoad: Data([0x5B]))
        Thread.sleep(forTimeInterval: 0.05)
      }
    }
  }

  override func stopLoading() { lock.withLock { stopped = true } }
}

/// 立刻回一页完整的 JSON（对照：正常请求不受总时限影响）。
private final class QuickProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "quick.test" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                                          headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("[]".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@Suite("压测 · 滴数据的对端")
struct StressDripTransportTests {
  private func transport() -> URLSessionTransport {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DripProtocol.self, QuickProtocol.self]
    return URLSessionTransport(session: URLSession(configuration: config))
  }

  @Test("空闲超时一直不触发的请求，到总时限报超时，不再永远挂着", .timeLimit(.minutes(1)))
  func dripEndsAtTotalDeadline() async throws {
    let http = transport()
    // 空闲超时 0.4 秒：每 50 ms 一个字节，空闲超时永远等不到；总时限是它的 3 倍。
    var thrown: (any Error)?
    do { _ = try await http.get(URL(string: "https://drip.test/api/v3/klines")!, timeout: 0.4) } catch { thrown = error }
    let code = (thrown as? URLError)?.code
    #expect(code == .timedOut, "滴数据的请求应当以超时收尾，实际 \(String(describing: thrown))")
  }

  @Test("正常请求照常拿到")
  func quickReplyUnaffected() async throws {
    let reply = try await transport().get(URL(string: "https://quick.test/api/v3/ping")!, timeout: 0.4)
    #expect(reply.status == 200)
    #expect(reply.body == Data("[]".utf8))
  }
}
