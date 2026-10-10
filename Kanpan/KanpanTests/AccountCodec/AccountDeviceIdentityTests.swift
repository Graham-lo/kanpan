import Foundation
import Testing
@testable import KanpanAccount
@testable import Kanpan

// 审查 2026-10-10 第 1 项：设备号跨启动、跨退登不变；记在别的设备号名下、还没发出去的操作
// 推送时改记到会话那台设备。两条用户路径都要走到「队列推得空」：
// - 冷启动、会话还没恢复出来就改了一笔；
// - 退出登录 → 重启 → 登回同一个号。

/// 所有请求原地答 200（退出时后台那一脚吊销会发出去）。一个字节都不出门。
final class DeviceIdentityProtocol: URLProtocol, @unchecked Sendable {
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

/// 内存里的钥匙串。
final class DeviceIdentityVault: CredentialVault, @unchecked Sendable {
  let slotIdentifier = "memory:device-identity-" + UUID().uuidString
  private let lock = NSLock()
  private var value: SavedAccount?
  init(_ value: SavedAccount?) { self.value = value }
  func read() throws -> SavedAccount? { lock.lock(); defer { lock.unlock() }; return value }
  func write(_ next: SavedAccount?) throws { lock.lock(); value = next; lock.unlock() }
}

/// 只认会话那台设备的假服务端（`sync.rs` 的 `screen`）：设备对得上就收下，对不上回单条拒绝格。
@MainActor final class SessionBoundTransport: SyncTransport {
  var session: UUID
  private(set) var landed: [UUID: UUID] = [:]          // 操作 id → 落库时的设备号
  private(set) var refusedForDevice = 0
  init(session: UUID) { self.session = session }
  private struct Body: Decodable { var operations: [Op] }
  private struct Op: Decodable {
    var id: UUID, collection: String, objectId: String, deviceId: UUID, fields: [String: KanpanAccount.JSONValue]
  }
  func push(_ body: Data, key: UUID) async throws -> SyncPushResponse {
    var results: [SyncResult] = [], rejections: [SyncRejection] = []
    for op in try JSONDecoder().decode(Body.self, from: body).operations {
      guard op.deviceId == session else {
        refusedForDevice += 1
        rejections.append(SyncRejection(operationId: op.id, code: "invalid_device")); continue
      }
      var object = SyncObject(collection: op.collection, id: op.objectId)
      object.body = op.fields; object.revision = 1
      landed[op.id] = op.deviceId
      results.append(SyncResult(operationId: op.id, object: object, cursor: Int64(landed.count), droppedFields: nil))
    }
    return SyncPushResponse(results: results, serverTime: 0, rejections: rejections)
  }
  func bootstrap(collection: String, prefix: String?, after: String?) async throws -> SyncPage {
    SyncPage(objects: [], next: nil, cursor: 0, serverTime: 0)
  }
}

@MainActor
@Suite("设备号跨启动、跨退登不变，记错设备号的操作照样推得上去", .serialized, .timeLimit(.minutes(1)))
struct AccountDeviceIdentityTests {
  private static let host = "kanpan.43-160-232-253.sslip.io"
  private let alice = AccountUser(id: UUID(uuidString: "A11CE000-3333-4C0A-9E2D-0A1B2C3D4E5F")!, email: "alice")

  private func defaults() -> (UserDefaults, String) {
    let suite = "kanpan.device-identity." + UUID().uuidString
    return (UserDefaults(suiteName: suite)!, suite)
  }
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }
  /// 钥匙串里那份存档（会话那台设备的号是 `device`）。走 JSON：成员初始化器在包外不可见。
  private func saved(_ user: AccountUser, device: UUID) throws -> SavedAccount {
    let json: [String: Any] = [
      "user": ["id": user.id.uuidString, "email": user.email],
      "sessionId": UUID().uuidString,
      "device": ["id": device.uuidString, "name": "phone", "secret": String(repeating: "s", count: 40)],
      "refreshToken": "refresh-" + user.email,
      "origin": Self.host,
    ]
    return try JSONDecoder().decode(SavedAccount.self, from: JSONSerialization.data(withJSONObject: json))
  }
  private func tokens(_ user: AccountUser) throws -> AccountTokens {
    let json: [String: Any] = [
      "user": ["id": user.id.uuidString, "email": user.email],
      "sessionId": UUID().uuidString, "accessToken": "access", "refreshToken": "refresh",
      "expiresAt": 900_000, "serverTime": 0,
    ]
    return try JSONDecoder().decode(AccountTokens.self, from: JSONSerialization.data(withJSONObject: json))
  }
  private func client(_ vault: DeviceIdentityVault) throws -> AccountClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DeviceIdentityProtocol.self]
    return try AccountClient(baseURL: URL(string: "https://" + Self.host)!, vault: vault,
                             session: URLSession(configuration: configuration))
  }
  /// 用户在设置里改了一笔：照桥上 `captureSettings` 那样记账，设备号就是 `AccountFeature.device` 当下那个。
  private func edit(_ store: SyncStore, _ feature: AccountFeature, spacing: Double) throws {
    var settings = SyncObject(collection: "settings", id: "chart")
    settings.body = ["barSpacing": .number(spacing)]
    try store.capture(settings, device: feature.device.id)
  }

  @Test("设备号存在本机：两次启动是同一个号，不再每次现起一个")
  func theDeviceIDSurvivesARestart() throws {
    let (store, suite) = defaults(); defer { UserDefaults().removePersistentDomain(forName: suite) }
    let first = AccountFeature(client: nil, defaults: store).device.id
    let second = AccountFeature(client: nil, defaults: store).device.id
    #expect(first == second)
  }

  /// 老版本升上来的第一次冷启动：本机还没存过设备号，钥匙串里那份会话的设备号是当年随手起的。
  /// 恢复会话之前改的那一笔记在新起的号名下——推送时改记到会话那台设备，照样落地、不隔离；
  /// 恢复之后会话那台设备的号记进本机，下一次冷启动一开始就是它。
  @Test("冷启动恢复会话之前改的一笔：推得上去，下次启动设备号就对上了")
  func anEditBeforeRestoreLands() async throws {
    let (defaults, suite) = defaults(); defer { UserDefaults().removePersistentDomain(forName: suite) }
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let sessionDevice = UUID()
    let vault = DeviceIdentityVault(try saved(alice, device: sessionDevice))
    let feature = AccountFeature(client: try client(vault), defaults: defaults)
    let store = try SyncStore(directory: root)
    #expect(feature.device.id != sessionDevice, "这一步要复现的就是「恢复之前设备号还不是会话那台」")
    try edit(store, feature, spacing: 9)                        // 会话还没恢复出来，用户先改了一笔

    await feature.restore()
    #expect(feature.user?.id == alice.id)
    #expect(feature.device.id == sessionDevice)
    let transport = SessionBoundTransport(session: sessionDevice)
    let engine = SyncEngine(store: store, transport: transport, device: feature.device.id)
    let outcome = try await engine.run(.push)
    #expect(store.archive.operations.isEmpty, "恢复之前那一笔没推上去")
    #expect(store.archive.rejected.isEmpty, "恢复之前那一笔被当成坏操作隔离了")
    #expect(outcome.acked == ["barSpacing"])
    #expect(Set(transport.landed.values) == [sessionDevice])

    // 重启：一开始（恢复之前）就是会话那台设备的号，这次连改记都不用。
    let restarted = AccountFeature(client: try client(vault), defaults: defaults)
    #expect(restarted.device.id == sessionDevice)
    try edit(store, restarted, spacing: 10)
    #expect(store.archive.operations.first?.deviceId == sessionDevice)
    _ = try await SyncEngine(store: store, transport: transport, device: sessionDevice).run(.push)
    #expect(store.archive.operations.isEmpty)
    #expect(transport.refusedForDevice == 0)
  }

  /// 登着时改了一笔没来得及推（断网），退出登录，重启，再登回同一个号：同一台机器、同一个设备号，
  /// 那一笔照样推得上去。
  @Test("退出 → 重启 → 登回同一个号：退出前没推上去的那一笔照样落地")
  func logoutRestartReloginLands() async throws {
    let (defaults, suite) = defaults(); defer { UserDefaults().removePersistentDomain(forName: suite) }
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let vault = DeviceIdentityVault(nil)
    let feature = AccountFeature(client: try client(vault), defaults: defaults)
    try await feature.accept(try tokens(alice))
    let before = feature.device.id
    #expect(await feature.client?.savedDevice()?.id == before)
    let store = try SyncStore(directory: root)
    try edit(store, feature, spacing: 7)                        // 断网，没推上去
    await feature.logout()
    #expect(feature.user == nil)
    #expect(feature.device.id == before, "退登不换设备号")

    let restarted = AccountFeature(client: try client(vault), defaults: defaults)
    #expect(restarted.device.id == before, "重启之后设备号变了")
    try await restarted.accept(try tokens(alice))
    let session = try #require(await restarted.client?.savedDevice()?.id)
    #expect(session == before)
    let transport = SessionBoundTransport(session: session)
    _ = try await SyncEngine(store: store, transport: transport, device: restarted.device.id).run(.push)
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.rejected.isEmpty)
    #expect(transport.refusedForDevice == 0)
  }

  /// 换了一台（或者老版本留下的、设备号和会话对不上的）：引擎开头把还没发出去的操作改记到会话那台，
  /// 已经发出去、服务端说「设备不对、没落库」的再改记重发——一条都不隔离。
  @Test("记在别的设备号名下、已经发出去过的那一条：服务端拒了设备之后改记重发")
  func aSentOperationUnderAnotherDeviceIsReassigned() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root)
    var settings = SyncObject(collection: "settings", id: "chart")
    settings.body = ["barSpacing": .number(5)]
    try store.capture(settings, device: UUID())
    try store.markSent(store.archive.operations.map(\.id))
    let session = UUID()
    let transport = SessionBoundTransport(session: session)
    _ = try await SyncEngine(store: store, transport: transport, device: session).run(.push)
    #expect(transport.refusedForDevice == 1)
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.rejected.isEmpty)
    #expect(Set(transport.landed.values) == [session])
  }

  /// 服务端不认识的设置字段：存档 `local` 叠回了用户的值，可云端没有它——脏标记不许被
  /// 「记账时没差异」那条路清掉（`SyncRecorder.settleAgreedSettings`）。
  @Test("服务端没收下的字段，记账对上了也不清脏标记")
  func anUnknownFieldStaysDirty() throws {
    var archive = SyncArchive()
    var cloud = SyncObject(collection: "settings", id: "chart")
    cloud.body = ["barSpacing": .number(6)]
    var local = cloud
    local.body["skin"] = .string("terra")
    archive.objects[cloud.key] = cloud
    archive.local[cloud.key] = local
    let blocked = try #require(SyncRecorder.unsettledSettingsFields(local, in: archive))
    #expect(!SettingsWire.fields(for: "skin").isEmpty)
    #expect(blocked.isSuperset(of: SettingsWire.fields(for: "skin")))
    #expect(blocked.isDisjoint(with: SettingsWire.fields(for: "barSpacing")))
  }
}
