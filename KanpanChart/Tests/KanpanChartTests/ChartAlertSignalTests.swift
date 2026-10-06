import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

// 2026-10-06：画线和提醒互不依赖。画线删了 / 藏起来时，提醒按自己存的那份几何在图上画一条
// 提醒线（细虚线 + 右端铃铛），点它开那条提醒。这里验三件事：哪几条该画、隐藏画线时全画、
// 点得中。假触摸手法同 `ChartDrawingTapDisciplineTests`（那份是 private，这儿照抄）。

private final class SignalTouch: UITouch {
  var point: CGPoint
  init(_ p: CGPoint) { self.point = p; super.init() }
  override func location(in view: UIView?) -> CGPoint { point }
  override func previousLocation(in view: UIView?) -> CGPoint { point }
}

private final class SignalEvent: UIEvent {
  private let ts: TimeInterval
  init(ms: Double) { self.ts = ms / 1000; super.init() }
  override var timestamp: TimeInterval { ts }
}

@MainActor
private func signalState(count: Int = 400) -> ChartState {
  var o: [Double] = [], h: [Double] = [], l: [Double] = [], c: [Double] = [], vol: [Double] = []
  for i in 0..<count {
    let p = 62_000 + sin(Double(i) / 9) * 600
    o.append(p); c.append(p + 40); h.append(p + 120); l.append(p - 120); vol.append(500)
  }
  let series = BarSeries(
    symbol: "BTCUSDT", interval: .h1, t0: 1_700_000_000_000, step: Interval.h1.stepMs,
    open: o, high: h, low: l, close: c, volume: vol)
  let span = Double(series.step) * 120
  return ChartState(
    series: series,
    symbol: SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1),
    view: ViewWindow(to: Double(series.lastTime) + span * 0.08, span: span),
    overlays: [], subs: [])
}

@MainActor
@Suite("提醒线：画线删了 / 藏着时替提醒指位置")
struct ChartAlertSignalTests {
  private func view() throws -> (ChartView, DrawAxes, UIWindow) {
    let v = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    let host = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    host.addSubview(v)
    v.state = signalState()
    v.drawingInteractive = true
    v.drawingEditable = false   // 看行情态：画线手势不收
    return (v, try #require(v.drawAxes, "布局没建起来"), host)
  }

  /// 一条两头延长的水平提醒线，压在图区 y = 300 那个价位上。
  private func signal(_ axes: DrawAxes, id: String = "a1", drawingID: String? = "d1") -> ChartAlertSignal {
    let p = axes.p(atY: 300)
    let line = AlertLine(points: [DrawPoint(t: axes.t(atX: 100), p: p)], extendLeft: true, extendRight: true)
    return ChartAlertSignal(id: id, drawingID: drawingID, lines: [line])
  }

  @Test("挂的那条画线还在、没藏：不画提醒线（画线自己带铃铛）")
  func liveDrawingSuppressesSignal() throws {
    let (v, axes, _) = try view()
    let p = axes.p(atY: 300)
    let line = Drawing(id: "d1", kind: .hline, a: DrawPoint(t: axes.t(atX: 100), p: p))
    v.setDrawings([line])
    v.alertSignals = [signal(axes)]
    #expect(v.shownAlertSignals.isEmpty)
  }

  @Test("画线删了：提醒线照画")
  func deletedDrawingShowsSignal() throws {
    let (v, axes, _) = try view()
    v.alertSignals = [signal(axes)]
    #expect(v.shownAlertSignals.map(\.id) == ["a1"])
  }

  @Test("画线这一条自己藏着：提醒线照画")
  func hiddenDrawingShowsSignal() throws {
    let (v, axes, _) = try view()
    var line = Drawing(id: "d1", kind: .hline, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 300)))
    line.hidden = true
    v.setDrawings([line])
    v.alertSignals = [signal(axes)]
    #expect(v.shownAlertSignals.map(\.id) == ["a1"])
  }

  @Test("隐藏画线（options.drawings 关）：画线在也画提醒线；对比态的百分比轴上一律不画")
  func hiddenLayerShowsAllSignalsButPercentAxisNone() throws {
    let (v, axes, _) = try view()
    v.setDrawings([Drawing(id: "d1", kind: .hline, a: DrawPoint(t: axes.t(atX: 100), p: axes.p(atY: 300)))])
    v.alertSignals = [signal(axes)]
    v.state?.options.drawings = false
    #expect(v.shownAlertSignals.map(\.id) == ["a1"])
    v.state?.percentAxis = true
    #expect(v.shownAlertSignals.isEmpty)
  }

  @Test("点中提醒线的线体或铃铛：交给外面开那条提醒；点空白不认")
  func tapOpensTheAlert() throws {
    let (v, axes, _) = try view()
    v.alertSignals = [signal(axes)]
    var opened: [String] = []
    v.onAlertSignalTap = { opened.append($0) }
    let bell = try #require(v.alertSignalBell(v.alertSignals[0], axes: axes))
    #expect(abs(bell.y - 300) < 1)

    func tap(_ q: CGPoint, ms: Double) {
      let t = SignalTouch(q)
      v.drawingTouchesBegan([t], with: SignalEvent(ms: ms))
      v.drawingTouchesEnded([t], with: SignalEvent(ms: ms + 50), cancelled: false)
    }
    tap(CGPoint(x: 160, y: 306), ms: 10_000)      // 线体旁 6pt
    tap(bell, ms: 20_000)                         // 铃铛
    tap(CGPoint(x: 160, y: 420), ms: 30_000)      // 空白
    #expect(opened == ["a1", "a1"])
  }
}
