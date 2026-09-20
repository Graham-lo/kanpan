import CoreGraphics
import Foundation
import KanpanCore
import QuartzCore
import Testing
import UIKit

@testable import KanpanChart

// 第五轮审查 A.5「测试缺口」里**必须踩到真触摸**的那几条（1、2、3、4、5、9、11、12、13、18）。
// 编号照报告原样保留。纯计算的那几条（6、8、14、15、16、17）在
// `KanpanCoreTests/ReviewA5Tests.swift`，7 在 `KanpanSettingsTests`，10 是 UI 用例，
// 三处不重复。
//
// 手势与画线都是自己接 `touchesBegan/Moved/Ended` 的，所以这里造的是假触摸而不是
// `UIGestureRecognizer`；动画（回弹、惯性、回到最新）靠手动步进 `ChartView.animation`
// 走完，不等真实时钟——`animation` 的 `didSet` 在离窗时会把动画整个丢掉，所以每条
// 用例的视图都真的挂在一个 `UIWindow` 上。

// ---------------------------------------------------------------- 场地

/// 位置可控的假触摸。和 `ChartGestureTests` / `ChartDrawingTests` 同一个手法。
private final class FakeTouch: UITouch {
  var point: CGPoint
  init(_ p: CGPoint) {
    self.point = p
    super.init()
  }
  override func location(in view: UIView?) -> CGPoint { point }
  override func previousLocation(in view: UIView?) -> CGPoint { point }
}

/// 时间戳可控的事件。轻点、双击、补历史都按毫秒判定，不能靠真实时钟碰运气。
private final class FakeEvent: UIEvent {
  private let ts: TimeInterval
  init(ms: Double) {
    self.ts = ms / 1000
    super.init()
  }
  override var timestamp: TimeInterval { ts }
}

@MainActor
private func a5Series(symbol: String = "BTCUSDT", bars: Int = 800, t0: Int64 = 1_700_000_000_000)
  -> BarSeries
{
  var seed: UInt64 = 20_260_920
  func next() -> Double {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double((seed >> 33) % 10_000) / 10_000
  }
  var o: [Double] = [], h: [Double] = [], l: [Double] = [], c: [Double] = [], vol: [Double] = []
  var p = 62_000.0
  for _ in 0..<bars {
    let open = p
    let close = open * (1 + (next() - 0.5) * 0.01)
    o.append(open)
    h.append(max(open, close) * (1 + next() * 0.003))
    l.append(min(open, close) * (1 - next() * 0.003))
    c.append(close)
    vol.append(100 + next() * 900)
    p = close
  }
  return BarSeries(
    symbol: symbol, interval: .h1, t0: t0, step: Interval.h1.stepMs,
    open: o, high: h, low: l, close: c, volume: vol)
}

@MainActor
private func a5State(symbol: String = "BTCUSDT", bars: Int = 800, t0: Int64 = 1_700_000_000_000)
  -> ChartState
{
  let series = a5Series(symbol: symbol, bars: bars, t0: t0)
  let span = Double(series.step) * 120
  return ChartState(
    series: series,
    symbol: SymbolInfo(symbol: symbol, base: String(symbol.prefix(3)), pricePrecision: 2, tickSize: 0.1),
    view: ViewWindow(to: Double(series.lastTime) + Double(series.step) / 2, span: span),
    overlays: [], subs: [.macd])
}

/// 停在历史里的视野：两端都离硬夹很远，拖动与捏合不会掺进弹性阻力，位移可以按像素对账。
@MainActor
private func historyState(bars: Int = 800) -> ChartState {
  var s = a5State(bars: bars)
  let step = Double(s.series.step)
  s.view = ViewWindow(to: Double(s.series.t0) + step * 400, span: step * 120)
  return s
}

/// 一块真的挂在窗口上的图。窗口要留在调用方手里：它一松手，`animation` 的帧循环就没了。
@MainActor
private func stage(_ state: ChartState? = nil, size: CGSize = CGSize(width: 390, height: 700))
  throws -> (window: UIWindow, view: ChartView, layout: Layout)
{
  let window = UIWindow(frame: CGRect(origin: .zero, size: size))
  let view = ChartView(frame: window.bounds)
  window.addSubview(view)
  view.state = state ?? a5State()
  return (window, view, try #require(view.chartLayout, "布局没建起来，后面都别测了"))
}

/// 把 `ChartView.animation` 手动跑完。返回步了多少毫秒。
@MainActor
@discardableResult
private func runAnimation(_ v: ChartView, upToMs: Double = 1_000, stepMs: Double = 16) -> Double {
  let t0 = CACurrentMediaTime()
  var elapsed = 0.0
  while let frame = v.animation, elapsed <= upToMs {
    elapsed += stepMs
    if frame(t0 + elapsed / 1000) {
      v.animation = nil
      break
    }
  }
  return elapsed
}

/// 视野右缘现在越界多少像素（0 = 落在硬夹之内）。
@MainActor
private func overscrollPx(_ v: ChartView, _ L: Layout) throws -> Double {
  let s = try #require(v.state)
  let settled = clampView(s.view, series: s.series, plotW: L.plotW, anchor: s.options.anchor)
  return abs(settled.to - s.view.to) / s.view.span * L.plotW
}

/// 走覆盖层那条路的一次轻点（画线开着时，所有触摸都先过画线再回落到图表手势）。
@MainActor
private func drawTap(_ v: ChartView, at q: CGPoint, ms: Double) {
  let t = FakeTouch(q)
  v.drawingTouchesBegan([t], with: FakeEvent(ms: ms))
  v.drawingTouchesEnded([t], with: FakeEvent(ms: ms + 60), cancelled: false)
}

// ---------------------------------------------------------------- 用例

@MainActor
@Suite("A.5 测试缺口 · 真触摸")
struct ChartReviewA5Tests {

  // ------------------------------------------------------------ 1 文字命中

  @Test("1 文字命中：点在标注文字中段能选中它，文字外不命中，两下都不出十字线")
  func case1_noteTextIsHittable() throws {
    let (_, v, _) = try stage()
    v.drawingInteractive = true
    let axes = try #require(v.drawAxes)
    let anchor = CGPoint(x: 90, y: 200)
    var note = Drawing(kind: .note, a: DrawPoint(t: axes.t(atX: 90), p: axes.p(atY: 200)))
    note.text = "这里是一条很长的文字标注，长到离锚点很远"
    v.setDrawings([note])

    let box = try #require(v.drawGeometry(note, axes: axes).labelBoxes.first, "标注得排出一块字")
    // 取字块里离锚点最远的那一头（不是几何中心——文字是绕着锚点排的，中心离锚点很近，
    // 点在那儿命中的会是 9.5pt 的手柄，证明不了「字本身可点」）。
    let farSide = (box.right - Double(anchor.x)) > (Double(anchor.x) - box.left)
      ? box.right - 3 : box.left + 3
    let mid = CGPoint(x: farSide, y: (box.top + box.bottom) / 2)
    #expect(hypot(Double(mid.x) - Double(anchor.x), Double(mid.y) - Double(anchor.y)) > 22,
            "取的这个点要真的离锚点够远，否则命中的是手柄不是字")

    drawTap(v, at: mid, ms: 10_000)
    #expect(v.selectedDrawingID == note.id, "看得见的字必须点得中（A-01）")
    #expect(v.state?.crosshair == nil, "这一下被画线收走了，不该顺手支起十字线")

    drawTap(v, at: CGPoint(x: box.right + 40, y: mid.y), ms: 11_000)
    #expect(v.selectedDrawingID == nil, "文字外不命中：这一下是取消选中")
    #expect(v.state?.crosshair == nil)
  }

  // ------------------------------------------------------------ 2 选中体不吞下层

  @Test("2 选中的矩形不吞下层：内部趋势线可选；点矩形自己的手柄仍然是手柄")
  func case2_selectedFillDoesNotSwallow() throws {
    let (_, v, _) = try stage()
    v.drawingInteractive = true
    let axes = try #require(v.drawAxes)
    func pt(_ x: Double, _ y: Double) -> DrawPoint { DrawPoint(t: axes.t(atX: x), p: axes.p(atY: y)) }
    let rect = Drawing(id: "rect", kind: .rectangle, points: [pt(80, 140), pt(300, 420)])
    let trend = Drawing(id: "trend", kind: .trend, points: [pt(140, 200), pt(260, 360)])
    v.setDrawings([rect, trend])
    v.selectedDrawingID = rect.id

    // 趋势线的中点：在矩形肚子里，离矩形的两个手柄都远得很。
    let onTrend = CGPoint(x: 200, y: 280)
    #expect(hypot(Double(onTrend.x) - 80, Double(onTrend.y) - 140) > Chart.selectedHandlePt)
    #expect(hypot(Double(onTrend.x) - 300, Double(onTrend.y) - 420) > Chart.selectedHandlePt)
    drawTap(v, at: onTrend, ms: 10_000)
    #expect(v.selectedDrawingID == trend.id, "选中的矩形那块填充不许吞掉压在它里面的线（A-02）")

    // 反过来：手柄照样优先。按在矩形自己的角上，开出来的是「拖手柄」，不是「拖整条」。
    v.selectedDrawingID = rect.id
    let onHandle = FakeTouch(CGPoint(x: 80, y: 140))
    v.drawingTouchesBegan([onHandle], with: FakeEvent(ms: 11_000))
    let drag = try #require(v.drawingSessionIfLoaded?.drag, "按在选中矩形的角上该开始拖")
    #expect(drag.id == rect.id)
    #expect(drag.part != .body, "点在手柄上就是手柄，不能退化成整只拖")
    v.drawingTouchesEnded([onHandle], with: FakeEvent(ms: 11_060), cancelled: true)
  }

  // ------------------------------------------------------------ 3 捏合降一指

  @Test("3 捏合降到一指：原地抬手不是轻点，交互结束只响一次")
  func case3_pinchDownToOneFingerIsNotATap() throws {
    let (_, v, L) = try stage(historyState())
    var taps = 0, ended = 0
    v.onTapped = { taps += 1 }
    v.onInteractionEnded = { ended += 1 }

    let a = FakeTouch(CGPoint(x: 150, y: 300)), b = FakeTouch(CGPoint(x: 270, y: 300))
    v.touchesBegan([a], with: FakeEvent(ms: 10_000))
    v.touchesBegan([b], with: FakeEvent(ms: 10_010))
    a.point = CGPoint(x: 130, y: 300); b.point = CGPoint(x: 290, y: 300)
    v.touchesMoved([a, b], with: FakeEvent(ms: 10_030))

    let beforeLift = try #require(v.state).view
    v.touchesEnded([b], with: FakeEvent(ms: 10_050))
    #expect(v.state?.view == beforeLift, "抬掉一根手指不该让图跳一段（G10）")
    #expect(ended == 0, "还有指头按着，这次交互没结束")

    v.touchesEnded([a], with: FakeEvent(ms: 10_070))   // 原地抬起
    #expect(v.state?.crosshair == nil, "捏合的收尾不是轻点，不该支起十字线（A-03）")
    #expect(taps == 0, "更不该报一次 onTapped")
    #expect(ended == 1, "最后一根手指离开，交互结束只响这一次")
    _ = L
  }

  @Test("3 捏合降到一指：剩下那根接着拖，位置按像素连续，没有跳变")
  func case3_pinchDownToOneFingerKeepsDragging() throws {
    let (_, v, L) = try stage(historyState())
    let a = FakeTouch(CGPoint(x: 150, y: 300)), b = FakeTouch(CGPoint(x: 270, y: 300))
    v.touchesBegan([a], with: FakeEvent(ms: 10_000))
    v.touchesBegan([b], with: FakeEvent(ms: 10_010))
    a.point = CGPoint(x: 130, y: 300); b.point = CGPoint(x: 290, y: 300)
    v.touchesMoved([a, b], with: FakeEvent(ms: 10_030))
    v.touchesEnded([b], with: FakeEvent(ms: 10_050))

    let base = try #require(v.state).view
    a.point = CGPoint(x: 110, y: 300)                  // 剩下那根往左挪 20pt
    v.touchesMoved([a], with: FakeEvent(ms: 10_070))
    let now = try #require(v.state).view
    #expect(abs(now.span - base.span) < 1e-6, "接着拖只改位置，不改根宽")
    // 比像素，不比毫秒：`to` 的单位是毫秒，1e-6 ms 这种尺度上比是在比浮点噪声。
    #expect(abs((now.to - base.to) - 20 / L.plotW * base.span) / base.span * L.plotW < 0.001,
            "以剩下那根手指的当前位置重新起手，20pt 就是 20pt")
  }

  // ------------------------------------------------------------ 4 点停回弹

  @Test("4 点停回弹：回弹到一半被点住，抬手后视野仍要落回硬夹之内")
  func case4_tapDuringReboundStillSettles() throws {
    let (_, v, L) = try stage()
    var taps = 0
    v.onTapped = { taps += 1 }
    let s0 = try #require(v.state)
    let spacing0 = s0.view.barSpacing(step: s0.series.step, plotW: L.plotW)

    // 往左拖出末根之外：右缘越界，松手才有回弹。
    let t = FakeTouch(CGPoint(x: 200, y: 300))
    v.touchesBegan([t], with: FakeEvent(ms: 10_000))
    for (i, dx) in [-40.0, -90, -150, -200].enumerated() {
      t.point = CGPoint(x: 200 + dx, y: 300)
      v.touchesMoved([t], with: FakeEvent(ms: 10_000 + Double(i + 1) * 16))
    }
    v.touchesMoved([t], with: FakeEvent(ms: 10_200))   // 原地停一会儿，别甩出去
    let pulled = try overscrollPx(v, L)
    #expect(pulled > 8, "先得真的拉出一片弹性空白")
    v.touchesEnded([t], with: FakeEvent(ms: 10_260))

    _ = try #require(v.animation, "抬手要起一段回弹")
    let t0 = CACurrentMediaTime()
    _ = v.animation?(t0 + 0.16)                        // 320ms 的回弹走到一半
    let halfway = try overscrollPx(v, L)
    #expect(halfway > 0.01 && halfway < pulled, "半路上：回了一些，还没回到位")

    // 就在这半路上点一下：这一下走「轻点」分支，早早 return，没人再管几何（A-04）。
    let tap = FakeTouch(CGPoint(x: 200, y: 300))
    v.touchesBegan([tap], with: FakeEvent(ms: 12_000))
    #expect(v.animation == nil, "手指一落下动画就停")
    v.touchesEnded([tap], with: FakeEvent(ms: 12_060))
    runAnimation(v)

    let s1 = try #require(v.state)
    #expect(try overscrollPx(v, L) < 0.02, "动画演完，视野必须落在 clamp 之内（A-04）")
    #expect(abs(s1.view.barSpacing(step: s1.series.step, plotW: L.plotW) - spacing0) < 1e-6,
            "收尾只归位，不许顺手改根宽")
    #expect(taps <= 1, "这一程最多一次点击语义")
  }

  // ------------------------------------------------------------ 5 两指平移

  @Test("5 两指整体横移：不用先捏，span 不变，右缘按像素走，纵轴一点不动")
  func case5_twoFingerPan() throws {
    var s = a5State()
    s.view = ViewWindow(to: Double(s.series.t0) + Double(s.series.step) * 400,
                        span: Double(s.series.step) * 120)
    let (_, v, L) = try stage(s)
    let before = try #require(v.state)

    let a = FakeTouch(CGPoint(x: 120, y: 300)), b = FakeTouch(CGPoint(x: 240, y: 300))
    v.touchesBegan([a], with: FakeEvent(ms: 10_000))
    v.touchesBegan([b], with: FakeEvent(ms: 10_010))
    a.point = CGPoint(x: 170, y: 300); b.point = CGPoint(x: 290, y: 300)   // 间距不变，整体 +50pt
    v.touchesMoved([a, b], with: FakeEvent(ms: 10_030))

    let after = try #require(v.state)
    #expect(abs(after.view.span - before.view.span) < 1e-6, "两指平移不缩放（A-06）")
    #expect(abs((before.view.to - after.view.to) - 50 / L.plotW * before.view.span)
            / before.view.span * L.plotW < 0.001,
            "中点挪了 50pt，图就挪 50pt")
    // 「Y 不变」＝这次手势一个字都没写进纵轴状态：缩放倍率、中心、log/线性、翻转、
    // 以及手动缩放的锚点全都保持原样。纵轴看上去的高低是自动量程跟着可见区间算出来的，
    // 那是 `view` 变了的结果，不是这次手势直接改的。
    #expect(after.price == before.price, "两指平移不碰价格变换")
    #expect(after.axisScaleAnchor == before.axisScaleAnchor, "也不该顺手按下手动 Y 的锚点")
    #expect(v.state?.crosshair == nil)
  }

  // ------------------------------------------------------------ 9 拖动时映射变

  @Test("9 拖动中行情改了纵轴：端点仍然贴着手指，另一端不动（A-08）")
  func case9_dragFollowsTheLiveAxis() throws {
    let (_, v, _) = try stage()
    v.drawingInteractive = true
    v.drawingMagnet = false                            // 磁吸会把价格吸到 OHLC，这条测的是映射
    let axes0 = try #require(v.drawAxes)
    let line = Drawing(id: "trend", kind: .trend,
                       points: [DrawPoint(t: axes0.t(atX: 120), p: axes0.p(atY: 300)),
                                DrawPoint(t: axes0.t(atX: 260), p: axes0.p(atY: 380))])
    v.setDrawings([line])
    v.selectedDrawingID = line.id

    let t = FakeTouch(CGPoint(x: 260, y: 380))
    v.drawingTouchesBegan([t], with: FakeEvent(ms: 10_000))
    let drag = try #require(v.drawingSessionIfLoaded?.drag, "按在选中线的端点上该开始拖")
    #expect(drag.part == .b)

    // 行情推进：末根冲出一根新高，自动纵轴整个重算。
    var s = try #require(v.state)
    let i = s.series.count - 1
    let top = s.series.high.max() ?? s.series.high[i]
    s.series.high[i] = top * 1.3                       // 必须高过全窗口的顶，自动量程才会跟着抬
    s.series.close[i] = top * 1.25
    v.state = s
    // 2026-09-20 起这一注推不歪纵轴了：手指按着端点的这段时间里价格区间是**钉住**的
    // （`ChartView.beginAxisFreeze`）。原来的现象是「手指没动，线自己往上跑」——
    // 轴在动，线钉在价格上，看上去就是线在动。所以这条用例先钉死冻结本身。
    let frozen = try #require(v.drawAxes)
    let sample = axes0.p(atY: 380)
    #expect(v.axesFrozen, "按住端点 = 坐标钉住")
    #expect(abs(frozen.y(sample) - axes0.y(sample)) < 0.001, "冻结期间纵轴不许被新高推歪")

    let q0 = CGPoint(x: 261, y: 379)                   // 手指只挪 1pt
    t.point = q0
    v.drawingTouchesMoved([t], with: FakeEvent(ms: 10_020))
    let held = try #require(v.drawingSessionIfLoaded?.preview)
    #expect(abs(frozen.x(held.points[1].t) - Double(q0.x)) < 0.5, "横着要贴手")
    #expect(abs(frozen.y(held.points[1].p) - Double(q0.y)) < 0.5, "竖着也要贴手")

    // A-08 本身（`applyDrag` 用**当前这一帧**的轴换算，不是按下那一刻的快照）仍然要守。
    // 把钉子摘掉，刚才那根新高立刻把自动纵轴抬起来，于是新旧两套轴真的不一样了——
    // 这时候手指再挪一下，落点还得贴着手指。
    v.cancelAxisFreeze()
    let axes1 = try #require(v.drawAxes)
    #expect(abs(axes1.y(sample) - axes0.y(sample)) > 5,
            "这一注要真的把纵轴推歪了，否则后面测不出新旧轴的差别")

    let q = CGPoint(x: 262, y: 378)
    t.point = q
    v.drawingTouchesMoved([t], with: FakeEvent(ms: 10_030))
    let preview = try #require(v.drawingSessionIfLoaded?.preview)
    #expect(abs(axes1.x(preview.points[1].t) - Double(q.x)) < 0.5, "横着要贴手")
    // 复现留档：把 `Drag` 里那份按下那一刻的 `axes` 快照临时恢复回去（`applyDrag`
    // 拿它遮蔽实时参数），这一条在 iPhone 17 Pro 模拟器上量到落点偏 97.3px——
    // 手指在 379，线落在 476。不是理论推导，是跑出来的。
    #expect(abs(axes1.y(preview.points[1].p) - Double(q.y)) < 0.5,
            "落地价格必须按**这一帧**的纵轴算，不是按下那一刻的（A-08）")
    #expect(preview.points[0] == line.points[0], "另一端一动不动")

    // 取消完全还原。
    v.drawingTouchesEnded([t], with: FakeEvent(ms: 10_040), cancelled: true)
    #expect(v.drawings.first == line, "取消要还原成按下那一刻的样子")
    #expect(v.canUndoDrawing == false, "取消不进撤销栈")
  }

  @Test("9 拖动中第二根手指落下：转交给捏合，不提交半笔")
  func case9_secondFingerDoesNotCommitHalfEdit() throws {
    let (_, v, _) = try stage()
    v.drawingInteractive = true
    v.drawingMagnet = false
    let axes = try #require(v.drawAxes)
    let line = Drawing(id: "trend", kind: .trend,
                       points: [DrawPoint(t: axes.t(atX: 120), p: axes.p(atY: 300)),
                                DrawPoint(t: axes.t(atX: 260), p: axes.p(atY: 380))])
    v.setDrawings([line])
    v.selectedDrawingID = line.id

    let a = FakeTouch(CGPoint(x: 260, y: 380))
    v.drawingTouchesBegan([a], with: FakeEvent(ms: 10_000))
    a.point = CGPoint(x: 280, y: 340)
    v.drawingTouchesMoved([a], with: FakeEvent(ms: 10_020))
    #expect(v.drawingSessionIfLoaded?.preview != nil)

    let b = FakeTouch(CGPoint(x: 150, y: 300))
    v.drawingTouchesBegan([b], with: FakeEvent(ms: 10_040))
    #expect(v.drawings.first == line, "半截的拖动不许落盘")
    #expect(v.canUndoDrawing == false, "也不许进撤销栈")
    #expect(v.drawingSessionIfLoaded?.drag == nil)
    #expect(v.drawingSessionIfLoaded?.preview == nil)
    #expect(v.state?.drawingPreviewID == nil)
  }

  // ------------------------------------------------------------ 11 回到最新

  @Test("11 回到最新：右缘落在末根 +半根，根宽照旧，且不算用户改的视野")
  func case11_scrollToLatest() throws {
    var s = a5State()
    let step = Double(s.series.step)
    // 先摆一版占位视野，等拿到真实 plotW 再按「根宽 7.3」重算。
    s.view = ViewWindow(to: Double(s.series.t0) + step * 400, span: 120 * step)
    let (_, v, L) = try stage(s)
    let historyView = ViewWindow(to: Double(s.series.t0) + step * 400, span: L.plotW / 7.3 * step)
    var seeded = try #require(v.state); seeded.view = historyView; v.state = seeded
    let spacing = try #require(v.state).view.barSpacing(step: s.series.step, plotW: L.plotW)
    var userChanges = 0, viewChanges = 0
    v.onUserViewChanged = { _ in userChanges += 1 }
    v.onViewChanged = { _ in viewChanges += 1 }

    for animated in [false, true] {
      var back = try #require(v.state)
      back.view = historyView
      v.state = back
      v.scrollToLatest(animated: animated)
      runAnimation(v)
      let now = try #require(v.state)
      #expect(abs(now.view.to - (Double(now.series.lastTime) + step / 2)) < 1,
              "右缘就是末根加半根（rightInset = 0）")
      #expect(abs(now.view.barSpacing(step: now.series.step, plotW: L.plotW) - spacing) < 1e-6,
              "回到最新只动位置，根宽还是用户自己那个")
      #expect(v.isAtLatest, "到位之后「回到最新」按钮该收起来")
    }
    #expect(viewChanges > 0, "视野确实变了，外面要知道")
    #expect(userChanges == 0, "程序滚动不是用户意图，不能报成 onUserViewChanged")
  }

  // ------------------------------------------------------------ 12 轴单双击

  @Test("12 价格轴单击恢复自动纵轴；同位置连着两下才翻转")
  func case12_axisSingleAndDoubleTap() throws {
    var s = a5State()
    s.options.allowMainInversion = true
    s.price.zoom = 2                                   // 先手动定标，好看出「恢复自动」
    let (_, v, L) = try stage(s)
    let axisX = L.plotW + 10.0, axisY = L.main.y + 40
    #expect(!L.hitsAutoFit(x: axisX, y: axisY), "取的这个点别压在「A」徽章上")
    var notices: [String] = []
    v.onNotice = { notices.append($0) }

    axisTap(v, x: axisX, y: axisY, ms: 10_000)
    #expect(v.state?.price.isManual == false, "轴上单击 = 恢复自动纵向缩放")
    #expect(v.state?.price.inverted == false, "一下不翻转")

    axisTap(v, x: axisX, y: axisY, ms: 10_250)         // 250ms、同位置
    #expect(v.state?.price.inverted == true, "连着来的两下才翻转")
    #expect(notices.count == 1, "翻了要说一句，不然用户不知道怎么翻回去")
  }

  @Test("12 中间插了别的动作、或第二下点在别处，都不算双击")
  func case12_axisDoubleTapNeedsTwoCleanTaps() throws {
    var s = a5State()
    s.options.allowMainInversion = true
    let (_, v, L) = try stage(s)
    let axisX = L.plotW + 10.0, axisY = L.main.y + 40

    // ① 两下之间插一次图内拖动：候选作废（A-09）。
    axisTap(v, x: axisX, y: axisY, ms: 10_000)
    let t = FakeTouch(CGPoint(x: 200, y: 300))
    v.touchesBegan([t], with: FakeEvent(ms: 10_050))
    t.point = CGPoint(x: 240, y: 300)
    v.touchesMoved([t], with: FakeEvent(ms: 10_070))
    v.touchesEnded([t], with: FakeEvent(ms: 10_090))
    axisTap(v, x: axisX, y: axisY, ms: 10_200)
    #expect(v.state?.price.inverted == false, "中间插了拖图，这两下不是一对（A-09）")

    // ② 第二下点在轴的另一头：也不是一对。挪 100pt 远超「一个手指宽」的 44pt，
    // 但还留在主图那一格里——跨进副图就成了「点了另一块轴」，测的就不是同一件事了。
    let far = axisY + 100
    #expect(far < L.main.y + L.main.h, "第二下仍要落在主图的价格轴上")
    axisTap(v, x: axisX, y: axisY, ms: 20_000)
    axisTap(v, x: axisX, y: far, ms: 20_150)
    #expect(v.state?.price.inverted == false, "隔了 100pt 的两下是两次「恢复自动」")

    // ③ 老老实实连着两下：翻。
    axisTap(v, x: axisX, y: axisY, ms: 30_000)
    axisTap(v, x: axisX, y: axisY + 20, ms: 30_150)
    #expect(v.state?.price.inverted == true, "同一个手指宽度之内、300ms 之内，才算双击")
  }

  @Test("12 设置里没开翻转就永远不翻；主图与副图互不污染")
  func case12_axisTapRespectsOptionsAndPanes() throws {
    var s = a5State()
    s.options.allowMainInversion = false
    s.options.allowSubInversion = true
    s.price.zoom = 2
    let (_, v, L) = try stage(s)
    let axisX = L.plotW + 10.0, axisY = L.main.y + 40
    let sub = try #require(L.panes.first(where: { $0.indicator != nil }), "这张图得有副图")

    axisTap(v, x: axisX, y: axisY, ms: 10_000)
    axisTap(v, x: axisX, y: axisY + 20, ms: 10_150)
    #expect(v.state?.price.inverted == false, "禁翻转时双击也只做「恢复自动」")
    #expect(v.state?.price.isManual == false)
    #expect(v.state?.subInverted.isEmpty == true, "主图轴上的动作不该碰副图")

    axisTap(v, x: axisX, y: sub.y + sub.h / 2, ms: 11_000)
    #expect(v.state?.subInverted.contains(try #require(sub.indicator)) == true, "副图轴单击翻这块副图")
    #expect(v.state?.price.inverted == false, "副图翻了主图不跟着翻")
  }

  // ------------------------------------------------------------ 13 补历史的门

  @Test("13 补历史的门：一轮只喊一次，失败了下一轮还能再喊，换品种各算各的")
  func case13_askedHistoryGate() throws {
    var s = a5State()
    let step = Double(s.series.step)
    s.view = ViewWindow(to: Double(s.series.t0) + step * 150, span: step * 120)
    let (_, v, _) = try stage(s)
    var asks = 0
    v.onNeedsHistory = { asks += 1 }

    /// 在左缘拖一把：请求要么喊一次，要么一次不喊，反正不会每帧都喊。
    func dragAtLeftEdge(_ baseMs: Double) {
      let t = FakeTouch(CGPoint(x: 120, y: 300))
      v.touchesBegan([t], with: FakeEvent(ms: baseMs))
      for (i, x) in [180.0, 240, 240].enumerated() {
        t.point = CGPoint(x: x, y: 300)
        v.touchesMoved([t], with: FakeEvent(ms: baseMs + Double(i + 1) * 16))
      }
      v.touchesEnded([t], with: FakeEvent(ms: baseMs + 120))
      runAnimation(v)
    }

    dragAtLeftEdge(10_000)
    #expect(asks == 1, "一轮手势只喊一次，不能每帧都去请求")

    // 这一次补历史失败了：序列没长，人还在左缘。手指再落一次就是一次新的意图。
    dragAtLeftEdge(20_000)
    #expect(asks == 2, "上一次没成功就永远不再请求，等于用户被锁死在左缘（A.5 用例 13）")

    // 换品种：另一张图，门跟着重开。
    var other = a5State(symbol: "ETHUSDT", bars: 300, t0: 1_600_000_000_000)
    other.view = ViewWindow(to: Double(other.series.t0) + step * 150, span: step * 120)
    v.state = other
    dragAtLeftEdge(30_000)
    #expect(asks == 3, "上一张图「已经喊过了」记的是上一张图的账")

    // 补历史真的回来了：不在需历史区，就该安静。
    var grown = try #require(v.state)
    var series = grown.series
    let first = series.firstTime
    series.prepend((1...600).map { k in
      let t = first - Int64(k) * series.step
      return Bar(openTime: t, open: 1_000, high: 1_010, low: 990, close: 1_005, volume: 10)
    })
    grown.series = series
    v.state = grown
    dragAtLeftEdge(40_000)
    #expect(asks == 3, "序列够长了就别再喊")
  }

  // ------------------------------------------------------------ 18 放大镜

  @Test("18 放大镜：镜子里那块就是锚点周围，镜头不挡落点，四角都摆得下")
  func case18_loupeFrameNeverCoversTheDropPoint() throws {
    let (_, _, L) = try stage()
    let pane = L.main
    let corners = [
      CGPoint(x: 2, y: pane.y + 2),
      CGPoint(x: L.plotW - 2, y: pane.y + 2),
      CGPoint(x: 2, y: pane.y + pane.h - 2),
      CGPoint(x: L.plotW - 2, y: pane.y + pane.h - 2),
      CGPoint(x: L.plotW / 2, y: pane.y + pane.h / 2),
    ]
    for q in corners {
      let lens = DrawLoupeFrame(at: q, plotW: L.plotW, pane: pane)
      #expect(!lens.box.contains(q), "镜头压在落点上，用户就看不见自己在放哪儿了")
      #expect(lens.box.minX >= 0 && lens.box.maxX <= L.plotW, "镜头不能跑出图区")
      #expect(abs(Double(lens.source.midX) - Double(q.x)) < 1e-9, "放大的那块要正对锚点")
      #expect(abs(Double(lens.source.midY) - Double(q.y)) < 1e-9)
      #expect(abs(Double(lens.source.width) * lens.scale - Double(lens.box.width)) < 1e-9, "倍数要对得上")
    }

    // 上下都摆不下的窄面板：横着让开，照样不挡落点。
    let narrow = Pane(indicator: nil, y: 100, h: 60)
    for x in [60.0, 300.0] {
      let q = CGPoint(x: x, y: 130)
      let lens = DrawLoupeFrame(at: q, plotW: L.plotW, pane: narrow)
      #expect(!lens.box.contains(q), "上下都放不下时要横着让开")
    }
  }

  @Test("18 放大镜的底图抬手就释放，转交给捏合也释放")
  func case18_loupeIsReleasedOnLift() throws {
    let (_, v, _) = try stage()
    v.drawingInteractive = true
    let axes = try #require(v.drawAxes)
    let line = Drawing(id: "trend", kind: .trend,
                       points: [DrawPoint(t: axes.t(atX: 120), p: axes.p(atY: 300)),
                                DrawPoint(t: axes.t(atX: 260), p: axes.p(atY: 380))])
    v.setDrawings([line])
    v.selectedDrawingID = line.id

    let a = FakeTouch(CGPoint(x: 260, y: 380))
    v.drawingTouchesBegan([a], with: FakeEvent(ms: 10_000))
    #expect(v.drawingSessionIfLoaded?.loupe != nil, "拖锚点的时候要有放大镜")
    a.point = CGPoint(x: 262, y: 378)
    v.drawingTouchesMoved([a], with: FakeEvent(ms: 10_020))
    v.drawingTouchesEnded([a], with: FakeEvent(ms: 10_040), cancelled: false)
    #expect(v.drawingSessionIfLoaded?.loupe == nil, "抬手这一刻就该把那张整屏位图扔掉")

    // 取消也一样。
    let b = FakeTouch(CGPoint(x: 260, y: 380))
    v.selectedDrawingID = line.id
    v.drawingTouchesBegan([b], with: FakeEvent(ms: 11_000))
    #expect(v.drawingSessionIfLoaded?.loupe != nil)
    v.drawingTouchesEnded([b], with: FakeEvent(ms: 11_040), cancelled: true)
    #expect(v.drawingSessionIfLoaded?.loupe == nil)

    // 二指介入：这一程转交给捏合，镜子也没用了。
    let c = FakeTouch(CGPoint(x: 260, y: 380))
    v.selectedDrawingID = line.id
    v.drawingTouchesBegan([c], with: FakeEvent(ms: 12_000))
    #expect(v.drawingSessionIfLoaded?.loupe != nil)
    v.drawingTouchesBegan([FakeTouch(CGPoint(x: 150, y: 300))], with: FakeEvent(ms: 12_020))
    #expect(v.drawingSessionIfLoaded?.loupe == nil, "转给捏合之后不该还压着一张位图")
  }

  // ------------------------------------------------------------ 小工具

  /// 价格轴上的一次轻点。位移为 0，所以一定落在「轴上轻点」那条分支。
  private func axisTap(_ v: ChartView, x: Double, y: Double, ms: Double) {
    let t = FakeTouch(CGPoint(x: x, y: y))
    v.touchesBegan([t], with: FakeEvent(ms: ms))
    v.touchesEnded([t], with: FakeEvent(ms: ms + 40))
  }
}
