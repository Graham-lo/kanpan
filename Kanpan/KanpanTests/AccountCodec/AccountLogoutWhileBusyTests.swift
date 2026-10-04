import Foundation
import Testing
import KanpanAccount
@testable import Kanpan

/// 审查 D-09：登录还在路上时点「退出登录」。原来 `logout()` 见 `busy` 直接返回，点了没反应；
/// 现在退登优先，在路上的登录回来时认出自己过时：不登回来，服务端那条新会话吊销掉。

/// 假服务器：`v1/auth/login` 扣住，扣住时报到一声；`session/revoke` 数趟数；别的原地答 ok。
final class BusyLogoutProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var released = false
  nonisolated(unsafe) private static var held: [@Sendable () -> Void] = []
  nonisolated(unsafe) private static var revokes = 0
  nonisolated(unsafe) private static var arrivals: AsyncStream<Void>.Continuation?
  static let tokens = #"{"data":{"user":{"id":"A11CE000-3333-4C0A-9E2D-0A1B2C3D4E5F","email":"alice"},"sessionId":"5E550000-0000-4000-8000-000000000001","accessToken":"a-late","refreshToken":"r-late","expiresAt":900000,"serverTime":0}}"#

  static func reset() -> AsyncStream<Void> {
    lock.lock(); defer { lock.unlock() }
    released = false; held = []; revokes = 0
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    arrivals = continuation
    return stream
  }
  static func release() {
    lock.lock(); released = true; let waiting = held; held = []; lock.unlock()
    for answer in waiting { DispatchQueue.global().async(execute: answer) }
  }
  static var revokeCount: Int { lock.lock(); defer { lock.unlock() }; return revokes }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url?.path ?? ""
    if path.hasSuffix("/v1/auth/session/revoke") {
      Self.lock.lock(); Self.revokes += 1; Self.lock.unlock()
    }
    guard path.hasSuffix("/v1/auth/login") else { answer(#"{"data":{"ok":true}}"#); return }
    Self.lock.lock()
    let hold = !Self.released
    if hold { Self.held.append { [self] in self.answer(Self.tokens) } }
    let arrived = Self.arrivals
    Self.lock.unlock()
    if hold { arrived?.yield() } else { answer(Self.tokens) }
  }
  private func answer(_ body: String) {
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private final class MemoryVault: CredentialVault, @unchecked Sendable {
  let slotIdentifier = "memory:busy-logout-" + UUID().uuidString
  private let lock = NSLock()
  private var value: SavedAccount?
  func read() throws -> SavedAccount? { lock.lock(); defer { lock.unlock() }; return value }
  func write(_ next: SavedAccount?) throws { lock.lock(); value = next; lock.unlock() }
}

@MainActor
@Suite("账号页 · 忙着的时候点退出", .serialized, .timeLimit(.minutes(1)))
struct AccountLogoutWhileBusyTests {
  @Test("登录还在路上时点退出：当场退掉；登录回包到了也不登回来，那条新会话吊销掉")
  func logoutWinsOverInFlightLogin() async throws {
    let arrivals = BusyLogoutProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BusyLogoutProtocol.self]
    let client = try AccountClient(baseURL: URL(string: "https://kanpan.43-160-232-253.sslip.io")!,
                                   vault: MemoryVault(), session: URLSession(configuration: configuration))
    let feature = AccountFeature(client: client)
    var prepared: [AccountUser?] = []
    feature.onPrepareAccount = { user in prepared.append(user); return {} }
    feature.page = .login; feature.email = "alice"; feature.password = "abc12345"
    feature.submit()
    #expect(feature.busy)
    for await _ in arrivals { break }

    await feature.logout()
    #expect(!feature.busy, "退登之后账号页还转着圈")
    #expect(feature.user == nil)

    BusyLogoutProtocol.release()
    for _ in 0..<300 where BusyLogoutProtocol.revokeCount == 0 { try await Task.sleep(for: .milliseconds(10)) }
    await client.settleRevocation()
    #expect(feature.user == nil, "退登之后迟到的登录回包又把人登回来了")
    #expect(await client.savedUser() == nil, "迟到的令牌被写进了钥匙串")
    #expect(BusyLogoutProtocol.revokeCount == 1, "服务端那条迟到签出的会话没吊销")
    #expect(!prepared.contains { $0 != nil }, "迟到的登录装上了那个人的档案")
    #expect(feature.error == nil)
    #expect(!feature.busy)
  }
}
