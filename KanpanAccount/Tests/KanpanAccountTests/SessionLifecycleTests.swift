import Foundation
import Testing
@testable import KanpanAccount

/// 一台假服务器：记下每一趟请求，按登记的答案回；也能整台「断网」。
final class StubServer: @unchecked Sendable {
  struct Call: Sendable { var path: String; var body: Data? }
  private let lock = NSLock()
  private var recorded: [Call] = []
  private var routes: [(suffix: String, status: Int, body: Data)] = []
  private var outage: Error?
  /// 扣住不答的路径（`hold`）：请求到了先记下、报到一声，等 `releaseHeld` 才答。
  private var holding: Set<String> = []
  private var parked: [@Sendable () -> Void] = []
  private var arrivals: AsyncStream<Void>.Continuation?
  func reset() {
    lock.lock(); defer { lock.unlock() }
    recorded = []; routes = []; outage = nil; holding = []; parked = []; arrivals = nil
  }
  /// 让 `suffix` 这条路的请求先扣着。返回的流在每趟被扣住的请求到达时响一声。
  func hold(_ suffix: String) -> AsyncStream<Void> {
    lock.lock(); defer { lock.unlock() }
    holding.insert(suffix)
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    arrivals = continuation
    return stream
  }
  /// 扣着的都答掉，此后不再扣。
  func releaseHeld() {
    lock.lock(); holding = []; let waiting = parked; parked = []; lock.unlock()
    for answer in waiting { DispatchQueue.global().async(execute: answer) }
  }
  /// 这趟要不要扣：要扣就把「答」收起来，返回 true。
  func park(_ path: String, _ answer: @escaping @Sendable () -> Void) -> Bool {
    lock.lock()
    guard holding.contains(where: { path.hasSuffix($0) }) else { lock.unlock(); return false }
    parked.append(answer); let signal = arrivals
    lock.unlock()
    signal?.yield()
    return true
  }
  func route(_ suffix: String, _ status: Int, _ json: String) {
    lock.lock(); defer { lock.unlock() }; routes.append((suffix, status, Data(json.utf8)))
  }
  func goOffline() { lock.lock(); defer { lock.unlock() }; outage = URLError(.notConnectedToInternet) }
  var calls: [Call] { lock.lock(); defer { lock.unlock() }; return recorded }
  func calls(_ suffix: String) -> [Call] { calls.filter { $0.path.hasSuffix(suffix) } }
  func record(_ call: Call) { lock.lock(); defer { lock.unlock() }; recorded.append(call) }
  func answer(_ path: String) -> Result<(Int, Data), any Error> {
    lock.lock(); defer { lock.unlock() }
    if let outage { return .failure(outage) }
    if let hit = routes.first(where: { path.hasSuffix($0.suffix) }) { return .success((hit.status, hit.body)) }
    return .success((404, Data(#"{"error":{"code":"not_found"}}"#.utf8)))
  }
}
final class StubProtocol: URLProtocol {
  static let server = StubServer()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url?.path ?? ""
    StubProtocol.server.record(.init(path: path, body: request.uploaded))
    nonisolated(unsafe) let me = self
    if StubProtocol.server.park(path, { me.respond(path) }) { return }
    respond(path)
  }
  private func respond(_ path: String) {
    switch StubProtocol.server.answer(path) {
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
extension URLRequest {
  /// URLProtocol 里 `httpBody` 常常是空的，真正的字节在 `httpBodyStream` 上。
  var uploaded: Data? {
    if let body = httpBody { return body }
    guard let stream = httpBodyStream else { return nil }
    stream.open(); defer { stream.close() }
    var data = Data(); let size = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size); defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let read = stream.read(buffer, maxLength: size)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}
/// 钥匙串的替身。`refuseWrite` 用来演「钥匙串抽风」。
final class StubVault: CredentialVault, @unchecked Sendable {
  private let lock = NSLock()
  private var value: SavedAccount?
  private var refuse = false
  /// 默认每个假钥匙串自成一槽（刷新协调者是进程级的，用例之间不许串味）；
  /// 要演「两个客户端共用同一份凭据」时把同一个 `StubVault` 实例传给两边。
  let slotIdentifier: String
  init(_ value: SavedAccount?, slot: String = "memory:" + UUID().uuidString) {
    self.value = value; self.slotIdentifier = slot
  }
  var stored: SavedAccount? { lock.lock(); defer { lock.unlock() }; return value }
  func refuseWrite() { lock.lock(); defer { lock.unlock() }; refuse = true }
  func read() throws -> SavedAccount? { stored }
  func write(_ next: SavedAccount?) throws {
    lock.lock(); defer { lock.unlock() }
    if refuse { throw AccountError.keychain }
    value = next
  }
}

/// 退登、重新认证这条链。跑的是 `AccountClient` 那一层——界面那层（`AccountFeature`）
/// 在 app 目标里没有测试宿主，所以凡是能下沉的判断都放在这儿由用例钉住。
///
/// 这一套从前整个裹在 `#if DEBUG` 里（审查 C-05）：它拿假主机 `accounts.invalid` 建
/// 客户端，靠的是只存在于 DEBUG 的 `Options(allowAnyHostForTests:)`。后果是
/// `swift test -c release` 下「退登清不清干净」「被顶下去走哪条路」这些行为一条都不存在，
/// 而汇总看起来照样全绿。现在改成白名单里那台网关——请求全被 `StubProtocol` 就地截下，
/// 一个字节都不出门，地址只是个名字——于是 Debug / Release 两边跑的是同一套。
@Suite("会话生命周期", .serialized)
struct SessionLifecycleTests {
  private static let host = "kanpan.43-160-232-253.sslip.io"

  private func makeClient(_ vault: StubVault) throws -> AccountClient {
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

  /// A-02：access 从不落盘，冷启动之后手上只有 refresh。退登时如果只在「内存里还有
  /// access」的情况下才去吊销，那么关过一次 app 再退登，服务端那条会话就会原样活满
  /// 三十天——手机丢了以后在设置里退登等于什么也没做。
  @Test("冷启动之后退登也要吊销服务端那条会话")
  func 冷启动退登() async throws {
    let vault = StubVault(saved())
    let client = try makeClient(vault)
    StubProtocol.server.route("/v1/auth/session/revoke", 200, #"{"data":{"ok":true}}"#)
    try await client.signOut()
    await client.settleRevocation()
    let hit = try #require(StubProtocol.server.calls("/v1/auth/session/revoke").first, "冷启动之后退登也得有一条能认证的吊销请求")
    let body = try #require(hit.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(body["refreshToken"] as? String == "refresh-token-value")
    #expect((body["device"] as? [String: Any])?["secret"] != nil, "吊销要带设备绑定，不能只凭一把令牌")
    #expect(vault.stored == nil, "本地凭据当场就该没了")
  }

  /// 审查 D-09：登录还在路上时点了退出。`signOut` 换了代际，迟到的回包被作废成
  /// `CancellationError`，调用方拿不到令牌——从前那条新会话就没人吊销，白占着
  /// 「同类设备一台在线」的名额活满三十天。现在客户端在作废之前自己吊销它。
  @Test("登录回包到手前退了登：回包作废、不落钥匙串，服务端那条新会话吊销掉")
  func 迟到的登录回包要吊销() async throws {
    let vault = StubVault(nil)
    let client = try makeClient(vault)
    StubProtocol.server.route("/v1/auth/login", 200, #"{"data":{"user":{"id":"A11CE000-3333-4C0A-9E2D-0A1B2C3D4E5F","email":"alice"},"sessionId":"5E550000-0000-4000-8000-000000000001","accessToken":"a-late","refreshToken":"r-late","expiresAt":900000,"serverTime":0}}"#)
    StubProtocol.server.route("/v1/auth/session/revoke", 200, #"{"data":{"ok":true}}"#)
    let arrived = StubProtocol.server.hold("/v1/auth/login")
    let device = AccountDevice(name: "phone")
    struct Input: Encodable { var username: String; var password: String; var device: AccountDevice }
    let body = try JSONEncoder().encode(Input(username: "alice", password: "abc12345", device: device))
    let login = Task { try await client.request("v1/auth/login", method: "POST", body: body, authenticated: false, as: AccountTokens.self) }
    for await _ in arrived { break }
    try await client.signOut()
    StubProtocol.server.releaseHeld()
    await #expect(throws: CancellationError.self) { _ = try await login.value }
    await client.settleRevocation()
    let hit = try #require(StubProtocol.server.calls("/v1/auth/session/revoke").first, "迟到签出的那条会话没吊销")
    let sent = try #require(hit.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(sent["refreshToken"] as? String == "r-late")
    #expect((sent["device"] as? [String: Any])?["secret"] as? String == device.secret, "吊销要带登录时那台设备的绑定")
    #expect(vault.stored == nil, "迟到的令牌不许落进钥匙串")
    #expect(await client.savedUser() == nil)
  }

  /// 退登在界面上必须是「已经退了」。钥匙串写失败要报出来，但不能把人留在登录态里，
  /// 更不能因为它就跳过吊销。
  @Test("钥匙串写失败也不会把人留在登录态")
  func 钥匙串抽风() async throws {
    let vault = StubVault(saved())
    let client = try makeClient(vault)
    StubProtocol.server.route("/v1/auth/session/revoke", 200, #"{"data":{"ok":true}}"#)
    vault.refuseWrite()
    await #expect(throws: AccountError.keychain) { try await client.signOut() }
    #expect(await client.savedUser() == nil, "内存里的身份要先卸干净")
    await client.settleRevocation()
    #expect(!StubProtocol.server.calls("/v1/auth/session/revoke").isEmpty, "写盘失败不该跳过吊销")
  }

  /// 离线退登仍然是退登：网络那一脚失败不能让本地退不掉。
  @Test("离线也能退登")
  func 离线退登() async throws {
    let vault = StubVault(saved())
    let client = try makeClient(vault)
    StubProtocol.server.goOffline()
    try await client.signOut()
    #expect(await client.savedUser() == nil)
    #expect(vault.stored == nil)
  }

  /// A-05：服务端明确说这套凭据不作数了（刷新回 401），要进入「需要重新登录」这个状态，
  /// 并且**停下来**——不能每一次同步、每一次请求都再去撞一次墙。
  @Test("刷新被拒之后停下来等重新登录")
  func 需要重新登录() async throws {
    let vault = StubVault(saved())
    let client = try makeClient(vault)
    StubProtocol.server.route("/v1/auth/refresh", 401, #"{"error":{"code":"authentication_failed"}}"#)
    await #expect(throws: (any Error).self) { let _: Probe = try await client.request("v1/auth/me") }
    #expect(StubProtocol.server.calls("/v1/auth/refresh").count == 1)
    await #expect(throws: (any Error).self) { let _: Probe = try await client.request("v1/auth/me") }
    #expect(StubProtocol.server.calls("/v1/auth/refresh").count == 1, "服务端已经拒过一次，别再空转")
    #expect(await client.needsReauthentication, "要能说出『该重新登录了』")
    #expect(vault.stored != nil, "云端只是同步通道：认证失效不许清本地凭据")
  }

  /// 反过来，断网只是断网：不能把它当成「认证失效」，否则飞机上开一次 app
  /// 就把人推到登录页，而且再也不重试。
  @Test("断网不是认证失效")
  func 断网不算失效() async throws {
    let vault = StubVault(saved())
    let client = try makeClient(vault)
    StubProtocol.server.goOffline()
    await #expect(throws: (any Error).self) { let _: Probe = try await client.request("v1/auth/me") }
    await #expect(throws: (any Error).self) { let _: Probe = try await client.request("v1/auth/me") }
    #expect(StubProtocol.server.calls("/v1/auth/refresh").count == 2, "断网要照常重试")
    #expect(await client.needsReauthentication == false)
    #expect(vault.stored != nil)
  }

  /// 重新登录成功之后，「需要重新登录」这个状态要跟着消失。
  @Test("重新登录会清掉失效状态")
  func 重新登录清状态() async throws {
    let vault = StubVault(saved())
    let client = try makeClient(vault)
    StubProtocol.server.route("/v1/auth/refresh", 401, #"{"error":{"code":"authentication_failed"}}"#)
    await #expect(throws: (any Error).self) { let _: Probe = try await client.request("v1/auth/me") }
    #expect(await client.needsReauthentication)
    let user = AccountUser(id: UUID(), email: "someone")
    let tokens = AccountTokens(user: user, sessionId: UUID(), accessToken: "fresh", refreshToken: "next",
                               expiresAt: 900_000, serverTime: 0)
    try await client.accept(tokens, device: AccountDevice(name: "phone"))
    #expect(await client.needsReauthentication == false)
  }
}
