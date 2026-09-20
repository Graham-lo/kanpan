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
@Suite("AICoin 手势状态机") struct ChartGestureTests {
  @Test("单击显示，第二次关闭；X吸柱中心、Y保留选中价")
  func taps() throws {
    let (v, _) = try makeView(magnet: false)
    stroke(v, from: CGPoint(x: 180, y: 120), through: [])
    let c = try #require(v.state?.crosshair)
    #expect(c.t == nil && c.price != nil)
    stroke(v, from: CGPoint(x: 180, y: 120), through: [], startMs: 11000)
    #expect(v.state?.crosshair == nil)
  }
  @Test("长按抬手保留选择")
  func longPress() async throws {
    let (v, _) = try makeView(magnet: false)
    let touch = FakeTouch(CGPoint(x: 180, y: 120))
    v.touchesBegan([touch], with: FakeEvent(ms: 10000))
    try await Task.sleep(for: .milliseconds(560))
    #expect(v.state?.crosshair != nil)
    v.touchesEnded([touch], with: FakeEvent(ms: 11000))
    #expect(v.state?.crosshair != nil)
  }
  @Test("十字中心才移线，远处横拖清选择并移动历史窗口")
  func crosshairDragTarget() throws {
    for pane in [IndicatorID?.none, .some(.vol)] {
      for inverted in [false, true] {
        for mode in [CrossPriceMode.selected, .close] {
          let (v, L) = try makeView(magnet: false)
          var s = v.state!
          s.options.crossPrice = mode; s.price.inverted = inverted
          if inverted { s.subInverted = [.vol] }
          s.view = s.view.dragged(byFingerPx: 400, plotW: L.plotW)
          v.state = s
          let y = pane == nil ? 120 : L.panes[1].y + L.panes[1].h / 2
          stroke(v, from: CGPoint(x: 150, y: y), through: [])
          let before = v.state!.view
          let center = try #require(v.renderer?.crosshairCenter(size: v.bounds.size))
          let index = try #require(v.state?.crosshair?.index)
          stroke(v, from: center, through: [CGPoint(x: center.x + 45, y: center.y + 12)])
          #expect(v.state!.view == before)
          #expect(v.state?.crosshair?.index != index)
          let far = CGPoint(x: 50, y: y)
          #expect(!v.hitsCrosshairCenter(far))
          stroke(v, from: far, through: [CGPoint(x: 120, y: y)], startMs: 12000, lift: false)
          #expect(v.state?.crosshair == nil)
          #expect(v.state!.view.from < before.from)
          #expect(v.gesture.mode == .pan)
        }
      }
    }
  }

  @Test("自动Y下纵向拖动不偷偷修改Y或X")
  func verticalAuto() throws {
    let (v, _) = try makeView()
    let before = v.state!
    stroke(v, from: CGPoint(x: 180, y: 120), through: [CGPoint(x: 185, y: 180)], lift: false)
    #expect(v.state!.price == before.price && v.state!.view == before.view)
    #expect(v.gesture.mode == .parentScroll)
  }
  @Test("价格轴拖动进入归一化手动Y，A只复位Y")
  func axis() throws {
    let (v, L) = try makeView()
    let x = L.plotW + 10
    stroke(v, from: CGPoint(x: x, y: 120),
           through: [CGPoint(x: x, y: 130), CGPoint(x: x, y: 190)])
    #expect(v.state!.price.isManual)
    let view = v.state!.view
    v.resetPriceScale()
    #expect(!v.state!.price.isManual && v.state!.view == view)
    // 双击价格轴翻转：`allowMainInversion` 现在默认关（一次误触把整张图倒过来，
    // 代价远大于用处，见 `handleAxisTap`），所以先要有人把它打开这一下才算数。
    // 两下之间必须在 300ms 以内，否则各算各的单击（单击 = 恢复自动纵向缩放）。
    func doubleTapAxis(at ms: Double) {
      stroke(v, from: CGPoint(x: x, y: 120), through: [], startMs: ms)
      stroke(v, from: CGPoint(x: x, y: 120), through: [], startMs: ms + 100)
    }
    doubleTapAxis(at: 12000)
    #expect(!v.state!.price.inverted, "默认关着还翻了")
    v.state?.options.allowMainInversion = true
    doubleTapAxis(at: 22000)
    #expect(v.state!.price.inverted)
    doubleTapAxis(at: 32000)
    #expect(!v.state!.price.inverted, "再双击一次该翻回来")
  }
  @Test("历史缩放抬起一指后不跳变")
  func pinchHandoff() throws {
    let (v, L) = try makeView()
    var state = v.state!
    state.view = ViewMath.reset(series: state.series, plotW: L.plotW, spacing: 4)
      .dragged(byFingerPx: 500, plotW: L.plotW)
    v.state = state
    let a = FakeTouch(CGPoint(x: 120, y: 120)), b = FakeTouch(CGPoint(x: 260, y: 120))
    v.touchesBegan([a], with: FakeEvent(ms: 10000))
    v.touchesBegan([b], with: FakeEvent(ms: 10010))
    a.point.x = 80; b.point.x = 300
    v.touchesMoved([a,b], with: FakeEvent(ms: 10030))
    let zoomed = v.state!.view
    #expect(zoomed.span < state.view.span)
    v.touchesEnded([a], with: FakeEvent(ms: 10050))
    #expect(v.state!.view == zoomed && v.gesture.mode == .pan)
    b.point.x -= 30
    v.touchesMoved([b], with: FakeEvent(ms: 10070))
    let expected = zoomed.dragged(byFingerPx: -30, plotW: L.plotW)
    #expect(abs(v.state!.view.to - expected.to) < 1)
  }
  @Test("双指小间距起步保留初始基准，越过门槛后缩放")
  func pinchFromSmallSpan() throws {
    let (v, _) = try makeView()
    v.traitOverrides.displayScale = 3
    let initial = v.state!.view
    let a = FakeTouch(CGPoint(x: 173, y: 120))
    let b = FakeTouch(CGPoint(x: 187, y: 120))
    v.touchesBegan([a], with: FakeEvent(ms: 10000))
    v.touchesBegan([b], with: FakeEvent(ms: 10010))
    a.point.x = 172; b.point.x = 188
    v.touchesMoved([a, b], with: FakeEvent(ms: 10020))
    #expect(v.gesture.pinchD0 == 14)
    #expect(v.state!.view == initial)
    a.point.x = 166; b.point.x = 194
    v.touchesMoved([a, b], with: FakeEvent(ms: 10030))
    #expect(v.gesture.pinchActive)
    #expect(abs(v.state!.view.span - initial.span / 2) < 1)
    v.touchesEnded([a, b], with: FakeEvent(ms: 10040))
  }
  @Test("实时末根更新与同数历史替换均刷新指标")
  func indicatorsRefresh() throws {
    var state = gestureState()
    state.overlays = [.ma]; state.params[.ma] = [10]
    var renderer = ChartRenderer(state: state)
    let old = try #require(renderer.engine[.ma]?.lines.first?.last)
    state.series.close[state.series.count - 1] += 100
    renderer.state = state
    let tail = try #require(renderer.engine[.ma]?.lines.first?.last)
    #expect(abs(tail - old - 10) < 1e-6)
    state.series.close[state.series.count - 5] += 200
    renderer.state = state
    let replaced = try #require(renderer.engine[.ma]?.lines.first?.last)
    #expect(abs(replaced - tail - 20) < 1e-6)
  }
}

// ---------------------------------------------------------------- 图外挪一根

/// 读数行右端那两颗「‹ 上一根 / 下一根 ›」按下去之后发生的事（§P3-7）。
///
/// 它们存在的理由是手指做不到这件事：一根 K 线只有几个点宽的时候，想精确地挪一根
/// 只能靠按钮。所以这套用例盯的不是「有没有动」，而是「只动了该动的那一维」——
/// 换的是根，价格那一维照十字线自己的规矩走。
@MainActor @Suite("十字线按根挪") struct CrosshairStepTests {
  /// 按一次挪一根；磁吸开着就贴上新那根的收盘。
  @Test("一次一根，磁吸跟着新那根的收盘走")
  func stepsOneBar() throws {
    let (v, _) = try makeView(magnet: true)
    stroke(v, from: CGPoint(x: 180, y: 120), through: [])
    let start = try #require(v.state?.crosshair?.index)
    v.moveCrosshair(by: 1)
    let after = try #require(v.state?.crosshair)
    #expect(after.index == start + 1)
    #expect(after.price == v.state?.series.close[start + 1])
    // 竖线得站到新那根的中心上：`t` 留着旧时刻就等于线没挪。
    #expect(after.t == nil)
    v.moveCrosshair(by: -1)
    #expect(v.state?.crosshair?.index == start)
  }

  /// 人手动摆的价位不因为挪根被改写——挪的是「哪一根」，不是「哪个价」。
  @Test("手动摆的价位挪根时原地不动")
  func keepsManualPrice() throws {
    let (v, _) = try makeView(magnet: false)
    stroke(v, from: CGPoint(x: 180, y: 120), through: [])
    var s = try #require(v.state)
    let index = try #require(s.crosshair?.index)
    let price = s.series.close[index] * 1.05  // 明显不等于收盘，就是人摆上去的
    s.crosshair?.price = price
    v.state = s
    v.moveCrosshair(by: 1)
    #expect(v.state?.crosshair?.index == index + 1)
    #expect(v.state?.crosshair?.price == price)
  }

  /// 到头就停在头上，不循环；没有十字线时按了也不该凭空变出一条。
  @Test("到头停住不循环，没十字线时什么也不做")
  func clampsAndIgnores() throws {
    let (v, _) = try makeView(magnet: true)
    stroke(v, from: CGPoint(x: 180, y: 120), through: [])
    var s = try #require(v.state)
    let last = s.series.count - 1
    s.crosshair?.index = last
    v.state = s
    v.moveCrosshair(by: 1)
    #expect(v.state?.crosshair?.index == last)
    s = try #require(v.state)
    s.crosshair?.index = 0
    v.state = s
    v.moveCrosshair(by: -1)
    #expect(v.state?.crosshair?.index == 0)
    v.clearCrosshair()
    v.moveCrosshair(by: 1)
    #expect(v.state?.crosshair == nil)
  }

  /// 一路挪到屏幕外面时视野跟着推一根，那根始终留在眼前。
  @Test("挪出可视区时视野跟着推")
  func pushesViewport() throws {
    let (v, L) = try makeView(magnet: true)
    stroke(v, from: CGPoint(x: 180, y: 120), through: [])
    let before = try #require(v.state).view
    var moved = false
    for _ in 0..<60 {
      v.moveCrosshair(by: -1)
      let s = try #require(v.state)
      let c = try #require(s.crosshair)
      let x = s.view.x(Double(s.series.time(at: c.index)), plotW: L.plotW)
      #expect(x > -0.5 && x < L.plotW + 0.5, "挪到屏幕外面去了，视野没跟上")
      if s.view.from < before.from { moved = true }
    }
    #expect(moved, "一直往左挪，视野一次都没动")
  }
}
