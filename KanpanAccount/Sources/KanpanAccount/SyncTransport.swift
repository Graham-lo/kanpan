import Foundation

/// 同步引擎和服务端之间的那一层：只有两个动作，推一批、拉一页。
///
/// 为什么要单独一层：推送循环（分批、413 对半砍、409 重拉重整、语义错误隔离）是整个
/// 同步里分支最多的一段，以前它长在 `AppAccountBridge.run` 里，直接拿 `AccountClient`
/// 发请求——app 靶子没有测试壳，测试只好在 `SyncConflictTests` 里手抄一份 `SyncLoop`，
/// 抄本还缺了 413 / 字节闸两条分支（深度审查 2026-09-24 §1.2）。现在循环住在
/// `SyncEngine`，网络从这个协议进：生产是 `HTTPSyncTransport`，测试是按服务端真实
/// 规则写的假服务端，**跑的是同一个引擎**。
///
/// 错误照原样往外抛：`AccountError.http(状态码, 理由)` 是引擎分支的依据
/// （`SyncEngine.isTooLarge` / `isRollback` / `isPermanent` / `demandsBootstrap`）。
@MainActor public protocol SyncTransport {
  /// `POST v1/sync/operations`。`body` 是编码好的 `SyncPushRequest`——引擎要按它的
  /// **真实字节数**切批，所以编码在引擎里做，传输层不再编一遍。`key` 是幂等键。
  func push(_ body: Data, key: UUID) async throws -> SyncPushResponse
  /// `GET v1/sync/bootstrap?collection=&prefix=&after=`：一页某个集合（可按 id 前缀收窄）
  /// 的云端对象。`after` 是上一页给的 `next`。
  func bootstrap(collection: String, prefix: String?, after: String?) async throws -> SyncPage
}

/// 生产用的那一份：走 `AccountClient`（令牌、刷新、被顶下线、错误分类都在它里面）。
public struct HTTPSyncTransport: SyncTransport {
  public let client: AccountClient
  public init(client: AccountClient) { self.client = client }
  public func push(_ body: Data, key: UUID) async throws -> SyncPushResponse {
    try await client.request("v1/sync/operations", method: "POST", body: body, key: key)
  }
  public func bootstrap(collection: String, prefix: String?, after: String?) async throws -> SyncPage {
    try await client.request(Self.bootstrapPath(collection: collection, prefix: prefix, after: after))
  }
  /// 拉取那一页的路径。单独拿出来是为了测「查询串拼对了没有」（前缀里的 `/` 要原样过去）。
  public static func bootstrapPath(collection: String, prefix: String?, after: String?) -> String {
    var query = [URLQueryItem(name: "collection", value: collection)]
    if let prefix { query.append(URLQueryItem(name: "prefix", value: prefix)) }
    if let after { query.append(URLQueryItem(name: "after", value: after)) }
    var components = URLComponents(); components.queryItems = query
    return "v1/sync/bootstrap" + (components.string ?? "")
  }
}
