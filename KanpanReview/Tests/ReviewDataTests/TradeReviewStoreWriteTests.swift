import Foundation
import Testing
import ReviewData

/// 审查 R22：交易复盘侧文件写盘失败不再悄悄吞掉（记日志），而且失败那一下不能把
/// 内存里的记账一起丢掉——下一次能写时整份写全。
@MainActor struct TradeReviewStoreWriteTests {
  @Test func writeFailureKeepsMemoryAndNextWriteCarriesEverything() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("trade-write-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    // 目录那个位置被一个普通文件占着：建目录、写盘都会失败。
    let directory = root.appendingPathComponent("account")
    try Data("x".utf8).write(to: directory)
    let store = TradeReviewStore(directory: directory)
    store.update { $0.rejected["a"] = 1 }
    #expect(store.archive.rejected["a"] == 1, "写盘失败，内存这份照样是新的")

    try FileManager.default.removeItem(at: directory)
    store.update { $0.rejected["b"] = 2 }
    let reopened = TradeReviewStore(directory: directory)
    #expect(reopened.archive.rejected == ["a": 1, "b": 2])
  }

  /// 解不开的档另存 `.backup`、从空档开始（原行为，改成 do/catch 记日志后不能变）。
  @Test func unreadableArchiveIsBackedUpAndStartsEmpty() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trade-bad-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(TradeReviewStore.fileName)
    try Data("{not json".utf8).write(to: url)
    let store = TradeReviewStore(directory: directory)
    #expect(store.archive == TradeArchive())
    #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("backup").path))

    // 版本对不上同样当解不开。
    try FileManager.default.removeItem(at: url.appendingPathExtension("backup"))
    try Data(#"{"version":2}"#.utf8).write(to: url)
    #expect(TradeReviewStore(directory: directory).archive == TradeArchive())
    #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("backup").path))
  }
}
