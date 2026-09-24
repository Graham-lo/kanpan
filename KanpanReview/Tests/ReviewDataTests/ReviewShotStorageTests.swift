import XCTest
import ReviewDomain
import ReviewData

/// 图不进队列、`shots/` 有上限（第 25 项）。
final class ReviewShotStorageTests: XCTestCase {
  private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("review-shots-" + UUID().uuidString)
  }
  private func record(cloud: Bool) -> ReviewRecord {
    var value = ReviewRecord(draft: ReviewDraft(range: ReviewRange(symbol: "BTCUSDT", interval: "1m", start: 0, end: 180_000, bars: 3),
                                                reference: 100, high: 110, low: 90, now: 240_000))
    if cloud { value.serverId = value.id; value.revision = 1 }
    return value
  }

  /// 老队列里 body 带整张图的那条：开档时落成 `shots/<id>.png`、body 清空，主档一下子瘦回来。
  @MainActor func testLegacyShotBodiesMoveOutOfTheArchive() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let image = Data((0..<300_000).map { UInt8($0 % 251) })   // 一张 300 KB 的图
    let mine = record(cloud: true)
    do {
      let store = try ReviewStore(directory: directory)
      let body = try JSONEncoder().encode(["image": image.base64EncodedString()])
      try store.transaction { $0.records = [mine]; $0.queue = [ReviewOperation(recordId: mine.id, kind: "shot", body: body)] }
    }
    let archive = directory.appendingPathComponent(ReviewPaths.archiveName)
    let before = try Data(contentsOf: archive).count
    let store = try ReviewStore(directory: directory)
    let after = try Data(contentsOf: archive).count
    XCTAssertEqual(store.shot(mine.id), image)
    XCTAssertEqual(store.archive.queue.map(\.kind), ["shot"])
    XCTAssertEqual(store.archive.queue.first?.body, Data())
    XCTAssertLessThan(after, before / 50, "主档 \(before) B → \(after) B")
    print("[review-shot] 一张 300 KB 的图：主档 \(before) B → \(after) B（每次 transaction 都整份重写它）")
  }

  /// 超预算按最久没看的删，只删上过云、不在队列里、不是草稿的那些；本机独有的宁可超。
  @MainActor func testTrimEvictsOnlyRecoverableShotsLeastRecentlyUsedFirst() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let oldCloud = record(cloud: true), newCloud = record(cloud: true), local = record(cloud: false), queued = record(cloud: true)
    try store.transaction {
      $0.records = [oldCloud, newCloud, local, queued]
      $0.queue = [ReviewOperation(recordId: queued.id, kind: "shot", body: Data())]
    }
    let bytes = Data(count: 1000)
    var age = -1000.0
    for item in [oldCloud, local, queued, newCloud] {
      try store.saveShot(bytes, for: item.id)
      // 修改时间一张比一张新：oldCloud 最久没看。
      try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: age)], ofItemAtPath: store.paths.shot(item.id).path)
      age += 100
    }
    XCTAssertEqual(store.trimShots(budget: 4000), 0, "没超就不动")
    XCTAssertEqual(store.trimShots(budget: 3000), 1)
    XCTAssertFalse(store.hasShot(oldCloud.id))
    XCTAssertTrue(store.hasShot(newCloud.id))
    // 读一次就算「刚看过」，但能删的只剩它，照删。
    XCTAssertEqual(store.trimShots(budget: 1000), 1)
    XCTAssertFalse(store.hasShot(newCloud.id))
    XCTAssertTrue(store.hasShot(local.id), "本机独有的不删")
    XCTAssertTrue(store.hasShot(queued.id), "还没传上去的不删")
  }

  /// 读图会把它拨成「刚看过」，淘汰顺序跟着变。
  @MainActor func testReadingAShotMarksItRecentlyUsed() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ReviewStore(directory: directory)
    let a = record(cloud: true), b = record(cloud: true)
    try store.transaction { $0.records = [a, b] }
    try store.saveShot(Data(count: 1000), for: a.id)
    try store.saveShot(Data(count: 1000), for: b.id)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -500)], ofItemAtPath: store.paths.shot(a.id).path)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: store.paths.shot(b.id).path)
    _ = store.shot(a.id)
    XCTAssertEqual(store.trimShots(budget: 1000), 1)
    XCTAssertTrue(store.hasShot(a.id))
    XCTAssertFalse(store.hasShot(b.id))
  }
}
