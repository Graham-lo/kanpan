import Foundation
import Testing
@testable import KanpanAccount

/// A.5：推送分批只按条数切，不按**实际字节**切。
///
/// 服务端整个请求体只收 512 KiB（`Backend/kanpan-api/src/lib.rs` 的
/// `DefaultBodyLimit`），而一条画线操作有多大完全由用户画了多少个点决定。
/// 「一百条合法操作」根本不保证装得下：越线之后请求在进 handler **之前**就被 413
/// 拒掉，这一批一条都没落库，客户端再把同一批原样发一次——这个账号的同步队列
/// 从此再也前进不了。
@MainActor @Suite("推送分批的字节闸")
struct PushBatchSizeTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }
  /// 一条「画了很多点」的线：`points` 那一串就是它的体积。
  private func line(_ id: String, points: Int) -> SyncObject {
    var object = SyncObject(collection: "drawings", id: "binance/usd_m/BTCUSDT/" + id)
    object.body = ["symbol": .string("BTCUSDT"),
                   "points": .string(String(repeating: "1728000000,64000.5;", count: points))]
    return object
  }

  @Test("一批发出去的字节数不许越过服务端的门槛")
  func aBatchFitsInTheBodyLimit() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), device = UUID()
    // 40 条、每条约 20 KiB：条数远没到 100，字节数却早就过了 512 KiB。
    try store.capture((0..<40).map { line("line-\($0)", points: 1000) }, device: device)
    #expect(store.archive.operations.count == 40)

    // 老口径（只按条数）：整批一次发出去，远超服务端的 512 KiB。
    let byCount = SyncStore.batch(store.archive.operations, limit: 100)
    #expect(byCount.count == 40)
    #expect(SyncStore.encodedSize(byCount) > 512 * 1024)

    // 新口径：按编码之后的真实字节切，装得下，而且不是空批。
    let budget = 384 * 1024
    let byBytes = store.nextBatch(limit: 100, maxBytes: budget)
    #expect(!byBytes.isEmpty)
    #expect(SyncStore.encodedSize(byBytes) <= budget)
    // 切出来的是**队首的前缀**：谁的前驱都不会被落在后面。
    #expect(byBytes.map(\.id) == Array(byCount.map(\.id).prefix(byBytes.count)))
  }

  @Test("单独一条就超预算时，把那一条单独交出来")
  func oneOversizedOperationComesBackAlone() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), device = UUID()
    try store.capture([line("huge", points: 20_000), line("small", points: 1)], device: device)
    // 预算比第一条还小：交出来的必须正好是那一条（调用方据此隔离它），
    // 既不能是空批（那会让循环空转），也不能把后面那条一起捎上。
    let batch = store.nextBatch(limit: 100, maxBytes: 64 * 1024)
    #expect(batch.count == 1)
    #expect(batch.first?.objectId.hasSuffix("huge") == true)
    #expect(SyncStore.encodedSize(batch) > 64 * 1024)
  }
}
