import Foundation
import Testing
import KanpanCore
@testable import Kanpan

/// 画线落盘那一层（`Kanpan/Kanpan/Drawing/DrawStore.swift`）的磁盘往返。
///
/// 这四条原本在 `KanpanCoreTests`（`DrawingEditTests` 的「磁盘往返」「比自己新的存档不乱读」，
/// `DrawingV2Tests` 的两条）；审查 24 把 `DrawStore` 请出 KanpanCore 之后跟着搬过来，
/// 用例名与断言原样不动。存档模型本身（分桶、容错解码、迁移）的用例仍在 Core。
@Suite("画线落盘")
struct DrawStoreTests {

  private func hline(_ p: Double, _ id: String = Drawing.newID()) -> Drawing {
    Drawing(id: id, kind: .hline, a: DrawPoint(t: 1_700_000_000_000, p: p))
  }

  @Test("磁盘往返")
  func diskRoundTrip() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-draw-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = DrawStore(url: dir.appendingPathComponent("nested/draws.json"))

    #expect(store.load().bySymbol.isEmpty, "还没有文件时该给一份空档，不是崩")

    var a = DrawArchive()
    a["BTCUSDT"] = [hline(64_321.5, "h1"), hline(70_000, "h2")]
    try store.save(a)                       // 目录不存在也要自己建出来
    #expect(store.load() == a)

    // 覆盖写：第二次存的才算数
    a["BTCUSDT"] = [hline(1, "h3")]
    try store.save(a)
    #expect(store.load()["BTCUSDT"].map(\.id) == ["h3"])

    // 坏文件：当空档，不抛
    try Data("{ 这不是 JSON".utf8).write(to: store.url)
    #expect(store.load().bySymbol.isEmpty)
  }

  @Test("比自己新的存档不乱读")
  func futureVersion() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-draw-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("draws.json")
    let store = DrawStore(url: url)
    try Data(#"{"v":99,"d":{"BTCUSDT":[{"id":"h","kind":"hline","a":{"t":1,"p":2}}]}}"#.utf8)
      .write(to: url)
    #expect(store.load().bySymbol.isEmpty, "看不懂的版本当空的")
    // 但磁盘上那份不许动，降级安装回去还在
    #expect(try Data(contentsOf: url).count > 0)
  }

  @Test func migrateV1AndRoundTripAllTools() throws {
    let legacy = Data(#"{"v":1,"d":{"BTCUSDT":[{"id":"old","kind":"trend","a":{"t":1,"p":100},"b":{"t":2,"p":200}}]}}"#.utf8)
    var archive = try JSONDecoder().decode(DrawArchive.self, from: legacy)
    #expect(archive["BTCUSDT"][0].points == [DrawPoint(t: 1, p: 100), DrawPoint(t: 2, p: 200)])
    archive["ETHUSDT"] = Drawing.Kind.allCases.map { kind in
      var d = Drawing(kind: kind, points: (0..<kind.pointCount).map { DrawPoint(t: Double($0 + 1), p: Double(100 + $0 * 20)) })
      d.color = "#4A90E2"; d.lineWidth = 3; d.dash = .dashed; d.locked = true; d.hidden = true; d.filled = false
      return d
    }
    archive.preferences.magnet = false; archive.preferences.continuous = true
    archive.preferences.favorites = [.channel, .hray]
    archive.preferences.styles["trend"] = DrawingStyle(archive["BTCUSDT"][0])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("draws.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try DrawStore(url: url).save(archive)
    let restored = try DrawStore(url: url).read()
    #expect(restored.bySymbol == archive.bySymbol)
    #expect(restored.preferences == archive.preferences)
    #expect(restored["OTHER"].isEmpty)
  }
  @Test func failedReadCannotOverwriteOriginal() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    for content in ["broken", #"{"v":999,"d":{}}"#] {
      let bytes = Data(content.utf8); try bytes.write(to: url)
      #expect(throws: (any Error).self) { try DrawStore(url: url).save(DrawArchive()) }
      #expect(try Data(contentsOf: url) == bytes)
    }
  }
}
