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
  /// `http(状态码, 机器可读错误码)`。第二个参数**不是**给人看的文案，而是服务端
  /// `{"error":{"code":"record_revision_changed"}}` 里那个码——文案由
  /// `ReviewFailure.message` 按码翻译，服务端原文一个字都不往界面上放。
  case invalidConnection, http(Int, String), invalidResponse
  public var errorDescription: String? {
    switch self {
    case .invalidConnection: "请输入有效服务地址和账户"
    case .http(let status, let code): ReviewFailure.message(code, status: status)
    case .invalidResponse: "服务返回的数据无法读取"
    }
  }
}

/// 一次上传失败之后，这条操作该怎么办（审查 B-02）。
public enum ReviewSyncVerdict: Sendable, Equatable {
  /// 网络不好、凭证过期、服务端忙。**原样留在队首**，下次同步拿同一个幂等键重发。
  case transient
  /// 409。别的设备先改了，这条基于旧版本的操作永远不会成功，但内容还值钱：
  /// 从队列里摘出来交给人裁决，队列继续跑。
  case conflict
  /// 400 / 404 / 422 这些。服务端**拒绝**这条操作的内容，重发多少次都一样：
  /// 同样摘出来，但不给「再试一次」，只给「留在本机」。
  case rejected
}

/// 任何一种错误都能被问出「HTTP 几」和「服务端的错误码」。
///
/// 复盘在 app 里跑的是注进来的 `ScorebookClient.Transport`（走账号那条带 token 的通道），
/// 它抛的是 `AccountError` 而不是 `ScorebookError`；而队列要不要停、该不该把这条
/// 摘出来，全看状态码。所以分类只认这个协议，不认具体是谁抛的。
public protocol ReviewFailureStatus {
  var reviewStatusCode: Int? { get }
  var reviewErrorCode: String? { get }
}
extension ScorebookError: ReviewFailureStatus {
  public var reviewStatusCode: Int? { if case .http(let status, _) = self { status } else { nil } }
  public var reviewErrorCode: String? { if case .http(_, let code) = self { code } else { nil } }
}

public enum ReviewFailure {
  /// 这条操作该怎么办。
  public static func verdict(for error: any Error) -> ReviewSyncVerdict {
    guard let status = (error as? any ReviewFailureStatus)?.reviewStatusCode else { return .transient }
    switch status {
    case 409: return .conflict
    case 400, 404, 405, 410, 413, 415, 422: return .rejected
    default: return .transient
    }
  }
  /// 服务端的机器可读错误码。形状不对的一律丢掉——那一栏会被原样存进本地记录，
  /// 不能让服务端往里塞任意文本。
  public static func code(for error: any Error) -> String {
    guard let raw = (error as? any ReviewFailureStatus)?.reviewErrorCode, !raw.isEmpty, raw.count <= 64,
          raw.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }) else { return "" }
    return raw
  }
  /// 给人看的一句话。认得的码说人话，不认得的码只说「没传上去」，绝不回显服务端原文。
  public static func message(_ code: String, status: Int?) -> String {
    switch code {
    case "record_revision_changed", "record_identity_conflict", "idempotency_mismatch":
      return "这条记录在别的设备上改过了"
    case "record_voided": return "这条记录已经作废，改不动了"
    case "group_already_resolved": return "这一组已经归并过了"
    case "invalid_review_evidence", "invalid_chart_range": return "这段行情服务端不收，换一段再记"
    case "invalid_chart_snapshot", "invalid_drawing_snapshot": return "这一屏的设置或画线太大，服务端收不下"
    case "invalid_reflection", "invalid_change": return "这次改动服务端不收"
    case "not_found": return "服务端找不到这条记录"
    default: break
    }
    switch status {
    case 401, 403: return "连接凭证已失效，请重新连接"
    case 409: return "这条记录在别的设备上改过了"
    case 404: return "服务端还未提供此功能"
    case .some(let value) where value >= 500: return "服务端暂时不可用，稍后自动重试"
    default: return "同步暂未成功，请稍后重试"
    }
  }
}
/// 详情响应：记录本身，外加三个**只住在外层**的字段。
///
/// `assessmentRevision`（服务端判到第几版）与 `reflectionAssessmentRevision`
/// （这份复盘是照着第几版结论写的）不在 `record` 里，客户端原来只解 `record`，
/// 于是「人写完复盘之后结论又变了」这件事在界面上完全看不出来（审查 B.2）。
public struct NativeRecordResponse: Codable, Sendable {
  public var record: ReviewRecord
  public var groupPending: Bool?
  public var assessmentRevision: Int?
  public var reflectionAssessmentRevision: Int?
  /// 服务端那边有没有这条记录的图（§4.3）。图本身不在详情里——它几百 KB，
  /// 而详情是翻记录时一条一条要的；本地没有、这儿写着有，才去取那一条路径。
  /// 老服务端不给这个键，当成「不知道」（nil），行为和以前一样。
  public var hasShot: Bool?
  /// 把外层那三个字段贴回记录里，调用方只管用这一份。
  public var merged: ReviewRecord {
    var value = record
    if let groupPending { value.groupPending = groupPending }
    if let assessmentRevision { value.assessmentRevision = assessmentRevision }
    if let reflectionAssessmentRevision { value.reflectionAssessmentRevision = reflectionAssessmentRevision }
    return value
  }
}
public struct NativeListResponse: Codable, Sendable { public var records: [ReviewRecord]; public var next: String? }
public struct NativeSearchResponse: Codable, Sendable { public var items: [ReviewMatch]; public var cutoff: Int64; public var next: String?; public var partial: Bool? }
public struct NativeSearchJob: Codable, Sendable { public var id: UUID; public var status: String; public var cutoff: Int64; public var checked: Int?; public var total: Int?; public var error: String? }
public struct NativeMatchResponse: Codable, Sendable { public var item: ReviewMatch }
private struct OKResponse: Codable, Sendable { var ok: Bool }
/// 战绩里每一组的**证据**。外层那几个键是驼峰，`proof` 里面是蛇形（它是领域层
/// `statistics::summarize` 直接吐出来的 JSON），所以这两层各写各的 `CodingKeys`。
public struct ReviewStatsProofGroup: Codable, Sendable {
  public var numerator: Int?
  public var denominator: Int?
  public var realizationRate: Double?
  /// 相对口径那份证据里可能带着这一组该怎么称呼；老的 `proof` 不带，就留空。
  public var title: String?
  /// `insufficient`（不足 20 笔）/ `verdict_due` / `observing`。
  public var verdictStatus: String?
  /// 最近十笔比整体差 20 个百分点以上，该回头看一眼。
  public var recheck: Bool?
  enum CodingKeys: String, CodingKey {
    case numerator, denominator
    case realizationRate = "realization_rate"
    case verdictStatus = "verdict_status"
    case recheck, title
  }
}
public struct ReviewStatsProof: Codable, Sendable {
  /// 键就是 `groups[].id`（服务端两处用的是同一个 signature）。
  public var compatibleGroups: [String: ReviewStatsProofGroup]?
  enum CodingKeys: String, CodingKey { case compatibleGroups = "compatible_groups" }
}
public struct NativeStatsResponse: Codable, Sendable {
  public var groups: [ReviewStatsGroup]
  public var proof: ReviewStatsProof?
  public var ruleVersion: String?
  public var grouping: String?
  public var asOf: Int64?
  /// **相对口径**的分组（服务端 B-07 新增的三个顶层键，驼峰）。
  ///
  /// 老的 `groups` 是按绝对价、绝对到期时刻分的：目标 80286.3、到期 9 月 21 日
  /// 14:00 —— 几乎一笔一组，永远凑不满服务端要的 20 笔，界面上只能一行行写
  /// 「样本不足」。相对口径按「同方向 / 确认方式 / 品种 / 周期 + 目标与止损的相对
  /// 幅度分档 + 时长分档」分，同一类判断才真的能攒到一起，这才是报告 B-07 要给
  /// 用户看的那份战绩。
  ///
  /// 老服务端没有这三个键，所以全是可选的：**给了就用这份，没给才退回 `groups`**。
  public var comparableGroups: [ReviewStatsGroup]?
  /// 与 `proof` 同形状（内层仍是蛇形），键是相对口径的 signature。
  public var comparableProof: ReviewStatsProof?
  /// `"confirmed_anchored_episode_relative_rule"`。
  public var comparableGrouping: String?
  /// 贴上判定状态之后的分组——**界面上只展示这一份**。
  ///
  /// 不给用户摆两套口径去挑：哪一份算数是我们该替他决定的事（同
  /// `kanpan-sector-page-no-basis-picker`）。有相对口径就是相对口径，没有才是老那份。
  ///
  /// 贴判定状态这件事本身是因为 `groups` 里只有「总数 / 判对数」两个裸数字，一笔一组
  /// 时就是 `0/1`，界面照着算出来是个 0%——那不是战绩，是噪声。服务端一直在
  /// `proof` 里标着 `verdict_status`，以前客户端连解都没解（审查 B.2 / B-07）。
  public var resolvedGroups: [ReviewStatsGroup] {
    if let comparable = comparableGroups { return Self.resolve(comparable, with: comparableProof) }
    return Self.resolve(groups, with: proof)
  }
  /// 屏幕上这份分组是按哪个口径分的（诊断与用例用，不摆到界面上）。
  public var resolvedGrouping: String? {
    comparableGroups == nil ? grouping : (comparableGrouping ?? grouping)
  }
  private static func resolve(_ groups: [ReviewStatsGroup], with proof: ReviewStatsProof?) -> [ReviewStatsGroup] {
    let table = proof?.compatibleGroups ?? [:]
    return groups.map { group in
      var value = group
      guard let hit = table[group.id] else { return value }
      // 一律「有才盖」：相对口径那份分组自己就带着 `verdictStatus`，证据里没写的时候
      // 不能反手把它抹成 nil——那等于把「样本不足」悄悄变回一个 0%。
      if let verdict = hit.verdictStatus { value.verdict = verdict }
      if let recheck = hit.recheck { value.recheck = recheck }
      if let denominator = hit.denominator { value.total = denominator }
      if let numerator = hit.numerator { value.correct = numerator }
      if value.title.isEmpty, let title = hit.title { value.title = title }
      return value
    }
  }
}
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
      //
      // 但**机器可读的那个码**要留下来：`record_revision_changed` 和
      // `invalid_reflection` 都是 4xx，前者重新基准之后还能成，后者再发一万次也一样。
      // 队列靠它决定「摘出来还是留着重试」（审查 B-02）。码只认 `[a-z0-9_]`，
      // 别的形状当没有；文案一律由本地按码翻译。
      throw ScorebookError.http(http.statusCode, Self.errorCode(data))
    }
    return try JSONDecoder().decode(Envelope<T>.self, from: data).data
  }
  /// 从 `{"error":{"code":"…"}}` 里取那个码，形状不对就当没有。
  static func errorCode(_ data: Data) -> String {
    struct Body: Decodable { struct Error: Decodable { var code: String? }; var error: Error? }
    guard let code = (try? JSONDecoder().decode(Body.self, from: data))?.error?.code, !code.isEmpty,
          code.count <= 64, code.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") })
    else { return "" }
    return code
  }
  public func create(_ operation: ReviewOperation) async throws -> ReviewRecord {
    let response: NativeRecordResponse = try await request("v1/native-review/records", method: "POST", body: operation.body, key: operation.id)
    return response.merged
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
  /// 把「记一笔」那张图放上去。
  ///
  /// 它不走 `update` 那条路：那条会被队列改写成带 `expectedRevision` 的形状，
  /// 而图不是对记录内容的一次修改，没有版本可锁。重复上传就是覆盖，天然幂等。
  public func uploadShot(_ operation: ReviewOperation) async throws {
    let _: OKResponse = try await request("v1/native-review/records/\(operation.recordId.uuidString)/shot",
                                          method: "POST", body: operation.body, key: operation.id)
  }
  /// 取回这条记录的图。没有就是 404，交给调用方当「没有」处理。
  public func shot(_ id: UUID) async throws -> Data? {
    struct Shot: Decodable, Sendable { var image: String; var mime: String? }
    let value: Shot = try await request("v1/native-review/records/\(id.uuidString)/shot")
    return Data(base64Encoded: value.image)
  }
  public func update(_ operation: ReviewOperation) async throws -> ReviewRecord {
    let response: NativeRecordResponse = try await request("v1/native-review/records/\(operation.recordId.uuidString)/\(operation.kind)", method: "POST", body: operation.body, key: operation.id)
    return response.merged
  }
}
