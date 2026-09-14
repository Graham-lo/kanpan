import Testing
import Foundation
import KanpanCore
import KanpanData
@testable import KanpanSettings

/// A6.11：清缓存清的是 `KanpanData.Paths` 指的那几处，不是另拼一套目录。
@Suite("清缓存")
struct MarketCacheTests {

  /// 造一个临时沙盒，塞进快照 / 品种表 / 两天 OI 切片。
  private func seed() throws -> (Paths, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-cache-test-\(UUID().uuidString)", isDirectory: true)
    let paths = Paths(root: root)
    try paths.ensureRoot()
    try Data(repeating: 7, count: 4096).write(to: paths.snapshot)
    try Data(repeating: 8, count: 2048).write(to: paths.exchangeInfo)
    let day = paths.oiDay(symbol: "BTCUSDT", day: "2026-09-14")
    try paths.ensure(day.deletingLastPathComponent())
    try Data(repeating: 9, count: 1024).write(to: day)
    return (paths, root)
  }

  @Test("量出来的是那三处，分三笔报")
  func 量() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }

    let u = await DiskMarketCache(paths: paths).usage()
    #expect(u.available)
    #expect(u.snapshotBytes >= 4096)
    #expect(u.catalogBytes >= 2048)
    #expect(u.oiBytes >= 1024)
    #expect(u.marketBytes == u.snapshotBytes + u.catalogBytes)
    #expect(u.totalBytes == u.marketBytes + u.oiBytes)
  }

  @Test("清完三处都没了，数字归零；沙盒里别的东西不动")
  func 清() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }
    let 无关 = paths.root.appendingPathComponent("draws.json")
    try Data(repeating: 1, count: 512).write(to: 无关)

    let cache = DiskMarketCache(paths: paths)
    await cache.clear()

    let fm = FileManager.default
    #expect(!fm.fileExists(atPath: paths.snapshot.path))
    #expect(!fm.fileExists(atPath: paths.exchangeInfo.path))
    #expect(!fm.fileExists(atPath: paths.oi.path))
    #expect(fm.fileExists(atPath: 无关.path))     // 画线不归清缓存管

    let after = await cache.usage()
    #expect(after.totalBytes == 0)
  }

  @Test("目录本来就不存在 → 量出 0，清也不报错")
  func 空沙盒() async {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-cache-empty-\(UUID().uuidString)", isDirectory: true)
    let cache = DiskMarketCache(paths: Paths(root: root))
    await cache.clear()
    let u = await cache.usage()
    #expect(u.available)
    #expect(u.totalBytes == 0)
  }

  @Test("store 清完会重新量，并给一句回执")
  @MainActor
  func 走store() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: DiskMarketCache(paths: paths))
    #expect(store.cacheUsage == nil)
    await store.refreshCacheUsage()
    #expect((store.cacheUsage?.totalBytes ?? 0) > 0)
    await store.clearCache()
    #expect(store.cacheUsage?.totalBytes == 0)
    #expect(store.notice != nil)
    store.clearNotice()
    #expect(store.notice == nil)
  }

  @Test("数据层没接上就如实说没接上，不报假的 0")
  func 占位() async {
    let u = await UnavailableMarketCache().usage()
    #expect(!u.available)
    #expect(u.totalBytes == 0)
  }

  @Test("体积文案")
  func 文案() {
    #expect(MarketCacheUsage.display(0) == "0 KB")
    #expect(MarketCacheUsage.display(312 * 1024) == "312 KB")
    #expect(MarketCacheUsage.display(1024 * 1024 + 1024 * 200) == "1.2 MB")
  }
}
