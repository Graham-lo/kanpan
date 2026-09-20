import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

// 手指按着一个目标的这段时间里，两根轴都不许动（任务 2），以及撤销栈要活得过图的重建
// （任务 3）。前者的现象是「手指没动，线自己跑了」：1 分钟图上一根新 K 线到货，
// `AICoinBehavior.reconcile` 把视野右移一格；行情走出新高，自动纵轴重算价格区间。

// ---------------------------------------------------------------- 假触摸

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
private func freezeState(count: Int = 600) -> ChartState {
  var seed: UInt64 = 20_260_920
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
    symbol: "BTCUSDT", interval: .m1, t0: 1_700_000_000_000, step: Interval.m1.stepMs,
    open: o, high: h, low: l, close: c, volume: vol)
  return ChartState(
    series: series,
    symbol: SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1),
    view: ViewWindow(to: Double(series.lastTime), span: Double(series.step) * 120),
    overlays: [], subs: [.vol])
}

/// 一张贴着末根的 1 分钟图。`scrollToLatest` 走的是「没有动画就直接落位」那条，
/// 落完 `view.to` 正好等于 `ViewMath.reset(...)`，也就是 `reconcile` 认的「跟着最新」。
@MainActor
private func freezeView(magnet: Bool = false) throws -> (ChartView, Layout) {
  let v = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
  var s = freezeState()
  s.magnet = magnet
  v.state = s
  v.drawingInteractive = true
  v.drawingMagnet = magnet
  v.scrollToLatest(animated: false)
  return (v, try #require(v.chartLayout, "布局没建起来，后面都别测了"))
}

/// 新 K 线到货，而且走出了一根远高于现价的新高——两根轴都有理由动。
///
/// `reconcile` 那一句照抄 `ChartHost.updateUIView`（宿主那边已经加了
/// `axesFrozen` 的门，这儿故意不加：连一份已经右移过的视野灌进来都得顶住）。
@MainActor
private func pushNewBar(_ v: ChartView, plotW: Double, highMultiplier: Double = 1.06) {
  guard var s = v.state else { return }
  let old = s.series
  let last = old.close[old.count - 1]
  var series = old
  series.append(
    Bar(openTime: old.lastTime + old.step, open: last, high: last * highMultiplier,
        low: last * 0.999, close: last * (highMultiplier - 0.01), volume: 500))
  let shifted = AICoinBehavior.reconcile(
    s.view, from: old, to: series, plotW: plotW, anchor: s.options.anchor)
  s.series = series
  s.view = shifted
  v.state = s
}

@MainActor
private func latestView(_ v: ChartView, plotW: Double) throws -> ViewWindow {
  let s = try #require(v.state)
  return ViewMath.reset(
    series: s.series, plotW: plotW,
    spacing: s.view.barSpacing(step: s.series.step, plotW: plotW), anchor: s.options.anchor)
}

// ---------------------------------------------------------------- 十字线

@MainActor
@Suite("拖动期间轴冻结") struct ChartAxisFreezeTests {
  @Test("按住十字线时新 K 线不挪视野，抬手一次追平")
  func crosshairHoldsTheViewport() throws {
    let (v, L) = try freezeView()
    // 先轻点出一条十字线，再从它的中心拎住——这就是用户「按住读数」的那一下。
    let tap = FakeTouch(CGPoint(x: 180, y: 160))
    v.touchesBegan([tap], with: FakeEvent(ms: 10_000))
    v.touchesEnded([tap], with: FakeEvent(ms: 10_050))
    let center = try #require(v.renderer?.crosshairCenter(size: v.bounds.size))
    let held = try #require(v.state?.crosshair?.index)
    let heldTime = try #require(v.state).series.time(at: held)

    let t = FakeTouch(center)
    v.touchesBegan([t], with: FakeEvent(ms: 11_000))
    #expect(v.axesFrozen)
    let before = try #require(v.state).view
    let rangeBefore = try #require(v.chartPriceRange)
    let xBefore = before.x(Double(heldTime), plotW: L.plotW)

    pushNewBar(v, plotW: L.plotW)

    let during = try #require(v.state).view
    #expect(during == before)                              // 时间轴一格都没挪
    #expect(v.chartPriceRange == rangeBefore)              // 纵轴也钉着，新高不重算
    #expect(abs(during.x(Double(heldTime), plotW: L.plotW) - xBefore) < 0.001)
    // 新 K 线本身照常进了序列——冻的是坐标，不是数据。
    #expect(try #require(v.state).series.count == 601)

    v.touchesEnded([t], with: FakeEvent(ms: 11_400))
    #expect(!v.axesFrozen)
    let after = try #require(v.state).view
    #expect(after.to > before.to)
    #expect(abs(after.to - (try latestView(v, plotW: L.plotW).to)) < 0.001)
    #expect(v.chartPriceRange != rangeBefore)              // 松开之后纵轴照常跟新高
  }

  @Test("在看历史的图，抬手不会被拽回最新")
  func historyViewDoesNotCatchUp() throws {
    let (v, L) = try freezeView()
    var s = try #require(v.state)
    s.view = s.view.dragged(byFingerPx: 600, plotW: L.plotW)
    v.state = s
    let tap = FakeTouch(CGPoint(x: 180, y: 160))
    v.touchesBegan([tap], with: FakeEvent(ms: 10_000))
    v.touchesEnded([tap], with: FakeEvent(ms: 10_050))
    let center = try #require(v.renderer?.crosshairCenter(size: v.bounds.size))

    let t = FakeTouch(center)
    v.touchesBegan([t], with: FakeEvent(ms: 11_000))
    #expect(v.axesFrozen)
    let before = try #require(v.state).view
    pushNewBar(v, plotW: L.plotW)
    v.touchesEnded([t], with: FakeEvent(ms: 11_400))
    #expect(!v.axesFrozen)
    #expect(try #require(v.state).view == before)
  }

  @Test("二指介入就解钉：捏合本来就是冲着视野来的")
  func pinchReleasesTheFreeze() throws {
    let (v, _) = try freezeView()
    let tap = FakeTouch(CGPoint(x: 180, y: 160))
    v.touchesBegan([tap], with: FakeEvent(ms: 10_000))
    v.touchesEnded([tap], with: FakeEvent(ms: 10_050))
    let t = FakeTouch(CGPoint(x: 60, y: 300))
    v.touchesBegan([t], with: FakeEvent(ms: 11_000))
    let second = FakeTouch(CGPoint(x: 300, y: 300))
    v.touchesBegan([second], with: FakeEvent(ms: 11_050))
    #expect(v.gesture.mode == .pinch)
    #expect(!v.axesFrozen)
  }

  // ---------------------------------------------------------------- 画线锚点

  @Test("按住线的端点时，新 K 线到货线也不从手指底下跑")
  func draggingAnAnchorHoldsBothAxes() throws {
    let (v, L) = try freezeView()
    let axes = try #require(v.drawAxes)
    // 先画一条趋势线。
    v.drawTool = .trend
    let a = CGPoint(x: 120, y: 260), b = CGPoint(x: 240, y: 200)
    let stroke = FakeTouch(a)
    v.drawingTouchesBegan([stroke], with: FakeEvent(ms: 12_000))
    stroke.point = b
    v.drawingTouchesMoved([stroke], with: FakeEvent(ms: 12_060))
    v.drawingTouchesEnded([stroke], with: FakeEvent(ms: 12_120), cancelled: false)
    let line = try #require(v.drawings.last)
    #expect(line.points.count == 2)
    v.selectedDrawingID = line.id
    _ = axes

    // 按住它的第二个端点开始拖，手指停在这儿不抬。
    let handle = CGPoint(x: axesPoint(v, line.points[1]).x, y: axesPoint(v, line.points[1]).y)
    let t = FakeTouch(handle)
    v.drawingTouchesBegan([t], with: FakeEvent(ms: 13_000))
    #expect(v.axesFrozen)
    let finger = CGPoint(x: handle.x - 30, y: handle.y + 24)
    t.point = finger
    v.drawingTouchesMoved([t], with: FakeEvent(ms: 13_060))
    let dragged = try #require(v.drawing.preview)
    let onScreen = axesPoint(v, dragged.points[1])
    #expect(abs(onScreen.x - finger.x) < 1 && abs(onScreen.y - finger.y) < 1)

    // 新 K 线到货 + 新高：没有冻结的话这一下会把线从手指底下挪走。
    let viewBefore = try #require(v.state).view
    let rangeBefore = try #require(v.chartPriceRange)
    pushNewBar(v, plotW: L.plotW)
    #expect(try #require(v.state).view == viewBefore)
    #expect(v.chartPriceRange == rangeBefore)
    let after = axesPoint(v, dragged.points[1])
    #expect(abs(after.x - finger.x) < 1 && abs(after.y - finger.y) < 1)

    v.drawingTouchesEnded([t], with: FakeEvent(ms: 13_200), cancelled: false)
    #expect(!v.axesFrozen)
    // 落下去的就是冻结期间手指底下那一点（换算用的是冻结期间那套坐标）。
    let committed = try #require(v.drawings.first { $0.id == line.id })
    #expect(committed.points[1] == dragged.points[1])
    // 抬手之后整张图一次追平，线跟着图一起左移**正好一根**——它钉在时间上，不是钉在
    // 像素上。这一下是「图动了」，不是「线在手指底下动了」，两者差一根 K 线的间距。
    let committedScreen = axesPoint(v, committed.points[1])
    let spacing = try #require(v.state).view.barSpacing(
      step: try #require(v.state).series.step, plotW: L.plotW)
    #expect(abs((committedScreen.x - finger.x) + spacing) < 0.5)
    // 抬手之后视野一次追平到末根。
    #expect(abs(try #require(v.state).view.to - (try latestView(v, plotW: L.plotW).to)) < 0.001)
  }

  // ---------------------------------------------------------------- 撤销栈接力

  @Test("撤销栈活得过图的重建：两笔画完换一张图，撤销撤掉的还是最后一笔")
  func historySurvivesARebuiltChart() throws {
    let (v, _) = try freezeView()
    v.drawTool = .hline
    for (i, y) in [200.0, 320.0].enumerated() {
      let t = FakeTouch(CGPoint(x: 150, y: y))
      v.drawingTouchesBegan([t], with: FakeEvent(ms: 20_000 + Double(i) * 1_000))
      v.drawingTouchesEnded([t], with: FakeEvent(ms: 20_050 + Double(i) * 1_000), cancelled: false)
      v.drawTool = .hline
    }
    #expect(v.drawings.count == 2)
    #expect(v.canUndoDrawing)
    let items = v.drawings
    let stack = v.drawingHistory

    // 换页 / 进出横屏工作台 = `ChartBox.makeUIView` 重造一张图。宿主
    // （`DrawingController`）按品种存着那摞栈，接上来就灌回去。
    let rebuilt = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    rebuilt.state = freezeState()
    rebuilt.drawingInteractive = true
    rebuilt.setDrawings(items)
    #expect(!rebuilt.canUndoDrawing, "`setDrawings` 是整批外部替换，它本来就该清栈")
    rebuilt.drawingHistory = stack
    #expect(rebuilt.canUndoDrawing)

    rebuilt.undoDrawing()
    #expect(rebuilt.drawings.count == 1)
    #expect(rebuilt.drawings.first?.id == items.first?.id, "撤掉的得是**最后**那一笔")
    #expect(rebuilt.canRedoDrawing)
    rebuilt.redoDrawing()
    #expect(rebuilt.drawings.map(\.id) == items.map(\.id))
  }

  @Test("空栈不建会话：没画过线的图别凭空多挂一个关联对象")
  func emptyHistoryDoesNotAllocate() throws {
    let v = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    v.state = freezeState()
    v.drawingHistory = DrawHistory()
    #expect(v.drawingSessionIfLoaded == nil)
    #expect(!v.canUndoDrawing)
  }
}

@MainActor
private func axesPoint(_ v: ChartView, _ p: DrawPoint) -> CGPoint {
  guard let axes = v.drawAxes else { return .zero }
  return CGPoint(x: axes.x(p.t), y: axes.y(p.p))
}
