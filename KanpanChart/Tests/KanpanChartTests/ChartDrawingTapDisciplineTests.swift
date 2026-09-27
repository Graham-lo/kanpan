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

/// 长按一条线 = 锁上 / 解开（收设置项 F，2026-09-28：样式表里的「锁定位置」挪到图上）。
@MainActor
@Suite("画线：长按线锁定")
struct ChartDrawingLongPressLockTests {
  private func lineView() throws -> (ChartView, Drawing) {
    let (v, axes) = try disciplineView()
    // `disciplineView` 的那扇窗是个局部变量，要等下一次自动释放池排空才真的走——
    // 走的那一刻图离窗、`teardownDrawingLink` 把半截交互（包括等着的长按）全收掉。
    // 这几条用例恰好要跨过那一刻去等定时器，所以先在这儿就让图离窗，别让它半路发生。
    v.removeFromSuperview()
    let line = Drawing(kind: .trend,
                       a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 300)),
                       b: DrawPoint(t: axes.t(atX: 300), p: axes.p(atY: 300)))
    v.setDrawings([line])
    v.drawingEditable = true
    return (v, line)
  }

  /// 按住、（可选）挪一下、等到 `settled` 成立或 3 秒到点再抬手。
  ///
  /// 不拿固定的 600ms 睡：Swift Testing 并行跑套件，主线程被别的用例占着时 400ms 的
  /// 定时器会晚到，固定睡法在那种时候就是随机红。
  private func hold(_ v: ChartView, at q: CGPoint, ms: Double = 10_000, moveTo: CGPoint? = nil,
                    until settled: @MainActor () -> Bool) async throws {
    let t = TapTouch(q)
    v.drawingTouchesBegan([t], with: TapEvent(ms: ms))
    if let moveTo {
      t.point = moveTo
      v.drawingTouchesMoved([t], with: TapEvent(ms: ms + 50))
    }
    try await Task.sleep(for: .milliseconds(450))
    for _ in 0..<50 where !settled() { try await Task.sleep(for: .milliseconds(50)) }
    v.drawingTouchesEnded([t], with: TapEvent(ms: ms + 3_000), cancelled: false)
  }

  @Test("没选中的线：按住不动就锁上、选中它，再按一次解开，震法分得出")
  func holdTogglesLock() async throws {
    let (v, line) = try lineView()
    var events: [DrawingFeedback] = []
    v.onDrawingFeedback = { events.append($0) }
    try await hold(v, at: CGPoint(x: 200, y: 300)) { v.drawings.first?.locked == true }
    #expect(v.drawings.first?.locked == true, "按住没锁上")
    #expect(v.selectedDrawingID == line.id, "锁上之后要选中它，选中栏上才看得见「已锁定」")
    #expect(v.state?.crosshair == nil, "按在线上的长按归锁定，不该再出十字线")
    try await hold(v, at: CGPoint(x: 200, y: 300), ms: 20_000) { v.drawings.first?.locked == false }
    #expect(v.drawings.first?.locked == false, "再按一次没解开")
    #expect(events == [.locked, .unlocked])
    #expect(v.drawings.count == 1)
  }

  @Test("选中的线：按住不动锁上，端点不跟着手指走；锁上之后拖不动")
  func holdOnSelectedLocksWithoutMoving() async throws {
    let (v, line) = try lineView()
    v.selectedDrawingID = line.id
    try await hold(v, at: CGPoint(x: 200, y: 300)) { v.drawings.first?.locked == true }
    let locked = try #require(v.drawings.first)
    #expect(locked.locked)
    #expect(locked.points == line.points, "锁的那一下把线挪了")
  }

  @Test("手指挪开了就不是长按：不锁")
  func movingCancelsTheLock() async throws {
    let (v, _) = try lineView()
    // 挪开之后等满一秒（长按定时器 400ms，就算晚到也早该响过了）。
    try await hold(v, at: CGPoint(x: 200, y: 300), moveTo: CGPoint(x: 240, y: 300)) { false }
    #expect(v.drawings.first?.locked == false)
  }

  @Test("空白处长按照旧出十字线，不碰线")
  func holdOnBlankStillShowsCrosshair() async throws {
    let (v, _) = try lineView()
    let t = TapTouch(CGPoint(x: 200, y: 450))
    v.drawingTouchesBegan([t], with: TapEvent(ms: 10_000))
    try await Task.sleep(for: .milliseconds(450))
    for _ in 0..<50 where v.state?.crosshair == nil { try await Task.sleep(for: .milliseconds(50)) }
    #expect(v.state?.crosshair != nil, "空白处的长按不出十字线了")
    v.drawingTouchesEnded([t], with: TapEvent(ms: 10_700), cancelled: false)
    #expect(v.drawings.first?.locked == false)
  }
}
