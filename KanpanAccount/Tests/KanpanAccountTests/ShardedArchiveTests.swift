import Foundation
import Testing
@testable import KanpanAccount

/// 同步存档分片落盘（`ArchiveDisk`）：盘上永远是某一次事务的完整快照，而一次抬手只写变了的那一片。
@MainActor @Suite("同步存档分片落盘", .serialized) struct ShardedArchiveTests {
  private let device = UUID()
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }
  private func folder(_ root: URL) -> URL { root.appendingPathComponent(ArchiveDisk.directoryName) }
  private func files(_ root: URL) -> Set<String> {
    Set((try? FileManager.default.contentsOfDirectory(atPath: folder(root).path)) ?? [])
  }
  /// 一条画线：几何照真实尺寸编（两个端点 + 样式 + 七档斐波那契）。
  private func line(_ symbol: String, _ id: String, price: Double) -> SyncObject {
    var object = SyncObject(collection: "drawings", id: "binance/usd_m/\(symbol)/\(id)")
    object.body = ["kind": .string("trend"), "anchors": .array([.object(["t": .number(1_700_000_000_000), "p": .number(price)]),
                                                                  .object(["t": .number(1_700_000_600_000), "p": .number(price + 10)])]),
                   "dash": .string("solid"), "lineWidth": .number(1.3), "filled": .bool(true), "hidden": .bool(false), "locked": .bool(false),
                   "levels": .array([0, 0.236, 0.382, 0.5, 0.618, 0.786, 1].map { .number($0) }),
                   "symbol": .string(symbol), "market": .string("usd_m"), "venue": .string("binance")]
    return object
  }
  /// 一份像样的存档：20 个品种 × 50 条线、一份 ~10 KB 的设置，云端镜像与本机影子各一份。
  private func seeded(_ root: URL) throws -> SyncStore {
    let store = try SyncStore(directory: root)
    var batch: [SyncObject] = []
    for s in 0..<20 { for d in 0..<50 { batch.append(line("S\(s)USDT", "d\(d)", price: Double(100 + d))) } }
    var settings = SyncObject(collection: "settings", id: "chart")
    for i in 0..<200 { settings.body["field\(i)"] = .string(String(repeating: "x", count: 40)) }
    batch.append(settings)
    try store.transaction { a in
      for object in batch { a.objects[object.key] = object; a.local[object.key] = object }
    }
    store.flushNow()
    return store
  }

  @Test func reopeningGivesBackTheSameArchive() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try seeded(root)
    try store.capture(line("S3USDT", "d7", price: 42), device: device)
    store.flushNow()
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.local == store.archive.local)
    #expect(reopened.archive.objects == store.archive.objects)
    #expect(reopened.archive.operations.map(\.id) == store.archive.operations.map(\.id))
    #expect(reopened.archive.logical == store.archive.logical)
    // 21 片（20 个品种 + 设置）+ head，没有多余文件。
    #expect(files(root).count == 22)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(ArchiveDisk.legacyName).path))
  }

  @Test func oneEditRewritesOnlyItsShardAndTheHead() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try seeded(root)
    let before = files(root)
    try store.capture(line("S3USDT", "d7", price: 42), device: device)
    store.flushNow()
    let after = files(root)
    // 换掉的只有 S3 那一片（新文件名），head 原地覆盖。
    #expect(before.subtracting(after).count == 1)
    #expect(after.subtracting(before).count == 1)
  }

  @Test func aLegacyArchiveIsMigratedAndTheOldFileGoes() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    var legacy = SyncArchive()
    let object = line("BTCUSDT", "a", price: 1)
    legacy.objects[object.key] = object; legacy.local[object.key] = object; legacy.lastSync = 900
    try JSONEncoder().encode(legacy).write(to: root.appendingPathComponent(ArchiveDisk.legacyName))
    let store = try SyncStore(directory: root)
    #expect(store.archive.local[object.key] == object)
    store.flushNow()   // 迁移那次提交是 init 里就排上的
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(ArchiveDisk.legacyName).path))
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.local[object.key] == object)
    #expect(reopened.archive.lastSync == 900)
  }

  /// 分片写了、head 还没写就断电：新分片是没人引用的孤儿，读出来仍是上一版；下一次提交把孤儿扫掉。
  @Test func aCrashBeforeTheHeadLeavesThePreviousVersion() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try seeded(root)
    let stray = folder(root).appendingPathComponent(UUID().uuidString.lowercased() + ".json")
    try JSONEncoder().encode(ArchiveShard(objects: [:], local: ["drawings:x/y/z/w": line("Z", "w", price: 9)])).write(to: stray)
    // 另一个进程的样子：注册表里没有这个目录，从盘上读。
    ArchiveWriter.queue.sync { ArchiveDisk.committed[root.standardizedFileURL.path] = nil }
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.local == store.archive.local)
    try reopened.capture(line("S0USDT", "d0", price: 5), device: device)
    reopened.flushNow()
    #expect(!FileManager.default.fileExists(atPath: stray.path))
    #expect(files(root).count == 22)
  }

  /// 同一个目录前后两个 store（换号再换回来）交替提交：谁都不会删掉对方 head 还引用着的文件。
  @Test func twoStoresOnOneDirectoryStayConsistent() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let a = try seeded(root)
    let b = try SyncStore(directory: root)
    try b.capture(line("S1USDT", "d1", price: 11), device: device); b.flushNow()
    try a.capture(line("S2USDT", "d2", price: 22), device: device); a.flushNow()
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.local == a.archive.local)
    try b.capture(line("S4USDT", "d4", price: 44), device: device); b.flushNow()
    let again = try SyncStore(directory: root)
    #expect(again.archive.local == b.archive.local)
  }

  /// 前后对比：整份编码 + 原子写（从前的 `sync-v1.json`）vs 分片提交，改一条线。
  @Test func measureWholeVersusSharded() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try seeded(root)
    let rounds = 20
    let clock = ContinuousClock()
    func ms(_ d: Duration) -> Double { (Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15) / Double(rounds) }
    let legacy = root.appendingPathComponent("whole.json")
    var wholeBytes = 0
    let whole = try clock.measure {
      for i in 0..<rounds {
        var archive = store.archive; let edited = line("S3USDT", "d7", price: Double(i))
        archive.local[edited.key] = edited
        let data = try JSONEncoder().encode(archive); wholeBytes = data.count
        try AccountFiles.writeData(data, to: legacy)
      }
    }
    let start = store.bytesWritten
    let sharded = try clock.measure {
      for i in 0..<rounds {
        try store.capture(line("S3USDT", "d7", price: Double(1000 + i)), device: device)
        store.flushNow()
      }
    }
    let shardedBytes = (store.bytesWritten - start) / rounds
    print("[ShardedArchive] 20×50 画线 + 10 KB 设置，改一条：整份 \(wholeBytes) B / \(String(format: "%.2f", ms(whole))) ms；分片 \(shardedBytes) B / \(String(format: "%.2f", ms(sharded))) ms（含记账与排空）")
    #expect(shardedBytes * 5 < wholeBytes)
  }
}
