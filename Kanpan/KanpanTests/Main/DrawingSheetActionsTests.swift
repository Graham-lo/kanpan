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
}
