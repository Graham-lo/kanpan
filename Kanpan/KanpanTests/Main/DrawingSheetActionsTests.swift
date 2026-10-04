import Foundation
import KanpanChart
import KanpanCore
import Testing
import UIKit

@testable import Kanpan

/// 画线列表 / 样式表上的那几个动作，以及画线存档读不动时的去向。
///
/// - 样式表只占下半截，上半截的图照样能拖线、能锁线；「保存」原来把进表那一刻的整条快照
///   写回去，刚拖好的端点、刚上的锁被盖回旧值（`DrawingController.saveEdits`）。
/// - 画线列表上左划删一条还没写字的文字标注，原来走「先选中再删」，选中那一步触发
///   「落点即开样式表」，整张表闪一下换成样式表（`DrawingController.delete`）。
/// - `draws.json` 坏了，原来留在原处挡住之后每一次写，新画的线全存不下来
///   （`DrawStore.setAside`）。
@Suite("画线表单动作与坏档", .serialized) @MainActor struct DrawingSheetActionsTests {

  private let trend = Drawing(id: "trend", kind: .trend,
                              points: [DrawPoint(t: 1000, p: 95), DrawPoint(t: 2000, p: 100)])
  private let note = Drawing(id: "note", kind: .note, points: [DrawPoint(t: 1000, p: 97)])

  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("draw-sheet-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func fixture() throws -> (DrawingController, ChartView, URL) {
    let folder = try folder()
    let file = DrawStore(url: folder.appendingPathComponent("draws.json"))
    try file.save(DrawArchive(bySymbol: ["BTCUSDT": [trend, note]]))
    let controller = DrawingController(store: file)
    let series = BarSeries(symbol: "BTCUSDT", interval: .h1, t0: 0, open: [100, 101],
                           high: [105, 106], low: [90, 91], close: [101, 102], volume: [1, 2])
    let chart = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
    chart.state = ChartState(series: series,
                             symbol: SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1),
                             view: ViewWindow(to: 3_600_000, span: 3_600_000))
    controller.attach(chart)
    controller.focus("BTCUSDT")
    #expect(controller.items.map(\.id) == [trend.id, note.id], "夹具没装上两条线：items=\(controller.items.map(\.id)) chart=\(chart.drawings.map(\.id))")
    return (controller, chart, folder)
  }

  @Test("样式表开着时拖过、锁过的线，保存只改颜色粗细，不把端点和锁盖回去")
  func saveKeepsGeometryChangedWhileTheSheetWasOpen() throws {
    let (controller, chart, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    controller.toggle()
    controller.select(trend.id)
    // 样式表进来那一刻拿到的整条线。
    var edited = try #require(controller.selected)
    // 表开着，人在上半截的图上把线拖走、又锁上。
    var moved = edited
    moved.points = [DrawPoint(t: 1000, p: 80), DrawPoint(t: 2000, p: 120)]
    moved.locked = true
    chart.updateDrawing(moved)
    // 表上改了颜色粗细，点保存。
    edited.color = "#4A90E2"
    edited.lineWidth = 3
    controller.saveEdits(edited, promoteStyle: true)
    let saved = try #require(controller.items.first { $0.id == trend.id })
    #expect(saved.points == moved.points, "保存把刚拖好的端点盖回了进表时的旧值")
    #expect(saved.locked, "保存把刚上的锁解开了")
    #expect(saved.color == "#4A90E2" && saved.lineWidth == 3, "表上改的样式没生效")
  }

  @Test("样式表开着时线被撤销掉了，保存不把它复活")
  func saveAfterTheLineIsGoneWritesNothing() throws {
    let (controller, chart, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    controller.toggle()
    controller.select(trend.id)
    var edited = try #require(controller.selected)
    chart.deleteSelectedDrawing()
    edited.color = "#4A90E2"
    controller.saveEdits(edited, promoteStyle: false)
    #expect(!controller.items.contains { $0.id == trend.id }, "删掉的线被保存那一下又写回来了")
  }

  @Test("画线列表上左划删一条空文字标注，表不跳成样式表")
  func swipeDeletingAnEmptyNoteDoesNotFlashTheStyleSheet() throws {
    let (controller, chart, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    controller.toggle()
    controller.panel = .objects
    let before = "chart=\(chart.drawings.map(\.id)) state=\(chart.state != nil) sel=\(chart.selectedDrawingID ?? "nil")"
    controller.delete(note.id)
    #expect(controller.panel == .objects, "删一条线，画线列表被换成了样式表")
    #expect(!controller.items.contains { $0.id == note.id },
            "没删掉：前 \(before)；后 chart=\(chart.drawings.map(\.id)) sel=\(chart.selectedDrawingID ?? "nil") items=\(controller.items.map(\.id))")
    #expect(controller.items.contains { $0.id == trend.id }, "删多了")
  }

  @Test("点中一条空文字标注照旧直接开样式表")
  func selectingAnEmptyNoteStillPromptsForText() throws {
    let (controller, chart, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    controller.toggle()
    controller.select(note.id)
    #expect(chart.selectedDrawingID == note.id && controller.selected?.id == note.id,
            "没选中：chart=\(chart.selectedDrawingID ?? "nil") controller=\(controller.selected?.id ?? "nil")")
    #expect(controller.panel == .style, "落点即开样式表那条规矩被删除的修法带坏了")
  }

  @Test("draws.json 解不动：原件挪到旁边一个字节不少，之后画的线照常落盘")
  func corruptArchiveIsSetAsideAndSavingResumes() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("draws.json")
    let bytes = Data("{ 这不是 JSON".utf8)
    try bytes.write(to: url)
    let store = DrawStore(url: url)
    let controller = DrawingController(store: store)
    #expect(controller.notice?.contains("损坏") == true, "提示没说是坏档：\(controller.notice ?? "nil")")
    let aside = try FileManager.default.contentsOfDirectory(atPath: folder.path)
      .filter { $0.hasPrefix("draws.json.unreadable-") }
    #expect(aside.count == 1, "原件没另存：\(aside)")
    if let name = aside.first {
      #expect(try Data(contentsOf: folder.appendingPathComponent(name)) == bytes, "另存的那份被改过")
    }
    // 正式文件的位置空出来了：这一下原来会抛（先读坏档、读不动就拒写）。
    try store.save(DrawArchive(bySymbol: ["BTCUSDT": [trend]]))
    #expect(try store.read()["BTCUSDT"].map(\.id) == [trend.id])
  }

  @Test("比自己新的存档原地留着，提示说要升级")
  func newerArchiveStaysInPlace() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("draws.json")
    let bytes = Data(#"{"v":99,"d":{}}"#.utf8)
    try bytes.write(to: url)
    let controller = DrawingController(store: DrawStore(url: url))
    #expect(controller.notice?.contains("升级") == true, "提示没说是新版本：\(controller.notice ?? "nil")")
    #expect(try Data(contentsOf: url) == bytes, "新版本的存档被动了")
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["draws.json"])
  }

  @Test("字节本身读不到（不是坏档）不当坏档挪走")
  func unreadableBytesAreNotTreatedAsCorrupt() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    // 一个同名目录：文件「在」，但字节读不出来——和设备没解锁时读受保护文件同一类错。
    let url = folder.appendingPathComponent("draws.json")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    #expect(throws: (any Error).self) { try DrawStore(url: url).read() }
    do { _ = try DrawStore(url: url).read() } catch {
      #expect((error as? DrawStore.StoreError) != .corrupt, "读不到字节被归成了坏档")
    }
    _ = DrawingController(store: DrawStore(url: url))
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["draws.json"], "没坏的东西被挪走了")
  }
}
