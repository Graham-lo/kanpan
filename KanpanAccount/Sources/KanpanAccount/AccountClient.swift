import Foundation
import KanpanCore

private struct Envelope<T: Decodable>: Decodable { var data: T }
private struct FailureEnvelope: Decodable {
  struct Failure: Decodable { var code: String; var deviceKind: DeviceKind? }
  var error: Failure
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}
/// Owns the single refresh flight and its persistent retry identity for all feature clients.
public actor AccountClient {
  /// 构造客户端时的开关。产品代码一个都不用传。
  public struct Options: Sendable {
    #if DEBUG
    /// 只在 DEBUG 里存在：单测要拿假服务器地址（`accounts.invalid` 之类）建客户端。
    /// UI 测试走的是线上那台网关，不需要它。
    public var allowAnyHostForTests: Bool
    public init(allowAnyHostForTests: Bool = false) { self.allowAnyHostForTests = allowAnyHostForTests }
    #else
    public init() {}
    #endif
  }
  /// 自家那两台网关（名单只在 `ServerHosts` 一处）。写错一个字母就是把钥匙串里那份
  /// refresh 令牌递给别人，所以这里只认名单，不认「看起来像 https」。
  static let allowedHosts: Set<String> = ServerHosts.names
  static let allowedPorts: Set<Int> = ServerHosts.ports
  public nonisolated let baseURL: URL
  private let vault: any CredentialVault
  /// 这一槽凭据的刷新协调者（进程级，按 `vault.slotIdentifier` 取）。
  /// 单飞和代际都在它身上，所以多开几个客户端也只会刷一次（A-06）。
  private let coordinator: RefreshCoordinator
  private let session: URLSession
  private var saved: SavedAccount?
  private var access: AccountTokens?
  private var accessDeadline: TimeInterval = 0
  private var revocation: Task<Void, Never>?
  private var lostAuthentication = false
  /// 被哪一类设备顶下去的（`nil` = 没被顶）。界面要靠它说出「另一台手机 / 平板 / 电脑」。
  private var replacement: DeviceKind?
  /// 钥匙串上一次读的时候读不动（见 `AccountError.credentialsUnavailable`）。
  ///
  /// 读不动**不等于没有凭据**：锁屏状态下被后台拉起时整片钥匙串都是锁着的。所以这时
  /// `saved` 虽然是 `nil`，客户端也不把自己当成「没登录」——`savedUser()`、发请求
  /// 之前都会先再读一次，读到了就接上；主动登录、退登会把它清掉（那时本机已经有了
  /// 比钥匙串里更新的结论，不能再让一次迟到的读把旧凭据翻回来）。
  private var vaultUnreadable = false
  /// 服务端已经明确说这套凭据不作数了（刷新拿回 401），不是「暂时连不上」。
  /// 这个状态要的是让人重新登录一次，**不是**清掉本地数据——云端只是同步通道。
  public var needsReauthentication: Bool { lostAuthentication }
  /// 被同一类设备顶下去时，顶掉它的是哪一类设备。没被顶就是 `nil`。
  public var replacedDeviceKind: DeviceKind? { replacement }
  public init(baseURL: URL, vault: any CredentialVault = KeychainCredentialVault(),
              session: URLSession? = nil, options: Options = Options()) throws {
    guard baseURL.scheme == "https" || (baseURL.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(baseURL.host ?? "")),
      baseURL.host != nil, baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil,
      AccountClient.isAllowed(baseURL, options: options) else { throw AccountError.invalidURL }
    self.baseURL = baseURL; self.vault = vault
    self.coordinator = RefreshCoordinator.shared(slot: vault.slotIdentifier)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    self.session = session ?? URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    // 槽里那份凭据是别人签的（换了网关、DEBUG 指到了别处）就当作没有会话：
    // 不把它删掉（云端只是同步通道，换回去还得认），只是不拿它出门。
    // 读不动不抛：客户端照样建起来，只是先记着「凭据欠着」（审查 17）。以前这里 `try`
    // 一抛，整个客户端就是 `nil`，账号页当场变成「账号服务暂不可用」，冷启动装的是访客
    // 档案——锁屏被拉起一次，登录的人一眼看去自选全没了。
    do { saved = AccountClient.admit(try vault.read(), baseURL: baseURL) } catch { vaultUnreadable = true }
    // 上一次运行里被顶下去了：身份还在（本机档案照常认得出这是谁的），但令牌已经没了。
    // 开机就知道这条会话不作数，一个字节都不用发出去再问一遍。
    if let kind = saved?.replacedBy { lostAuthentication = true; replacement = kind }
  }
  /// 槽里那份凭据是别人签的（换了网关、DEBUG 指到了别处）就当作没有会话。
  static func admit(_ stored: SavedAccount?, baseURL: URL) -> SavedAccount? {
    stored.flatMap { AccountClient.accepts($0, baseURL: baseURL) ? $0 : nil }
  }
  /// 钥匙串是不是还读不动（凭据欠着）。界面用它区分「没登录」和「登录状态稍后才读得到」。
  public var credentialsUnavailable: Bool { vaultUnreadable }
  /// 凭据欠着的话再读一次钥匙串。返回 `true` = 这回读到了（里面有没有凭据另说），
  /// `false` = 还是读不动。本来就读到过的直接答 `true`，不碰钥匙串。
  @discardableResult public func retryCredentials() -> Bool {
    guard vaultUnreadable else { return true }
    // 不用 `try?`：它会把「读到了、里面没有」（`nil`）和「读不动」压成同一个 `nil`。
    let stored: SavedAccount?
    do { stored = try vault.read() } catch { return false }
    vaultUnreadable = false
    saved = AccountClient.admit(stored, baseURL: baseURL)
    if let kind = saved?.replacedBy { lostAuthentication = true; replacement = kind }
    return true
  }
  /// 这份凭据是不是这台服务器签的。老存档没有 `origin`，按当前地址算数——迁移不清人。
  static func accepts(_ stored: SavedAccount, baseURL: URL) -> Bool {
    guard let origin = stored.origin else { return true }
    return origin == AccountClient.origin(of: baseURL)
  }
  static func origin(of url: URL) -> String { url.host?.lowercased() ?? "" }
  /// 只认自家那两台网关（含 :8443 那个端口变体）。
  static func isAllowed(_ url: URL, options: Options) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    #if DEBUG
    if options.allowAnyHostForTests { return true }
    // 本机调试用的后端。Release 里这两行根本不存在。
    if ["localhost", "127.0.0.1", "::1"].contains(host) { return true }
    #endif
    guard url.scheme == "https", allowedHosts.contains(host) else { return false }
    guard let port = url.port else { return true }
    return allowedPorts.contains(port)
  }
  public func savedUser() -> AccountUser? { retryCredentials(); return saved?.user }
  public func savedDevice() -> AccountDevice? { retryCredentials(); return saved?.device }
  public func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil,
                                             key: UUID? = nil, authenticated: Bool = true, as type: T.Type = T.self) async throws -> T {
    let data = try await data(path, method: method, body: body, key: key, authenticated: authenticated)
    return try JSONDecoder().decode(Envelope<T>.self, from: data).data
  }
  public func data(_ path: String, method: String = "GET", body: Data? = nil, key: UUID? = nil, authenticated: Bool = true, contentType: String = "application/json") async throws -> Data {
    // 「被顶下去」从这一处进。它可能发生在两个地方：拿着 access 令牌访问任何接口，
    // 或者刷新那一趟。两条路都收在这儿，省得各写一遍、各漏一处。
    do { return try await perform(path, method: method, body: body, key: key, authenticated: authenticated, contentType: contentType) }
    catch AccountError.sessionReplaced(let kind) { replaced(by: kind); throw AccountError.sessionReplaced(kind) }
  }
  /// 服务端说这条会话被同一类设备顶掉了。
  ///
  /// **令牌清掉，身份留着。** 那把 refresh 令牌服务端已经作废（会话真的没了，
  /// 不是「暂时不认」），留着只会在下一次刷新时再撞一次墙；而整条存档删掉的话，
  /// 下次开 app 装进来的就是访客档案，用户的自选、画线、复盘一眼看去全没了
  /// ——云端只是同步通道，不是可用性依赖。所以这儿留下的是一份「认得出是谁、
  /// 但出不了门」的存档，界面照常摆着这个人的东西，只是同步停着。
  private func replaced(by kind: DeviceKind) {
    lostAuthentication = true; replacement = kind
    access = nil; accessDeadline = 0
    guard var stored = saved else { return }
    stored.refreshToken = ""; stored.refreshRequestId = nil; stored.replacedBy = kind
    try? vault.write(stored); saved = stored
  }
  private func perform(_ path: String, method: String, body: Data?, key: UUID?, authenticated: Bool, contentType: String) async throws -> Data {
    let epoch = await coordinator.generation
    let token = authenticated ? try await accessToken() : nil
    do {
      let result = try await send(path, method: method, body: body, key: key, token: token, contentType: contentType)
      guard await coordinator.generation == epoch else { throw CancellationError() }; return result
    } catch AccountError.http(401, _) where authenticated {
      guard await coordinator.generation == epoch else { throw CancellationError() }
      // Several requests can return 401 for the same old access token; don't rotate again.
      if access?.accessToken == token { access = nil }
      let refreshed = try await accessToken()
      let result = try await send(path, method: method, body: body, key: key, token: refreshed, contentType: contentType)
      guard await coordinator.generation == epoch else { throw CancellationError() }; return result
    }
  }
  /// 路径守卫：这条路径能不能拼到 baseURL 后面出门。
  ///
  /// 只拦字面量的 `..` 等于没拦——`%2e%2e` 在服务端（以及中间任何一层代理、
  /// Foundation 自己拼 URL 的时候）会被解回 `..`。所以先**解码到解不动为止**，
  /// 原样和解开的两份都要过同一道检查：不许有 `..` / `.` 段、不许空段、
  /// 不许前导斜杠、不许带协议头、不许有控制字符。
  static func isSafe(path: String) -> Bool {
    var decoded = path
    for _ in 0..<4 {
      guard let next = decoded.removingPercentEncoding, next != decoded else { break }
      decoded = next
    }
    for candidate in [path, decoded] {
      guard !candidate.isEmpty, !candidate.hasPrefix("/"), !candidate.contains("://"), !candidate.contains("\\") else { return false }
      if candidate.unicodeScalars.contains(where: { $0.value <= 0x20 || $0.value == 0x7F }) { return false }
      if candidate.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == ".." || $0 == "." }) { return false }
    }
    return true
  }
  /// 查询串那一半的守卫。
  ///
  /// 它不是路径：`/` 在这儿只是个普通字符（画线的前缀 `binance/usd_m/BTCUSDT/` 正靠它），
  /// 所以「不许空段 / `.` / `..`」那套规则一句都不适用。这儿只挡真正有害的东西——
  /// 控制字符（能把请求行拆开）、反斜杠、协议头，以及片段：`#` 后面那一截压根到不了
  /// 服务端，出现在自家接口的地址里只可能是拼错了。
  static func isSafe(query: String) -> Bool {
    guard !query.isEmpty else { return true }
    guard query.hasPrefix("?"), !query.contains("#"), !query.contains("\\"), !query.contains("://") else { return false }
    return !query.unicodeScalars.contains { $0.value <= 0x20 || $0.value == 0x7F }
  }
  private func send(_ path: String, method: String, body: Data?, key: UUID?, token: String?, contentType: String = "application/json") async throws -> Data {
    // 调用方递进来的字符串后面可能还挂着查询串（拉画线那一段拼的是
    // `v1/sync/bootstrap?collection=drawings&prefix=binance/usd_m/BTCUSDT/`）。
    // **先把这两半分开再各按各的规矩查**：查询串里的斜杠不是路径段，拿路径那套
    // 「按 / 切段」去切它，前缀末尾那一道斜杠就成了「空段」，一条完全正当的地址
    // 被当成路径遍历拒掉，整档全量同步停在拉画线这一步（M8 兼容性矩阵里
    // `FavoritesGroupSyncUITests` 等不到「已同步」、账号页挂着「账号服务地址无效」）。
    // 切只切**字面量**的 `?` / `#`：编码过的 `%3f` 留在路径那一半里，
    // 照旧要过解码到底的那道检查，父目录还是跳不出去。
    let head = path.prefix { $0 != "?" && $0 != "#" }
    guard AccountClient.isSafe(path: String(head)),
      AccountClient.isSafe(query: String(path.dropFirst(head.count))),
      let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("/"))?.absoluteURL,
      url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port,
      // 拼完再看一遍：解析过的那条路径也得是干净的（`url.path` 是解过码的）。
      AccountClient.isSafe(path: String(url.path.drop(while: { $0 == "/" }))) else { throw AccountError.invalidURL }
    var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    if let key { request.setValue(key.uuidString, forHTTPHeaderField: "Idempotency-Key") }
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
    guard (200..<300).contains(response.statusCode) else {
      let failure = try? JSONDecoder().decode(FailureEnvelope.self, from: data).error
      if response.statusCode == 401, failure?.code == "session_replaced" {
        throw AccountError.sessionReplaced(failure?.deviceKind ?? .phone)
      }
      throw AccountError.http(response.statusCode, failure?.code ?? "request_failed")
    }
    return data
  }
  private func accessToken() async throws -> String {
    if let access, ProcessInfo.processInfo.systemUptime < accessDeadline { return access.accessToken }
    // 凭据欠着：先再读一次；还读不动就报「稍后再试」，**不是** 401——一个 401 会被
    // 上层当成「登录失效」把人推去重新登录，而他其实什么都没丢。
    guard retryCredentials() else { throw AccountError.credentialsUnavailable }
    // 服务端已经拒过一次了，再撞第二次也是同一堵墙。停在这儿，等人重新登录。
    if let replacement { throw AccountError.sessionReplaced(replacement) }
    if lostAuthentication { throw AccountError.reauthenticationRequired }
    guard saved != nil else { throw AccountError.http(401, "authentication_failed") }
    let epoch = await coordinator.generation
    do {
      // 领跑还是搭车由协调者说了算：同一槽凭据上只有一趟刷新真的出门（A-06）。
      let value = try await coordinator.refresh { [weak self] in
        guard let self else { throw CancellationError() }
        return try await self.performRefresh()
      }
      guard await coordinator.generation == epoch else { throw CancellationError() }
      try adopt(value)
      return value.accessToken
    } catch {
      guard await coordinator.generation == epoch else { throw error }
      // 只有服务端**明确拒绝**才算「该重新登录了」。断网、超时、502 都只是这一趟没成，
      // 下一趟还得照常重试——否则在飞机上开一次 app 就把人推到登录页，再也不重试了。
      //
      // 搭车的人也走这一段：一趟刷新回 401，发起者和等在后面的那几个要拿到同一个结论。
      if case AccountError.http(401, _) = error {
        lostAuthentication = true; access = nil; accessDeadline = 0
        throw AccountError.reauthenticationRequired
      }
      if lostAuthentication { throw AccountError.reauthenticationRequired }
      throw error
    }
  }
  /// 真的去刷那一趟。只有协调者选中的**领跑者**会走到这儿。
  private func performRefresh() async throws -> AccountTokens {
    // 先把槽里最新的那份读回来：共用这一槽的另一个实例可能刚刚轮换过令牌，
    // 手上这份已经作废了，拿它去刷就是「令牌重用」，整条会话家族会被吊销。
    if let stored = try? vault.read(), AccountClient.accepts(stored, baseURL: baseURL), stored.user.id == saved?.user.id {
      saved = stored
    }
    guard var saved else { throw AccountError.http(401, "authentication_failed") }
    // 共用这一槽的另一个客户端刚被顶下去、把令牌清掉了：那就是同一条会话的结局，
    // 别拿一把空令牌再出门问一遍。
    if let kind = saved.replacedBy { throw AccountError.sessionReplaced(kind) }
    let requestId = saved.refreshRequestId ?? UUID(); saved.refreshRequestId = requestId
    // 顺手把老存档的来源补上（迁移）。
    saved.origin = saved.origin ?? AccountClient.origin(of: baseURL)
    try vault.write(saved); self.saved = saved
    struct Refresh: Encodable { var refreshToken: String; var requestId: UUID; var device: AccountDevice }
    let body = try JSONEncoder().encode(Refresh(refreshToken: saved.refreshToken, requestId: requestId, device: saved.device))
    let data = try await send("v1/auth/refresh", method: "POST", body: body, key: requestId, token: nil)
    return try JSONDecoder().decode(Envelope<AccountTokens>.self, from: data).data
  }
  /// 把刷新回来的这一对令牌落到自己这份状态里。发起者和搭车的都要走这一步。
  private func adopt(_ value: AccountTokens) throws {
    guard let saved, value.user.id == saved.user.id else { throw CancellationError() }
    try persist(value, device: saved.device)
  }
  public func accept(_ tokens: AccountTokens, device: AccountDevice) async throws {
    lostAuthentication = false; replacement = nil; access = nil; accessDeadline = 0
    await coordinator.invalidate()
    try persist(tokens, device: device)
  }
  private func persist(_ tokens: AccountTokens, device: AccountDevice) throws {
    let next = SavedAccount(user: tokens.user, sessionId: tokens.sessionId, device: device,
                            refreshToken: tokens.refreshToken, origin: AccountClient.origin(of: baseURL))
    try vault.write(next); saved = next; access = tokens; vaultUnreadable = false
    accessDeadline = ProcessInfo.processInfo.systemUptime + max(0, min(900, Double(tokens.expiresAt - tokens.serverTime) / 1000) - 30)
  }
  /// 退登分两步，而且两步的地位不一样。
  ///
  /// **本地那一步一定做完**：内存里的身份先卸干净，钥匙串写失败也照卸不误——
  /// 界面上「已经退了」不能因为钥匙串抽一下风就变回「还登着」。写失败仍旧抛出来
  /// 让人知道，但那是在身份已经卸掉之后。
  ///
  /// **网络那一步尽力而为**：它在后台跑，离线退登照样是退登（云端只是同步通道）。
  /// 界面不等它——等它就得等满一次超时。
  public func signOut() async throws {
    let credential = saved
    let token = access?.accessToken
    // `vaultUnreadable` 也清：人已经退了，钥匙串那次删哪怕没删成，稍后一次「读到了」
    // 也不许把退掉的凭据翻回来。
    saved = nil; access = nil; accessDeadline = 0; lostAuthentication = false; replacement = nil
    vaultUnreadable = false
    // 这一槽的凭据要作废，不只是我手上这一份：共用它的其他客户端也得跟着走。
    await coordinator.invalidate()
    var failure: (any Error)?
    do { try vault.write(nil) } catch { failure = error }
    revocation = Task { await self.revoke(credential, access: token) }
    if let failure { throw failure }
  }
  /// 测试用：等后台那一脚吊销落地。产品代码不等它。
  public func settleRevocation() async { await revocation?.value }
  /// 让服务端那条会话真的结束。
  ///
  /// 首选 `session/revoke`：它拿 refresh + 设备绑定认证，**冷启动之后照样能用**
  /// ——access 从不落盘，关过一次 app 再退登时内存里根本没有 access，
  /// 旧的「有 access 才吊销」等于关过 app 就再也退不掉了（会话原样活满三十天）。
  /// 它也不轮换令牌：为了退登先换一对新的再扔掉，只会在服务端多留一份没人要的凭据。
  ///
  /// 失败只重试两次就算了：退登本来就是尽力而为，会话三十天后总会自己过期，
  /// 而一个永远重试的后台任务比那条会话更碍事。
  private func revoke(_ credential: SavedAccount?, access token: String?) async {
    for attempt in 0..<3 {
      if attempt > 0 { try? await Task.sleep(for: .seconds(attempt == 1 ? 3 : 10)) }
      if let credential {
        struct Revoke: Encodable { var refreshToken: String; var device: AccountDevice }
        guard let body = try? JSONEncoder().encode(Revoke(refreshToken: credential.refreshToken, device: credential.device)) else { return }
        do { _ = try await send("v1/auth/session/revoke", method: "POST", body: body, key: nil, token: nil); return }
        // 服务端答复了就是答复了（令牌已经作废、会话已经没了、被别人顶掉了都算完成），
        // 只有连不上才重试。
        catch AccountError.http { return } catch AccountError.sessionReplaced { return } catch { continue }
      }
      guard let token else { return }
      do { _ = try await send("v1/auth/logout", method: "POST", body: nil, key: nil, token: token); return }
      catch AccountError.http { return } catch AccountError.sessionReplaced { return } catch { continue }
    }
  }
}
