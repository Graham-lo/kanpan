import Foundation
import KanpanChart
import KanpanCore
import Testing
import UIKit

@testable import KanpanMain

/// 画线只有一份真值（审查 23.2）：`DrawingController.book`。
///
/// 图按品种从它投影，分享、提醒对账、落盘都只读它；中文提示与震动归 app。
@Suite(.serialized) @MainActor struct DrawingTruthTests {
  private func state(_ symbol: String, drawings: [Drawing] = []) -> ChartState {
    let series = BarSeries(symbol: symbol, interval: .h1, t0: 0, open: [100, 101],
                           high: [105, 106], low: [90, 91], close: [101, 102], volume: [1, 2])
    var s = ChartState(series: series,
                       symbol: SymbolInfo(symbol: symbol, base: "X", pricePrecision: 2, tickSize: 0.1),
                       view: ViewWindow(to: 3_600_000, span: 3_600_000))
    s.drawings = drawings
    return s
  }

  private func fixture() throws -> (DrawingController, ChartView, Drawing, DrawStore, URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = DrawStore(url: folder.appendingPathComponent("draws.json"))
    let line = Drawing(id: "own", kind: .hline, points: [DrawPoint(t: 1000, p: 95)])
    try file.save(DrawArchive(bySymbol: ["BTCUSDT": [line]]))
    let controller = DrawingController(store: file)
    let chart = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
    chart.state = state("BTCUSDT")
    controller.attach(chart)
    controller.focus("BTCUSDT")
    return (controller, chart, line, file, folder)
  }

  @Test("提示文案搬到 app 之后逐字不变")
  func hintsAreVerbatim() {
    #expect(DrawingHints.text(for: .hline, placed: 0) == "按住放置水平线")
    #expect(DrawingHints.text(for: .trend, placed: 0) == "按住拖动画趋势线")
    #expect(DrawingHints.text(for: .trend, placed: 1) == "选择终点")
    #expect(DrawingHints.text(for: .position, placed: 1) == "选择目标价")
    #expect(DrawingHints.text(for: .position, placed: 9) == "选择止损价")
    #expect(DrawingHints.text(for: .channel, placed: 2) == "选择通道宽度")
    #expect(DrawingHints.text(for: .elliottImpulse, placed: 3) == "选择 3 浪终点")
    #expect(DrawingHints.text(for: .headShoulders, placed: 6) == "选择终点")
    #expect(DrawingHints.text(for: .regression, placed: 0) == "圈住要拟合的那一段")
  }

  @Test("举起工具，顶上那行提示由壳按图报的点数说话")
  func controllerHintFollowsTool() throws {
    let (controller, chart, _, _, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(controller.hint == nil)
    controller.pick(.position)
    #expect(controller.tool == .position)
    #expect(controller.active)
    #expect(chart.drawTool == .position)
    #expect(chart.placedDrawAnchors == 0)
    #expect(controller.hint == "按住放置入场价")
    controller.finish()
    #expect(controller.hint == nil)
  }

  @Test("绑了真值的图不认外面 state 里的线；分享只读真值")
  func boundChartProjectsTheTruth() throws {
    let (controller, chart, own, _, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(chart.drawings == [own])
    // 宿主揉出来的 state 带着别的线（或者干脆是空的）——都不作数。
    let stranger = Drawing(id: "stranger", kind: .hline, points: [DrawPoint(t: 1000, p: 99)])
    chart.state = state("BTCUSDT", drawings: [stranger])
    #expect(chart.drawings == [own])
    chart.state = state("BTCUSDT")
    #expect(chart.drawings == [own])
    #expect(controller.shareable("BTCUSDT") == [own])
    controller.hideAll()
    #expect(controller.shareable("BTCUSDT").isEmpty, "隐藏的线不该发出去")
    #expect(controller.storedArchive["BTCUSDT"].allSatisfy { $0.hidden })
  }

  @Test("图上的编辑直接写进真值并落盘，重建的图接上就有线和撤销")
  func editsLandInTheTruth() throws {
    let (controller, chart, own, file, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(chart.addHorizontalLine(at: 97))
    #expect(controller.items.count == 2)
    #expect(try file.read()["BTCUSDT"].count == 2)
    // 和 `ChartHost.makeUIView` 同一个顺序：先接宿主（这时图还空着），再灌第一份 state。
    let rebuilt = ChartView(frame: chart.frame)
    controller.attach(rebuilt)
    #expect(!controller.canUndo)
    rebuilt.state = state("BTCUSDT")
    #expect(rebuilt.drawings.count == 2)
    #expect(controller.canUndo, "重建之后撤销是灰的")
    controller.undo()
    #expect(rebuilt.drawings == [own])
    #expect(try file.read()["BTCUSDT"] == [own])
  }

  @Test("换品种：图自己清掉手上的工具，线换成那只的")
  func symbolSwitchResetsTool() throws {
    let (controller, chart, _, _, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    controller.pick(.trend)
    #expect(controller.tool == .trend)
    chart.state = state("ETHUSDT")
    controller.focus("ETHUSDT")
    #expect(controller.tool == nil, "上一只品种的待画状态跟过来了")
    #expect(chart.drawings.isEmpty && controller.items.isEmpty)
  }

  @Test("云端推下来别的品种变了，这只的撤销栈留着；这只变了才清（A-07）")
  func publishOnlyClearsTouchedBuckets() throws {
    let (controller, chart, own, _, folder) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(chart.addHorizontalLine(at: 97))
    #expect(controller.canUndo)
    var other = controller.storedArchive
    other["ETHUSDT"] = [Drawing(id: "eth", kind: .hline, points: [DrawPoint(t: 1000, p: 3000)])]
    controller.publishSynced(other)
    #expect(controller.canUndo, "别的品种的云端变化清掉了这只的撤销")
    var mine = controller.storedArchive
    mine["BTCUSDT"] = [own]
    controller.publishSynced(mine)
    #expect(!controller.canUndo)
    #expect(chart.drawings == [own])
  }
}
