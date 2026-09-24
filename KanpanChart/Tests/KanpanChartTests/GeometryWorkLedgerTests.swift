import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

// MARK: - 几何缓存的账本（审查 23.4 的数据口径）
//
// 同一份重负载 state（3 副图 + 主副图都藏了输出），每种交互各走 100 步，每步按
// `ChartView` 的三层各画一帧，数「真的算了一遍」的次数。只打印不断言——这张表要在
// 改之前的代码上也能原样跑一遍，前后两份读数对着看。断言在 `CrosshairWorkTests`。
// 不圈 DEBUG：它不断言，Release 下计数恒为 0 只是打印一张零表，不会假绿也不会红
// （Release 测试名册只收「整体关掉」有理由的套件，见 `ReleaseTestRosterTests`）。
@MainActor @Suite(.serialized) struct GeometryWorkLedgerTests {
  let size = CGSize(width: 393, height: 780)

  func heavyState() -> ChartState {
    var s = Evidence.state(dark: false, size: size, overlays: [.ma, .ema], subs: [.vol, .macd, .rsi])
    s.params[.ema] = [12, 26, 60]
    s.hiddenOutputs = [.ma: [1], .ema: [2], .macd: [0], .rsi: [1]]
    s.drawings = [Drawing(kind: .trend, points: [
      DrawPoint(t: Double(s.series.time(at: 150)), p: s.series.close[150]),
      DrawPoint(t: Double(s.series.time(at: 190)), p: s.series.close[190]),
    ])]
    return s
  }

  func frame(_ renderer: ChartRenderer) {
    let f = UIGraphicsImageRendererFormat.preferred()
    f.scale = 3
    f.opaque = false
    _ = UIGraphicsImageRenderer(size: size, format: f).image { ctx in
      renderer.drawPlot(in: ctx.cgContext, size: size, scale: 3)
      renderer.drawLive(in: ctx.cgContext, size: size, scale: 3)
      renderer.drawCross(in: ctx.cgContext, size: size, scale: 3)
    }
  }

  func run(_ label: String, _ step: (inout ChartState, Int) -> Void) -> [ChartWork: Int] {
    var s = heavyState()
    var renderer = ChartRenderer(state: s)
    frame(renderer)
    ChartWorkCounter.reset()
    let clock = ContinuousClock()
    let start = clock.now
    for k in 0..<100 {
      step(&s, k)
      renderer.state = s
      frame(renderer)
    }
    let ms = (clock.now - start) / .milliseconds(1)
    print(ChartWorkCounter.line("ledger \(label) steps=100 ms=\(String(format: "%.1f", ms))"))
    return ChartWorkCounter.snapshot()
  }

  @Test("账本：拖图 / 捏合 / 分隔线 / 画线拖动 / 十字线 / tick / 换皮肤")
  func ledger() {
    let step = { (s: ChartState) in Double(s.series.step) }
    _ = run("pan") { s, _ in s.view.to -= step(s) * 0.5 }
    _ = run("zoom") { s, k in s.view.span *= (k % 2 == 0 ? 1.01 : 0.995) }
    _ = run("divider") { s, k in s.subScale[.macd] = 1 + Double(k % 20) * 0.01 }
    _ = run("drawing-drag") { s, k in s.drawings[0].points[1].p *= (k % 2 == 0 ? 1.001 : 0.9995) }
    _ = run("crosshair") { s, k in s.crosshair = Crosshair(index: 120 + k % 60, price: s.series.close[120 + k % 60]) }
    _ = run("tick") { s, k in
      var t = s.series
      let last = t.bar(at: t.count - 1)
      t.replaceLast(with: Bar(openTime: last.openTime, open: last.open, high: last.high, low: last.low,
                              close: last.close * (k % 2 == 0 ? 1.0001 : 0.9999), volume: last.volume + 1))
      s.series = t
    }
    _ = run("skin") { s, k in s.dark = k % 2 == 0 }
  }
}
