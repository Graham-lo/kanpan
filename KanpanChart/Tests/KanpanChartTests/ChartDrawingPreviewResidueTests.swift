import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

// `drawingPreviewID` 的残留（网页版移植审查 2026-09-30 发现）。
//
// 拖一条选中的线时，底层按 `drawingPreviewID` 跳过它，由覆盖层拿拖动预览整只画。
// 拖动正常结束（抬手、取消、转交捏合、长按锁定）都会把这个 id 收掉；但有两条路只收了
// 拖动快照、没收这个 id：拖到一半撤销 / 重做（`afterHistoryJump`），和拖到一半视图离窗
// （`teardownDrawingLink`）。于是 id 一直指着那条线——选中时覆盖层替它画着看不出来，
// 一取消选中，那条线就从图上消失了。

private final class FakeTouch: UITouch {
  var point: CGPoint
  init(_ p: CGPoint) {
    self.point = p
    super.init()
  }
  override func location(in view: UIView?) -> CGPoint { point }
  override func previousLocation(in view: UIView?) -> CGPoint { point }
}

private final class FakeEvent: UIEvent {
  private let ts: TimeInterval
  init(ms: Double) {
    self.ts = ms / 1000
    super.init()
  }
  override var timestamp: TimeInterval { ts }
}

@MainActor
private func residueState() -> ChartState {
  var o: [Double] = [], h: [Double] = [], l: [Double] = [], c: [Double] = [], vol: [Double] = []
  var p = 62_000.0
  for i in 0..<400 {
    let open = p
    let close = open * (1 + sin(Double(i) / 7) * 0.004)
    o.append(open); c.append(close)
    h.append(max(open, close) * 1.002); l.append(min(open, close) * 0.998)
    vol.append(500)
    p = close
  }
  let series = BarSeries(symbol: "BTCUSDT", interval: .h1, t0: 1_700_000_000_000, step: Interval.h1.stepMs,
                         open: o, high: h, low: l, close: c, volume: vol)
  return ChartState(
    series: series,
    symbol: SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1),
    view: ViewWindow(to: Double(series.lastTime) + Double(series.step) / 2, span: Double(series.step) * 120),
    overlays: [], subs: [])
}

/// 一块挂在窗口上的图，上面一条选中的趋势线，第二个端点在 (260, 380)。
@MainActor
private func stageWithSelectedLine() throws -> (window: UIWindow, view: ChartView, line: Drawing) {
  let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
  let v = ChartView(frame: window.bounds)
  window.addSubview(v)
  v.state = residueState()
  v.drawingInteractive = true
  v.drawingMagnet = false
  let axes = try #require(v.drawAxes)
  let line = Drawing(id: "trend", kind: .trend,
                     points: [DrawPoint(t: axes.t(atX: 120), p: axes.p(atY: 300)),
                              DrawPoint(t: axes.t(atX: 260), p: axes.p(atY: 380))])
  v.setDrawings([line])
  v.selectedDrawingID = line.id
  return (window, v, line)
}

@MainActor
@Suite("画线：拖到一半被打断，预览标记不残留")
struct ChartDrawingPreviewResidueTests {

  @Test("拖到一半撤销：drawingPreviewID 与预览一起收掉，取消选中后线还在底层")
  func undoMidDragClearsPreviewID() throws {
    let (_, v, line) = try stageWithSelectedLine()

    // 先完整拖一次，撤销栈里有一步。
    let first = FakeTouch(CGPoint(x: 260, y: 380))
    v.drawingTouchesBegan([first], with: FakeEvent(ms: 10_000))
    first.point = CGPoint(x: 280, y: 340)
    v.drawingTouchesMoved([first], with: FakeEvent(ms: 10_020))
    v.drawingTouchesEnded([first], with: FakeEvent(ms: 10_040), cancelled: false)
    #expect(v.canUndoDrawing)
    #expect(v.drawings.first != line)

    // 第二次从挪过去的端点起手，拖到一半按撤销。
    let second = FakeTouch(CGPoint(x: 280, y: 340))
    v.drawingTouchesBegan([second], with: FakeEvent(ms: 20_000))
    #expect(v.drawingSessionIfLoaded?.drag != nil, "按在选中线的端点上该开始拖")
    #expect(v.state?.drawingPreviewID == line.id, "拖着的那条让出底层")
    second.point = CGPoint(x: 300, y: 320)
    v.drawingTouchesMoved([second], with: FakeEvent(ms: 20_020))

    v.undoDrawing()
    #expect(v.drawings.first == line, "撤销回到最初那条")
    #expect(v.state?.drawingPreviewID == nil, "拖动作废，底层不许再跳过那条线")
    #expect(v.drawingSessionIfLoaded?.preview == nil, "旧预览不许再盖在撤销后的线上")

    v.drawingTouchesEnded([second], with: FakeEvent(ms: 20_040), cancelled: false)
    v.selectedDrawingID = nil
    #expect(v.state?.drawingPreviewID == nil, "取消选中后那条线要由底层画出来")
    #expect(v.drawings.first == line, "抬手不再提交已经作废的那一程")

    // 重做同一条路。
    let third = FakeTouch(CGPoint(x: 260, y: 380))
    v.selectedDrawingID = line.id
    v.drawingTouchesBegan([third], with: FakeEvent(ms: 30_000))
    #expect(v.state?.drawingPreviewID == line.id)
    v.redoDrawing()
    #expect(v.state?.drawingPreviewID == nil)
    #expect(v.drawingSessionIfLoaded?.preview == nil)
    v.drawingTouchesEnded([third], with: FakeEvent(ms: 30_040), cancelled: false)
  }

  @Test("拖到一半离窗：drawingPreviewID 收掉，回到窗口取消选中后线还在底层")
  func teardownMidDragClearsPreviewID() throws {
    let (window, v, line) = try stageWithSelectedLine()
    let t = FakeTouch(CGPoint(x: 260, y: 380))
    v.drawingTouchesBegan([t], with: FakeEvent(ms: 10_000))
    t.point = CGPoint(x: 280, y: 340)
    v.drawingTouchesMoved([t], with: FakeEvent(ms: 10_020))
    #expect(v.state?.drawingPreviewID == line.id)

    v.removeFromSuperview()                       // didMoveToWindow(nil) → teardownDrawingLink
    #expect(v.drawingSessionIfLoaded?.drag == nil)
    #expect(v.state?.drawingPreviewID == nil, "拖动随离窗作废，底层不许再跳过那条线")
    #expect(v.drawings.first == line, "半截的拖动不落盘")

    window.addSubview(v)
    v.selectedDrawingID = nil
    #expect(v.state?.drawingPreviewID == nil)
  }

  @Test("拖到一半那条线被删掉：拖动当场作废，下一笔落笔不被当成拖那条已经没了的线")
  func deleteMidDragDropsTheDrag() throws {
    let (_, v, line) = try stageWithSelectedLine()
    let t = FakeTouch(CGPoint(x: 260, y: 380))
    v.drawingTouchesBegan([t], with: FakeEvent(ms: 10_000))
    t.point = CGPoint(x: 280, y: 340)
    v.drawingTouchesMoved([t], with: FakeEvent(ms: 10_020))
    #expect(v.state?.drawingPreviewID == line.id)

    v.deleteSelectedDrawing()                     // 另一根手指点了选中条上的「删除」
    #expect(v.drawings.isEmpty)
    #expect(v.drawingSessionIfLoaded?.drag == nil, "线没了，拖动当场作废")
    #expect(v.drawingSessionIfLoaded?.preview == nil, "覆盖层不许再画那条线的预览和读数")
    #expect(v.state?.drawingPreviewID == nil)

    t.point = CGPoint(x: 300, y: 320)
    v.drawingTouchesMoved([t], with: FakeEvent(ms: 10_040))
    v.drawingTouchesEnded([t], with: FakeEvent(ms: 10_060), cancelled: false)
    #expect(v.drawings.isEmpty, "抬手不许把删掉的线写回来")
    #expect(v.drawingSessionIfLoaded?.drag == nil)

    // 拿起趋势线工具拖一笔：得画出一条新线，而不是被残留的拖动收走。
    v.drawTool = .trend
    let pen = FakeTouch(CGPoint(x: 100, y: 250))
    v.drawingTouchesBegan([pen], with: FakeEvent(ms: 20_000))
    pen.point = CGPoint(x: 220, y: 200)
    v.drawingTouchesMoved([pen], with: FakeEvent(ms: 20_100))
    v.drawingTouchesEnded([pen], with: FakeEvent(ms: 20_200), cancelled: false)
    #expect(v.drawings.count == 1)
    #expect(v.drawings.first?.kind == .trend)
    #expect(v.drawings.first?.id != line.id)
  }
}
