import Foundation
import Testing
import KanpanAccount
@testable import Kanpan

// 审查 17：钥匙串读不动（锁屏被后台拉起时的 errSecInteractionNotAllowed）时，
// 登录的人冷启动不能被装成访客——那在他眼里就是「自选没了」。按上次那个人把本地
// 档案装上、同步停着，钥匙串读得到了再接上。

/// `lock()` 时每次读都抛「这一刻读不动」，`unlock()` 之后照常。
final class LockedVault: CredentialVault, @unchecked Sendable {
  let slotIdentifier = "memory:locked-main-" + UUID().uuidString
  private let lock = NSLock()
  private var value: SavedAccount?
  private var locked = true
  init(_ value: SavedAccount?) { self.value = value }
  func unlock() { lock.lock(); locked = false; lock.unlock() }
  func read() throws -> SavedAccount? {
    lock.lock(); defer { lock.unlock() }
    if locked { throw AccountError.credentialsUnavailable }
    return value
  }
  func write(_ next: SavedAccount?) throws {
    lock.lock(); defer { lock.unlock() }
    if locked { throw AccountError.credentialsUnavailable }
    value = next
  }
}

@MainActor private final class Journal { var events: [String] = [] }

@MainActor
@Suite("钥匙串读不动时照常装上次那个人的档案", .serialized, .timeLimit(.minutes(1)))
struct AccountCredentialFallbackTests {
  private static let host = "kanpan.107-174-172-10.sslip.io"
  private let alice = AccountUser(id: UUID(uuidString: "A11CE000-3333-4C0A-9E2D-0A1B2C3D4E5F")!, email: "alice")

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
  private func rig(lastOwner: AccountUser?) throws -> (AccountFeature, LockedVault, Journal) {
    let vault = LockedVault(try saved(alice))
    let client = try AccountClient(baseURL: URL(string: "https://" + Self.host)!, vault: vault)
    let feature = AccountFeature(client: client)
    let journal = Journal()
    feature.lastOwner = { lastOwner }
    feature.onPrepareAccount = { [journal] owner in
      journal.events.append("prepare:" + (owner?.email ?? "guest"))
      return { journal.events.append("apply:" + (owner?.email ?? "guest")) }
    }
    feature.onSynchronize = { [journal] in journal.events.append("sync") }
    return (feature, vault, journal)
  }

  @Test("读不动：按上次那个人装档案，不同步、不要求重新登录；解锁后只补同步，不重装档案")
  func holdsLastOwnerThenResumes() async throws {
    let (feature, vault, journal) = try rig(lastOwner: alice)
    await feature.restore()
    #expect(journal.events == ["prepare:alice", "apply:alice"], "\(journal.events)")
    #expect(feature.user?.id == alice.id, "登录的人被装成了访客")
    #expect(feature.credentialsPending)
    #expect(!feature.needsReauthentication, "读不动不是登录失效")

    await feature.resumeCredentials()          // 还锁着：什么都不变
    #expect(feature.credentialsPending)
    #expect(journal.events == ["prepare:alice", "apply:alice"])

    vault.unlock()
    await feature.resumeCredentials()
    #expect(!feature.credentialsPending)
    #expect(journal.events == ["prepare:alice", "apply:alice", "sync"], "\(journal.events)")
    #expect(feature.user?.id == alice.id)
  }

  @Test("不知道上次是谁（老版本升上来）：先留在访客，解锁后照常把账号那份装上")
  func unknownOwnerWaitsThenAdopts() async throws {
    let (feature, vault, journal) = try rig(lastOwner: nil)
    await feature.restore()
    #expect(journal.events.isEmpty)
    #expect(feature.credentialsPending)
    vault.unlock()
    await feature.resumeCredentials()
    #expect(journal.events == ["prepare:alice", "apply:alice", "sync"], "\(journal.events)")
    #expect(feature.user?.id == alice.id)
  }
}

/// 推送 token 的补发账本（审查 17）。
@Suite("推送 token 补发")
struct PushTokenLedgerTests {
  let token = String(repeating: "ab", count: 32)
  let alice = UUID(), bob = UUID()

  @Test("没登录时来的 token：先不报，登录后补报")
  func arrivesWhileLoggedOut() {
    let ledger = PushTokenLedger()
    #expect(ledger.due(token: token, owner: nil) == nil)
    #expect(ledger.due(token: token, owner: alice) == token)
  }
  @Test("报成功之后不再重复报；换了账号要再报一次")
  func sentOncePerOwner() {
    var ledger = PushTokenLedger()
    ledger.begin(token: token, owner: alice)
    #expect(ledger.due(token: token, owner: alice) == nil, "正在报的不许再发一趟")
    ledger.finish(token: token, owner: alice, ok: true)
    #expect(ledger.due(token: token, owner: alice) == nil)
    #expect(ledger.due(token: token, owner: bob) == token)
  }
  @Test("报失败（断网）下一次同步再报")
  func failureRetries() {
    var ledger = PushTokenLedger()
    ledger.begin(token: token, owner: alice)
    ledger.finish(token: token, owner: alice, ok: false)
    #expect(ledger.due(token: token, owner: alice) == token)
  }
  @Test("没有 APNs 密钥 / capability：token 永远不来，一个请求都不发")
  func noKeyNoRequest() {
    #expect(PushTokenLedger().due(token: nil, owner: alice) == nil)
  }
}
