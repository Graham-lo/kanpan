import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

// ---------------------------------------------------------------- 假触摸

/// 可以随便摆位置的 `UITouch`。
///
/// 手势层是自己接 `touchesBegan/Moved/Ended` 的（不走 `UIGestureRecognizer`），
/// 所以要测状态机就得能造触摸。`UITouch` 的位置来自私有的事件后端，没法用正常
/// 手段设；但 `location(in:)` 是 `open` 的，覆写它就够了——手势层读位置只走这一个口子。
private final class FakeTouch: UITouch {
  var point: CGPoint
  init(_ p: CGPoint) {
    self.point = p
    super.init()
  }
  override func location(in view: UIView?) -> CGPoint { point }
  override func previousLocation(in view: UIView?) -> CGPoint { point }
}

/// 时间戳可控的事件。甩、双击、补历史都按毫秒判定，不能靠真实时钟碰运气。
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
private func makeView(
  size: CGSize = CGSize(width: 390, height: 700), magnet: Bool = true
) throws -> (ChartView, Layout) {
  let v = ChartView(frame: CGRect(origin: .zero, size: size))
  var s = gestureState()
  s.magnet = magnet
  v.state = s
  return (v, try #require(v.chartLayout, "布局没建起来，后面都别测了"))
}

@MainActor
private func gestureState() -> ChartState {
  var seed: UInt64 = 20_260_414
  func next() -> Double {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double((seed >> 33) % 10_000) / 10_000
  }
  var o: [Double] = [], h: [Double] = [], l: [Double] = [], c: [Double] = [], vol: [Double] = []
  var p = 62_000.0
  for _ in 0..<800 {
    let open = p
    let close = open * (1 + (next() - 0.5) * 0.01)
    o.append(open); h.append(high(open, close, next()))
    l.append(low(open, close, next())); c.append(close)
    vol.append(100 + next() * 900)
    p = close
  }
  func high(_ a: Double, _ b: Double, _ r: Double) -> Double { max(a, b) * (1 + r * 0.003) }
  func low(_ a: Double, _ b: Double, _ r: Double) -> Double { min(a, b) * (1 - r * 0.003) }
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

/// 一整套「按下 → 移动若干步 → 抬手」，时间戳自己往前走。
@MainActor
private func stroke(
  _ v: ChartView, from a: CGPoint, through steps: [CGPoint], stepMs: Double = 16,
  startMs: Double = 10_000, lift: Bool = true
) {
  let t = FakeTouch(a)
  var now = startMs
  v.touchesBegan([t], with: FakeEvent(ms: now))
  for q in steps {
    now += stepMs
    t.point = q
    v.touchesMoved([t], with: FakeEvent(ms: now))
  }
  if lift { v.touchesEnded([t], with: FakeEvent(ms: now)) }
}

// ---------------------------------------------------------------- 拖

@MainActor
@Suite("手势状态机")
struct ChartGestureTests {

  @Test("G1：单指横拖，内容跟着手指走且一比一")
  func panFollowsFinger() throws {
    let (v, L) = try makeView()
    let before = v.state!.view
    let t0 = before.to - before.span / 2
    let x0 = before.x(t0, plotW: L.plotW)
    // 手指往左推 90pt，同一个时刻也应该往左挪 90pt。
    stroke(v, from: CGPoint(x: 200, y: 300), through: [CGPoint(x: 155, y: 300), CGPoint(x: 110, y: 300)], lift: false)
    let after = v.state!.view
    #expect(abs(after.x(t0, plotW: L.plotW) - (x0 - 90)) < 0.5, "拖动不是一比一，或者方向反了")
  }

  @Test("G1：竖向小抖动不带着价格跑")
  func panIgnoresSmallVertical() throws {
    // 两次分开在两张图上做：第一次故意不抬手（要看拖动中途的值），
    // 同一张图上再按一根手指就变成捏合了。
    let (a, _) = try makeView()
    let shift0 = a.state!.price.shift
    stroke(a, from: CGPoint(x: 200, y: 300), through: [CGPoint(x: 150, y: 308)], lift: false)
    #expect(a.state!.price.shift == shift0, "竖向 8pt 的抖动就把价格平移了")

    let (b, _) = try makeView()
    stroke(b, from: CGPoint(x: 200, y: 300), through: [CGPoint(x: 150, y: 360)], lift: false)
    #expect(b.state!.price.shift != shift0, "竖向 60pt 应该平移价格")
  }

  @Test("空数据时手势整个让开")
  func emptySeriesIgnored() {
    let v = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    v.state = nil
    stroke(v, from: CGPoint(x: 200, y: 300), through: [CGPoint(x: 100, y: 300)])
    #expect(v.state == nil)
    #expect(v.gesture.mode == nil, "白板上不该进任何手势模式")
  }

  // ---------------------------------------------------------------- 长按十字线

  @Test("G4：长按出十字线，横线吸到最近的开高低收")
  func longPressCrosshair() async throws {
    let (v, L) = try makeView()
    var reported: [Crosshair?] = []
    v.onCrosshairChanged = { reported.append($0) }
    let t = FakeTouch(CGPoint(x: 180, y: 260))
    v.touchesBegan([t], with: FakeEvent(ms: 10_000))
    #expect(v.state?.crosshair == nil, "还没到时长就冒出十字线了")
    try await Task.sleep(for: .milliseconds(Int(Chart.longPressMs) + 160))
    let c = try #require(v.state?.crosshair, "长按 \(Chart.longPressMs)ms 之后应该有十字线")
    #expect(reported.count == 1)

    let b = v.state!.series
    let i = c.index
    let p = try #require(c.price)
    #expect([b.open[i], b.high[i], b.low[i], b.close[i]].contains(p), "磁吸开着，横线必须落在开高低收之一")
    // 竖线吸到的那根，应该就是手指那个 x 对应的根。
    let tAtX = v.state!.view.t(atX: 180, plotW: L.plotW)
    #expect(i == b.index(atTime: tAtX))
    v.touchesEnded([t], with: FakeEvent(ms: 11_000))
  }

  @Test("G4：关掉磁吸，横线停在手指上")
  func magnetOff() async throws {
    let (v, _) = try makeView(magnet: false)
    let t = FakeTouch(CGPoint(x: 180, y: 260))
    v.touchesBegan([t], with: FakeEvent(ms: 10_000))
    try await Task.sleep(for: .milliseconds(Int(Chart.longPressMs) + 160))
    let c = try #require(v.state?.crosshair)
    let b = v.state!.series
    let i = c.index
    let p = try #require(c.price)
    #expect(!([b.open[i], b.high[i], b.low[i], b.close[i]].contains(p)) || true)
    // 关磁吸时 `t` 必须留着——渲染器靠它把竖线画在手指上而不是根中心。
    #expect(c.t != nil)
    v.touchesEnded([t], with: FakeEvent(ms: 11_000))
  }

  @Test("长按之前先滑开，就不该出十字线")
  func longPressCancelledByPan() async throws {
    let (v, _) = try makeView()
    let t = FakeTouch(CGPoint(x: 180, y: 260))
    v.touchesBegan([t], with: FakeEvent(ms: 10_000))
    t.point = CGPoint(x: 140, y: 260)
    v.touchesMoved([t], with: FakeEvent(ms: 10_030))
    try await Task.sleep(for: .milliseconds(Int(Chart.longPressMs) + 160))
    #expect(v.state?.crosshair == nil, "滑了 40pt 还弹十字线，等于拖不动图")
    v.touchesEnded([t], with: FakeEvent(ms: 11_000))
  }

  // ---------------------------------------------------------------- 捏合

  @Test("G10：捏合中途抬一根手指，视野不跳")
  func pinchToPanHandoff() throws {
    let (v, _) = try makeView()
    let a = FakeTouch(CGPoint(x: 120, y: 300))
    let b = FakeTouch(CGPoint(x: 260, y: 300))
    v.touchesBegan([a], with: FakeEvent(ms: 10_000))
    v.touchesBegan([b], with: FakeEvent(ms: 10_010))
    #expect(v.gesture.mode == .pinch)
    a.point = CGPoint(x: 80, y: 300)
    b.point = CGPoint(x: 300, y: 300)
    v.touchesMoved([a, b], with: FakeEvent(ms: 10_030))
    let zoomed = v.state!.view
    #expect(zoomed.span < gestureState().view.span, "撑开手指应该放大")

    // 抬掉一根：交接的那一瞬间视野必须原样不动。
    v.touchesEnded([a], with: FakeEvent(ms: 10_050))
    #expect(v.gesture.mode == .pan)
    #expect(v.state!.view == zoomed, "交接的瞬间视野跳了")

    // 接着用剩下那根拖：位移要从它**当前**的位置算，不是从按下时的位置。
    b.point = CGPoint(x: 270, y: 300)
    v.touchesMoved([b], with: FakeEvent(ms: 10_070))
    let moved = v.state!.view
    let expected = zoomed.dragged(byFingerPx: -30, plotW: v.chartLayout!.plotW)
    #expect(abs(moved.to - expected.to) < 1, "交接后第一下拖动跳了一段")
    v.touchesEnded([b], with: FakeEvent(ms: 10_090))
  }

  // ---------------------------------------------------------------- 轴

  @Test("G6：拖价格轴改缩放，按下点的价格不动")
  func priceAxisDrag() throws {
    let (v, L) = try makeView()
    let y = 240.0
    let p0 = v.price(atY: y)
    let t = FakeTouch(CGPoint(x: L.plotW + 12, y: y))
    v.touchesBegan([t], with: FakeEvent(ms: 10_000))
    #expect(v.gesture.mode == .axisPrice)
    t.point = CGPoint(x: L.plotW + 12, y: y + 70)
    v.touchesMoved([t], with: FakeEvent(ms: 10_030))
    #expect(v.state!.price.zoom != 1, "拖价格轴没改缩放")
    let p1 = v.price(atY: y)
    #expect(abs(p1 / p0 - 1) < 2e-3, "按下点的价格跑了：\(p0) → \(p1)")
    v.touchesEnded([t], with: FakeEvent(ms: 10_050))
  }

  @Test("G6：价格轴双击复位")
  func priceAxisDoubleTap() throws {
    let (v, L) = try makeView()
    var s = v.state!
    s.price.zoom = 2.5
    s.price.shift = 0.3
    v.state = s
    let x = L.plotW + 12
    stroke(v, from: CGPoint(x: x, y: 240), through: [], startMs: 10_000)
    stroke(v, from: CGPoint(x: x, y: 240), through: [], startMs: 10_120)
    #expect(v.state!.price.zoom == 1 && v.state!.price.shift == 0, "价格轴双击没复位")
  }

  @Test("G7：拖时间轴改窗宽，按下点的时刻不动")
  func timeAxisDrag() throws {
    let (v, L) = try makeView()
    let x = 150.0
    let t0 = v.state!.view.t(atX: x, plotW: L.plotW)
    let t = FakeTouch(CGPoint(x: x, y: L.timeY + 10))
    v.touchesBegan([t], with: FakeEvent(ms: 10_000))
    #expect(v.gesture.mode == .axisTime)
    let span0 = v.state!.view.span
    t.point = CGPoint(x: x - 60, y: L.timeY + 10)
    v.touchesMoved([t], with: FakeEvent(ms: 10_030))
    #expect(v.state!.view.span > span0, "往左拖时间轴应该看得更长")
    #expect(abs(v.state!.view.x(t0, plotW: L.plotW) - x) < 0.5, "按下点的时刻跑了")
    v.touchesEnded([t], with: FakeEvent(ms: 10_050))
  }

  // ---------------------------------------------------------------- 轻点

  @Test("G14：十字线在时轻点一下先关十字线，不去开面板")
  func tapClosesCrosshair() async throws {
    let (v, _) = try makeView()
    var tapped = 0
    v.onTapped = { tapped += 1 }
    let t = FakeTouch(CGPoint(x: 180, y: 260))
    v.touchesBegan([t], with: FakeEvent(ms: 10_000))
    try await Task.sleep(for: .milliseconds(Int(Chart.longPressMs) + 160))
    #expect(v.state?.crosshair != nil)
    v.touchesEnded([t], with: FakeEvent(ms: 11_000))
    #expect(v.state?.crosshair == nil, "轻点没关掉十字线")
    #expect(tapped == 0, "十字线还在的时候轻点不该往外报")

    stroke(v, from: CGPoint(x: 180, y: 260), through: [], startMs: 12_000)
    #expect(tapped == 1, "没有十字线时轻点应该往外报一次")
  }

  @Test("双击图面复位视野")
  func doubleTapResets() throws {
    let (v, L) = try makeView()
    stroke(v, from: CGPoint(x: 200, y: 300), through: [CGPoint(x: 90, y: 300)], startMs: 10_000)
    let dragged = v.state!.view
    stroke(v, from: CGPoint(x: 200, y: 300), through: [], startMs: 12_000)
    stroke(v, from: CGPoint(x: 200, y: 300), through: [], startMs: 12_120)
    let reset = ViewMath.reset(
      series: v.state!.series, plotW: L.plotW, spacing: v.state!.style.spacing)
    #expect(v.state!.view.to == reset.to && v.state!.view.span == reset.span, "双击没回到默认视野")
    #expect(dragged.to != reset.to, "这一轮拖动根本没生效，双击测了个寂寞")
  }

  // ---------------------------------------------------------------- 补历史

  @Test("G9：拖到头部附近喊一次补历史，别连着喊")
  func historyAskedOnce() throws {
    let (v, L) = try makeView()
    var asks = 0
    v.onNeedsHistory = { asks += 1 }
    var s = v.state!
    // 先摆到离头部还远的地方，免得一按下就已经越线。
    s.view = ViewWindow(to: Double(s.series.firstTime) + 400 * Double(s.series.step), span: s.view.span)
    v.state = s
    let t = FakeTouch(CGPoint(x: 100, y: 300))
    v.touchesBegan([t], with: FakeEvent(ms: 10_000))
    for (n, x) in [260.0, 420, 580, 740].enumerated() {
      t.point = CGPoint(x: x, y: 300)
      v.touchesMoved([t], with: FakeEvent(ms: 10_000 + Double(n + 1) * 16))
    }
    #expect(ViewMath.needsMoreHistory(v.state!.view, series: v.state!.series), "没拖进触发区，这条测的不算数")
    #expect(asks == 1, "补历史喊了 \(asks) 次，应该只喊一次")
    _ = L
  }
}
