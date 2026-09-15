import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

// ---------------------------------------------------------------- 假触摸

/// 和 `ChartGestureTests` 里那两个是同一个手法（`UITouch` 的位置来自私有后端，
/// 只能覆写 `location(in:)`）。那边是 `private` 的，这边照抄一份，省得为了共用
/// 去动 M4 的测试文件。
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

// ---------------------------------------------------------------- 场地

@MainActor
private func drawState(count: Int = 800) -> ChartState {
  var seed: UInt64 = 20_260_907
  func next() -> Double {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double((seed >> 33) % 10_000) / 10_000
  }
  var o: [Double] = [], h: [Double] = [], l: [Double] = [], c: [Double] = [], vol: [Double] = []
  var p = 62_000.0
  for _ in 0..<count {
    let open = p
    let close = open * (1 + (next() - 0.5) * 0.01)
    o.append(open)
    h.append(max(open, close) * (1 + next() * 0.003))
    l.append(min(open, close) * (1 - next() * 0.003))
    c.append(close)
    vol.append(100 + next() * 900)
    p = close
  }
  let series = BarSeries(
    symbol: "BTCUSDT", interval: .h1, t0: 1_700_000_000_000, step: Interval.h1.stepMs,
    open: o, high: h, low: l, close: c, volume: vol)
  let span = Double(series.step) * 120
  return ChartState(
    series: series,
    symbol: SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1),
    view: ViewWindow(to: Double(series.lastTime) + span * 0.08, span: span),
    overlays: [], subs: [.macd])
}

@MainActor
private func makeView(magnet: Bool = false) throws -> (ChartView, DrawAxes) {
  let v = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
  var s = drawState()
  s.magnet = magnet
  v.state = s
  v.drawingInteractive = true
  v.drawingMagnet = magnet
  return (v, try #require(v.drawAxes, "布局没建起来，后面都别测了"))
}

/// 一次轻点：按下到抬起 50ms、一动不动，满足 §10.8 的落笔判定。
@MainActor
private func tap(_ v: ChartView, at q: CGPoint, ms: Double = 10_000) {
  let t = FakeTouch(q)
  v.drawingTouchesBegan([t], with: FakeEvent(ms: ms))
  v.drawingTouchesEnded([t], with: FakeEvent(ms: ms + 50), cancelled: false)
}

/// 一次拖：分四步走完，时间戳跟着往前。
@MainActor
private func drag(
  _ v: ChartView, from a: CGPoint, to b: CGPoint, ms: Double = 10_000, lift: Bool = true
) {
  let t = FakeTouch(a)
  var now = ms
  v.drawingTouchesBegan([t], with: FakeEvent(ms: now))
  for k in 1...4 {
    now += 16
    let f = CGFloat(k) / 4
    t.point = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    v.drawingTouchesMoved([t], with: FakeEvent(ms: now))
  }
  if lift { v.drawingTouchesEnded([t], with: FakeEvent(ms: now + 16), cancelled: false) }
}

@MainActor
private func at(_ axes: DrawAxes, _ p: DrawPoint) -> CGPoint {
  CGPoint(x: axes.x(p.t), y: axes.y(p.p))
}

// ---------------------------------------------------------------- 落笔

@MainActor
@Suite("画线交互")
struct ChartDrawingTests {

  @Test("A7.3：水平线一点即成，工具用完自动松开")
  func hlinePlacedByOneTap() throws {
    let (v, axes) = try makeView()
    v.drawTool = .hline
    let q = CGPoint(x: 180, y: 260)
    tap(v, at: q)
    let d = try #require(v.drawings.first, "一点没成线")
    #expect(v.drawings.count == 1)
    #expect(d.kind == .hline)
    #expect(abs(axes.y(d.a.p) - 260) < 0.5, "水平线没落在手指那个高度上")
    #expect(v.drawTool == nil, "画完一条工具该松开，不然会一直往下画")
  }

  @Test("A7.2：趋势线点两下成线，第一点落下后提示改口")
  func trendNeedsTwoTaps() throws {
    let (v, axes) = try makeView()
    v.drawTool = .trend
    #expect(v.drawHint == "点两下画一条趋势线")
    tap(v, at: CGPoint(x: 120, y: 300), ms: 10_000)
    #expect(v.drawings.isEmpty, "第一点不该直接成线")
    #expect(v.drawing.pending != nil)
    #expect(v.drawHint == "再点一下")
    tap(v, at: CGPoint(x: 280, y: 200), ms: 12_000)
    let d = try #require(v.drawings.first)
    #expect(d.kind == .trend)
    #expect(abs(axes.x(d.a.t) - 120) < 0.5 && abs(axes.y(d.a.p) - 300) < 0.5)
    let b = try #require(d.b)
    #expect(abs(axes.x(b.t) - 280) < 0.5 && abs(axes.y(b.p) - 200) < 0.5)
    #expect(v.drawTool == nil && v.drawing.pending == nil)
  }

  @Test("§10.8：第一点落下后预览点跟着手指走")
  func previewFollowsFinger() throws {
    let (v, axes) = try makeView()
    v.drawTool = .trend
    tap(v, at: CGPoint(x: 120, y: 300))
    // 第二根手指落下来就开始瞄，不用抬手也该有预览落点。
    let t = FakeTouch(CGPoint(x: 200, y: 250))
    v.drawingTouchesBegan([t], with: FakeEvent(ms: 12_000))
    let first = try #require(v.drawing.aim)
    #expect(abs(axes.x(first.t) - 200) < 0.5 && abs(axes.y(first.p) - 250) < 0.5)
    t.point = CGPoint(x: 300, y: 180)
    v.drawingTouchesMoved([t], with: FakeEvent(ms: 12_016))
    let moved = try #require(v.drawing.aim)
    #expect(abs(axes.x(moved.t) - 300) < 0.5 && abs(axes.y(moved.p) - 180) < 0.5, "预览没跟上手指")
    // 抬手就落在预览的位置上。
    v.drawingTouchesEnded([t], with: FakeEvent(ms: 12_032), cancelled: false)
    let b = try #require(v.drawings.first?.b)
    #expect(b == moved)
  }

  @Test("A7.2：磁吸开着，落点吸到那根的 OHLC")
  func magnetSnapsToOHLC() throws {
    let (v, axes) = try makeView(magnet: true)
    let s = try #require(v.state)
    v.drawTool = .hline
    let i = s.series.index(atTime: axes.t(atX: 200))
    let q = CGPoint(x: axes.x(Double(s.series.time(at: i))), y: axes.y(s.series.high[i]) + 2)
    tap(v, at: q)
    let d = try #require(v.drawings.first)
    let ohlc = [s.series.open[i], s.series.high[i], s.series.low[i], s.series.close[i]]
    #expect(ohlc.contains(d.a.p), "价格没吸到开高低收里的任何一个")
    #expect(d.a.t == Double(s.series.time(at: i)), "时间没吸到这根的开盘时刻")
  }

  @Test("磁吸关掉就停在手指上")
  func magnetOffKeepsFinger() throws {
    let (v, axes) = try makeView(magnet: false)
    v.drawTool = .hline
    tap(v, at: CGPoint(x: 200, y: 317))
    let d = try #require(v.drawings.first)
    #expect(abs(axes.y(d.a.p) - 317) < 0.001)
  }

  // ---------------------------------------------------------------- 选中

  @Test("A7.4：轻点线身选中，空白处轻点取消")
  func tapSelectsAndDeselects() throws {
    let (v, axes) = try makeView()
    let a = DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 300))
    let b = DrawPoint(t: axes.t(atX: 300), p: axes.p(atY: 300))
    let line = Drawing(kind: .trend, a: a, b: b)
    v.setDrawings([line])
    // 线身上方 6pt（< 命中阈值 9pt）
    tap(v, at: CGPoint(x: 200, y: 294), ms: 10_000)
    #expect(v.selectedDrawingID == line.id, "8pt 内没选中")
    // 离线 40pt 的空白处
    tap(v, at: CGPoint(x: 200, y: 500), ms: 20_000)
    #expect(v.selectedDrawingID == nil, "空白处轻点没取消选中")
  }

  @Test("A7.4：离线太远的轻点不选中")
  func tapFarMisses() throws {
    let (v, axes) = try makeView()
    let line = Drawing(
      kind: .trend, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 300)),
      b: DrawPoint(t: axes.t(atX: 300), p: axes.p(atY: 300)))
    v.setDrawings([line])
    tap(v, at: CGPoint(x: 200, y: 312))   // 12pt > 9pt
    #expect(v.selectedDrawingID == nil)
  }

  // ---------------------------------------------------------------- 拖

  @Test("A7.4：拖手柄只改那一端")
  func dragHandleMovesOneEnd() throws {
    let (v, axes) = try makeView()
    let line = Drawing(
      kind: .trend, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 320)),
      b: DrawPoint(t: axes.t(atX: 300), p: axes.p(atY: 280)))
    v.setDrawings([line])
    v.selectedDrawingID = line.id
    drag(v, from: at(axes, line.a), to: CGPoint(x: 140, y: 360))
    let d = try #require(v.drawings.first)
    let now = try #require(v.drawAxes)
    #expect(abs(now.x(d.a.t) - 140) < 1 && abs(now.y(d.a.p) - 360) < 1, "手柄没跟着手指")
    #expect(d.b == line.b, "拖一端把另一端也带走了")
  }

  @Test("A7.4：拖线身整条平移，两端位移一样")
  func dragBodyMovesWhole() throws {
    let (v, axes) = try makeView()
    let line = Drawing(
      kind: .trend, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 320)),
      b: DrawPoint(t: axes.t(atX: 300), p: axes.p(atY: 300)))
    v.setDrawings([line])
    v.selectedDrawingID = line.id          // 线身只有选中的那条拖得动（原型的规矩）
    drag(v, from: CGPoint(x: 200, y: 310), to: CGPoint(x: 240, y: 340))
    let d = try #require(v.drawings.first)
    let now = try #require(v.drawAxes)
    let b = try #require(d.b)
    #expect(abs(now.x(d.a.t) - 140) < 1 && abs(now.x(b.t) - 340) < 1, "横向不是整条一起走")
    #expect(abs(now.y(d.a.p) - 350) < 1 && abs(now.y(b.p) - 330) < 1, "纵向不是整条一起走")
  }

  @Test("没选中的线拖不动，那一下是拖图")
  func dragUnselectedBodyPansChart() throws {
    let (v, axes) = try makeView()
    let line = Drawing(
      kind: .trend, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 320)),
      b: DrawPoint(t: axes.t(atX: 300), p: axes.p(atY: 320)))
    v.setDrawings([line])
    let before = try #require(v.state).view
    drag(v, from: CGPoint(x: 200, y: 320), to: CGPoint(x: 120, y: 320), lift: false)
    #expect(v.drawings.first == line, "没选中的线身不该被拖走")
    #expect(try #require(v.state).view.from != before.from, "这一下应该是在拖图")
  }

  @Test("Phone: unselected endpoint pans; selected endpoint has a 44pt touch target")
  func phoneEndpointSelection() throws {
    let (v, axes) = try makeView()
    let line = Drawing(kind: .trend, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 300)),
      b: DrawPoint(t: axes.t(atX: 300), p: axes.p(atY: 260)))
    v.setDrawings([line])
    drag(v, from: CGPoint(x: 100, y: 300), to: CGPoint(x: 50, y: 300))
    #expect(v.drawings == [line], "A swipe over an unselected endpoint must not edit it")
    v.selectedDrawingID = line.id
    let current = try #require(v.drawAxes)
    let start = CGPoint(x: current.x(line.a.t), y: current.y(line.a.p) + 17)
    drag(v, from: start, to: CGPoint(x: start.x + 25, y: start.y + 30))
    #expect(v.drawings[0].a != line.a)
    #expect(v.drawings[0].b == line.b)
  }

  @Test("A7.5：对数模式下拖动按像素走，两端的像素位移一致")
  func dragIsPixelWiseInLogMode() throws {
    let (v, _) = try makeView()
    var s = try #require(v.state)
    s.price.mode = .log
    v.state = s
    let axes = try #require(v.drawAxes)
    let line = Drawing(
      kind: .trend, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 200)),
      b: DrawPoint(t: axes.t(atX: 300), p: axes.p(atY: 420)))
    v.setDrawings([line])
    v.selectedDrawingID = line.id
    let y0a = axes.y(line.a.p), y0b = axes.y(line.b!.p)
    drag(v, from: CGPoint(x: 200, y: 310), to: CGPoint(x: 200, y: 355))
    let d = try #require(v.drawings.first)
    let now = try #require(v.drawAxes)
    #expect(abs(now.y(d.a.p) - (y0a + 45)) < 1, "高价那端的像素位移不对")
    #expect(abs(now.y(d.b!.p) - (y0b + 45)) < 1, "低价那端的像素位移不对")
    // 等像素在对数轴上不是等价差——这正是不能直接加 dp 的原因。
    #expect(abs((d.a.p - line.a.p) - (d.b!.p - line.b!.p)) > 1e-6)
  }

  @Test("水平线整条拖只动价格，不动时间")
  func hlineBodyKeepsTime() throws {
    let (v, axes) = try makeView()
    let line = Drawing(kind: .hline, a: DrawPoint(t: axes.t(atX: 150), p: axes.p(atY: 300)))
    v.setDrawings([line])
    v.selectedDrawingID = line.id
    drag(v, from: CGPoint(x: 200, y: 300), to: CGPoint(x: 260, y: 350))
    let d = try #require(v.drawings.first)
    #expect(d.a.t == line.a.t, "水平线横着拖不该改时间")
    let now = try #require(v.drawAxes)
    #expect(abs(now.y(d.a.p) - 350) < 1)
  }

  // ---------------------------------------------------------------- 视野

  @Test("A7.5：拖图缩放之后线还钉在同一对 (时间, 价格) 上")
  func drawingsStickToTimeAndPrice() throws {
    let (v, _) = try makeView()
    var historical = try #require(v.state)
    historical.view = historical.view.dragged(byFingerPx: 300, plotW: v.chartLayout!.plotW)
    v.state = historical
    let axes = try #require(v.drawAxes)
    let line = Drawing(
      kind: .trend, a: DrawPoint(t: axes.t(atX: 120), p: axes.p(atY: 300)),
      b: DrawPoint(t: axes.t(atX: 320), p: axes.p(atY: 260)))
    v.setDrawings([line])
    // 横向拖 60pt
    drag(v, from: CGPoint(x: 200, y: 500), to: CGPoint(x: 140, y: 500), lift: false)
    #expect(v.drawings.first == line, "拖图把线的数值改了")
    let now = try #require(v.drawAxes)
    #expect(abs(now.x(line.a.t) - 60) < 1, "线没跟着视野一起走")
    // 再换价格轴模式，端点数值依然不动
    var s = try #require(v.state)
    s.price.mode = .percent
    v.state = s
    #expect(v.drawings.first == line)
  }

  @Test("A7.8：选着工具照样能拖图，拖动不算落笔")
  func panStillWorksWithToolArmed() throws {
    let (v, _) = try makeView()
    v.drawTool = .trend
    let before = try #require(v.state).view
    drag(v, from: CGPoint(x: 200, y: 300), to: CGPoint(x: 120, y: 300))
    #expect(try #require(v.state).view.from != before.from, "画线态下拖不动图了")
    #expect(v.drawings.isEmpty && v.drawing.pending == nil, "一拖就落笔了")
    #expect(v.drawTool == .trend, "工具不该因为拖了一下就松开")
  }

  @Test("A7.8：两指照样能捏合")
  func pinchStillWorks() throws {
    let (v, _) = try makeView()
    v.drawTool = .hline
    let before = try #require(v.state).view.span
    let a = FakeTouch(CGPoint(x: 120, y: 300))
    let b = FakeTouch(CGPoint(x: 260, y: 300))
    v.drawingTouchesBegan([a], with: FakeEvent(ms: 10_000))
    v.drawingTouchesBegan([b], with: FakeEvent(ms: 10_010))
    a.point = CGPoint(x: 60, y: 300)
    b.point = CGPoint(x: 320, y: 300)
    v.drawingTouchesMoved([a, b], with: FakeEvent(ms: 10_026))
    #expect(try #require(v.state).view.span < before, "捏开没把窗口缩窄")
    #expect(v.drawings.isEmpty)
  }

  // ---------------------------------------------------------------- 删除 / 完成

  @Test("A7.6：删除只删选中的那条；完成退出画线态但线留着")
  func deleteAndFinish() throws {
    let (v, axes) = try makeView()
    let one = Drawing(kind: .hline, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 300)))
    let two = Drawing(kind: .hline, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 400)))
    v.setDrawings([one, two])
    v.selectedDrawingID = two.id
    v.deleteSelectedDrawing()
    #expect(v.drawings.map(\.id) == [one.id])
    #expect(v.selectedDrawingID == nil)
    v.deleteSelectedDrawing()
    #expect(v.drawings.count == 1, "没选中就点删除，不该删掉别的线")

    v.drawTool = .trend
    tap(v, at: CGPoint(x: 150, y: 250))
    v.endDrawing()
    #expect(v.drawTool == nil && v.drawing.pending == nil && v.selectedDrawingID == nil)
    #expect(v.drawHint == nil)
    #expect(v.drawings.count == 1, "「完成」把线也清掉了")
  }

  // ---------------------------------------------------------------- 撤销

  @Test("撤销重做走一圈：画两条、撤两步、重做一步")
  func undoRedoRoundTrip() throws {
    let (v, _) = try makeView()
    v.drawTool = .hline
    tap(v, at: CGPoint(x: 120, y: 260), ms: 10_000)
    v.drawTool = .hline
    tap(v, at: CGPoint(x: 120, y: 360), ms: 20_000)
    #expect(v.drawings.count == 2)
    v.undoDrawing()
    #expect(v.drawings.count == 1)
    v.undoDrawing()
    #expect(v.drawings.isEmpty && !v.canUndoDrawing)
    v.undoDrawing()
    #expect(v.drawings.isEmpty, "撤到底了还能继续退")
    v.redoDrawing()
    #expect(v.drawings.count == 1 && v.canRedoDrawing)
  }

  @Test("删除也能撤销回来")
  func undoDelete() throws {
    let (v, axes) = try makeView()
    let one = Drawing(kind: .hline, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 300)))
    v.setDrawings([one])
    v.selectedDrawingID = one.id
    v.deleteSelectedDrawing()
    #expect(v.drawings.isEmpty)
    v.undoDrawing()
    #expect(v.drawings.first == one)
  }

  // ---------------------------------------------------------------- 上限

  @Test("A7.7：一个品种画满 50 条就不再往里塞")
  func perSymbolLimit() throws {
    let (v, axes) = try makeView()
    let full = (0..<50).map {
      Drawing(kind: .hline, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: Double(200 + $0))))
    }
    v.setDrawings(full)
    var hitLimit = false
    v.onDrawingLimitReached = { hitLimit = true }
    v.drawTool = .hline
    tap(v, at: CGPoint(x: 200, y: axes.pane.y + 30))
    #expect(v.drawings.count == 50)
    #expect(hitLimit, "满了没吭声")
  }

  // ---------------------------------------------------------------- 接线

  @Test("覆盖层装上之后，触摸从它这儿转进来")
  func overlayForwardsTouches() throws {
    let (v, _) = try makeView()
    let overlay = try #require(v.subviews.compactMap { $0 as? DrawingOverlayView }.first)
    #expect(overlay.isUserInteractionEnabled)
    v.drawTool = .hline
    let t = FakeTouch(CGPoint(x: 200, y: 300))
    overlay.touchesBegan([t], with: FakeEvent(ms: 10_000))
    overlay.touchesEnded([t], with: FakeEvent(ms: 10_050))
    #expect(v.drawings.count == 1, "覆盖层没把触摸转给画线层")
    v.drawingInteractive = false
    #expect(v.subviews.compactMap { $0 as? DrawingOverlayView }.isEmpty)
  }

  @Test("换一批线（切品种）把选中、半截的线和撤销栈一起清掉")
  func setDrawingsResets() throws {
    let (v, _) = try makeView()
    v.drawTool = .trend
    tap(v, at: CGPoint(x: 150, y: 250))
    #expect(v.drawing.pending != nil)
    v.setDrawings([])
    #expect(v.drawing.pending == nil && v.selectedDrawingID == nil && !v.canUndoDrawing)
  }

  @Test("线变了会叫外面存盘")
  func notifiesOnChange() throws {
    let (v, _) = try makeView()
    var seen: [[Drawing]] = []
    v.onDrawingsChanged = { seen.append($0) }
    v.drawTool = .hline
    tap(v, at: CGPoint(x: 200, y: 300))
    #expect(seen.count == 1 && seen.last?.count == 1)
  }
}

extension ChartDrawingTests {
  @Test("All tools create, undo and redo")
  func allToolsCreate() throws {
    for tool in Drawing.Kind.allCases {
      let (v, axes) = try makeView(); v.drawTool = tool
      let coords = [CGPoint(x: 80, y: axes.pane.h * 0.65), CGPoint(x: 240, y: axes.pane.h * 0.4), CGPoint(x: 140, y: axes.pane.h * 0.25)]
      for i in 0..<tool.pointCount { tap(v, at: coords[i], ms: Double(10000 + i * 1000)) }
      let result = try #require(v.drawings.first, "Missing \(tool)")
      #expect(result.kind == tool && result.points.count == tool.pointCount)
      #expect(v.selectedDrawingID == result.id)
      v.undoDrawing(); #expect(v.drawings.isEmpty)
      v.redoDrawing(); #expect(v.drawings == [result])
    }
  }
  @Test("Drag previews do not mutate committed model; cancel and no-op have no undo entry")
  func cancelledDragAndNoOp() throws {
    let (v, axes) = try makeView()
    let line = Drawing(kind: .trend, a: DrawPoint(t: axes.t(atX: 80), p: axes.p(atY: 120)), b: DrawPoint(t: axes.t(atX: 240), p: axes.p(atY: 180)))
    v.setDrawings([line]); v.selectedDrawingID = line.id
    let touch = FakeTouch(CGPoint(x: 80, y: 120))
    v.drawingTouchesBegan([touch], with: FakeEvent(ms: 10000))
    touch.point = CGPoint(x: 110, y: 140)
    v.drawingTouchesMoved([touch], with: FakeEvent(ms: 10020))
    #expect(v.state?.drawings == [line]); #expect(v.drawing.preview != line)
    v.drawingTouchesEnded([touch], with: FakeEvent(ms: 10040), cancelled: true)
    #expect(v.drawings == [line] && !v.canUndoDrawing); #expect(v.state?.drawingPreviewID == nil)
    tap(v, at: CGPoint(x: 80, y: 120), ms: 20000); #expect(!v.canUndoDrawing)
  }
  @Test("Pinch while placing preserves anchors")
  func pinchWhilePending() throws {
    let (v, _) = try makeView(); v.drawTool = .channel
    tap(v, at: CGPoint(x: 80, y: 120))
    let anchors = v.drawing.anchors
    let a = FakeTouch(CGPoint(x: 130, y: 160)), b = FakeTouch(CGPoint(x: 240, y: 160))
    v.drawingTouchesBegan([a], with: FakeEvent(ms: 11000))
    v.drawingTouchesBegan([b], with: FakeEvent(ms: 11010))
    a.point.x = 90; b.point.x = 280
    v.drawingTouchesMoved([a,b], with: FakeEvent(ms: 11030))
    v.drawingTouchesEnded([a,b], with: FakeEvent(ms: 11050), cancelled: false)
    #expect(v.drawing.anchors == anchors && v.drawings.isEmpty)
    v.undoDrawing(); #expect(v.drawing.pending == nil)
  }
  @Test("Lock, hide, copy and styles support undo")
  func objectActions() throws {
    let (v, axes) = try makeView()
    let line = Drawing(kind: .hline, a: DrawPoint(t: axes.t(atX: 80), p: axes.p(atY: 120)))
    v.setDrawings([line]); v.selectedDrawingID = line.id
    var edited = line; edited.locked = true; edited.color = "#4A90E2"; edited.lineWidth = 3
    v.updateDrawing(edited)
    drag(v, from: CGPoint(x: 150, y: 120), to: CGPoint(x: 170, y: 150))
    #expect(v.drawings == [edited])
    v.selectedDrawingID = line.id; v.duplicateSelectedDrawing(); #expect(v.drawings.count == 2)
    #expect(v.drawings.last?.locked == false && v.drawings.last?.color == edited.color)
    v.undoDrawing(); #expect(v.drawings == [edited])
    v.setAllDrawingsHidden(true); #expect(v.drawings[0].hidden)
    v.undoDrawing(); #expect(!v.drawings[0].hidden)
    v.clearDrawings(); #expect(v.drawings.isEmpty)
    v.undoDrawing(); #expect(v.drawings == [edited])
  }
  @Test("Distant drawings do not distort Y; hidden objects cannot be selected")
  func rangeAndHidden() throws {
    let (v, axes) = try makeView(); let before = v.chartPriceRange
    var line = Drawing(kind: .hline, a: DrawPoint(t: 0, p: 1e12))
    v.setDrawings([line]); #expect(v.chartPriceRange == before)
    line.a.p = axes.p(atY: 120); line.hidden = true
    v.setDrawings([line]); tap(v, at: CGPoint(x: 150, y: 120)); #expect(v.selectedDrawingID == nil)
  }
  @Test("MA EMA colors are independent from each other and calculations")
  func indicatorColorsDoNotAffectValues() {
    var s = drawState(); s.overlays = [.ma, .ema]
    var renderer = ChartRenderer(state: s); let before = renderer.engine[.ma]
    s.indicatorColors = [.ma: [0: "#4A90E2", 1: "#E46A76"], .ema: [0: "#37A78F"]]; renderer.state = s
    #expect(renderer.indicatorColor(.ma, 0) == "#4A90E2")
    #expect(renderer.indicatorColor(.ema, 0) == "#37A78F")
    #expect(renderer.indicatorColor(.ma, 2) == s.colors.palette[2])
    let old = before?.lines.first?.filter(\.isFinite)
    let new = renderer.engine[.ma]?.lines.first?.filter(\.isFinite)
    #expect(new == old)
  }
}
