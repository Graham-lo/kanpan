import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ReviewDomain

public struct ReviewConnection: Codable, Sendable, Equatable {
  public var baseURL: URL
  public var account: String
  public init(baseURL: URL, account: String) { self.baseURL = baseURL; self.account = account }
}
public enum ScorebookError: LocalizedError {
  case invalidConnection, http(Int, String), invalidResponse
  public var errorDescription: String? {
    switch self {
    case .invalidConnection: "请输入有效服务地址和账户"
    case .http(401, _), .http(403, _): "连接凭证已失效，请重新连接"
    case .http(409, _): "记录已在其他设备更新，本地内容已保留"
    case .http(404, _): "服务端还未提供此功能"
    case .http(_, let text): text.isEmpty ? "同步暂未成功，请稍后重试" : text
    case .invalidResponse: "服务返回的数据无法读取"
    }
  }
}
public struct NativeRecordResponse: Codable, Sendable { public var record: ReviewRecord }
public struct NativeListResponse: Codable, Sendable { public var records: [ReviewRecord]; public var next: String? }
public struct NativeSearchResponse: Codable, Sendable { public var items: [ReviewMatch]; public var cutoff: Int64; public var next: String?; public var partial: Bool? }
public struct NativeSearchJob: Codable, Sendable { public var id: UUID; public var status: String; public var cutoff: Int64; public var checked: Int?; public var total: Int?; public var error: String? }
public struct NativeMatchResponse: Codable, Sendable { public var item: ReviewMatch }
private struct OKResponse: Codable, Sendable { var ok: Bool }
public struct NativeStatsResponse: Codable, Sendable { public var groups: [ReviewStatsGroup] }
private struct Envelope<T: Decodable>: Decodable { var data: T }

public struct ScorebookClient: Sendable {
  public typealias Transport = @Sendable (String, String, Data?, UUID?) async throws -> Data
  public let connection: ReviewConnection
  private let token: String
  private var transport: Transport?
  public init(connection: ReviewConnection, token: String) { self.connection = connection; self.token = token }
  public init(connection: ReviewConnection, transport: @escaping Transport) {
    self.connection = connection; self.token = ""; self.transport = transport
  }
  public func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil, key: UUID? = nil, as: T.Type = T.self) async throws -> T {
    if let transport {
      let data = try await transport(path, method, body, key)
      return try JSONDecoder().decode(Envelope<T>.self, from: data).data
    }
    guard ["https", "http"].contains(connection.baseURL.scheme), connection.baseURL.host != nil,
      !token.isEmpty else { throw ScorebookError.invalidConnection }
    guard let url = URL(string: path, relativeTo: connection.baseURL.appendingPathComponent("/"))?.absoluteURL,
      url.host == connection.baseURL.host else { throw ScorebookError.invalidConnection }
    var request = URLRequest(url: url, timeoutInterval: 45)
    request.httpMethod = method; request.httpBody = body
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let key { request.setValue(key.uuidString, forHTTPHeaderField: "Idempotency-Key") }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ScorebookError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      // No server internals or echoed request/credential bodies in product errors.
      throw ScorebookError.http(http.statusCode, "")
    }
    return try JSONDecoder().decode(Envelope<T>.self, from: data).data
  }
  public func create(_ operation: ReviewOperation) async throws -> ReviewRecord {
    let response: NativeRecordResponse = try await request("v1/native-review/records", method: "POST", body: operation.body, key: operation.id)
    return response.record
  }
  public func list(after: String? = nil, query: String = "", todo: Bool = false) async throws -> NativeListResponse {
    var parts = URLComponents(); var items: [URLQueryItem] = []
    if let after { items.append(URLQueryItem(name: "after", value: after)) }
    if !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
    if todo { items.append(URLQueryItem(name: "todo", value: "true")) }
    parts.queryItems = items.isEmpty ? nil : items
    return try await request("v1/native-review/records" + (parts.string ?? ""))
  }
  public func detail(_ id: UUID) async throws -> NativeRecordResponse { try await request("v1/native-review/records/\(id.uuidString)") }
  public func startSearch(range: ReviewRange, cutoff: Int64, scope: String, id: UUID) async throws -> NativeSearchJob {
    struct Query: Encodable { var range: ReviewRange; var cutoff: Int64; var scope: String }
    return try await request("v1/native-review/searches", method: "POST", body: JSONEncoder().encode(Query(range: range, cutoff: cutoff, scope: scope)), key: id)
  }
  public func searchStatus(_ id: UUID) async throws -> NativeSearchJob { try await request("v1/native-review/searches/\(id.uuidString)") }
  public func searchResults(_ id: UUID, after: String? = nil) async throws -> NativeSearchResponse {
    let suffix = after.flatMap(Int.init).map { "?after=\($0)" } ?? ""
    return try await request("v1/native-review/searches/\(id.uuidString)/results" + suffix)
  }
  public func cancelSearch(_ id: UUID) async throws { let _: OKResponse = try await request("v1/native-review/searches/\(id.uuidString)", method: "DELETE", key: UUID()) }
  public func saveMatch(_ match: ReviewMatch, search: UUID) async throws {
    struct Input: Encodable { var searchId: UUID; var matchId: String }
    let _: NativeMatchResponse = try await request("v1/native-review/saved-matches", method: "POST", body: JSONEncoder().encode(Input(searchId: search, matchId: match.id)), key: UUID())
  }
  public func stats() async throws -> NativeStatsResponse { try await request("v1/native-review/statistics") }
  public func update(_ operation: ReviewOperation) async throws -> ReviewRecord {
    let response: NativeRecordResponse = try await request("v1/native-review/records/\(operation.recordId.uuidString)/\(operation.kind)", method: "POST", body: operation.body, key: operation.id)
    return response.record
  }
}
