import Foundation
import CoreGraphics
import UIKit
import Testing
import KanpanCore
@testable import KanpanChart

private final class FoundationTouch: UITouch {
  var point: CGPoint
  init(_ x: Double, _ y: Double) { point = CGPoint(x: x, y: y); super.init() }
  override func location(in view: UIView?) -> CGPoint { point }
}
private final class FoundationEvent: UIEvent {
  let time: Double
  init(_ ms: Double) { time = ms / 1000; super.init() }
  override var timestamp: TimeInterval { time }
}

@MainActor @Suite("图表补全渲染与交互")
struct ChartFoundationTests {
  let size = CGSize(width: 393, height: 720)
  func state() -> ChartState { Evidence.state(dark: false, size: size) }
  func view() -> ChartView {
    let view = ChartView(frame: CGRect(origin: .zero, size: size)); view.state = state(); return view
  }
  func tap(_ v: ChartView, _ x: Double, _ y: Double, at: Double = 1000) {
    let t = FoundationTouch(x, y)
    v.touchesBegan([t], with: FoundationEvent(at)); v.touchesEnded([t], with: FoundationEvent(at + 20))
  }

  @Test("主图均线输出参与范围，关闭槽位曲线和数值同步消失")
  func outputs() throws {
    var s = state()
    s.overlays = [.ma, .ema]; s.params[.ema] = [12, 144, 169, 200]
    var renderer = ChartRenderer(state: s)
    let baseline = renderer.priceRange(size: size)
    let viewBefore = s.view
    s.hiddenOutputs = [.ma: Set(0..<20), .ema: Set(0..<20)]
    renderer.state = s
    let hidden = renderer.priceRange(size: size)
    s.overlays = []; renderer.state = s
    let bare = renderer.priceRange(size: size)
    #expect(hidden == bare)
    #expect(hidden.hi <= baseline.hi && hidden.lo >= baseline.lo)
    #expect(renderer.state.view == viewBefore)
    s.overlays = [.ma]; renderer.state = s
    #expect(try #require(renderer.displayed(.ma)).lines.allSatisfy { $0.allSatisfy { !$0.isFinite } })
  }

  @Test("高度改变不改变横向布局；副图重排完整区域跟随指标身份")
  func layout() throws {
    var s = state(); s.subs = [.vol, .oi, .macd, .kdj, .rsi]
    var renderer = ChartRenderer(state: s)
    let a = renderer.layout(size: CGSize(width: 393, height: 500))
    let b = renderer.layout(size: CGSize(width: 393, height: 1000))
    #expect(a.plotW == b.plotW)
    #expect(a.mainH < b.mainH && a.panes[1].h < b.panes[1].h)
    s.subs.swapAt(2, 4); renderer.state = s
    let c = renderer.layout(size: CGSize(width: 393, height: 1000))
    #expect(c.panes[3].indicator == .rsi)
    #expect(c.panes[5].indicator == .macd)
  }

  @Test("共享历史列读数与关闭恢复最后有效值")
  func readings() {
    var s = state(); s.crosshair = .init(index: 1, pane: .rsi)
    var renderer = ChartRenderer(state: s)
    #expect(renderer.reading([10, 20, 30, .nan]) == 20)
    #expect(renderer.reading([10, .nan, 30]).isNaN)
    s.crosshair = nil; renderer.state = s
    #expect(renderer.reading([10, 20, 30, .nan]) == 30)
  }

  @Test("数额一律 K/M/B/T，价格与振荡读数原样不缩写")
  func numberFormats() {
    let renderer = ChartRenderer(state: state())
    // 十字线框「量」、成交量 / 均量 / 持仓量图例都走这一条。
    #expect(renderer.amountNumber(457_977_283) == "457.98M")
    #expect(renderer.amountNumber(10_618_099_697) == "10.62B")
    #expect(renderer.amountNumber(3_178_552_003) == "3.18B")
    #expect(renderer.amountNumber(12.345) == "12.35")
    #expect(renderer.amountNumber(.nan) == "--")
    // 均线、均价这些是价格：小价格按品种小数位原样印，大价格也不缩成 K。
    #expect(renderer.indicatorNumber(0.001779, decimals: 6) == "0.001779")
    #expect(renderer.indicatorNumber(67_123.4, decimals: 1) == "67123.4")
  }

  @Test("显示模式和选中价格模式切换清空单一选择源")
  func cleanup() {
    let v = view()
    var callbacks: [Crosshair?] = []
    v.onCrosshairChanged = { callbacks.append($0) }
    for display in [CandleDataDisplay.top, .follow, .inside] {
      v.state?.crosshair = .init(index: 20, price: 100)
      v.state?.options.dataDisplay = display
      #expect(v.state?.crosshair == nil)
      #expect(callbacks.last! == nil)
    }
    v.state?.crosshair = .init(index: 20, price: 100)
    v.state?.options.crossPrice = .close
    #expect(v.state?.crosshair == nil)
    v.state?.crosshair = .init(index: 20, pane: .rsi)
    v.state?.subs = [.vol]
    #expect(v.state?.crosshair == nil)
    v.state = nil
    #expect(callbacks.last! == nil)
  }

  @Test("主副轴独立权限，倒置曲线与反向触摸映射一致")
  func inversion() throws {
    let v = view()
    v.state?.subs = [.vol, .oi, .macd, .kdj, .rsi]
    let L = try #require(v.chartLayout)
    let before = v.state!.price.inverted
    v.state?.options.allowMainInversion = false
    tap(v, L.plotW + 20, 70)
    #expect(v.state?.price.inverted == before)
    let pane = L.panes[1]
    tap(v, L.plotW + 20, pane.y + 40, at: 2000)
    #expect(v.state?.crosshair == nil && v.state?.subInverted.isEmpty == true)
    v.state?.options.allowSubInversion = true
    tap(v, L.plotW + 20, pane.y + 40, at: 3000)
    #expect(v.state!.subInverted == [.vol])
    let renderer = try #require(v.renderer)
    let y = pane.y + pane.h * 0.65
    let price = renderer.subCrosshairValue(y: y, pane: pane)
    #expect(abs(renderer.subCrosshairY(value: price, pane: pane) - y) < 1e-8)
    #expect(v.state?.price.inverted == before)
  }

  @Test("收盘模式按Android在松手取收盘，选中模式保留自由Y")
  func closeMode() throws {
    let v = view()
    v.state?.options.crossPrice = .close
    tap(v, 180, 120)
    #expect(v.state?.crosshair != nil)
    #expect(v.state?.crosshair?.price == nil)
    v.state?.options.crossPrice = .selected
    tap(v, 180, 120, at: 2000)
    #expect(v.state?.crosshair?.price != nil)
  }

  @Test("三指变两指重建基准，取消清掉触点和Y锚定")
  func pointerRebase() throws {
    let v = view()
    let a = FoundationTouch(80, 120), b = FoundationTouch(230, 140), c = FoundationTouch(290, 150)
    v.touchesBegan([a], with: FoundationEvent(1000))
    v.touchesBegan([b], with: FoundationEvent(1020))
    a.point.x -= 30; b.point.x += 30
    v.touchesMoved([a, b], with: FoundationEvent(1040))
    v.touchesBegan([c], with: FoundationEvent(1060))
    v.touchesEnded([a], with: FoundationEvent(1080))
    let previous = v.state!.view
    v.touchesMoved([b, c], with: FoundationEvent(1100))
    #expect(v.state!.view == previous)
    v.state?.axisScaleAnchor = 100
    v.touchesCancelled([b], with: FoundationEvent(1120))
    #expect(v.gesture.touches.isEmpty && v.gesture.mode == nil)
    #expect(v.state?.axisScaleAnchor == nil)
    #expect(v.animation == nil)
  }

  @Test("只有时钟变化也更新倒计时层，百分比最新价用同一基准")
  func countdown() {
    var s = state(); s.options.countdown = true
    let close = Double(s.series.lastTime + s.series.step)
    s.nowMs = close - 120_000
    let renderer = ChartRenderer(state: s)
    #expect(renderer.countdownText(now: close - 120_000) != renderer.countdownText(now: close - 119_000))
    var next = s; next.nowMs = close - 119_000
    #expect(ChartView.changed(from: s, to: next) == .live)
    s.price.mode = .percent
    let percent = ChartRenderer(state: s), r = percent.priceRange(size: size)
    #expect(percent.axisLabel(r.base, range: r) == "0.00%")
  }
}
