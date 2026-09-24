import Foundation
import ReviewDomain

/// 同步引擎和服务端之间的那条线（`ReviewSyncEngine` 只认这个协议）。
///
/// 形状照 `KanpanAccount.SyncTransport`：引擎是纯逻辑，线是注进来的——生产上是
/// `ScorebookClient`（走账号那条带 token 的通道），测试里是一台假服务器，
/// 拿真引擎对着它跑，断言线上看得见的那一串请求。
///
/// 只列队列真正用到的五样；搜索、战绩、补图这些「打开那一页才问」的只读接口
/// 不进队列，仍然直接挂在 `ScorebookClient` 上。
public protocol ReviewTransport: Sendable {
  /// 新建一条记录。幂等键是 `operation.id`。
  func create(_ operation: ReviewOperation) async throws -> ReviewRecord
  /// 对已有记录的一次修改（复盘 / 作废 / 归组），`operation.kind` 就是路径最后一段。
  func update(_ operation: ReviewOperation) async throws -> ReviewRecord
  /// 把「记一笔」那张图放上去。重复上传就是覆盖，天然幂等；`key` 仍然带上，
  /// 服务端据此把同一次重发认成同一次。
  func uploadShot(record: UUID, image: Data, key: UUID) async throws
  /// 一页记录。`after` 是上一页给的游标。
  func list(after: String?, query: String, todo: Bool, decided: Bool) async throws -> NativeListResponse
  /// 一条记录的详情（含只住在外层的两个裁定版本）。
  func detail(_ id: UUID) async throws -> NativeRecordResponse
}

extension ScorebookClient: ReviewTransport {}
