import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

// ---------------------------------------------------------------- 假触摸
//
// 和 `ChartDrawingTests` / `ChartGestureTests` 里那两份同一个手法（`UITouch` 的位置
// 来自私有后端，只能覆写 `location(in:)`）。那两份都是 `private`，这儿照抄一份。

private final class TapTouch: UITouch {
  var point: CGPoint
  init(_ p: CGPoint) { self.point = p; super.init() }
  override func location(in view: UIView?) -> CGPoint { point }
  override func previousLocation(in view: UIView?) -> CGPoint { point }
}

private final class TapEvent: UIEvent {
  private let ts: TimeInterval
  init(ms: Double) { self.ts = ms / 1000; super.init() }
  override var timestamp: TimeInterval { ts }
}

@MainActor
private func disciplineState(count: Int = 800) -> ChartState {
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
private func disciplineView() throws -> (ChartView, DrawAxes) {
  let v = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
  // 图得在窗口上：`startDrawingLink` 不在窗口上就不建帧循环，行为和真机一致。
  let host = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
  host.addSubview(v)
  v.state = disciplineState()
  v.drawingInteractive = true
  return (v, try #require(v.drawAxes, "布局没建起来"))
}

@MainActor
private func oneTap(_ v: ChartView, at q: CGPoint, ms: Double = 10_000) {
  let t = TapTouch(q)
  v.drawingTouchesBegan([t], with: TapEvent(ms: ms))
  v.drawingTouchesEnded([t], with: TapEvent(ms: ms + 50), cancelled: false)
}

/// 两指捏合：一起落下、一根一根抬起来。真机上两根手指几乎不可能同一毫秒落地，
/// 但 UIKit 会把同一帧里落下的触点放进同一次 `touchesBegan`，这就是那一次。
@MainActor
private func pinch(_ v: ChartView, ms: Double) {
  let a = TapTouch(CGPoint(x: 140, y: 300)), b = TapTouch(CGPoint(x: 240, y: 340))
  v.drawingTouchesBegan([a, b], with: TapEvent(ms: ms))
  v.drawingTouchesEnded([a], with: TapEvent(ms: ms + 100), cancelled: false)
  v.drawingTouchesEnded([b], with: TapEvent(ms: ms + 160), cancelled: false)
}

/// 「一次点击只许多出一条」以及「不在画线态就不许选中」。
///
/// 两条都是第五轮收尾时留下的观察，2026-09-22 复现并从根因修掉：
/// 落笔只认 `drawingTouchesBegan` 当场收走（`claimed`）的那根手指，
/// 选中只在宿主把画线台打开（`drawingEditable`）的时候才认。
@MainActor
@Suite("画线：一次点击落几条 / 什么时候才选中")
struct ChartDrawingTapDisciplineTests {

  @Test("单锚点工具一次点击只落一条")
  func singleAnchorTapPlacesOne() throws {
    for kind in [Drawing.Kind.hline, .vline, .hray, .note, .crossLine, .priceLabel, .flag,
                 .markerUp, .markerDown, .anchoredVWAP, .anchoredVolumeProfile] {
      let (v, _) = try disciplineView()
      v.drawTool = kind
      oneTap(v, at: CGPoint(x: 180, y: 260))
      #expect(v.drawings.count == 1, "\(kind.rawValue) 一次点击落了 \(v.drawings.count) 条")
    }
  }

  /// 复现序列：连续画开着，点一条水平线，**紧接着**两指捏合缩放。
  ///
  /// 捏合抬手时 `finishUnclaimed` 会拿 `d.beganMs` 判「这是不是一次轻点」，而那个时刻
  /// 从前只在「单指落在图区内」那一条路上更新——两指捏合用的是上一次点击留下的时间戳，
  /// 于是 500ms 内的捏合被判成轻点，手上还举着的单锚点工具就地又落一条。
  @Test("点一条之后马上捏合：捏合不是第二条")
  func pinchAfterTapDoesNotPlaceAnother() throws {
    let (v, _) = try disciplineView()
    v.continuousDrawing = true
    v.drawTool = .hline
    oneTap(v, at: CGPoint(x: 180, y: 260), ms: 10_000)
    #expect(v.drawings.count == 1, "第一下就没画对")
    pinch(v, ms: 10_100)
    #expect(v.drawings.count == 1, "捏合又落了一条，图上成了 \(v.drawings.count) 条")
  }

  /// 手指先按在图上（那时还没工具，整程归图表手势），按着的时候工具才被拿起来。
  /// 抬手时那一下从前会被追认成落笔——用户根本没在这儿点过。
  @Test("手指已经按在图上才拿起工具：这一下不落笔")
  func toolPickedMidTouchDoesNotPlace() throws {
    let (v, _) = try disciplineView()
    let t = TapTouch(CGPoint(x: 180, y: 260))
    v.drawingTouchesBegan([t], with: TapEvent(ms: 10_000))
    v.drawTool = .hline
    v.drawingTouchesEnded([t], with: TapEvent(ms: 10_050), cancelled: false)
    #expect(v.drawings.isEmpty, "凭空落了 \(v.drawings.count) 条")
  }

  @Test("不在画线态：点中一条已有的线不选中")
  func tapDoesNotSelectWhenNotEditable() throws {
    let (v, axes) = try disciplineView()
    let line = Drawing(kind: .trend,
                       a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 300)),
                       b: DrawPoint(t: axes.t(atX: 300), p: axes.p(atY: 300)))
    v.setDrawings([line])
    v.drawingEditable = false
    oneTap(v, at: CGPoint(x: 200, y: 294))
    #expect(v.selectedDrawingID == nil, "不在画线态却把线选中了——宿主会据此把竖屏转成横屏")
  }

  @Test("不在画线态：深链指过来的那条点一下能取消")
  func tapClearsHighlightWhenNotEditable() throws {
    let (v, axes) = try disciplineView()
    let line = Drawing(kind: .trend,
                       a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 300)),
                       b: DrawPoint(t: axes.t(atX: 300), p: axes.p(atY: 300)))
    v.setDrawings([line])
    v.drawingEditable = false
    v.selectedDrawingID = line.id          // 提醒列表点进来那一下
    oneTap(v, at: CGPoint(x: 200, y: 500)) // 空白处点一下
    #expect(v.selectedDrawingID == nil, "高亮收不掉")
  }

  @Test("在画线态：点中还是照样选中")
  func tapStillSelectsWhenEditable() throws {
    let (v, axes) = try disciplineView()
    let line = Drawing(kind: .trend,
                       a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 300)),
                       b: DrawPoint(t: axes.t(atX: 300), p: axes.p(atY: 300)))
    v.setDrawings([line])
    v.drawingEditable = true
    oneTap(v, at: CGPoint(x: 200, y: 294))
    #expect(v.selectedDrawingID == line.id, "画线态下选不中了")
  }
}
