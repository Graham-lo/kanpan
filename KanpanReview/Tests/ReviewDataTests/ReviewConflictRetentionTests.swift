import Foundation
import Testing
import ReviewDomain
import ReviewData

/// 审查 R4：409 被隔离下来、还没裁决的那条记录已经不在队列里了，以前云端缓存一裁
/// （落盘时的 200 条 / 12 MB、拉列表并档时的 200 条、图的 64 MB 预算）就把它连同冲突、
/// 人写的那份复盘、裁决入口一起裁掉。现在三处都认 `conflict != nil`。
@MainActor struct ReviewConflictRetentionTests {
  private func directory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("review-conflict-" + UUID().uuidString)
  }
  private func cloud(created: Int64) -> ReviewRecord {
    var draft = ReviewDraft(range: ReviewRange(symbol: "BTCUSDT", interval: "1m", start: 0, end: 180_000, bars: 3),
                            reference: 100, high: 110, low: 90, now: 240_000)
    draft.created = created
    var value = ReviewRecord(draft: draft)
    value.serverId = value.id; value.revision = 2
    return value
  }
  private func conflicted(created: Int64) -> ReviewRecord {
    var value = cloud(created: created)
    value.conflict = ReviewConflict(kind: "reflection", code: "revision_conflict", reason: "", at: 0, body: Data(), retryable: true)
    value.reflection.note = "我写的、还没裁决"
    return value
  }

  @Test func conflictedRecordSurvivesCloudCachePrune() throws {
    let dir = directory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = try ReviewStore(directory: dir)
    store.cloudCache = true
    let stuck = conflicted(created: -1)
    // 最旧的一条排在最后：只靠「挂着冲突」才留得下。
    try store.transaction { $0.records = (0..<300).map { cloud(created: Int64(1_000 + $0)) } + [stuck] }
    let kept = store.archive.records.first { $0.id == stuck.id }
    #expect(kept != nil)
    #expect(kept?.conflict != nil)
    #expect(kept?.reflection.note == "我写的、还没裁决")
    #expect(store.archive.records.count == 201, "200 条缓存 + 挂着冲突的那条")
  }

  @Test func conflictedRecordSurvivesMergePrune() {
    var archive = ReviewArchive()
    let stuck = conflicted(created: -1)
    archive.records = [stuck]
    let crowd = (0..<250).map { cloud(created: Int64(1_000 + $0)) }
    ReviewSyncEngine.merge(crowd, into: &archive)
    #expect(archive.records.contains { $0.id == stuck.id && $0.conflict != nil })
    #expect(archive.records.count == ReviewSyncEngine.cloudCacheLimit + 1)
  }

  @Test func conflictedRecordKeepsItsShotOverBudget() throws {
    let dir = directory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = try ReviewStore(directory: dir)
    let stuck = conflicted(created: 1), plain = cloud(created: 2)
    try store.transaction { $0.records = [stuck, plain] }
    let image = Data(repeating: 7, count: 4_096)
    try store.saveShot(image, for: stuck.id)
    try store.saveShot(image, for: plain.id)
    store.trimShots(budget: 1)
    #expect(store.hasShot(stuck.id), "裁决「用我这份」时还要再发这张图")
    #expect(!store.hasShot(plain.id))
  }
}
