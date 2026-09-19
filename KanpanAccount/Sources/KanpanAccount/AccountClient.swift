import Foundation

private struct Envelope<T: Decodable>: Decodable { var data: T }
private struct FailureEnvelope: Decodable { struct Failure: Decodable { var code: String }; var error: Failure }
private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}
/// Owns the single refresh flight and its persistent retry identity for all feature clients.
public actor AccountClient {
  public nonisolated let baseURL: URL
  private let vault: any CredentialVault
  private let session: URLSession
  private var saved: SavedAccount?
  private var access: AccountTokens?
  private var accessDeadline: TimeInterval = 0
  private var refreshFlight: Task<AccountTokens, Error>?
  private var revocation: Task<Void, Never>?
  private var generation = UUID()
  private var lostAuthentication = false
  /// 服务端已经明确说这套凭据不作数了（刷新拿回 401），不是「暂时连不上」。
  /// 这个状态要的是让人重新登录一次，**不是**清掉本地数据——云端只是同步通道。
  public var needsReauthentication: Bool { lostAuthentication }
  public init(baseURL: URL, vault: any CredentialVault = KeychainCredentialVault(), session: URLSession? = nil) throws {
    guard baseURL.scheme == "https" || (baseURL.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(baseURL.host ?? "")),
      baseURL.host != nil, baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil else { throw AccountError.invalidURL }
    self.baseURL = baseURL; self.vault = vault
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    self.session = session ?? URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    saved = try vault.read()
  }
  public func savedUser() -> AccountUser? { saved?.user }
  public func savedDevice() -> AccountDevice? { saved?.device }
  public func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil,
                                             key: UUID? = nil, authenticated: Bool = true, as type: T.Type = T.self) async throws -> T {
    let data = try await data(path, method: method, body: body, key: key, authenticated: authenticated)
    return try JSONDecoder().decode(Envelope<T>.self, from: data).data
  }
  public func data(_ path: String, method: String = "GET", body: Data? = nil, key: UUID? = nil, authenticated: Bool = true) async throws -> Data {
    let epoch = generation
    let token = authenticated ? try await accessToken() : nil
    do {
      let result = try await send(path, method: method, body: body, key: key, token: token)
      guard epoch == generation else { throw CancellationError() }; return result
    } catch AccountError.http(401, _) where authenticated {
      guard epoch == generation else { throw CancellationError() }
      // Several requests can return 401 for the same old access token; don't rotate again.
      if access?.accessToken == token { access = nil }
      let refreshed = try await accessToken()
      let result = try await send(path, method: method, body: body, key: key, token: refreshed)
      guard epoch == generation else { throw CancellationError() }; return result
    }
  }
  private func send(_ path: String, method: String, body: Data?, key: UUID?, token: String?) async throws -> Data {
    guard !path.hasPrefix("/"), !path.contains("://"), !path.contains(".."),
      let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("/"))?.absoluteURL,
      url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port else { throw AccountError.invalidURL }
    var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    if let key { request.setValue(key.uuidString, forHTTPHeaderField: "Idempotency-Key") }
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
    guard (200..<300).contains(response.statusCode) else {
      let code = (try? JSONDecoder().decode(FailureEnvelope.self, from: data).error.code) ?? "request_failed"
      throw AccountError.http(response.statusCode, code)
    }
    return data
  }
  private func accessToken() async throws -> String {
    if let access, ProcessInfo.processInfo.systemUptime < accessDeadline { return access.accessToken }
    // 服务端已经拒过一次了，再撞第二次也是同一堵墙。停在这儿，等人重新登录。
    if lostAuthentication { throw AccountError.reauthenticationRequired }
    if let flight = refreshFlight {
      let epoch = generation
      do {
        let result = try await flight.value
        guard epoch == generation else { throw CancellationError() }
        return result.accessToken
      } catch {
        // 搭同一班车的人也要拿到同一个结论，否则一趟刷新回 401，发起者知道「该重登了」，
        // 等在后面的那几个却各自拿着 401 继续重试。
        if lostAuthentication { throw AccountError.reauthenticationRequired }
        throw error
      }
    }
    guard var saved else { throw AccountError.http(401, "authentication_failed") }
    let requestId = saved.refreshRequestId ?? UUID(); saved.refreshRequestId = requestId
    try vault.write(saved); self.saved = saved
    let epoch = generation
    struct Refresh: Encodable { var refreshToken: String; var requestId: UUID; var device: AccountDevice }
    let body = try JSONEncoder().encode(Refresh(refreshToken: saved.refreshToken, requestId: requestId, device: saved.device))
    let flight = Task { () throws -> AccountTokens in
      let data = try await self.send("v1/auth/refresh", method: "POST", body: body, key: requestId, token: nil)
      return try JSONDecoder().decode(Envelope<AccountTokens>.self, from: data).data
    }
    refreshFlight = flight
    do {
      let value = try await flight.value
      guard epoch == generation, value.user.id == saved.user.id else { throw CancellationError() }
      try persist(value, device: saved.device); refreshFlight = nil; return value.accessToken
    } catch {
      guard epoch == generation else { throw error }
      refreshFlight = nil
      // 只有服务端**明确拒绝**才算「该重新登录了」。断网、超时、502 都只是这一趟没成，
      // 下一趟还得照常重试——否则在飞机上开一次 app 就把人推到登录页，再也不重试了。
      if case AccountError.http(401, _) = error {
        lostAuthentication = true; access = nil; accessDeadline = 0
        throw AccountError.reauthenticationRequired
      }
      throw error
    }
  }
  public func accept(_ tokens: AccountTokens, device: AccountDevice) throws {
    refreshFlight?.cancel(); refreshFlight = nil; generation = UUID(); lostAuthentication = false
    try persist(tokens, device: device)
  }
  private func persist(_ tokens: AccountTokens, device: AccountDevice) throws {
    let next = SavedAccount(user: tokens.user, sessionId: tokens.sessionId, device: device, refreshToken: tokens.refreshToken)
    try vault.write(next); saved = next; access = tokens
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
    generation = UUID(); saved = nil; access = nil; accessDeadline = 0; lostAuthentication = false
    refreshFlight?.cancel(); refreshFlight = nil
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
        // 服务端答复了就是答复了（令牌已经作废、会话已经没了都算完成），只有连不上才重试。
        catch AccountError.http { return } catch { continue }
      }
      guard let token else { return }
      do { _ = try await send("v1/auth/logout", method: "POST", body: nil, key: nil, token: token); return }
      catch AccountError.http { return } catch { continue }
    }
  }
}
