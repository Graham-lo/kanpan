import Foundation
import Testing
@testable import ReviewData

/// 复盘本缩略图的盘上那份：读写、按档案分开、总量封顶按最近使用淘汰（体感优化 2026-10-07）。
struct TradeImageStoreTests {
  func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("timg-\(UUID().uuidString)", isDirectory: true)
  }

  @Test func writeThenReadBackAcrossInstances() async {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = TradeImageStore(root: root, profile: "/a/u-1")
    await store.write("k1", data: Data([1, 2, 3]))
    #expect(await store.read("k1") == Data([1, 2, 3]))
    let again = TradeImageStore(root: root, profile: "/a/u-1")
    #expect(await again.read("k1") == Data([1, 2, 3]))
    #expect(await again.read("missing") == nil)
    let batch = await again.read(["k1", "missing"])
    #expect(batch.keys.sorted() == ["k1"])
  }

  @Test func profilesDoNotSeeEachOther() async {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let a = TradeImageStore(root: root, profile: "/a/u-1")
    let b = TradeImageStore(root: root, profile: "/a/u-2")
    #expect(a.directory != b.directory)
    await a.write("same", data: Data([9]))
    #expect(await b.read("same") == nil)
  }

  @Test func totalCapEvictsLeastRecentlyUsed() async throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    // 一张 4 KB，封顶 11 KB（删到 8.25 KB）：第三张写进来时删掉最久没用的那一张。
    let store = TradeImageStore(root: root, profile: "p", maxBytes: 11_000)
    let blob = Data(repeating: 7, count: 4_000)
    await store.write("a", data: blob)
    try await Task.sleep(nanoseconds: 20_000_000)
    await store.write("b", data: blob)
    try await Task.sleep(nanoseconds: 20_000_000)
    _ = await store.read("a")            // a 成了最近用过的
    try await Task.sleep(nanoseconds: 20_000_000)
    await store.write("c", data: blob)
    #expect(await store.totalBytes() <= 11_000)
    let fresh = TradeImageStore(root: root, profile: "p", maxBytes: 11_000)
    #expect(await fresh.read("b") == nil)
    #expect(await fresh.read("a") != nil)
    #expect(await fresh.read("c") != nil)
  }

  @Test func survivesCacheWipe() async {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = TradeImageStore(root: root, profile: "p")
    await store.write("a", data: Data([1]))
    try? FileManager.default.removeItem(at: root)   // 「清缓存」
    #expect(await store.read("a") == nil)
    await store.write("b", data: Data([2]))
    #expect(await store.read("b") == Data([2]))
    #expect(await store.totalBytes() == 1)
  }
}
