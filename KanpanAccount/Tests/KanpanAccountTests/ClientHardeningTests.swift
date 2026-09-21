import Foundation
import Testing
@testable import KanpanAccount

/// 把一趟答复扣在闸门后面，等测试放行再回。用来把「两个客户端同时在飞」摆成确定的场面，
/// 而不是靠 sleep 去碰运气。
final class ResponseGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var opened = true
  func close() { condition.lock(); opened = false; condition.unlock() }
  func open() { condition.lock(); opened = true; condition.broadcast(); condition.unlock() }
  func waitUntilOpen() {
    condition.lock(); defer { condition.unlock() }
    let deadline = Date().addingTimeInterval(10)
    while !opened, Date() < deadline { condition.wait(until: Date().addingTimeInterval(0.05)) }
  }
}

/// 这一套假服务器和 `SessionLifecycleTests` 里那台分开：A-06 要两个客户端同时在飞，
/// 中途还要把刷新的答复扣住，和别的用例共用一台会互相干扰。
final class GateStubProtocol: URLProtocol {
  static let server = StubServer()
  static let gate = ResponseGate()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url?.path ?? ""
    GateStubProtocol.server.record(.init(path: path, body: request.uploaded))
    // 刷新这一趟才扣住：闸门开着的时候和普通假服务器没有区别。
    if path.hasSuffix("/v1/auth/refresh") { GateStubProtocol.gate.waitUntilOpen() }
    switch GateStubProtocol.server.answer(path) {
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

/// GPT Pro 第三轮 A-06 及附带项：多客户端互踢、来源绑定、路径归一化。
@Suite("客户端加固", .serialized)
struct ClientHardeningTests {
  private let person = AccountUser(id: UUID(uuidString: "6E4B4A2C-1111-4C0A-9E2D-0A1B2C3D4E5F")!, email: "someone")
  private struct Probe: Decodable, Sendable { var ok: Bool? }

  private func reset(gateClosed: Bool = false) {
    GateStubProtocol.server.reset()
    if gateClosed { GateStubProtocol.gate.close() } else { GateStubProtocol.gate.open() }
  }
  /// 出厂白名单里那台网关。**这一套用例一个字节都不出门**：`GateStubProtocol` 把
  /// 这个 session 上的所有请求原地截下来，地址只是个名字。
  ///
  /// 从前这儿写的是 `accounts.invalid` + `allowAnyHostForTests: true`，而那个开关
  /// 按 A-07 只存在于 DEBUG，于是底下一半用例整块被 `#if DEBUG` 包走——Release 配置下
  /// 「两个客户端只刷一次」「来源不符不认存档」「URL 编码跳不出父目录」这些行为
  /// 一条都不存在（审查 C-05：不是改成 Release 可运行的同等测试，是让它们消失）。
  /// 换成白名单内的主机之后，这些用例在 Debug / Release 两边都真的跑。
  static let host = "kanpan.107-174-172-10.sslip.io"

  private func makeClient(_ vault: StubVault) throws -> AccountClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GateStubProtocol.self]
    return try AccountClient(baseURL: URL(string: "https://" + Self.host)!, vault: vault,
                             session: URLSession(configuration: configuration))
  }
  /// 钥匙串里那份存档。`origin` 传 nil 就是**旧版本写下的那一份**（还没有这个字段）。
  /// 故意走 JSON：老存档在真机上就是这样躺着的，少一个键也得解得开。
  private func archive(origin: String?, refreshToken: String = "refresh-1") throws -> SavedAccount {
    var json: [String: Any] = [
      "user": ["id": person.id.uuidString, "email": person.email],
      "sessionId": UUID().uuidString,
      "device": ["id": UUID().uuidString, "name": "phone", "secret": "device-secret"],
      "refreshToken": refreshToken,
    ]
    if let origin { json["origin"] = origin }
    return try JSONDecoder().decode(SavedAccount.self, from: JSONSerialization.data(withJSONObject: json))
  }
  private func tokens(access: String, refresh: String) -> String {
    """
    {"data":{"user":{"id":"\(person.id.uuidString)","email":"\(person.email)"},
    "sessionId":"\(UUID().uuidString)","accessToken":"\(access)","refreshToken":"\(refresh)",
    "expiresAt":900000,"serverTime":0}}
    """
  }
  private func waitUntil(_ what: String, _ check: @Sendable () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      if await check() { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("等不到：\(what)")
  }

  /// A-06：两个 `AccountClient` 共用同一个凭据槽时，刷新只许发出去**一趟**。
  ///
  /// 各发各的会被服务端读成「refresh 令牌重用」，整个会话家族当场吊销，用户被登出。
  /// 单飞保护过去是实例字段，第二个实例等于没有保护。
  @Test("两个客户端共用一份凭据时只发出一次刷新")
  func 互踢() async throws {
    reset(gateClosed: true)
    GateStubProtocol.server.route("/v1/auth/refresh", 200, tokens(access: "access-2", refresh: "refresh-2"))
    GateStubProtocol.server.route("/v1/auth/me", 200, #"{"data":{"ok":true}}"#)
    let vault = StubVault(try archive(origin: nil))
    let first = try makeClient(vault)
    let second = try makeClient(vault)
    async let one: Probe = first.request("v1/auth/me")
    try await waitUntil("第一个客户端的刷新已经上路") { GateStubProtocol.server.calls("/v1/auth/refresh").count == 1 }
    async let two: Probe = second.request("v1/auth/me")
    let coordinator = RefreshCoordinator.shared(slot: vault.slotIdentifier)
    try await waitUntil("第二个客户端搭上了同一班车") { await coordinator.joinedFlights == 1 }
    GateStubProtocol.gate.open()
    let (a, b) = try await (one, two)
    #expect(a.ok == true, "搭车的和发起的都得拿到结果")
    #expect(b.ok == true)
    #expect(GateStubProtocol.server.calls("/v1/auth/refresh").count == 1, "同一个凭据槽上只许有一趟刷新")
    #expect(vault.stored?.refreshToken == "refresh-2", "槽里留下的是同一把新令牌")
  }

  /// 构造器过去接受任意 https 主机。令牌是拿钥匙串里那份换的，地址写错一个字母就是
  /// 把凭据递给别人。出厂只认自家那两台网关。
  @Test("白名单之外的主机构造不出客户端")
  func 主机白名单() throws {
    reset()
    #expect(throws: AccountError.invalidURL) {
      _ = try AccountClient(baseURL: URL(string: "https://accounts.evil.example")!, vault: StubVault(nil))
    }
    #expect(throws: AccountError.invalidURL) {
      _ = try AccountClient(baseURL: URL(string: "https://kanpan.107-174-172-10.sslip.io.evil.example")!, vault: StubVault(nil))
    }
    for allowed in ["https://kanpan.107-174-172-10.sslip.io",
                    "https://kanpan.96-44-162-222.sslip.io:8443",
                    "https://kanpan.107-174-172-10.sslip.io:8443"] {
      #expect(throws: Never.self, "\(allowed) 是自家网关") {
        _ = try AccountClient(baseURL: URL(string: allowed)!, vault: StubVault(nil))
      }
    }
  }

  /// 存档要记得自己是谁签发的。换了服务器地址（换了台网关、DEBUG 下指到别处）时，
  /// 这份令牌不能跟着出门——那等于把 A 家的钥匙往 B 家的锁上试。
  @Test("来源不符的存档当作没有会话")
  func 来源不符() async throws {
    reset()
    // 另一台网关签的：同样在白名单里，但不是这个客户端连的那台。
    let vault = StubVault(try archive(origin: "kanpan.96-44-162-222.sslip.io"))
    let client = try makeClient(vault)
    #expect(await client.savedUser() == nil, "不是这台服务器签的，就不算有会话")
    await #expect(throws: (any Error).self) { let _: Probe = try await client.request("v1/auth/me") }
    #expect(GateStubProtocol.server.calls("/v1/auth/refresh").isEmpty, "令牌不许发到别的服务器去")
    #expect(vault.stored != nil, "不认它不等于清掉它：云端只是同步通道")
  }

  /// 反过来，老版本写下的存档没有这个字段，不能因此把人踢出去——迁移不清人。
  /// 而新签下来的凭据要当场把来源记上。
  @Test("旧存档没有来源照样认，新凭据当场记上来源")
  func 来源迁移() async throws {
    reset()
    let vault = StubVault(try archive(origin: nil))
    let client = try makeClient(vault)
    #expect(await client.savedUser() != nil, "老存档按当前地址算数")
    let fresh = AccountTokens(user: person, sessionId: UUID(), accessToken: "access-2",
                              refreshToken: "refresh-2", expiresAt: 900_000, serverTime: 0)
    try await client.accept(fresh, device: AccountDevice(name: "phone"))
    let stored = try #require(vault.stored)
    let raw = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(stored)) as? [String: Any])
    #expect(raw["origin"] as? String == Self.host, "新凭据要记下是谁签的")
  }

  /// 路径守卫过去只拦字面量 `..`：URL 编码过的 `%2e%2e` 照样过得去，
  /// 而服务端那一侧是会解码的。守卫要先解码到解不动为止再判。
  @Test("URL 编码的父目录跳不出去")
  func 路径归一化() async throws {
    reset()
    let client = try makeClient(StubVault(nil))
    for path in ["%2e%2e/x", "v1/%2e%2e/health", "%252e%252e/x", "%2E%2E%2Fx", "..%2fx",
                 "v1//health", "/v1/health", "https://evil.example/x", "v1/auth/me\u{7F}"] {
      await #expect(throws: AccountError.invalidURL, "\(path) 必须被拒") {
        _ = try await client.data(path, authenticated: false)
      }
    }
    #expect(GateStubProtocol.server.calls.isEmpty, "被拒的路径一个字节都不该出门")
    // 正常路径不能被误伤。
    let device = UUID().uuidString
    GateStubProtocol.server.route("/v1/auth/devices/" + device, 200, #"{"data":{"devices":[]}}"#)
    _ = try await client.data("v1/auth/devices/" + device, authenticated: false)
  }

  /// 守卫守的是**路径**，可它拿到的字符串后面还挂着查询串。
  ///
  /// `AppAccountBridge` 拉画线那一段拼出来的是
  /// `v1/sync/bootstrap?collection=drawings&prefix=binance/usd_m/BTCUSDT/`：
  /// 前缀是画线 id 的头几段（`venue/market/symbol/`），带着斜杠、还以斜杠收尾。
  /// 这些斜杠本不属于路径，却一路参与了「按 / 切段」那道检查，末尾那一道切出一个空段，
  /// 于是一条完全正当的地址被当成路径遍历拒掉——整档全量同步停在拉画线这一步，
  /// 账号页上从此挂着「账号服务地址无效」，同步页永远等不到「已同步」
  /// （M8 兼容性矩阵 iPhone 15 上 `FavoritesGroupSyncUITests` 那条红的根因）。
  @Test("查询串里的斜杠不算路径段")
  func 查询串不被误伤() async throws {
    reset()
    let client = try makeClient(StubVault(nil))
    GateStubProtocol.server.route("/v1/sync/bootstrap", 200, #"{"data":{"ok":true}}"#)
    for path in ["v1/sync/bootstrap?collection=drawings&prefix=binance/usd_m/BTCUSDT/",
                 "v1/sync/bootstrap?collection=settings",
                 "v1/sync/bootstrap?collection=drawings&prefix=binance/usd_m/BTCUSDT/&after=a/b"] {
      _ = try await client.data(path, authenticated: false)
    }
    #expect(GateStubProtocol.server.calls("/v1/sync/bootstrap").count == 3, "带查询串的正当地址一条都不该被拦")
    // 放行的只有查询串那一半：路径那一半照旧一个都不许过。
    for path in ["v1/%2e%2e/sync?collection=x", "v1//sync?collection=x", "/v1/sync?collection=x",
                 "https://evil.example/x?collection=y", "v1/sync\u{7F}?collection=x"] {
      await #expect(throws: AccountError.invalidURL, "\(path) 必须被拒") {
        _ = try await client.data(path, authenticated: false)
      }
    }
    #expect(GateStubProtocol.server.calls("/v1/sync/bootstrap").count == 3, "被拒的路径一个字节都不该出门")
  }
}
