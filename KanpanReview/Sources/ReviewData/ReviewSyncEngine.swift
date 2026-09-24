import Foundation
import ReviewDomain

/// 复盘的上传队列 + 拉第一页（第 25 项：从 `ReviewFeature` 里搬出来的那一段）。
///
/// 形状照 `KanpanAccount.SyncEngine`：纯逻辑、线是注进来的（`ReviewTransport`），
/// 状态全在 `ReviewStore` 里，引擎自己不留任何跨轮次的东西——一轮一个实例，
/// 宿主（`ReviewFeature`）只管「什么时候跑、跑完告诉谁」。
///
/// 一轮做两件事：
///
/// 1. **按入队顺序逐条发**。更新类（复盘 / 作废 / 归组）发之前把 `expectedRevision`
///    改写成本机那一刻的版本，并标成 `attempted`——从此这条的 body 和幂等键都不再变，
///    断网重发一模一样（幂等重试的前提就是同一个键配同一份 body）。
///    失败分三种（审查 B-02）：暂时的原样留在队首、这一轮到此为止；409 / 4xx 摘下来存成
///    冲突（人写的内容一个字不丢），队列接着往下跑。
/// 2. 队列跑空之后**拉一次第一页**并入本机存档，云端记录最多缓存最近 `cloudCacheLimit` 条。
///    还在队列里的记录不拿云端那份去盖。
@MainActor public final class ReviewSyncEngine {
  /// 云端记录在本机最多留多少条（还在队列里的、从没上过云的不算）。
  public static let cloudCacheLimit = 200

  private let store: ReviewStore
  private let transport: any ReviewTransport

  /// 这一轮还算不算数（账号换了、宿主又起了一轮）。每一次 `await` 回来都问一次，
  /// 不算数就安静收场，一个字都不往存档里写。
  public var stillCurrent: () -> Bool = { true }
  /// 这条先别发（撤销窗口还没过的作废）。问到就停下这一轮，等宿主再叫。
  public var isHeld: (ReviewOperation) -> Bool = { _ in false }
  /// 存档变了一次（宿主据此刷新屏幕上的记录）。
  public var onChange: () -> Void = {}
  /// 该给人看的一句话（暂时失败的原因、被摘成冲突的原因）。
  public var onNotice: (String) -> Void = { _ in }
  /// 服务端回了一份新的记录（宿主拿它去补已经摆在复盘本上的那一行）。
  public var onAdopted: (ReviewRecord) -> Void = { _ in }
  /// 发图那一条要的字节。队列里只记「哪条记录」，图住在 `shots/<id>.png`，发的那一刻现读
  /// （`ReviewStore.shot`）；老队列 body 里还带着 base64 的（开档时没迁成的）先认它。
  public var shotBytes: (ReviewOperation) -> Data?

  public init(store: ReviewStore, transport: any ReviewTransport) {
    self.store = store; self.transport = transport
    shotBytes = { [store] operation in
      struct Body: Decodable { var image: String }
      if let body = try? JSONDecoder().decode(Body.self, from: operation.body), let data = Data(base64Encoded: body.image) { return data }
      return store.shot(operation.recordId)
    }
  }

  /// 跑一轮。返回 `true` 表示队列跑空、第一页也并进来了（宿主据此报「同步完成」）。
  public func run() async -> Bool {
    do {
      while var operation = store.archive.queue.first {
        try checkpoint()
        if isHeld(operation) { return false }
        if operation.attempted != true {
          // 图不是对记录内容的一次修改，没有版本可锁（服务端那条路也不读它）。
          if operation.kind != "create", operation.kind != "shot",
             let current = store.archive.records.first(where: { $0.id == operation.recordId }),
             var body = try JSONSerialization.jsonObject(with: operation.body) as? [String: Any] {
            body["expectedRevision"] = current.revision
            operation.body = try JSONSerialization.data(withJSONObject: body)
          }
          operation.attempted = true
          let pending = operation
          guard commit({ archive in
            if let index = archive.queue.firstIndex(where: { $0.id == pending.id }) { archive.queue[index] = pending }
          }) else { return false }
        }
        let remote: ReviewRecord?
        do {
          remote = try await send(operation)
        } catch {
          if error is CancellationError { return false }
          guard stillCurrent() else { return false }
          switch ReviewFailure.verdict(for: error) {
          case .transient:
            // 网络断了、凭证过期、服务端忙：原样留在队首，连幂等键一起留着。
            onNotice(error.localizedDescription)
            _ = commit { archive in
              if let index = archive.records.firstIndex(where: { $0.id == operation.recordId }) {
                archive.records[index].syncError = error.localizedDescription
              }
            }
            return false
          case .conflict where operation.kind == "shot", .rejected where operation.kind == "shot":
            // 图没有「人写的内容」可裁决：服务端不收（太大、记录没了）或者本机的图已经
            // 不在了，重发多少次都一样，挂成冲突只会让人面对一条他什么也做不了的提示。
            // 安静摘掉，记录本身不受影响。
            guard commit({ archive in archive.queue.removeAll { $0.id == operation.id } }) else { return false }
            continue
          case .conflict, .rejected:
            // 这条再也发不出去了。摘下来，队列接着往下跑。
            guard quarantine(operation, error: error) else { return false }
            continue
          }
        }
        try checkpoint()
        guard commit({ archive in
          archive.queue.removeAll { $0.id == operation.id }
          if let remote, let i = archive.records.firstIndex(where: { $0.id == remote.id }) {
            var merged = Self.adopt(remote, over: archive.records[i])
            // 这一次成功的如果正是那条冲突的重发，冲突就算解了。
            if merged.conflict?.kind == operation.kind { merged.conflict = nil }
            if archive.queue.contains(where: { $0.recordId == remote.id && $0.kind == "reflection" }) { merged.reflection = archive.records[i].reflection }
            if archive.queue.contains(where: { $0.recordId == remote.id && $0.kind == "void" }) { merged.voided = true }
            archive.records[i] = merged
          }
        }) else { return false }
        if let remote { onAdopted(remote) }
      }
      let page = try await transport.list(after: nil, query: "", todo: false, decided: false)
      try checkpoint()
      return commit { archive in Self.merge(page.records, into: &archive) }
    } catch is CancellationError {
      return false
    } catch {
      guard stillCurrent() else { return false }
      onNotice(error.localizedDescription)
      if let id = store.archive.queue.first?.recordId {
        _ = commit { archive in
          if let i = archive.records.firstIndex(where: { $0.id == id }) { archive.records[i].syncError = error.localizedDescription }
        }
      }
      return false
    }
  }

  private func send(_ operation: ReviewOperation) async throws -> ReviewRecord? {
    switch operation.kind {
    case "create": return try await transport.create(operation)
    case "shot":
      guard let image = shotBytes(operation) else { throw ReviewShotMissing() }
      // 图那条不换回一份记录：服务端只答「收下了」。
      try await transport.uploadShot(record: operation.recordId, image: image, key: operation.id)
      return nil
    default: return try await transport.update(operation)
    }
  }

  private func checkpoint() throws {
    try Task.checkCancellation()
    guard stillCurrent() else { throw CancellationError() }
  }

  @discardableResult private func commit(_ edit: (inout ReviewArchive) throws -> Void) -> Bool {
    do { try store.transaction(edit); onChange(); return true }
    catch { onNotice(error.localizedDescription); return false }
  }

  /// 把一条再也发不出去的操作从队列里摘下来，内容原样存进这条记录的 `conflict`。
  ///
  /// 摘掉的是「这一次投递」，不是「人写的东西」：正文、备注、作废意图都在 `body` 里
  /// 留着，等人裁决（`ReviewFeature.resolveConflict`）。
  private func quarantine(_ operation: ReviewOperation, error: any Error) -> Bool {
    let code = ReviewFailure.code(for: error)
    let status = (error as? any ReviewFailureStatus)?.reviewStatusCode
    let reason = ReviewFailure.message(code, status: status)
    // 新建被拒没法「重新基准」——它本来就没有 expectedRevision 可以换；
    // 4xx 的参数拒绝更是重发一万次都一样。这两种只给「留在本机」。
    let retryable = ReviewFailure.verdict(for: error) == .conflict && operation.kind != "create"
    let conflict = ReviewConflict(kind: operation.kind, code: code, reason: reason,
                                  at: ReviewClock.now, body: operation.body, retryable: retryable)
    onNotice(reason)
    return commit { archive in
      archive.queue.removeAll { $0.id == operation.id }
      if let index = archive.records.firstIndex(where: { $0.id == operation.recordId }) {
        archive.records[index].conflict = conflict
        archive.records[index].syncError = nil
      }
    }
  }

  /// 把拉回来的一页并进存档。
  ///
  /// `adopt` 而不是直接赋值：列表里没有 `conflict`，也没有那两个裁定版本。
  /// 直接盖回去，刚被隔离下来的那条冲突就在同一轮同步的末尾被自己抹掉了（审查 B-02）。
  public static func merge(_ page: [ReviewRecord], into archive: inout ReviewArchive) {
    for remote in page {
      guard !archive.queue.contains(where: { $0.recordId == remote.id }) else { continue }
      if let i = archive.records.firstIndex(where: { $0.id == remote.id }) {
        archive.records[i] = adopt(remote, over: archive.records[i])
      } else { archive.records.append(remote) }
    }
    archive.records.sort { $0.draft.created > $1.draft.created }
    let protected = Set(archive.queue.map(\.recordId))
    let recent = Set(archive.records.prefix(cloudCacheLimit).map(\.id))
    archive.records.removeAll { $0.serverId != nil && !protected.contains($0.id) && !recent.contains($0.id) }
  }

  /// 云端那份 + 只活在本机的那几样。
  ///
  /// `conflict`（被隔离下来的上传）压根不在协议里，拉一次列表就会被抹掉；
  /// 两个裁定版本只在详情响应的外层出现，列表里没有，也不能被 `nil` 盖掉。
  /// 还挂着未裁决的冲突时，人写的那份要留在屏幕上（审查 B-02）：被隔离的那条上传里
  /// 装的正是他刚写下的复盘，把云端那份盖回来他看到的就是一段旧文字。
  public static func adopt(_ remote: ReviewRecord, over local: ReviewRecord) -> ReviewRecord {
    var value = remote
    value.conflict = local.conflict
    if local.conflict != nil {
      value.reflection = local.reflection
      value.reflectionHistory = local.reflectionHistory
      value.voided = local.voided || value.voided
    }
    if value.assessmentRevision == nil { value.assessmentRevision = local.assessmentRevision }
    if value.reflectionAssessmentRevision == nil { value.reflectionAssessmentRevision = local.reflectionAssessmentRevision }
    return value
  }
}

/// 发图那一条要的字节已经不在了（图被清掉、或者从没存下来）。按「内容被拒」处理：
/// 摘下来、不重发——它不可能自己长回来。
public struct ReviewShotMissing: Error, ReviewFailureStatus {
  public init() {}
  public var reviewStatusCode: Int? { 410 }
  public var reviewErrorCode: String? { "shot_missing" }
}
