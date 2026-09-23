import Foundation
import Testing
@testable import KanpanCore

@Suite("AICoin 冷启动与尺寸")
struct AICoinBehaviorTests {
  private func series(start: Int64, count: Int = 600) -> BarSeries {
    BarSeries(symbol: "BTCUSDT", interval: .h1, bars: (0..<count).map {
      Bar(openTime: start + Int64($0) * 3_600_000, open: 100, high: 120, low: 90, close: 110, volume: 1)
    })
  }
  @Test("快照补到现在时跟随末根；历史视野不跳")
  func snapshotFollow() {
    let old = series(start: 1_700_000_000_000)
    let new = series(start: old.firstTime + 48 * old.step)
    let view = ViewMath.reset(series: old, plotW: 352, spacing: 4)
    let next = AICoinBehavior.reconcile(view, from: old, to: new, plotW: 352)
    #expect(next.span == view.span)
    #expect(abs(view.x(Double(old.lastTime), plotW: 352) - next.x(Double(new.lastTime), plotW: 352)) < 1e-8)
    let history = ViewWindow(to: Double(old.lastTime - 100 * old.step), span: view.span)
    #expect(AICoinBehavior.reconcile(history, from: old, to: new, plotW: 352) == history)
  }
  @Test("纯未来视野和短指标数组不越界，对数倒置可往返")
  func rangeBounds() {
    let b = series(start: 1_700_000_000_000)
    let v = ViewWindow(to: Double(b.lastTime + b.step * 100), span: Double(b.step * 10))
    var transform = PriceTransform(mode: .log)
    transform.inverted = true
    let range = priceRange(view: v, series: b, overlayValues: [[], [100]],
                           transform: transform, paneHeight: 300)
    #expect(range.lo > 0 && range.hi > range.lo)
    let pane = Pane(indicator: nil, y: 0, h: 300)
    #expect(yOf(120, pane: pane, range: range, mode: .log) > yOf(90, pane: pane, range: range, mode: .log))
    #expect(abs(pOf(yOf(110, pane: pane, range: range, mode: .log), pane: pane, range: range, mode: .log) - 110) < 1e-8)
  }
}
