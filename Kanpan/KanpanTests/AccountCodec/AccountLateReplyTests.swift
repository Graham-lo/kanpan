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
  /// DELETE 一律答 500（「退出某设备」没成那条路）。
  nonisolated(unsafe) static var failDeletes = false
  nonisolated(unsafe) private static var released = false
  nonisolated(unsafe) private static var held: [@Sendable () -> Void] = []
  nonisolated(unsafe) private static var arrivals: AsyncStream<Void>.Continuation?

  static func reset(holdDevices hold: Bool) -> AsyncStream<Void> {
    lock.lock(); defer { lock.unlock() }
    holdDevices = hold; deletes = 0; released = false; held = []; failDeletes = false
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
      Self.lock.lock(); Self.deletes += 1; let fail = Self.failDeletes; Self.lock.unlock()
      if fail { answer(#"{"error":{"code":"internal","message":"x"}}"#, status: 500); return }
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
  private func answer(_ body: String, status: Int = 200) {
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
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
    let client = try AccountClient(baseURL: URL(string: "https://kanpan.43-160-232-253.sslip.io")!,
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
    feature.devices = [other]
    let first = feature.revoke(other)
    let second = feature.revoke(other)
    #expect(first != nil)
    #expect(second == nil)
    await first?.value
    #expect(LateReplyProtocol.deleteCount == 1)
    #expect(feature.error == nil)
  }

  // MARK: - 体感优化 2026-10-07：设备表先摆本机那份、踢设备乐观更新

  private func cacheDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("devices-\(UUID().uuidString)", isDirectory: true)
  }
  private let phone = AccountSessionDevice(id: UUID(uuidString: "D0000000-0000-4000-8000-000000000001")!,
                                           name: "alice 的手机", createdAt: 0, lastSeen: 0, current: true)
  private let pad = AccountSessionDevice(id: UUID(uuidString: "D0000000-0000-4000-8000-000000000002")!,
                                         name: "旧平板", kind: .tablet, createdAt: 0, lastSeen: 0, current: false)
  private let mac = AccountSessionDevice(id: UUID(uuidString: "D0000000-0000-4000-8000-000000000003")!,
                                         name: "办公室电脑", kind: .desktop, createdAt: 0, lastSeen: 0, current: false)

  @Test("设备表的本机那份：按人记、封顶、清得掉")
  func deviceCacheIsPerUserAndCapped() {
    let directory = cacheDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = DeviceListCache(directory: directory)
    #expect(cache.load(for: alice.id) == nil)
    cache.save([phone, pad], for: alice.id)
    #expect(cache.load(for: alice.id)?.map(\.id) == [phone.id, pad.id])
    #expect(cache.load(for: UUID()) == nil, "换了人还摆着上一个人的设备")
    let many = (0..<50).map { AccountSessionDevice(id: UUID(), name: "\($0)", createdAt: 0, lastSeen: 0, current: false) }
    cache.save(many, for: alice.id)
    #expect(cache.load(for: alice.id)?.count == DeviceListCache.limit)
    cache.clear()
    #expect(cache.load(for: alice.id) == nil)
  }

  @Test("进设备页先摆上回那张，服务端回来整张换掉并记下")
  func deviceListShowsCacheFirstThenRefreshes() async throws {
    let directory = cacheDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let arrivals = LateReplyProtocol.reset(holdDevices: true)
    let (feature, _) = try await signedIn()
    let cache = DeviceListCache(directory: directory)
    cache.save([phone, pad, mac], for: alice.id)
    feature.deviceCache = cache
    let load = Task { await feature.loadDevices() }
    for await _ in arrivals { break }
    // 服务端还没回：页上已经是上回那张。
    #expect(feature.devices.map(\.id) == [phone.id, pad.id, mac.id])
    LateReplyProtocol.release()
    await load.value
    #expect(feature.devices.map(\.id) == [phone.id])
    #expect(cache.load(for: alice.id)?.map(\.id) == [phone.id])
    #expect(feature.error == nil)
  }

  @Test("踢设备：那一行当场没了，成了不再刷新、本机那份跟着少一行")
  func revokeRemovesRowImmediately() async throws {
    let directory = cacheDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = LateReplyProtocol.reset(holdDevices: false)
    let (feature, _) = try await signedIn()
    feature.deviceCache = DeviceListCache(directory: directory)
    await feature.loadDevices()
    feature.devices = [phone, pad, mac]
    let task = feature.revoke(pad)
    #expect(feature.devices.map(\.id) == [phone.id, mac.id], "点完还得等回包才消失")
    await task?.value
    #expect(feature.devices.map(\.id) == [phone.id, mac.id])
    #expect(feature.deviceCache?.load(for: alice.id)?.map(\.id) == [phone.id, mac.id])
    #expect(feature.error == nil)
    #expect(feature.user != nil)
  }

  @Test("踢设备没成：那一行回到原位，底下念一句")
  func failedRevokePutsRowBack() async throws {
    let directory = cacheDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = LateReplyProtocol.reset(holdDevices: false)
    LateReplyProtocol.failDeletes = true
    let (feature, _) = try await signedIn()
    feature.deviceCache = DeviceListCache(directory: directory)
    await feature.loadDevices()
    feature.devices = [phone, pad, mac]
    let task = feature.revoke(pad)
    #expect(feature.devices.map(\.id) == [phone.id, mac.id])
    await task?.value
    #expect(feature.devices.map(\.id) == [phone.id, pad.id, mac.id])
    #expect(feature.error == AccountFeature.revokeFailure)
    #expect(feature.deviceCache?.load(for: alice.id)?.map(\.id) == [phone.id, pad.id, mac.id])
    #expect(feature.user != nil)
  }

  @Test("退登把本机那份设备表一起删掉")
  func logoutClearsDeviceCache() async throws {
    let directory = cacheDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = LateReplyProtocol.reset(holdDevices: false)
    let (feature, client) = try await signedIn()
    let cache = DeviceListCache(directory: directory)
    feature.deviceCache = cache
    await feature.loadDevices()
    #expect(cache.load(for: alice.id) != nil)
    await feature.logout()
    await client.settleRevocation()
    #expect(cache.load(for: alice.id) == nil)
  }
}
