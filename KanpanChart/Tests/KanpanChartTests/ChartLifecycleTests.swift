import CoreGraphics
import Foundation
import KanpanCore
import QuartzCore
import Testing
import UIKit

@testable import KanpanChart

// BT-15：两条 `CADisplayLink` 的生命周期。
//
// 它们都是「注册在主 runloop 上、每帧醒一次」的东西，出了窗口没有任何自然力量会收它们：
// 主图那条原来靠 `didMoveToWindow` 收（只收了一条），画线那条靠「下一帧发现没事干」自灭
// ——而离屏之后根本没有下一帧。宿主被释放时更糟：弱引用让回调变成空操作，link 却一直醒着。
// 这一组用例盯的就是这三件事：不在窗口上不建帧、出窗两条一起收、宿主没了自己作废。

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

private final class FakeEvent: UIEvent {
  private let ts: TimeInterval
  init(ms: Double) {
    self.ts = ms / 1000
    super.init()
  }
  override var timestamp: TimeInterval { ts }
}

@MainActor
private func lifecycleState() -> ChartState {
  var seed: UInt64 = 20_260_919
  func next() -> Double {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double((seed >> 33) % 10_000) / 10_000
  }
  var o: [Double] = [], h: [Double] = [], l: [Double] = [], c: [Double] = [], vol: [Double] = []
  var p = 62_000.0
  for _ in 0..<400 {
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

/// 跑一小段主 runloop，让 `CADisplayLink` 真的醒几帧。
@MainActor
private func spinFrames(_ seconds: TimeInterval = 0.12) {
  RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

// ---------------------------------------------------------------- 用例

@MainActor
@Suite("BT-15 图表帧循环的生命周期")
struct ChartLifecycleTests {

  @Test("离屏时挂上的动画不建帧循环")
  func animationOffscreenBuildsNoLink() {
    let v = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    v.state = lifecycleState()
    #expect(v.window == nil)
    v.animation = { _ in false }  // 一条永远演不完的惯性
    // 没有窗口就没有帧：这半程用户看不见，留着它只会让下次入窗从半截惯性开始，
    // 更要命的是它会在没人清理的地方建起一条 link。
    #expect(v.animation == nil, "离屏挂的动画应该当场丢掉")
    #expect(v.link == nil, "离屏不该建 CADisplayLink")
  }

  @Test("不在窗口上不建画线那条帧循环")
  func drawingLinkOffscreenBuildsNothing() throws {
    let v = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    v.state = lifecycleState()
    v.drawingInteractive = true
    v.drawTool = .trend
    _ = try #require(v.drawAxes, "布局没建起来，后面都别测了")
    v.drawingTouchesBegan([FakeTouch(CGPoint(x: 120, y: 220))], with: FakeEvent(ms: 10_000))
    #expect(v.drawingSessionIfLoaded?.link == nil, "离屏不该建画线的 CADisplayLink")
  }

  @Test("出窗把两条 link 和半截触点一起收掉")
  func leavingWindowTearsDownBothLinks() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    let v = ChartView(frame: window.bounds)
    window.addSubview(v)
    v.state = lifecycleState()
    v.drawingInteractive = true
    v.drawTool = .trend
    _ = try #require(v.drawAxes, "布局没建起来，后面都别测了")

    v.setNeedsRedraw(.all)
    let main = try #require(v.link, "入窗之后主图该有帧循环")
    v.drawingTouchesBegan([FakeTouch(CGPoint(x: 120, y: 220))], with: FakeEvent(ms: 10_000))
    let draw = try #require(v.drawingSessionIfLoaded?.link, "按下之后画线该有帧循环")
    #expect(v.drawingSessionIfLoaded?.claimed != nil, "这根手指应该归画线管")

    v.removeFromSuperview()

    #expect(v.link == nil, "出窗之后主图那条 link 必须收掉")
    #expect(v.drawingSessionIfLoaded?.link == nil, "出窗之后画线那条 link 必须收掉")
    #expect(v.drawingSessionIfLoaded?.claimed == nil, "手指跟着视图一起离开，不能留半截触点")
    #expect(v.drawingSessionIfLoaded?.drag == nil)
    #expect(v.drawingSessionIfLoaded?.preview == nil)

    // 收掉不只是把引用置 nil：两条 link 都不能再醒。
    let mt = main.timestamp, dt = draw.timestamp
    spinFrames()
    #expect(main.timestamp == mt, "主图那条 link 出窗后还在跑帧")
    #expect(draw.timestamp == dt, "画线那条 link 出窗后还在跑帧")
  }

  @Test("宿主连窗一起释放，画线的帧循环不会留下")
  func drawingLinkDiesWithItsHost() throws {
    var link: CADisplayLink?
    weak var probe: ChartView?

    try autoreleasepool {
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
      let v = ChartView(frame: window.bounds)
      window.addSubview(v)
      v.state = lifecycleState()
      v.drawingInteractive = true
      v.drawTool = .trend
      _ = try #require(v.drawAxes, "布局没建起来，后面都别测了")
      v.drawingTouchesBegan([FakeTouch(CGPoint(x: 120, y: 220))], with: FakeEvent(ms: 10_000))
      link = try #require(v.drawingSessionIfLoaded?.link, "按下之后画线该有帧循环")
      probe = v
      // 先确认这条 link 在测试进程里真的会醒，否则后面的「不再醒」毫无意义。
      spinFrames()
      #expect(link!.timestamp > 0, "CADisplayLink 在这台模拟器上根本没跑，用例不成立")
    }

    #expect(probe == nil, "两个 LinkProxy 都必须是弱引用，不然视图根本释放不掉")

    let l = try #require(link)
    spinFrames()          // 这一段里它该被收掉（出窗清理，或者回调发现宿主没了自己作废）
    let t1 = l.timestamp
    spinFrames()
    #expect(l.timestamp == t1, "宿主已经释放，画线那条 link 还在每帧醒来")
  }

  // P2.10：低电量模式下跟手也只给 60 Hz，不进 120 档。
  @Test("低电量模式不进高刷档")
  func lowPowerCapsFrameRate() {
    #expect(ChartView.usesHighFrameRate(wantsHigh: true, lowPower: false))
    #expect(!ChartView.usesHighFrameRate(wantsHigh: true, lowPower: true))
    #expect(!ChartView.usesHighFrameRate(wantsHigh: false, lowPower: false))
    #expect(!ChartView.usesHighFrameRate(wantsHigh: false, lowPower: true))
  }
}
