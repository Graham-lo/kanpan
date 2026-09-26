import Foundation
import Testing
@testable import KanpanAccount

/// 一台照 `Backend/kanpan-api/src/auth.rs` 规矩写的假账号服务：会签发、会轮换、认得出令牌重用、
/// 会把同类设备顶下去。压账号状态机用的——结论都从**服务端账本**上读（有没有令牌重用、
/// 有没有哪一趟推送带着 B 的令牌送来了 A 的东西、钥匙串里留下的那把 refresh 还算不算数），
/// 不看墙钟。
final class FakeAuthServer: @unchecked Sendable {
  private struct Grant { var session: UUID; var used = false; var requestId: UUID?; var sealed: Data? }
  private struct Session { var user: AccountUser; var replacedBy: DeviceKind?; var revoked = false }
  private let lock = NSLock()
  private var grants: [String: Grant] = [:]
  private var accessTokens: [String: UUID] = [:]
  private var sessions: [UUID: Session] = [:]
  private var parked: [@Sendable () -> Void] = []
  private var serial = 0
  private var _refreshCalls = 0, _reuses = 0, _crossOwner = 0, _pushes = 0, _received = 0
  /// 刷新签出来的 access 活多久（毫秒）。
  var refreshLifetime: Int64 = 900_000
  /// 答复前随机停一下（微秒上限），把在途请求的落地顺序打乱。0 = 当场答。
  var jitterMicros: UInt32 = 0
  /// 哪些路径的答复先扣住，等 `release()` 再回。
  var holding: @Sendable (String) -> Bool = { _ in false }

  var refreshCalls: Int { lock.withLock { _refreshCalls } }
  /// 服务端判成「令牌重用」的次数。一次都不许有：那是整条会话家族被吊销、用户被登出。
  var reuses: Int { lock.withLock { _reuses } }
  /// 推送里声明的属主和令牌的主人对不上的次数（A 的东西带着 B 的令牌进了 B 的云端）。
  var crossOwner: Int { lock.withLock { _crossOwner } }
  var pushes: Int { lock.withLock { _pushes } }
  /// 已经收到（不管答没答）的请求数。
  var received: Int { lock.withLock { _received } }
  var parkedCount: Int { lock.withLock { parked.count } }

  func login(_ user: AccountUser, lifetime: Int64 = 900_000) -> AccountTokens {
    lock.withLock { issue(session: UUID(), user: user, lifetime: lifetime, fresh: true) }
  }
  /// 这个人的会话全部被同一类设备顶掉。
  func replace(_ user: UUID, by kind: DeviceKind = .phone) {
    lock.withLock { for (id, s) in sessions where s.user.id == user { sessions[id]?.replacedBy = kind } }
  }
  /// 这把 access 在服务端作废（它自己到期了），refresh 照旧有效。
  func expireAccess(_ token: String) { _ = lock.withLock { accessTokens.removeValue(forKey: token) } }
  /// 钥匙串里那把 refresh 还能不能用：签过、没用过、会话没被吊销也没被顶。
  func isLive(refresh token: String) -> Bool {
    lock.withLock {
      guard let grant = grants[token], !grant.used, let session = sessions[grant.session] else { return false }
      return !session.revoked && session.replacedBy == nil
    }
  }
  func release() {
    let work = lock.withLock { let w = parked; parked.removeAll(); return w }
    for item in work { item() }
  }
  func park(_ work: @escaping @Sendable () -> Void) { lock.withLock { parked.append(work) } }
  func arrived() { lock.withLock { _received += 1 } }

  private func issue(session id: UUID, user: AccountUser, lifetime: Int64, fresh: Bool) -> AccountTokens {
    serial += 1
    if fresh { sessions[id] = Session(user: user) }
    let access = "access-\(user.email)-\(serial)", refresh = "refresh-\(user.email)-\(serial)"
    accessTokens[access] = id; grants[refresh] = Grant(session: id)
    return AccountTokens(user: user, sessionId: id, accessToken: access, refreshToken: refresh,
                         expiresAt: lifetime, serverTime: 0)
  }
  private static func failure(_ code: String, kind: DeviceKind? = nil) -> (Int, Data) {
    let extra = kind.map { #","deviceKind":"\#($0.rawValue)""# } ?? ""
    return (401, Data(#"{"error":{"code":"\#(code)"\#(extra)}}"#.utf8))
  }
  private struct Envelope<V: Encodable>: Encodable { var data: V }
  private static func wrap<T: Encodable>(_ value: T) -> Data { try! JSONEncoder().encode(Envelope(data: value)) }

  func respond(path: String, authorization: String?, body: Data?) -> (Int, Data) {
    lock.withLock {
      if path.hasSuffix("/v1/auth/refresh") {
        _refreshCalls += 1
        struct Input: Decodable { var refreshToken: String; var requestId: UUID }
        guard let body, let input = try? JSONDecoder().decode(Input.self, from: body),
              var grant = grants[input.refreshToken], let session = sessions[grant.session], !session.revoked
        else { return Self.failure("authentication_failed") }
        if let kind = session.replacedBy { return Self.failure("session_replaced", kind: kind) }
        if grant.used {
          // 同一个 request_id 是同一次请求的重试：原样回放。换了 id 还拿旧令牌来才是重用。
          if grant.requestId == input.requestId, let sealed = grant.sealed { return (200, sealed) }
          _reuses += 1; sessions[grant.session]?.revoked = true
          return Self.failure("authentication_failed")
        }
        let tokens = issue(session: grant.session, user: session.user, lifetime: refreshLifetime, fresh: false)
        let sealed = Self.wrap(tokens)
        grant.used = true; grant.requestId = input.requestId; grant.sealed = sealed; grants[input.refreshToken] = grant
        return (200, sealed)
      }
      if path.hasSuffix("/v1/auth/session/revoke") { return (200, Self.wrap(["ok": true])) }
      guard let authorization, authorization.hasPrefix("Bearer "),
            let id = accessTokens[String(authorization.dropFirst(7))], let session = sessions[id], !session.revoked
      else { return Self.failure("authentication_failed") }
      if let kind = session.replacedBy { return Self.failure("session_replaced", kind: kind) }
      if path.hasSuffix("/v1/sync/operations") {
        _pushes += 1
        struct Marker: Decodable { var owner: UUID }
        if let body, let marker = try? JSONDecoder().decode(Marker.self, from: body), marker.owner != session.user.id {
          _crossOwner += 1
        }
        return (200, Self.wrap(SyncPushResponse(results: [], serverTime: 0)))
      }
      if path.hasSuffix("/v1/sync/bootstrap") {
        return (200, Self.wrap(SyncPage(objects: [], next: nil, cursor: 0, serverTime: 0)))
      }
      return (200, Self.wrap(["ok": true]))
    }
  }
}

/// 把 `FakeAuthServer` 接到 `URLSession` 上。答复在后台队列上回，扣住的等 `release()`。
final class FakeAuthProtocol: URLProtocol {
  nonisolated(unsafe) static var server = FakeAuthServer()
  private struct Box: @unchecked Sendable { let loader: FakeAuthProtocol }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let server = Self.server
    let path = request.url?.path ?? "", auth = request.value(forHTTPHeaderField: "Authorization"), body = request.uploaded
    let box = Box(loader: self)
    server.arrived()
    let reply: @Sendable () -> Void = {
      // 答复在放行的那一刻才算：扣着的时候会话可能已经被顶掉了。
      let (status, data) = server.respond(path: path, authorization: auth, body: body)
      let loader = box.loader
      let response = HTTPURLResponse(url: loader.request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      loader.client?.urlProtocol(loader, didReceive: response, cacheStoragePolicy: .notAllowed)
      loader.client?.urlProtocol(loader, didLoad: data)
      loader.client?.urlProtocolDidFinishLoading(loader)
    }
    if server.holding(path) { server.park(reply); return }
    let jitter = server.jitterMicros
    if jitter == 0 { DispatchQueue.global().async(execute: reply); return }
    DispatchQueue.global().asyncAfter(deadline: .now() + .microseconds(Int.random(in: 0...Int(jitter))), execute: reply)
  }
  override func stopLoading() {}
}

/// 账号状态机压测（2026-09-26）：换号、退登、被顶、并发 401、刷新在途时换人。
///
/// 这一套守的是「在途请求带回来的结论只属于它出门时的那个人」：
/// - 旧会话那一趟带回来的 `session_replaced` / 401 不许把新登录的会话清掉或判成失效；
/// - 按 A 建的同步传输，换成 B 之后不许再带着 B 的令牌出门（A 的东西进 B 的云端）；
/// - 并发撞墙只刷一次，服务端账本上一次令牌重用都不许有；钥匙串里留下的永远是服务端认的那把。
@Suite("账号状态机压测", .serialized)
struct AccountSessionStressTests {
  private static let host = "kanpan.107-174-172-10.sslip.io"
  private struct Probe: Decodable, Sendable { var ok: Bool? }
  private struct Marker: Encodable { var owner: UUID }
  private let alice = AccountUser(id: UUID(), email: "alice")
  private let bob = AccountUser(id: UUID(), email: "bob")

  private func rig(_ configure: (FakeAuthServer) -> Void = { _ in }) throws -> (FakeAuthServer, AccountClient, StubVault) {
    let server = FakeAuthServer(); configure(server)
    FakeAuthProtocol.server = server
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FakeAuthProtocol.self]
    let vault = StubVault(nil)
    let client = try AccountClient(baseURL: URL(string: "https://" + Self.host)!, vault: vault,
                                   session: URLSession(configuration: configuration))
    return (server, client, vault)
  }
  private func waitUntil(_ what: String, _ check: @Sendable () async -> Bool) async throws {
    for _ in 0..<2000 {
      if await check() { return }
      try await Task.sleep(for: .milliseconds(2))
    }
    Issue.record("等不到：\(what)")
  }
  private func outcome(_ work: @escaping @Sendable () async throws -> Void) async -> (any Error)? {
    do { try await work(); return nil } catch { return error }
  }

  // MARK: - 旧会话的结论不许落到新会话上

  /// 被顶下去的是**上一条**会话：那一趟请求出门时带的是旧令牌，回来的 `session_replaced`
  /// 说的是旧会话。它要是照样走「令牌清掉、记下被顶」，刚登录的新会话就当场被清空——
  /// 钥匙串里的 refresh 变成空串，15 分钟后 access 一过期，这个人就被莫名其妙登出。
  @Test("旧会话带回的「被顶下去」不清掉刚登录的新会话", arguments: [false, true])
  func 旧顶号不清新会话(sameUser: Bool) async throws {
    let (server, client, vault) = try rig { $0.holding = { $0.hasSuffix("/v1/auth/me") } }
    try await client.accept(server.login(alice), device: AccountDevice(name: "phone"))
    let inFlight = Task { await outcome { let _: Probe = try await client.request("v1/auth/me") } }
    try await waitUntil("旧会话那一趟已经出门") { server.parkedCount == 1 }
    server.replace(alice.id)
    let next = server.login(sameUser ? alice : bob)
    try await client.accept(next, device: AccountDevice(name: "phone"))
    server.release()
    let error = await inFlight.value
    #expect(error is CancellationError, "上一条会话的结论只属于上一条会话：\(String(describing: error))")
    #expect(vault.stored?.refreshToken == next.refreshToken, "新会话的 refresh 不许被旧请求清掉")
    #expect(vault.stored?.replacedBy == nil)
    #expect(await client.replacedDeviceKind == nil)
    #expect(await client.needsReauthentication == false)
    server.holding = { _ in false }
    let _: Probe = try await client.request("v1/auth/me")
  }

  /// 旧会话的刷新被拒（401）落地时人已经换了：那是旧会话的结局，不许把新会话记成
  /// 「该重新登录了」，也不许以原样的 401 冒到调用方那里（账号页会把它念成「登录已失效」）。
  @Test("旧会话的刷新被拒不把新会话判成失效")
  func 旧刷新失败不连坐() async throws {
    let (server, client, vault) = try rig { $0.holding = { $0.hasSuffix("/v1/auth/refresh") } }
    let first = server.login(alice, lifetime: 0)
    try await client.accept(first, device: AccountDevice(name: "phone"))
    server.replace(alice.id)  // 刷新会回 session_replaced
    let inFlight = Task { await outcome { let _: Probe = try await client.request("v1/auth/me") } }
    try await waitUntil("旧会话的刷新已经出门") { server.parkedCount == 1 }
    let next = server.login(bob)
    try await client.accept(next, device: AccountDevice(name: "phone"))
    server.release()
    let error = await inFlight.value
    #expect(error is CancellationError, "\(String(describing: error))")
    #expect(await client.needsReauthentication == false)
    #expect(await client.replacedDeviceKind == nil)
    #expect(vault.stored?.refreshToken == next.refreshToken)
    #expect(vault.stored?.user.id == bob.id)
  }

  /// 同步那一轮是按「A 的档案」起的，传输层却只认「客户端现在是谁」。换成 B 之后这一轮
  /// 再发一趟，A 的待发操作就带着 B 的令牌进了 B 的云端；拉取则反过来，把 B 的对象写进
  /// A 的同步存档——两个号的数据互相串。
  @Test("按 A 建的同步传输，换成 B 之后一个字节都不出门")
  @MainActor func 传输钉住属主() async throws {
    let (server, client, _) = try rig()
    try await client.accept(server.login(alice), device: AccountDevice(name: "phone"))
    let transport = HTTPSyncTransport(client: client)
    _ = try await transport.push(try JSONEncoder().encode(Marker(owner: alice.id)), key: UUID())
    #expect(server.pushes == 1)
    try await client.signOut()
    try await client.accept(server.login(bob), device: AccountDevice(name: "phone"))
    await #expect(throws: CancellationError.self) {
      _ = try await transport.push(try JSONEncoder().encode(Marker(owner: self.alice.id)), key: UUID())
    }
    await #expect(throws: CancellationError.self) {
      _ = try await transport.bootstrap(collection: "settings", prefix: nil, after: nil)
    }
    #expect(server.crossOwner == 0, "A 的操作带着 B 的令牌进了 B 的云端")
    #expect(server.pushes == 1, "换号之后按 A 建的传输一趟都不该出门")
    // 按 B 新建的那一个照常能用。
    let fresh = HTTPSyncTransport(client: client)
    _ = try await fresh.push(try JSONEncoder().encode(Marker(owner: bob.id)), key: UUID())
    #expect(server.pushes == 2 && server.crossOwner == 0)
  }

  /// 调用方明说「这是替谁发的」时，客户端现在是别人就不发——覆盖「新号的凭据已经落地、
  /// 桥上的档案还没换过去」那一小段（`AccountFeature.accept` 里 `client.accept` 与提交之间）。
  @Test("明说替谁发的请求，客户端换了人就不出门")
  @MainActor func 显式属主() async throws {
    let (server, client, _) = try rig()
    try await client.accept(server.login(bob), device: AccountDevice(name: "phone"))
    let forAlice = HTTPSyncTransport(client: client, owner: alice.id)
    await #expect(throws: CancellationError.self) {
      _ = try await forAlice.push(try JSONEncoder().encode(Marker(owner: self.alice.id)), key: UUID())
    }
    await #expect(throws: CancellationError.self) {
      _ = try await client.data("v1/review/records", owner: self.alice.id)
    }
    #expect(server.received == 0)
    _ = try await client.data("v1/auth/me", owner: bob.id)
    #expect(server.received == 1)
  }

  // MARK: - 并发撞墙只刷一次

  /// access 到期那一刻五十个请求一起要令牌：只许一趟刷新出门，服务端账本上零重用。
  /// 重复 150 轮，每轮先换一条「到期即作废」的会话。
  @Test("到期那一刻五十个并发请求只刷一次（150 轮）")
  func 到期并发单刷() async throws {
    let (server, client, vault) = try rig { $0.jitterMicros = 300 }
    for round in 0..<150 {
      try await client.accept(server.login(alice, lifetime: 0), device: AccountDevice(name: "phone"))
      let before = server.refreshCalls
      try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<50 { group.addTask { let _: Probe = try await client.request("v1/auth/me") } }
        try await group.waitForAll()
      }
      #expect(server.refreshCalls - before == 1, "第 \(round) 轮刷了 \(server.refreshCalls - before) 次")
      #expect(server.isLive(refresh: vault.stored?.refreshToken ?? ""), "钥匙串里留下的必须是服务端认的那把")
    }
    #expect(server.reuses == 0)
  }

  /// 同一把 access 被服务端作废，五十个在途请求一起撞 401：刷一次，全部用新令牌重发成功。
  @Test("同一把 access 同时撞 401 只刷一次（150 轮）")
  func 同时401单刷() async throws {
    let (server, client, vault) = try rig { $0.jitterMicros = 300 }
    let first = server.login(alice)
    try await client.accept(first, device: AccountDevice(name: "phone"))
    var current = first.accessToken
    for round in 0..<150 {
      server.expireAccess(current)
      let before = server.refreshCalls
      try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<50 { group.addTask { let _: Probe = try await client.request("v1/auth/me") } }
        try await group.waitForAll()
      }
      #expect(server.refreshCalls - before == 1, "第 \(round) 轮刷了 \(server.refreshCalls - before) 次")
      let stored = try #require(vault.stored)
      #expect(server.isLive(refresh: stored.refreshToken))
      current = "access-alice-\(stored.refreshToken.split(separator: "-").last!)"
    }
    #expect(server.reuses == 0)
  }

  // MARK: - 登录 A → 退登 → 登录 B 几百轮，途中顶号、过期、在途请求乱序落地

  /// 每一轮：A 登录（有时 access 当场到期）→ 按 A 建一条同步传输，发一串推送、拉取、
  /// 普通请求（答复乱序落地）→ 有时 A 被顶 → 退登 → B 登录 → 按 A 的传输再发几趟 →
  /// 旧请求陆续落地。每轮收尾时对账：
  /// - 服务端账本：零令牌重用、零「A 的推送带着 B 的令牌」；
  /// - 钥匙串：留下的是 B 这条会话、而且那把 refresh 服务端还认；
  /// - 客户端：不是「该重新登录」、不是「被顶下去」。
  @Test("A 登录 → 退登 → B 登录循环 300 轮，旧请求乱序落地")
  @MainActor func 换号循环() async throws {
    let (server, client, vault) = try rig { $0.jitterMicros = 800 }
    var rng = SystemRandomNumberGenerator()
    for round in 0..<300 {
      let expired = Bool.random(using: &rng)
      try await client.accept(server.login(alice, lifetime: expired ? 0 : 900_000), device: AccountDevice(name: "phone"))
      let transport = HTTPSyncTransport(client: client)
      let aliceBody = try JSONEncoder().encode(Marker(owner: alice.id))
      var inFlight: [Task<(any Error)?, Never>] = []
      for i in 0..<6 {
        inFlight.append(Task { @MainActor in
          await outcome {
            switch i % 3 {
            case 0: _ = try await transport.push(aliceBody, key: UUID())
            case 1: _ = try await transport.bootstrap(collection: "favorites", prefix: nil, after: nil)
            default: let _: Probe = try await client.request("v1/auth/me")
            }
          }
        })
      }
      if Int.random(in: 0..<4, using: &rng) == 0 { server.replace(alice.id) }
      await Task.yield()
      try await client.signOut()
      let next = server.login(bob, lifetime: Bool.random(using: &rng) ? 0 : 900_000)
      try await client.accept(next, device: AccountDevice(name: "phone"))
      // 换号之后，按 A 建的那条传输还在被这一轮的尾巴用着。
      for _ in 0..<2 {
        inFlight.append(Task { @MainActor in await outcome { _ = try await transport.push(aliceBody, key: UUID()) } })
      }
      for task in inFlight { _ = await task.value }
      // B 这条会话照常能用（access 可能当场到期，要刷一次）。
      let _: Probe = try await client.request("v1/auth/me")
      let stored = try #require(vault.stored)
      #expect(stored.user.id == bob.id, "第 \(round) 轮：钥匙串里不是 B")
      #expect(stored.replacedBy == nil && !stored.refreshToken.isEmpty, "第 \(round) 轮：B 的会话被旧请求清掉了")
      #expect(server.isLive(refresh: stored.refreshToken), "第 \(round) 轮：钥匙串里留下的 refresh 服务端不认了")
      #expect(await client.needsReauthentication == false, "第 \(round) 轮：B 被旧请求判成失效")
      #expect(await client.replacedDeviceKind == nil, "第 \(round) 轮")
      try await client.signOut()
      await client.settleRevocation()
    }
    #expect(server.reuses == 0, "令牌重用 = 整条会话家族被吊销")
    #expect(server.crossOwner == 0, "A 的推送带着 B 的令牌进了 B 的云端")
  }

  // MARK: - 档案：访客 → A → 访客 → B 几百轮

  /// 照 `AppAccountBridge` 的顺序走档案：访客写东西 → 登录时认领访客批次、搬进本人目录、
  /// 记完成 → 提交（`activate` + `remember`）→ 本人写东西 → 退登回访客。A、B 交替 300 轮，
  /// 每轮对账：谁的目录里都只有自己（和自己认领的访客批次）的东西；`lastOwner` 永远是
  /// 刚提交的那个人，重新从盘上读一遍也一样；认领过的批次不会被第二个人再认领。
  @Test("访客 → A → 访客 → B 循环 300 轮，档案不串号、lastOwner 记账对")
  @MainActor func 档案隔离() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("account-files-stress-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var files = try AccountFiles(root: root)
    var claimedBy: [UUID: UUID] = [:]
    func mark(_ directory: URL, _ tag: String) throws {
      try Data(tag.utf8).write(to: directory.appendingPathComponent(tag + ".mark"))
    }
    func marks(_ directory: URL) -> Set<String> {
      Set(((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".mark") })
    }
    for round in 0..<300 {
      let person = round % 2 == 0 ? alice : bob
      // 访客那一段：有时候什么都没写（认领就该是空手）。
      files.activate(user: nil); files.remember(owner: nil)
      let guestTag = "guest-\(round)"
      if round % 3 != 0 { try mark(try files.directory(user: nil), guestTag) }
      // 登录：认领访客批次，搬进本人目录。
      let home = try files.directory(user: person.id)
      if let claim = try files.claimGuest(user: person.id) {
        #expect(claimedBy[claim.id] == nil, "第 \(round) 轮：访客批次被认领了第二次")
        claimedBy[claim.id] = person.id
        for name in marks(claim.directory) {
          try FileManager.default.copyItem(at: claim.directory.appendingPathComponent(name), to: home.appendingPathComponent(name))
        }
        try files.completeGuestClaim(user: person.id, batch: claim.id)
      } else {
        #expect(round % 3 == 0, "第 \(round) 轮：访客写了东西却没认领到")
      }
      files.activate(user: person.id); files.remember(owner: person)
      #expect(AccountFiles.currentProfile == "u-" + person.id.uuidString.lowercased())
      try mark(home, "\(person.email)-\(round)")
      #expect(files.lastOwner == person)
      #expect(try files.pendingGuest(user: person.id) == nil, "第 \(round) 轮：认领完还挂着")
      // 隔一阵从盘上重读一遍：记账不能只活在内存里。
      if round % 25 == 0 {
        files = try AccountFiles(root: root)
        #expect(files.lastOwner == person, "第 \(round) 轮：重读之后 lastOwner 不对")
      }
      // 退登。
      files.activate(user: nil); files.remember(owner: nil)
      #expect(files.lastOwner == nil)
      #expect(!marks(try files.directory(user: nil)).contains(where: { $0.hasPrefix(person.email) }), "本人的东西不许落进访客目录")
    }
    // 收尾对账：A 的目录里没有一样东西带着 B 的名字，反过来也一样；访客的东西只在认领它的那个人那里。
    let aliceMarks = marks(try files.directory(user: alice.id)), bobMarks = marks(try files.directory(user: bob.id))
    #expect(!aliceMarks.contains(where: { $0.hasPrefix("bob-") }))
    #expect(!bobMarks.contains(where: { $0.hasPrefix("alice-") }))
    #expect(aliceMarks.filter { $0.hasPrefix("guest-") }.isDisjoint(with: bobMarks.filter { $0.hasPrefix("guest-") }))
    #expect(aliceMarks.count == 150 + aliceMarks.filter { $0.hasPrefix("guest-") }.count)
    #expect(try AccountFiles(root: root).lastOwner == nil, "最后一轮退登了，盘上记的也得是访客")
  }
}
