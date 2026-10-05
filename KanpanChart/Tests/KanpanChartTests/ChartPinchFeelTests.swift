import CoreGraphics
import Foundation
import KanpanCore
import QuartzCore
import Testing
import UIKit

@testable import KanpanChart

// 双指捏合的手感（2026-10-05，横屏画线台起头，竖屏同一套）：
// P1 3pt 死区、越过那一帧只重设基准；P2 竖捏缩价格轴；P3 贴着最新的判据只有一条；
// P5 根宽软边界 + 抬手回弹 + 只震一次，「减少动效」下不越界。
// 视图挂在真窗口上：回弹靠手动步进 `ChartView.animation`，离窗时动画会被整个丢掉。

private final class FakeTouch: UITouch {
  var point: CGPoint
  init(_ p: CGPoint) { self.point = p; super.init() }
  override func location(in view: UIView?) -> CGPoint { point }
  override func previousLocation(in view: UIView?) -> CGPoint { point }
}

private final class FakeEvent: UIEvent {
  private let ts: TimeInterval
  init(ms: Double) { self.ts = ms / 1000; super.init() }
  override var timestamp: TimeInterval { ts }
}

@MainActor
private func pinchSeries(bars: Int = 800) -> BarSeries {
  var seed: UInt64 = 20_261_005
  func next() -> Double {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double((seed >> 33) % 10_000) / 10_000
  }
  var o: [Double] = [], h: [Double] = [], l: [Double] = [], c: [Double] = [], vol: [Double] = []
  var p = 62_000.0
  for _ in 0..<bars {
    let open = p, close = open * (1 + (next() - 0.5) * 0.01)
    o.append(open); h.append(max(open, close) * (1 + next() * 0.003))
    l.append(min(open, close) * (1 - next() * 0.003)); c.append(close)
    vol.append(100 + next() * 900); p = close
  }
  return BarSeries(symbol: "BTCUSDT", interval: .h1, t0: 1_700_000_000_000, step: Interval.h1.stepMs,
                   open: o, high: h, low: l, close: c, volume: vol)
}

/// 横屏画线台那种尺寸（宽、只有主图）。`spacing` 是起手根宽，`history` 往历史挪多少像素。
@MainActor
private func stage(spacing: Double = 8, history: Double = 0, priceMode: PriceMode = .linear)
  throws -> (window: UIWindow, view: ChartView, layout: Layout)
{
  let size = CGSize(width: 800, height: 360)
  let window = UIWindow(frame: CGRect(origin: .zero, size: size))
  let view = ChartView(frame: window.bounds)
  window.addSubview(view)
  let series = pinchSeries()
  var s = ChartState(series: series,
                     symbol: SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1),
                     view: ViewWindow(from: 0, to: 1), overlays: [], subs: [])
  s.price.mode = priceMode
  view.state = s
  let L = try #require(view.chartLayout, "布局没建起来")
  var t = view.state!
  t.view = ViewMath.reset(series: series, plotW: L.plotW, spacing: spacing).dragged(byFingerPx: history, plotW: L.plotW)
  view.state = t
  return (window, view, L)
}

@MainActor
private func runAnimation(_ v: ChartView, upToMs: Double = 1_000) {
  let t0 = CACurrentMediaTime()
  var elapsed = 0.0
  while let frame = v.animation, elapsed <= upToMs {
    elapsed += 16
    if frame(t0 + elapsed / 1000) { v.animation = nil; break }
  }
}

@MainActor
private func spacing(_ v: ChartView, _ L: Layout) -> Double {
  v.state!.view.barSpacing(step: v.state!.series.step, plotW: L.plotW)
}

@MainActor
@Suite("捏合手感（P1–P5）") struct ChartPinchFeelTests {
  @Test("P1 死区 3pt：死区里不缩放、两指平移照走；越过那一帧只换基准，下一帧起按比例")
  func deadZone() throws {
    let (_, v, L) = try stage(history: 2000)
    let start = v.state!.view
    let a = FakeTouch(CGPoint(x: 300, y: 150)), b = FakeTouch(CGPoint(x: 400, y: 150))
    v.touchesBegan([a], with: FakeEvent(ms: 1000))
    v.touchesBegan([b], with: FakeEvent(ms: 1010))
    a.point.x = 299; b.point.x = 401                    // 张开 2pt：死区里
    v.touchesMoved([a, b], with: FakeEvent(ms: 1020))
    #expect(v.state!.view.span == start.span)
    #expect(!v.gesture.pinchActive)
    a.point.x += 30; b.point.x += 30                    // 一起挪 30：平移
    v.touchesMoved([a, b], with: FakeEvent(ms: 1030))
    #expect(v.state!.view.span == start.span)
    let panned = start.dragged(byFingerPx: 30, plotW: L.plotW)
    #expect(abs(v.state!.view.to - panned.to) / start.span * L.plotW < 0.01)
    a.point.x -= 2; b.point.x += 2                      // 张开 6pt：越过死区
    v.touchesMoved([a, b], with: FakeEvent(ms: 1040))
    #expect(v.gesture.pinchActive)
    #expect(v.gesture.pinchAxis == .time)
    #expect(v.state!.view.span == start.span, "越过那一帧不缩放，不跳")
    let sx = b.point.x - a.point.x
    a.point.x -= sx / 4; b.point.x += sx / 4            // 横向张开 1.5 倍
    v.touchesMoved([a, b], with: FakeEvent(ms: 1050))
    #expect(abs(v.state!.view.span - start.span / 1.5) / start.span < 1e-6)
    v.touchesEnded([a, b], with: FakeEvent(ms: 1060))
  }

  @Test("P2 时间轴只看横向张开：斜着捏，纵向那一半不带根宽")
  func timeUsesHorizontalSpreadOnly() throws {
    let (_, v, _) = try stage(history: 2000)
    let start = v.state!.view
    let a = FakeTouch(CGPoint(x: 300, y: 100)), b = FakeTouch(CGPoint(x: 400, y: 200))
    v.touchesBegan([a, b], with: FakeEvent(ms: 1000))
    a.point = CGPoint(x: 295, y: 100); b.point = CGPoint(x: 405, y: 200)
    v.touchesMoved([a, b], with: FakeEvent(ms: 1010))   // 越过死区（横向 +10）
    #expect(v.gesture.pinchAxis == .time)
    a.point = CGPoint(x: 295, y: 60); b.point = CGPoint(x: 405, y: 240)  // 只竖着张开
    v.touchesMoved([a, b], with: FakeEvent(ms: 1020))
    #expect(abs(v.state!.view.span - start.span) / start.span < 1e-9)
    #expect(v.state!.price.zoom == 1)
    v.touchesEnded([a, b], with: FakeEvent(ms: 1030))
  }

  @Test("P2 竖捏缩价格轴：绕两指中点那个价位，时间轴不动，进的是手动态", arguments: [PriceMode.linear, .log])
  func verticalPinchZoomsPrice(_ mode: PriceMode) throws {
    let (_, v, L) = try stage(history: 2000, priceMode: mode)
    let start = v.state!.view
    let midY = L.main.y + L.main.h * 0.4
    let a = FakeTouch(CGPoint(x: 400, y: midY - 60)), b = FakeTouch(CGPoint(x: 410, y: midY + 60))
    v.touchesBegan([a, b], with: FakeEvent(ms: 1000))
    a.point.y -= 5; b.point.y += 5                      // 纵向 +10：越过死区，定为价格轴
    v.touchesMoved([a, b], with: FakeEvent(ms: 1010))
    #expect(v.gesture.pinchAxis == .price)
    let anchor = v.price(atY: midY)
    a.point.y -= 35; b.point.y += 35                    // 130 → 200
    v.touchesMoved([a, b], with: FakeEvent(ms: 1020))
    #expect(abs(v.state!.price.zoom - 200.0 / 130) < 1e-6)
    #expect(v.state!.price.isManual)
    #expect(v.state!.view == start, "竖捏不碰时间轴")
    #expect(abs(v.price(atY: midY) - anchor) / anchor < 1e-6, "中点底下的价位挪了")
    // 两指一起往上挪 20：价位跟着中点走。
    a.point.y -= 20; b.point.y -= 20
    v.touchesMoved([a, b], with: FakeEvent(ms: 1030))
    #expect(abs(v.price(atY: midY - 20) - anchor) / anchor < 1e-6)
    // 捏回去：倍数靠近 1 吸回自动贴合。
    a.point.y += 35; b.point.y -= 35
    v.touchesMoved([a, b], with: FakeEvent(ms: 1040))
    #expect(v.state!.price.zoom == 1)
    #expect(!v.state!.price.isManual)
    v.touchesEnded([a, b], with: FakeEvent(ms: 1050))
  }

  @Test("P2 竖捏但两指中点不在主图里：照旧按时间轴算")
  func verticalPinchOutsideMainStaysTime() throws {
    let (_, v, L) = try stage(history: 2000)
    let y = L.main.y + L.main.h + 6                     // 时间刻度那一条
    let a = FakeTouch(CGPoint(x: 400, y: y - 60)), b = FakeTouch(CGPoint(x: 410, y: y + 60))
    v.touchesBegan([a, b], with: FakeEvent(ms: 1000))
    a.point.y -= 5; b.point.y += 5
    v.touchesMoved([a, b], with: FakeEvent(ms: 1010))
    #expect(v.gesture.pinchAxis == .time)
    v.touchesEnded([a, b], with: FakeEvent(ms: 1020))
  }

  @Test("P3 贴着最新：末根钉在右缘，中点漂移不算；看历史：绕中点缩、跟着中点走")
  func pinnedVersusHistory() throws {
    do {
      let (_, v, L) = try stage(spacing: 8)
      let last = Double(v.state!.series.lastTime)
      let a = FakeTouch(CGPoint(x: 300, y: 150)), b = FakeTouch(CGPoint(x: 400, y: 150))
      v.touchesBegan([a, b], with: FakeEvent(ms: 1000))
      a.point.x = 290; b.point.x = 410
      v.touchesMoved([a, b], with: FakeEvent(ms: 1010))
      for k in 1...6 {                                  // 一边捏开一边往左偏
        a.point.x -= 12 + 6; b.point.x += 12 - 6
        v.touchesMoved([a, b], with: FakeEvent(ms: 1010 + Double(k) * 10))
        let sp = spacing(v, L)
        #expect(abs(v.state!.view.x(last, plotW: L.plotW) + sp / 2 - L.plotW) < 1e-6, "第 \(k) 帧末根离开了右缘")
      }
      v.touchesEnded([a, b], with: FakeEvent(ms: 1100))
    }
    do {
      let (_, v, L) = try stage(spacing: 8, history: 2000)
      let a = FakeTouch(CGPoint(x: 300, y: 150)), b = FakeTouch(CGPoint(x: 400, y: 150))
      v.touchesBegan([a, b], with: FakeEvent(ms: 1000))
      a.point.x = 290; b.point.x = 410
      v.touchesMoved([a, b], with: FakeEvent(ms: 1010))
      let t = v.state!.view.t(atX: 350, plotW: L.plotW)
      a.point.x = 260; b.point.x = 480                  // 张开、中点 350 → 370
      v.touchesMoved([a, b], with: FakeEvent(ms: 1020))
      #expect(abs(v.state!.view.x(t, plotW: L.plotW) - 370) < 1e-6, "中点底下那一刻没跟着中点走")
      v.touchesEnded([a, b], with: FakeEvent(ms: 1030))
    }
  }

  @Test("P5 软边界：越过 40 带阻尼、只震一次，抬手绕捏的那一点弹回 40")
  func overshootAndRebound() throws {
    let (_, v, L) = try stage(spacing: 36, history: 3000)
    let hi = AICoinBehavior.maximumSpacing
    let buzz0 = ChartHaptics.boundaryCount
    let a = FakeTouch(CGPoint(x: 350, y: 150)), b = FakeTouch(CGPoint(x: 450, y: 150))
    v.touchesBegan([a, b], with: FakeEvent(ms: 1000))
    a.point.x = 345; b.point.x = 455
    v.touchesMoved([a, b], with: FakeEvent(ms: 1010))
    var widths: [Double] = []
    for k in 1...8 {
      a.point.x -= 15; b.point.x += 15
      v.touchesMoved([a, b], with: FakeEvent(ms: 1010 + Double(k) * 10))
      widths.append(spacing(v, L))
    }
    #expect(widths.last! > hi, "没越过 40")
    #expect(widths.allSatisfy { $0 < hi * (1 + ViewMath.zoomOvershoot) }, "越过了 1.15 倍")
    #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 })
    #expect(ChartHaptics.boundaryCount - buzz0 == 1, "顶到边界该只震一次")
    let t = v.state!.view.t(atX: 400, plotW: L.plotW)
    v.touchesEnded([a, b], with: FakeEvent(ms: 1200))
    #expect(v.animation != nil, "抬手该回弹")
    runAnimation(v)
    #expect(abs(spacing(v, L) - hi) < 1e-9)
    #expect(abs(v.state!.view.x(t, plotW: L.plotW) - 400) < 1e-6, "回弹不该绕右缘，该绕捏的那一点")
  }

  @Test("P5 软越界时抬掉一根：先收回 40 再接着拖，不跳")
  func overshootHandoffSnaps() throws {
    let (_, v, L) = try stage(spacing: 38, history: 3000)
    let a = FakeTouch(CGPoint(x: 350, y: 150)), b = FakeTouch(CGPoint(x: 450, y: 150))
    v.touchesBegan([a, b], with: FakeEvent(ms: 1000))
    a.point.x = 345; b.point.x = 455
    v.touchesMoved([a, b], with: FakeEvent(ms: 1010))
    a.point.x = 300; b.point.x = 500
    v.touchesMoved([a, b], with: FakeEvent(ms: 1020))
    #expect(spacing(v, L) > AICoinBehavior.maximumSpacing)
    v.touchesEnded([a], with: FakeEvent(ms: 1030))
    #expect(abs(spacing(v, L) - AICoinBehavior.maximumSpacing) < 1e-9)
    let held = v.state!.view
    b.point.x -= 20
    v.touchesMoved([b], with: FakeEvent(ms: 1040))
    #expect(v.state!.view.span == held.span)
    #expect(abs(v.state!.view.to - held.dragged(byFingerPx: -20, plotW: L.plotW).to) / held.span * L.plotW < 0.01)
    v.touchesEnded([b], with: FakeEvent(ms: 1050))
  }

  @Test("P5 减少动效：硬停在边界上，不越界、不回弹")
  func reduceMotionNoOvershoot() throws {
    ChartHaptics.reduceMotionOverride = true
    defer { ChartHaptics.reduceMotionOverride = nil }
    let (_, v, L) = try stage(spacing: 2, history: 3000)
    let a = FakeTouch(CGPoint(x: 300, y: 150)), b = FakeTouch(CGPoint(x: 500, y: 150))
    v.touchesBegan([a, b], with: FakeEvent(ms: 1000))
    a.point.x = 305; b.point.x = 495
    v.touchesMoved([a, b], with: FakeEvent(ms: 1010))
    a.point.x = 390; b.point.x = 410                    // 捏拢到 1/10
    v.touchesMoved([a, b], with: FakeEvent(ms: 1020))
    #expect(abs(spacing(v, L) - AICoinBehavior.minimumSpacing) < 1e-9)
    // 往回张开一点马上就有反应：没在边界外面白攒一截。
    a.point.x = 380; b.point.x = 420
    v.touchesMoved([a, b], with: FakeEvent(ms: 1030))
    #expect(abs(spacing(v, L) - AICoinBehavior.minimumSpacing * 2) < 1e-6)
    v.touchesEnded([a, b], with: FakeEvent(ms: 1040))
    #expect(v.animation == nil)
  }
}
