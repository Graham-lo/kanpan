import Foundation
import Testing
import KanpanAccount
@testable import Kanpan

/// app 里按人落盘的那几条请求（同步、复盘、收件箱）钉在档案的主人上：
/// 客户端这一刻替的是别人时不出门，不带着新人的令牌去拉 / 推上一个人的东西。

/// 假服务器：记下每一趟出门的路径，一律答空。
final class OwnerPinProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var seen: [String] = []
  static func reset() { lock.lock(); seen = []; lock.unlock() }
  static var paths: [String] { lock.lock(); defer { lock.unlock() }; return seen }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url?.path ?? ""
    Self.lock.lock(); Self.seen.append(path); Self.lock.unlock()
    let body: String
    if path.hasSuffix("/v1/friends") { body = #"{"data":[]}"# }
    else if path.hasSuffix("/v1/shares/inbox") { body = #"{"data":{"items":[],"cursor":""}}"# }
    else { body = #"{"data":{"ok":true}}"# }
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private final class PinVault: CredentialVault, @unchecked Sendable {
  let slotIdentifier = "memory:owner-pin-" + UUID().uuidString
  private let lock = NSLock()
  private var value: SavedAccount?
  func read() throws -> SavedAccount? { lock.lock(); defer { lock.unlock() }; return value }
  func write(_ next: SavedAccount?) throws { lock.lock(); value = next; lock.unlock() }
}

@MainActor
@Suite("按人落盘的请求钉住档案主人", .serialized, .timeLimit(.minutes(1)))
struct OwnerPinnedRequestsTests {
  private let alice = AccountUser(id: UUID(uuidString: "A11CE000-3333-4C0A-9E2D-0A1B2C3D4E5F")!, email: "alice")
  private let bob = UUID(uuidString: "B0B00000-3333-4C0A-9E2D-0A1B2C3D4E5F")!

  private func signedInAsAlice() async throws -> AccountClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OwnerPinProtocol.self]
    let client = try AccountClient(baseURL: URL(string: "https://kanpan.107-174-172-10.sslip.io")!,
                                   vault: PinVault(), session: URLSession(configuration: configuration))
    let feature = AccountFeature(client: client)
    feature.onPrepareAccount = { _ in {} }
    let json: [String: Any] = [
      "user": ["id": alice.id.uuidString, "email": alice.email],
      "sessionId": UUID().uuidString, "accessToken": "a-1", "refreshToken": "r-1",
      "expiresAt": 900_000, "serverTime": 0,
    ]
    try await feature.accept(JSONDecoder().decode(AccountTokens.self, from: JSONSerialization.data(withJSONObject: json)))
    return client
  }

  @Test("收件箱替 bob 拉、客户端现在是 alice：不出门，当场取消")
  func inboxPinnedToAnotherOwnerStaysHome() async throws {
    OwnerPinProtocol.reset()
    let client = try await signedInAsAlice()
    await #expect(throws: CancellationError.self) { _ = try await ShareClient(api: client, owner: bob).inbox(after: nil) }
    await #expect(throws: CancellationError.self) { _ = try await ShareClient(api: client, owner: bob).friends() }
    #expect(OwnerPinProtocol.paths.allSatisfy { !$0.contains("/v1/shares") && !$0.contains("/v1/friends") })
    // 替自己拉照常出门。
    _ = try await ShareClient(api: client, owner: alice.id).inbox(after: nil)
    #expect(OwnerPinProtocol.paths.contains { $0.hasSuffix("/v1/shares/inbox") })
  }

  @Test("按 bob 的档案建的同步传输，客户端现在是 alice：推、拉都不出门")
  func syncTransportPinnedToAnotherOwnerStaysHome() async throws {
    OwnerPinProtocol.reset()
    let client = try await signedInAsAlice()
    let transport = HTTPSyncTransport(client: client, owner: bob)
    await #expect(throws: CancellationError.self) { _ = try await transport.push(Data("{}".utf8), key: UUID()) }
    await #expect(throws: CancellationError.self) { _ = try await transport.bootstrap(collection: "drawings", prefix: nil, after: nil) }
    #expect(OwnerPinProtocol.paths.allSatisfy { !$0.contains("/v1/sync") })
  }
}
