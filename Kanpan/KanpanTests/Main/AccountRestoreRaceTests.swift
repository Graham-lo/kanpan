import Foundation
import Testing
import KanpanAccount
@testable import Kanpan

// §B.10 回归规格 BT-22：冷启动那一下的 `AccountFeature.restore()` 还挂着的时候，
// 用户主动退出 / 登上另一个号。迟到的 restore 不许把旧的那个人重新挂回来。
//
// 时序全靠「堵住的钥匙串」摆：A 的一次后台凭据写（令牌轮换）卡在 `HeldVault.write`
// 里，`AccountClient` 这个 actor 就被它占着。restore 和退出 / 登录都要进这个 actor，
// 于是按主 actor 上的先后（FIFO）排在它后面：restore 先读到 A，退出 / 登录紧跟着
// 换人——restore 回到主线程时，世界已经不是它出发时那个了。一条 sleep 都不靠。

/// 所有请求原地答 200（退出时后台那一脚吊销会发出去）。一个字节都不出门。
final class BT22Protocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(#"{"data":{"ok":true}}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

/// 能把「下一次写」扣住的假钥匙串。扣住时报到一声（`held`），等测试 `release()`。
final class HeldVault: CredentialVault, @unchecked Sendable {
  let slotIdentifier = "memory:bt22-" + UUID().uuidString
  private let lock = NSLock()
  private var value: SavedAccount?
  private var holdNext = false
  private let gate = DispatchSemaphore(value: 0)
  private let arrivals: AsyncStream<Void>.Continuation
  let held: AsyncStream<Void>
  init(_ value: SavedAccount?) {
    self.value = value
    (held, arrivals) = AsyncStream<Void>.makeStream()
  }
  func holdNextWrite() { lock.lock(); holdNext = true; lock.unlock() }
  func release() { gate.signal() }
  var stored: SavedAccount? { lock.lock(); defer { lock.unlock() }; return value }
  func read() throws -> SavedAccount? { stored }
  func write(_ next: SavedAccount?) throws {
    lock.lock(); let hold = holdNext; holdNext = false; lock.unlock()
    if hold { arrivals.yield(); gate.wait() }
    lock.lock(); value = next; lock.unlock()
  }
}

/// 「装了谁的档案」按发生顺序记下来。
@MainActor private final class OwnerLog { var events: [String] = [] }

@MainActor
@Suite("BT-22 restore 挂着时换人：迟到的 restore 不许挂回旧 owner", .serialized, .timeLimit(.minutes(1)))
struct AccountRestoreRaceTests {
  private static let host = "kanpan.107-174-172-10.sslip.io"
  private let alice = AccountUser(id: UUID(uuidString: "A11CE000-1111-4C0A-9E2D-0A1B2C3D4E5F")!, email: "alice")
  private let bob = AccountUser(id: UUID(uuidString: "B0B00000-2222-4C0A-9E2D-0A1B2C3D4E5F")!, email: "bob")

  /// 钥匙串里那份 A 的存档。走 JSON：成员初始化器在包外不可见。
  private func saved(_ user: AccountUser) throws -> SavedAccount {
    let json: [String: Any] = [
      "user": ["id": user.id.uuidString, "email": user.email],
      "sessionId": UUID().uuidString,
      "device": ["id": UUID().uuidString, "name": "phone", "secret": "device-secret"],
      "refreshToken": "refresh-" + user.email,
      "origin": Self.host,
    ]
    return try JSONDecoder().decode(SavedAccount.self, from: JSONSerialization.data(withJSONObject: json))
  }
  private func tokens(_ user: AccountUser, access: String) throws -> AccountTokens {
    let json: [String: Any] = [
      "user": ["id": user.id.uuidString, "email": user.email],
      "sessionId": UUID().uuidString, "accessToken": access, "refreshToken": "refresh-" + access,
      "expiresAt": 900_000, "serverTime": 0,
    ]
    return try JSONDecoder().decode(AccountTokens.self, from: JSONSerialization.data(withJSONObject: json))
  }
  private func rig() throws -> (AccountFeature, AccountClient, HeldVault, OwnerLog) {
    let vault = HeldVault(try saved(alice))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BT22Protocol.self]
    let client = try AccountClient(baseURL: URL(string: "https://" + Self.host)!, vault: vault,
                                   session: URLSession(configuration: configuration))
    let feature = AccountFeature(client: client)
    let log = OwnerLog()
    feature.onPrepareAccount = { [log] owner in
      log.events.append("prepare:" + (owner?.email ?? "guest"))
      return { log.events.append("apply:" + (owner?.email ?? "guest")) }
    }
    return (feature, client, vault, log)
  }
  /// 把客户端 actor 堵住：A 的一次后台凭据写卡在钥匙串上。返回时它确实卡着了。
  private func holdClient(_ client: AccountClient, _ vault: HeldVault) async throws -> Task<Void, any Error> {
    vault.holdNextWrite()
    let rotated = try tokens(alice, access: "a-rotated")
    let background = Task { try await client.accept(rotated, device: AccountDevice(name: "phone")) }
    for await _ in vault.held { break }
    return background
  }
  /// 主 actor 是 FIFO 的：等这一格跑到，排在它前面的任务都已经走到了各自的第一个 `await`
  /// （也就是都排进了被堵住的客户端 actor）。
  private func drainMainActor() async { await Task { @MainActor in }.value }

  @Test("对照：没人打扰时 restore 照常把 A 装上")
  func restoreAloneMountsSavedOwner() async throws {
    let (feature, _, _, log) = try rig()
    await feature.restore()
    #expect(log.events == ["prepare:alice", "apply:alice"])
    #expect(feature.user?.id == alice.id)
  }

  @Test("restore 挂着时用户退出：迟到的 restore 不许把 A 挂回来")
  func lateRestoreAfterLogoutDoesNotRemountOldOwner() async throws {
    let (feature, client, vault, log) = try rig()
    let background = try await holdClient(client, vault)

    let restore = Task { await feature.restore() }    // 先出发：它会读到 A
    let logout = Task { await feature.logout() }      // 紧跟着：用户点了退出
    await drainMainActor()
    vault.release()
    try await background.value
    await restore.value
    await logout.value
    await client.settleRevocation()

    #expect(!log.events.contains("prepare:alice"), "退出之后又去装 A 的档案了：\(log.events)")
    #expect(!log.events.contains("apply:alice"), "退出之后 A 的档案又被挂回来了：\(log.events)")
    #expect(log.events.last == "apply:guest")
    #expect(feature.user == nil, "退出之后界面上还登着 \(feature.user?.email ?? "")")
    #expect(await client.savedUser() == nil)
    #expect(vault.stored == nil, "钥匙串里的凭据要跟着走")
  }

  @Test("restore 挂着时用户登上 B：迟到的 restore 不许用 A 把 B 盖掉")
  func lateRestoreAfterLoginDoesNotRemountOldOwner() async throws {
    let (feature, client, vault, log) = try rig()
    let background = try await holdClient(client, vault)
    let bobTokens = try tokens(bob, access: "b-1")

    let restore = Task { await feature.restore() }                      // 先出发：它会读到 A
    let login = Task { try await feature.accept(bobTokens) }            // 登录那一趟 HTTP 已经回来了
    await drainMainActor()
    vault.release()
    try await background.value
    await restore.value
    try await login.value

    #expect(!log.events.contains("prepare:alice"), "B 登录之后又去装 A 的档案了：\(log.events)")
    #expect(!log.events.contains("apply:alice"), "B 登录之后 A 的档案又被挂回来了：\(log.events)")
    #expect(log.events == ["prepare:bob", "apply:bob"])
    #expect(feature.user?.id == bob.id)
    #expect(await client.savedUser()?.id == bob.id)
    #expect(vault.stored?.user.id == bob.id)
  }
}
