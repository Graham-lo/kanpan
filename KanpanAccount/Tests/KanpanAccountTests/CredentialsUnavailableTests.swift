import Foundation
import Testing
@testable import KanpanAccount

/// 钥匙串「这一刻读不动」的替身：`lock()` 之后每次读都抛 `credentialsUnavailable`
/// （真机上是锁屏被后台拉起时的 `errSecInteractionNotAllowed`），`unlock()` 之后照常。
final class LockableVault: CredentialVault, @unchecked Sendable {
  let slotIdentifier = "memory:locked-" + UUID().uuidString
  private let lock = NSLock()
  private var value: SavedAccount?
  private var locked: Bool
  private(set) var reads = 0
  init(_ value: SavedAccount?, locked: Bool) { self.value = value; self.locked = locked }
  func unlock() { lock.lock(); locked = false; lock.unlock() }
  var stored: SavedAccount? { lock.lock(); defer { lock.unlock() }; return value }
  func read() throws -> SavedAccount? {
    lock.lock(); defer { lock.unlock() }
    reads += 1
    if locked { throw AccountError.credentialsUnavailable }
    return value
  }
  func write(_ next: SavedAccount?) throws {
    lock.lock(); defer { lock.unlock() }
    if locked { throw AccountError.credentialsUnavailable }
    value = next
  }
}

/// 审查 17：钥匙串读不动（含 `errSecInteractionNotAllowed`）时，客户端不能把自己当成
/// 「没登录」——不抛、不清、不把人推去重新登录，读得到了就接上。
@Suite("钥匙串读不动", .serialized)
struct CredentialsUnavailableTests {
  private static let host = "kanpan.107-174-172-10.sslip.io"
  private func makeClient(_ vault: LockableVault) throws -> AccountClient {
    StubProtocol.server.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return try AccountClient(baseURL: URL(string: "https://" + Self.host)!, vault: vault,
                             session: URLSession(configuration: configuration))
  }
  private func saved() -> SavedAccount {
    SavedAccount(user: AccountUser(id: UUID(), email: "someone"), sessionId: UUID(),
                 device: AccountDevice(name: "phone"), refreshToken: "refresh-token-value", refreshRequestId: nil)
  }
  private struct Probe: Decodable, Sendable { var ok: Bool? }

  @Test("读不动时客户端照样建起来，并且知道凭据欠着")
  func 建得起来() async throws {
    let client = try makeClient(LockableVault(saved(), locked: true))
    #expect(await client.credentialsUnavailable)
    #expect(await client.savedUser() == nil)
  }

  @Test("读不动时发请求：报「稍后再试」，不是 401、不算登录失效、一个字节都不出门")
  func 请求不当成失效() async throws {
    let client = try makeClient(LockableVault(saved(), locked: true))
    await #expect(throws: AccountError.credentialsUnavailable) {
      let _: Probe = try await client.request("v1/sync/state")
    }
    #expect(await !client.needsReauthentication)
    #expect(StubProtocol.server.calls.isEmpty)
  }

  @Test("解锁之后下一次读就接上：用户、设备都回来了，凭据一个字没丢")
  func 解锁接上() async throws {
    let account = saved()
    let vault = LockableVault(account, locked: true)
    let client = try makeClient(vault)
    #expect(await !client.retryCredentials())
    vault.unlock()
    #expect(await client.savedUser()?.id == account.user.id)
    #expect(await !client.credentialsUnavailable)
    #expect(await client.savedDevice()?.id == account.device.id)
    #expect(vault.stored?.refreshToken == "refresh-token-value")
  }

  @Test("凭据欠着时退登：之后钥匙串读得到了，也不许把退掉的凭据翻回来")
  func 退登不翻旧账() async throws {
    let vault = LockableVault(saved(), locked: true)
    let client = try makeClient(vault)
    try? await client.signOut()
    vault.unlock()
    #expect(await client.savedUser() == nil)
    #expect(await !client.credentialsUnavailable)
  }

  @Test("钥匙串里确实没有（errSecItemNotFound）和读不动是两回事")
  func 没有不是读不动() async throws {
    let client = try makeClient(LockableVault(nil, locked: false))
    #expect(await !client.credentialsUnavailable)
    #expect(await client.savedUser() == nil)
  }
}

/// 钥匙串读不动时靠 `AccountFiles.lastOwner` 知道这台机器上是谁。
@MainActor
@Suite("上次装的是谁")
struct LastOwnerTests {
  private func temp() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("last-owner-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
  }

  @Test("记下的人重开之后还在；退登（nil）清掉")
  func 跨重开() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let owner = AccountUser(id: UUID(), email: "alice")
    try AccountFiles(root: root).remember(owner: owner)
    #expect(try AccountFiles(root: root).lastOwner == owner)
    try AccountFiles(root: root).remember(owner: nil)
    #expect(try AccountFiles(root: root).lastOwner == nil)
  }

  @Test("老版本的 registry.json 没有 owner 键：照常解开，答 nil")
  func 老文件() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let legacy = #"{"version":1,"guest":"\#(UUID().uuidString)","claims":{},"completed":[]}"#
    try Data(legacy.utf8).write(to: root.appendingPathComponent("registry.json"))
    let files = try AccountFiles(root: root)
    #expect(files.lastOwner == nil)
  }

  @Test("存的只有身份，没有任何令牌")
  func 不存令牌() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    try AccountFiles(root: root).remember(owner: AccountUser(id: UUID(), email: "alice"))
    let text = try String(contentsOf: root.appendingPathComponent("registry.json"), encoding: .utf8)
    #expect(!text.contains("token") && !text.contains("refresh"))
  }
}
