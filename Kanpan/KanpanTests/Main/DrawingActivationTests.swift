import Foundation
import KanpanChart
import KanpanCore
import Testing
import UIKit

@testable import Kanpan

/// 「选中」不等于「人在画线」。
///
/// 第五轮留下的观察之一：竖屏随手点中一条已有的画线，屏幕自己转成横屏画线工作台。
/// 病根是 `DrawingController.sync()` 里那句「选中了就 `active = true`」——它写着
/// 「正常情况下选中线只可能发生在用户正在画线的时候」，而图上的画线手势一接上宿主
/// 就开着，竖屏点中一条旧线照样会选中它。`MainScreen` 对 `draw.active` 的 onChange
/// 接着把屏幕转过去。
///
/// 现在的规矩是两条：选中**永远**不开工作台；不在画线态时图根本不收画线的手
/// （`ChartView.drawingEditable`），点图只是平移 / 十字光标。
@Suite(.serialized) @MainActor struct DrawingActivationTests {

  private func fixture() throws -> (DrawingController, ChartView, Drawing, DrawStore, URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = DrawStore(url: folder.appendingPathComponent("draws.json"))
    let line = Drawing(id: "old", kind: .hline, points: [DrawPoint(t: 1000, p: 95)])
    try file.save(DrawArchive(bySymbol: ["BTCUSDT": [line]]))
    let controller = DrawingController(store: file)
    let series = BarSeries(symbol: "BTCUSDT", interval: .h1, t0: 0, open: [100, 101],
                           high: [105, 106], low: [90, 91], close: [101, 102], volume: [1, 2])
    let state = ChartState(series: series,
                           symbol: SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1),
                           view: ViewWindow(to: 3_600_000, span: 3_600_000))
    let chart = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
    chart.state = state
    controller.attach(chart)
    controller.focus("BTCUSDT")
    return (controller, chart, line, file, folder)
  }

  @Test("点中一条旧线只是选中，画线工作台不许开")
  func selectionNeverOpensTheWorkbench() throws {
    let (controller, chart, line, _, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(!controller.active)
    // 图上报上来一个选中（真机上就是手指点中了线身）。
    chart.selectedDrawingID = line.id
    #expect(controller.selected?.id == line.id, "选中没同步上来")
    #expect(!controller.active, "选中把画线工作台打开了——竖屏会当场转横屏")
  }

  @Test("深链高亮同样不开工作台")
  func highlightNeverOpensTheWorkbench() throws {
    let (controller, chart, line, _, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    controller.highlight(drawingID: line.id, symbol: "BTCUSDT")
    #expect(chart.selectedDrawingID == line.id, "没指出来")
    #expect(!controller.active, "高亮把人拽进了画线工作台")
  }

  @Test("不在画线态时图不收画线的手，进了画线态才收")
  func editabilityFollowsTheWorkbench() throws {
    let (controller, chart, _, _, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(!chart.drawingEditable, "没在画线却收着画线的手")
    controller.toggle()
    #expect(controller.active && chart.drawingEditable, "进了画线态还不收手")
    controller.finish()
    #expect(!controller.active && !chart.drawingEditable, "退出画线态没把手收回去")
    // 换一张图（转屏、切页都会重建）也要接着当前状态走。
    controller.toggle()
    let replacement = ChartView(frame: chart.frame)
    replacement.state = chart.state
    controller.attach(replacement)
    #expect(replacement.drawingEditable, "新建的图没接上画线态")
  }

  @Test("真正的入口照旧自己开台")
  func realEntriesStillActivate() throws {
    let (controller, chart, line, _, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    controller.select(line.id)
    #expect(controller.active, "「管理」里点一行没进画线台")
    controller.finish()
    controller.openTools()
    #expect(controller.active, "开工具面板没进画线台")
    controller.finish()
    controller.pick(.hline)
    #expect(controller.active && chart.drawingEditable, "拿起工具没进画线台")
    // 画完一笔图会自己选中新线（`placeDrawPoint` 的 commit）：那时候 `active` 早就是真的，
    // 删掉 `sync()` 里那句「选中即 active」不会把这条路弄丢。
    chart.selectedDrawingID = line.id
    #expect(controller.active, "画完一笔反而退出了画线台")
  }
}
