import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

/// 造一段确定性的 K 线：线性同余随机游走，跑多少次都是同一段数。
private func fixtureSeries(count: Int = 300) -> BarSeries {
  var seed: UInt64 = 20_260_314
  func next() -> Double {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double((seed >> 33) % 10_000) / 10_000
  }
  var o: [Double] = [], h: [Double] = [], l: [Double] = [], c: [Double] = [], v: [Double] = []
  var p = 62_000.0
  for _ in 0..<count {
    let open = p
    let close = open * (1 + (next() - 0.5) * 0.01)
    let high = max(open, close) * (1 + next() * 0.003)
    let low = min(open, close) * (1 - next() * 0.003)
    o.append(open); h.append(high); l.append(low); c.append(close)
    v.append(100 + next() * 900)
    p = close
  }
  return BarSeries(
    symbol: "BTCUSDT", interval: .h1, t0: 1_700_000_000_000, step: Interval.h1.stepMs,
    open: o, high: h, low: l, close: c, volume: v)
}

private let fixtureSymbol = SymbolInfo(
  symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1)

private func fixtureState(
  series: BarSeries = fixtureSeries(),
  overlays: [IndicatorID] = [],
  subs: [IndicatorID] = [],
  crosshair: Crosshair? = nil
) -> ChartState {
  let span = Double(series.step) * 120
  let view = ViewWindow(to: Double(series.lastTime) + span * 0.08, span: span)
  return ChartState(
    series: series, symbol: fixtureSymbol, view: view,
    overlays: overlays, subs: subs, crosshair: crosshair)
}

/// 三层的脏位算得对不对：这是「只重画受影响的层」的全部依据。
@MainActor
@Suite("ChartView 脏位")
struct ChartViewDirtyTests {
  @Test("护眼配色变更立即重画全部图层，不等待新行情")
  func paletteChange() {
    let original = fixtureState()
    var changed = original
    changed.paletteSeed = Palette.terraSeed
    #expect(ChartView.changed(from: original, to: changed) == .all)
    let size = CGSize(width: 393, height: 720)
    let a = ChartRenderer(state: original).layout(size: size)
    let b = ChartRenderer(state: changed).layout(size: size)
    #expect(a.plotW == b.plotW && a.H == b.H && a.mainH == b.mainH)
    #expect(changed.view == original.view)
  }

  @Test("第一帧三层全画")
  func first() {
    #expect(ChartView.changed(from: nil, to: fixtureState()) == .all)
  }

  @Test("一模一样就一层都不画")
  func idle() {
    let s = fixtureState()
    #expect(ChartView.changed(from: s, to: s).isEmpty)
  }

  @Test("只动十字线就只画十字线层")
  func crossOnly() {
    let a = fixtureState()
    var b = a
    b.crosshair = Crosshair(index: 200)
    #expect(ChartView.changed(from: a, to: b) == .cross)
  }

  @Test("末根动（ticker）：底图 + 最新价 + 图例，不含十字线内容")
  func lastBar() {
    let a = fixtureState()
    var s = a.series
    s.close[s.count - 1] *= 1.001
    var b = a
    b.series = s
    // 图例画在 `crossLayer` 上（§5.7 的「读数」），没有十字线时它读的就是末根，
    // 所以末根一动 cross 也得脏；否则图例数值会停在旧值上。
    #expect(ChartView.changed(from: a, to: b) == [.plot, .live, .cross])
  }

  @Test("十字线在时，末根动不必重画十字线那层")
  func lastBarWithCrosshair() {
    var a = fixtureState()
    a.crosshair = Crosshair(index: 10)
    var s = a.series
    s.close[s.count - 1] *= 1.001
    var b = a
    b.series = s
    // 图例读的是十字线那根（第 10 根），末根怎么动都和它无关。
    #expect(ChartView.changed(from: a, to: b) == [.plot, .live])
  }

  @Test("视野 / 指标一动，三层全画")
  func geometry() {
    let a = fixtureState()
    var moved = a
    moved.view = a.view.shifted(byPx: 40, plotW: 320)
    #expect(ChartView.changed(from: a, to: moved) == .all)

    // 这儿原来还切一次 `style` 验「造型一变三层全画」。风格表收成 AICoin 一套之后
    // （见 `CandleStyle`）`state.style` 在运行期不会再变，这条断言没有可造的输入了。
    // 「阳线实心 / 空心」那档走的是 `options.body`，由下面 `ChartOptionsRenderTests` 管。

    var withSub = a
    withSub.subs = [.vol]
    #expect(ChartView.changed(from: a, to: withSub) == .all)
  }
}

/// 三层合成出来的画面，必须跟渲染器自己一次画完的画面一致。
///
/// 这条同时守住三件事：层的坐标系没翻（`CALayer.draw(in:)` 的 context 是不是 y 向下）、
/// `contentsScale` 和层的 frame 对得上、三层的叠放次序没搞反。
@MainActor
@Suite("ChartView 三层合成")
struct ChartViewRenderTests {
  private static let size = CGSize(width: 390, height: 640)
  private static let scale: CGFloat = 3

  private func image(_ draw: (CGContext) -> Void) -> CGImage {
    let f = UIGraphicsImageRendererFormat.preferred()
    f.scale = Self.scale
    f.opaque = false
    let r = UIGraphicsImageRenderer(size: Self.size, format: f)
    return r.image { ctx in draw(ctx.cgContext) }.cgImage!
  }

  /// 逐像素比，返回差异超过 2/255 的像素占比。
  private func diff(_ a: CGImage, _ b: CGImage) -> Double {
    #expect(a.width == b.width && a.height == b.height)
    func bytes(_ img: CGImage) -> [UInt8] {
      var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
      buf.withUnsafeMutableBytes { raw in
        let ctx = CGContext(
          data: raw.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8,
          bytesPerRow: img.width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
      }
      return buf
    }
    let x = bytes(a), y = bytes(b)
    var bad = 0
    for i in stride(from: 0, to: x.count, by: 4) {
      for k in 0..<4 where abs(Int(x[i + k]) - Int(y[i + k])) > 2 {
        bad += 1
        break
      }
    }
    return Double(bad) / Double(x.count / 4)
  }

  @Test("视图画出来的和 ChartRenderer 一次画完的一样")
  func composited() {
    let state = fixtureState()
    let renderer = ChartRenderer(state: state)
    let reference = image { renderer.draw(in: $0, size: Self.size, scale: Self.scale) }

    let view = ChartView(state: state)
    view.frame = CGRect(origin: .zero, size: Self.size)
    view.layoutIfNeeded()
    view.redrawNow()
    let composited = image { view.layer.render(in: $0) }

    // 层是分开的位图再合成，边缘抗锯齿会有零星差别；翻转或错位的话这个数会是几十个百分点。
    #expect(diff(reference, composited) < 0.02)
  }

  @Test("离屏也能画出东西来")
  func offscreenDraws() {
    let view = ChartView(state: fixtureState(overlays: [.ma], subs: [.vol, .macd]))
    view.frame = CGRect(origin: .zero, size: Self.size)
    view.layoutIfNeeded()
    view.redrawNow()
    let img = image { view.layer.render(in: $0) }
    let blank = image { _ in }
    #expect(diff(img, blank) > 0.5)
  }

  @Test("没有 state 就是一张白纸")
  func emptyState() {
    let view = ChartView(state: nil)
    view.frame = CGRect(origin: .zero, size: Self.size)
    view.layoutIfNeeded()
    view.redrawNow()
    let img = image { view.layer.render(in: $0) }
    let blank = image { _ in }
    #expect(diff(img, blank) == 0)
  }
}
