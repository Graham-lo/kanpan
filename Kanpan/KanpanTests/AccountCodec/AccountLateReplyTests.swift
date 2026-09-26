import Foundation
import Testing
import KanpanAccount
@testable import Kanpan

/// 账号页上那几件在路上的事（设备列表、踢设备）回来时，人要是已经退了或换了，
/// 回来的东西一概不认：不摆到页上，也不把客户端作废旧请求时抛的错念成一句提示。
/// 同一行「退出」连点两下只发一趟。

/// 假服务器：`v1/auth/devices` 这一条可以扣住，扣住时报到一声；别的一律原地答 ok。
/// 记下每一趟 DELETE，数连点发了几趟。扣住不阻塞加载线程（那条线程别的请求也要用）：
/// 把这一趟的回话存起来，放行时再在后台队列上答。
final class LateReplyProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var holdDevices = false
  nonisolated(unsafe) private static var deletes = 0
  nonisolated(unsafe) private static var released = false
  nonisolated(unsafe) private static var held: [@Sendable () -> Void] = []
  nonisolated(unsafe) private static var arrivals: AsyncStream<Void>.Continuation?

  static func reset(holdDevices hold: Bool) -> AsyncStream<Void> {
    lock.lock(); defer { lock.unlock() }
    holdDevices = hold; deletes = 0; released = false; held = []
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    arrivals = continuation
    return stream
  }
  static func release() {
    lock.lock(); released = true; let waiting = held; held = []; lock.unlock()
    for answer in waiting { DispatchQueue.global().async(execute: answer) }
  }
  static var deleteCount: Int { lock.lock(); defer { lock.unlock() }; return deletes }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url?.path ?? ""
    if request.httpMethod == "DELETE" {
      Self.lock.lock(); Self.deletes += 1; Self.lock.unlock()
    }
    guard path.hasSuffix("/v1/auth/devices"), request.httpMethod == "GET" else {
      answer(#"{"data":{"ok":true}}"#)
      return
    }
    let body = #"{"data":{"devices":[{"id":"D0000000-0000-4000-8000-000000000001","name":"alice 的手机","kind":"phone","createdAt":0,"lastSeen":0,"current":true}]}}"#
    Self.lock.lock()
    let hold = Self.holdDevices && !Self.released
    if hold { Self.held.append { [self] in self.answer(body) } }
    let arrived = Self.arrivals
    Self.lock.unlock()
    if hold { arrived?.yield() } else { answer(body) }
  }
  private func answer(_ body: String) {
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

/// 空钥匙串（只在内存里）。
private final class MemoryVault: CredentialVault, @unchecked Sendable {
  let slotIdentifier = "memory:late-reply-" + UUID().uuidString
  private let lock = NSLock()
  private var value: SavedAccount?
  func read() throws -> SavedAccount? { lock.lock(); defer { lock.unlock() }; return value }
  func write(_ next: SavedAccount?) throws { lock.lock(); value = next; lock.unlock() }
}

@MainActor
@Suite("账号页 · 迟到的回复与连点", .serialized, .timeLimit(.minutes(1)))
struct AccountLateReplyTests {
  private let alice = AccountUser(id: UUID(uuidString: "A11CE000-3333-4C0A-9E2D-0A1B2C3D4E5F")!, email: "alice")

  private func signedIn() async throws -> (AccountFeature, AccountClient) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LateReplyProtocol.self]
    let client = try AccountClient(baseURL: URL(string: "https://kanpan.107-174-172-10.sslip.io")!,
                                   vault: MemoryVault(), session: URLSession(configuration: configuration))
    let feature = AccountFeature(client: client)
    feature.onPrepareAccount = { _ in {} }
    let json: [String: Any] = [
      "user": ["id": alice.id.uuidString, "email": alice.email],
      "sessionId": UUID().uuidString, "accessToken": "a-1", "refreshToken": "r-1",
      "expiresAt": 900_000, "serverTime": 0,
    ]
    let tokens = try JSONDecoder().decode(AccountTokens.self, from: JSONSerialization.data(withJSONObject: json))
    try await feature.accept(tokens)
    #expect(feature.user?.id == alice.id)
    return (feature, client)
  }

  @Test("设备列表还在路上时退了登：回来的列表不摆、也不念一句错")
  func lateDeviceListAfterLogoutIsDropped() async throws {
    let arrivals = LateReplyProtocol.reset(holdDevices: true)
    let (feature, client) = try await signedIn()
    let load = Task { await feature.loadDevices() }
    for await _ in arrivals { break }
    await feature.logout()
    LateReplyProtocol.release()
    await load.value
    await client.settleRevocation()
    #expect(feature.user == nil)
    #expect(feature.devices.isEmpty, "退登之后还摆着上一个人的设备：\(feature.devices.map(\.name))")
    #expect(feature.error == nil, "退登之后账号页上多了一句：\(feature.error ?? "")")
  }

  @Test("同一台设备的「退出」连点两下只发一趟")
  func doubleTapRevokeSendsOnce() async throws {
    _ = LateReplyProtocol.reset(holdDevices: false)
    let (feature, _) = try await signedIn()
    let other = AccountSessionDevice(id: UUID(), name: "旧手机", createdAt: 0, lastSeen: 0, current: false)
    feature.revoke(other)
    feature.revoke(other)
    for _ in 0..<200 where feature.devices.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!feature.devices.isEmpty)
    #expect(LateReplyProtocol.deleteCount == 1)
    #expect(feature.error == nil)
  }
}
