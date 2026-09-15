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
  private var generation = UUID()
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
    if let flight = refreshFlight {
      let epoch = generation
      let result = try await flight.value
      guard epoch == generation else { throw CancellationError() }
      return result.accessToken
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
      if epoch == generation { refreshFlight = nil }
      throw error
    }
  }
  public func accept(_ tokens: AccountTokens, device: AccountDevice) throws {
    refreshFlight?.cancel(); refreshFlight = nil; generation = UUID()
    try persist(tokens, device: device)
  }
  private func persist(_ tokens: AccountTokens, device: AccountDevice) throws {
    let next = SavedAccount(user: tokens.user, sessionId: tokens.sessionId, device: device, refreshToken: tokens.refreshToken)
    try vault.write(next); saved = next; access = tokens
    accessDeadline = ProcessInfo.processInfo.systemUptime + max(0, min(900, Double(tokens.expiresAt - tokens.serverTime) / 1000) - 30)
  }
  public func signOut() async throws {
    let token = access?.accessToken
    try vault.write(nil); generation = UUID(); saved = nil; access = nil
    refreshFlight?.cancel(); refreshFlight = nil
    if let token { Task { _ = try? await self.send("v1/auth/logout", method: "POST", body: nil, key: nil, token: token) } }
  }
}
