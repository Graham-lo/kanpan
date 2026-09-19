import Foundation
import Testing
@testable import KanpanAccount

/// 这一套假服务器和别的 suite 分开一台。Swift Testing 默认让**不同 suite 并行跑**，
/// 共用一台会互相把路由和调用记录冲掉（`ClientHardeningTests` 里是同一个理由）。
final class KindStubProtocol: URLProtocol {
  static let server = StubServer()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url?.path ?? ""
    KindStubProtocol.server.record(.init(path: path, body: request.uploaded))
    switch KindStubProtocol.server.answer(path) {
    case .success(let (status, data)):
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    case .failure(let error):
      client?.urlProtocol(self, didFailWithError: error)
    }
  }
  override func stopLoading() {}
}

/// 「一个账号每类设备只许一台在线」在客户端这一侧的全部落点：设备报类别、被顶下去
/// 之后走一条和「登录失效」不一样的路、设备列表看得见类别。
@Suite("设备类别与会话被顶", .serialized)
struct DeviceKindTests {
  private let person = AccountUser(id: UUID(uuidString: "3C6A2B10-2222-4D0B-8E1F-0A1B2C3D4E5F")!, email: "someone")
  private struct Probe: Decodable, Sendable { var ok: Bool? }
  private var server: StubServer { KindStubProtocol.server }

  private func makeClient(_ vault: StubVault) throws -> AccountClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [KindStubProtocol.self]
    return try AccountClient(baseURL: URL(string: "https://accounts.invalid")!, vault: vault,
                             session: URLSession(configuration: configuration),
                             options: AccountClient.Options(allowAnyHostForTests: true))
  }
  private func saved(_ kind: DeviceKind) -> SavedAccount {
    SavedAccount(user: person, sessionId: UUID(),
                 device: AccountDevice(name: "机器", kind: kind),
                 refreshToken: "refresh-1", refreshRequestId: nil)
  }
  private func tokens(access: String, refresh: String) -> String {
    """
    {"data":{"user":{"id":"\(person.id.uuidString)","email":"\(person.email)"},
    "sessionId":"\(UUID().uuidString)","accessToken":"\(access)","refreshToken":"\(refresh)",
    "expiresAt":900000,"serverTime":0}}
    """
  }
  /// 一趟请求里报上去的设备类别（没带 device 的请求返回 nil）。
  private func reportedKind(_ call: StubServer.Call) -> String? {
    guard let body = call.body,
      let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      let device = json["device"] as? [String: Any] else { return nil }
    return device["kind"] as? String ?? "<缺失>"
  }

  /// 服务端按「同一台设备每次都报同一个类别」判：refresh 时对不上就是 `invalid_device`。
  /// 所以凡是带设备出门的请求（刷新、吊销）都得带上，而且是同一个值。
  @Test("每一趟带设备的请求都报同一个类别")
  func 类别恒定() async throws {
    server.reset()
    let vault = StubVault(saved(.tablet))
    let client = try makeClient(vault)
    server.route("/v1/auth/refresh", 200, tokens(access: "access-2", refresh: "refresh-2"))
    server.route("/v1/auth/me", 200, #"{"data":{"ok":true}}"#)
    server.route("/v1/auth/session/revoke", 200, #"{"data":{"ok":true}}"#)
    let _: Probe = try await client.request("v1/auth/me")
    try await client.signOut()
    await client.settleRevocation()
    let reported = server.calls.compactMap(reportedKind)
    #expect(reported.count >= 2, "刷新和吊销都要带着设备出门")
    #expect(Set(reported) == ["tablet"], "同一台设备每一趟都得报同一个类别，实际是 \(reported)")
  }

  /// 被同类设备顶下去和「登录失效」是两件事：前者要说得出**是哪一类设备**顶的，
  /// 而且这条会话已经死透了，本机那份令牌留着也没用。
  @Test("刷新被顶下去：清掉令牌，说得出是哪一类设备")
  func 刷新被顶() async throws {
    server.reset()
    let vault = StubVault(saved(.phone))
    let client = try makeClient(vault)
    server.route("/v1/auth/refresh", 401, #"{"error":{"code":"session_replaced","deviceKind":"phone"}}"#)
    await #expect(throws: AccountError.sessionReplaced(.phone)) { let _: Probe = try await client.request("v1/auth/me") }
    #expect(await client.needsReauthentication, "要重新签一次名")
    #expect(await client.replacedDeviceKind == .phone)
    // 令牌清掉（服务端那条会话真的没了，留着只会再撞一次墙），身份留着
    // ——本机档案是按用户 id 存的，整条存档删掉，下次开 app 装进来的就是访客那份。
    #expect(vault.stored?.refreshToken == "", "被顶掉的会话，那把令牌是废纸")
    #expect(vault.stored?.replacedBy == .phone)
    #expect(vault.stored?.user.id == person.id, "身份得留着：本机的自选、画线、复盘照常能用")
    #expect(AccountError.sessionReplaced(.phone).errorDescription == "这个账号在另一台手机上登录了")
    #expect(AccountError.sessionReplaced(.tablet).errorDescription == "这个账号在另一台平板上登录了")
    #expect(AccountError.sessionReplaced(.desktop).errorDescription == "这个账号在另一台电脑上登录了")
    // 再撞一次也是同一堵墙：不许再发刷新，而且拿到的还是那句话。
    await #expect(throws: AccountError.sessionReplaced(.phone)) { let _: Probe = try await client.request("v1/auth/me") }
    #expect(server.calls("/v1/auth/refresh").count == 1, "服务端已经说死了，别再空转")
  }

  /// 拿着还没过期的 access 令牌去访问任何接口，也会收到同一个码。这条路不能悄悄
  /// 走回「401 就再刷一次」的老路——刷了也是白刷。
  @Test("带 access 令牌的普通请求被顶下去也走同一条路")
  func 访问被顶() async throws {
    server.reset()
    let vault = StubVault(saved(.tablet))
    let client = try makeClient(vault)
    server.route("/v1/auth/refresh", 200, tokens(access: "access-2", refresh: "refresh-2"))
    server.route("/v1/auth/me", 401, #"{"error":{"code":"session_replaced","deviceKind":"tablet"}}"#)
    await #expect(throws: AccountError.sessionReplaced(.tablet)) { let _: Probe = try await client.request("v1/auth/me") }
    #expect(server.calls("/v1/auth/refresh").count == 1, "被顶下去之后不该再去刷一趟")
    #expect(await client.replacedDeviceKind == .tablet)
    #expect(vault.stored?.refreshToken == "")
    #expect(vault.stored?.replacedBy == .tablet)
  }

  /// 被顶下去之后关掉 app 再打开：不用再问一次服务器就知道这条会话不作数，
  /// 而且**档案还是这个人的**——自选、画线、复盘一个字都不少，只是同步停着。
  @Test("重开 app 还记得自己是被顶下去的，档案照常是这个人的")
  func 重开还记得() async throws {
    server.reset()
    let vault = StubVault(saved(.desktop))
    let first = try makeClient(vault)
    server.route("/v1/auth/refresh", 401, #"{"error":{"code":"session_replaced","deviceKind":"desktop"}}"#)
    await #expect(throws: AccountError.sessionReplaced(.desktop)) { let _: Probe = try await first.request("v1/auth/me") }
    let refreshes = server.calls("/v1/auth/refresh").count
    // 换一个客户端 = 关掉 app 再打开（钥匙串那份原样躺在那儿）。
    let second = try makeClient(vault)
    #expect(await second.savedUser()?.id == person.id, "档案得认得出这是谁的")
    #expect(await second.replacedDeviceKind == .desktop)
    await #expect(throws: AccountError.sessionReplaced(.desktop)) { let _: Probe = try await second.request("v1/auth/me") }
    #expect(server.calls("/v1/auth/refresh").count == refreshes, "开机就知道了，不用再问一遍")
  }

  /// 其余的撤销（退登、踢设备、改密）仍旧是笼统那一句，走的还是原来那条路：
  /// 本机凭据不清、也没有「在另一台机器上登录了」这句话。
  @Test("普通的认证失效还是原来那条路")
  func 认证失效不变() async throws {
    server.reset()
    let vault = StubVault(saved(.phone))
    let client = try makeClient(vault)
    server.route("/v1/auth/refresh", 401, #"{"error":{"code":"authentication_failed"}}"#)
    await #expect(throws: AccountError.reauthenticationRequired) { let _: Probe = try await client.request("v1/auth/me") }
    #expect(await client.needsReauthentication)
    #expect(await client.replacedDeviceKind == nil, "没人顶它，就不许说是被顶的")
    #expect(vault.stored != nil, "云端只是同步通道：认证失效不许清本地凭据")
  }

  /// 设备列表要能说出每条会话是哪一类设备。将来服务端多一类（手表之类）时，
  /// 不认识的那一条不能把整张列表带得解不开。
  @Test("设备列表解得出类别，不认识的按手机算")
  func 设备列表带类别() async throws {
    server.reset()
    let vault = StubVault(saved(.phone))
    let client = try makeClient(vault)
    server.route("/v1/auth/refresh", 200, tokens(access: "access-2", refresh: "refresh-2"))
    server.route("/v1/auth/devices", 200, """
    {"data":{"devices":[
    {"id":"\(UUID().uuidString)","name":"iPhone","kind":"phone","createdAt":1,"lastSeen":2,"current":true},
    {"id":"\(UUID().uuidString)","name":"iPad","kind":"tablet","createdAt":1,"lastSeen":2,"current":false},
    {"id":"\(UUID().uuidString)","name":"Mac","kind":"desktop","createdAt":1,"lastSeen":2,"current":false},
    {"id":"\(UUID().uuidString)","name":"Watch","kind":"watch","createdAt":1,"lastSeen":2,"current":false},
    {"id":"\(UUID().uuidString)","name":"旧网关","createdAt":1,"lastSeen":2,"current":false}]}}
    """)
    let listed = try await client.request("v1/auth/devices", as: AccountDevices.self).devices
    #expect(listed.map(\.kind) == [.phone, .tablet, .desktop, .phone, .phone])
    #expect(listed.map(\.kind.label) == ["手机", "平板", "电脑", "手机", "手机"])
  }

  /// 旧版本写下的钥匙串存档里没有这个字段。它对应的那条服务端会话也是按「手机」记的
  /// （服务端 `DeviceKind` 的 `#[default]`），所以解出来必须是手机——解成别的类别，
  /// 下一次刷新就会被判 `invalid_device`，用户白白被登出。
  @Test("旧存档没有类别时算手机")
  func 旧存档迁移() throws {
    let json = """
    {"user":{"id":"\(person.id.uuidString)","email":"someone"},"sessionId":"\(UUID().uuidString)",
    "device":{"id":"\(UUID().uuidString)","name":"phone","secret":"device-secret"},
    "refreshToken":"refresh-1"}
    """
    let stored = try JSONDecoder().decode(SavedAccount.self, from: Data(json.utf8))
    #expect(stored.device.kind == .phone)
  }
}
