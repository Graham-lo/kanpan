import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit
@testable import KanpanChart

@MainActor
@Suite("主力订单流 · 图表")
struct OrderFlowChartTests {
  static let size = AxisWidthTests.size

  static func order(_ product: OrderFlowProduct, _ side: BookSide, price: Double, firstSeen: Int64,
                    end: Int64? = nil, status: BigOrder.Status = .live, notional: Double = 10_000_000,
                    initial: Double = 10_000_000, filled: Double = 0, threshold: Double = 5_000_000,
                    bucket: Int64 = 0) -> BigOrder {
    BigOrder(venueID: "binance:\(product.rawValue):X", exchange: "币安", product: product, side: side,
             bucket: bucket, price: price, firstSeenMs: firstSeen, endMs: end, status: status,
             initialNotional: initial, notional: notional, filledNotional: filled, threshold: threshold)
  }

  /// 最新价上下摆几单：U 本位买（挂着）、现货买卖、币本位卖、一条已成交买、一条已撤销卖。
  static func renderer(redUp: Bool = false) -> (ChartRenderer, [BigOrder]) {
    var r = AxisWidthTests.renderer()
    let b = r.state.series
    let price = b.close.last!
    let d = price * 0.002
    let seen = b.time(at: b.count - 10) + 1
    let ended = b.time(at: b.count - 4) + 1
    let orders = [
      order(.usdtPerp, .bid, price: price - d, firstSeen: seen, bucket: 1),
      order(.spot, .bid, price: price - 2 * d, firstSeen: seen, notional: 1_500_000, initial: 1_500_000,
            threshold: 1_000_000, bucket: 2),
      order(.spot, .ask, price: price + 2 * d, firstSeen: seen, notional: 1_500_000, initial: 1_500_000,
            threshold: 1_000_000, bucket: 3),
      // 挂着的单成交比例按此刻名义算：2.014M ÷ 5.3M = 38%。
      order(.coinPerp, .ask, price: price + d, firstSeen: b.firstTime - 60_000, notional: 5_300_000,
            initial: 8_000_000, filled: 2_014_000, bucket: 4),
      order(.usdtPerp, .bid, price: price - 3 * d, firstSeen: seen, end: ended, status: .filled,
            filled: 9_000_000, bucket: 5),
      order(.delivery, .ask, price: price + 3 * d, firstSeen: seen, end: ended, status: .cancelled, bucket: 6),
    ]
    r.state.redUp = redUp
    r.state.orderFlow = OrderFlowSnapshot(symbol: r.state.symbol.symbol, phase: .ready, orders: orders,
                                          asOfMs: seen + 12 * 60_000)
    return (r, orders)
  }

  func frame(_ r: ChartRenderer) -> ChartRenderer.OrderFlowFrame {
    let L = r.layout(size: Self.size)
    return r.orderFlowFrame(pane: L.main, range: r.priceRange(size: Self.size), L: L)
  }

  @Test("一单一块：首见那根左缘起，挂着的画到主图右缘、结束的画到结束那根右缘")
  func geometry() throws {
    let (r, orders) = Self.renderer()
    let L = r.layout(size: Self.size)
    let f = frame(r)
    #expect(f.bands.count == orders.count)
    let b = r.state.series
    let spacing = r.state.view.barSpacing(step: b.step, plotW: L.plotW)
    let left = r.state.view.x(Double(b.time(at: b.count - 10)), plotW: L.plotW) - spacing / 2
    let endRight = r.state.view.x(Double(b.time(at: b.count - 4)), plotW: L.plotW) + spacing / 2
    for band in f.bands {
      if band.order.firstSeenMs < b.firstTime { #expect(band.frame.minX == 0) }
      else { #expect(abs(band.frame.minX - max(0, left)) < 0.001) }
      if band.order.isLive { #expect(abs(band.frame.maxX - L.plotW) < 0.001) }
      else { #expect(abs(band.frame.maxX - endRight) < 0.001) }
    }
  }

  @Test("厚度：名义 ÷ (门槛 ÷ 8) 格、一格 0.25 pt、封顶 40 格，夹到 1.5–10 pt")
  func thickness() {
    #expect(ChartRenderer.orderFlowBandHeight(notional: 5_000_000, threshold: 5_000_000) == 2)
    #expect(ChartRenderer.orderFlowBandHeight(notional: 12_500_000, threshold: 5_000_000) == 5)
    #expect(ChartRenderer.orderFlowBandHeight(notional: 25_000_000, threshold: 5_000_000) == 10)
    #expect(ChartRenderer.orderFlowBandHeight(notional: 500_000_000, threshold: 5_000_000) == 10)
    #expect(ChartRenderer.orderFlowBandHeight(notional: 1_000_000, threshold: 5_000_000) == 1.5)
    #expect(ChartRenderer.orderFlowBandHeight(notional: 1, threshold: 0) == 1.5)
    let (r, _) = Self.renderer()
    #expect(frame(r).bands.allSatisfy { $0.frame.height >= 1.5 && $0.frame.height <= 10 })
  }

  @Test("透明度：0.25 + 0.65 × 成交比例；已撤销再 × 0.45 并描虚线")
  func alpha() throws {
    let (r, _) = Self.renderer()
    let f = frame(r)
    let fresh = try #require(f.bands.first { $0.order.bucket == 1 })
    #expect(abs(fresh.alpha - 0.25) < 1e-9 && !fresh.dashed)
    let coin = try #require(f.bands.first { $0.order.bucket == 4 })
    #expect(abs(coin.alpha - (0.25 + 0.65 * 0.38)) < 1e-9)
    let filled = try #require(f.bands.first { $0.order.bucket == 5 })
    #expect(abs(filled.alpha - 0.835) < 1e-9)
    let cancelled = try #require(f.bands.first { $0.order.bucket == 6 })
    #expect(abs(cancelled.alpha - 0.25 * 0.45) < 1e-9 && cancelled.dashed)
    var full = fresh.order; full.filledNotional = 50_000_000
    #expect(ChartRenderer.orderFlowAlpha(full) == 0.9)
  }

  @Test("颜色：合约走涨跌色（红涨绿跌跟着反）、现货黄紫不随涨跌、按底色明暗两套、币本位往正文色混四成")
  func colors() throws {
    for redUp in [false, true] {
      let (r, _) = Self.renderer(redUp: redUp)
      let t = r.state.colors
      let f = frame(r)
      #expect(f.bands.first { $0.order.bucket == 1 }?.color == t.up)
      #expect(f.bands.first { $0.order.bucket == 6 }?.color == t.down)
      #expect(f.bands.first { $0.order.bucket == 2 }?.color == "#B8A800", "浅色底：黄压暗")
      #expect(f.bands.first { $0.order.bucket == 3 }?.color == "#A806BC", "浅色底：紫压暗")
      #expect(f.bands.first { $0.order.bucket == 4 }?.color == mixHex(t.down, t.text, 0.4))
    }
    #expect(Self.renderer(redUp: true).0.state.colors.up == Palette.chart(Palette.lightSeed, redUp: true).up)
    // 六套皮肤按底色分两套：浅色三套压暗、深色三套用 CoinAnk 原色。
    for skin in Skin.allCases {
      for dark in [false, true] {
        var (r, _) = Self.renderer()
        r.state.paletteSeed = Palette.seed(skin, dark: dark)
        let f = frame(r)
        #expect(f.bands.first { $0.order.bucket == 2 }?.color == (dark ? "#E1D610" : "#B8A800"), "\(skin) \(dark)")
        #expect(f.bands.first { $0.order.bucket == 3 }?.color == (dark ? "#CF09E7" : "#A806BC"), "\(skin) \(dark)")
      }
    }
  }

  @Test("显示开关：关现货 / 合约 / 已成交买 / 已撤销卖各自只藏那一类；合计只算还挂着的")
  func display() {
    var (r, orders) = Self.renderer()
    let live = orders.filter(\.isLive)
    #expect(frame(r).bidTotal == live.filter { $0.side == .bid }.map(\.notional).reduce(0, +))
    #expect(frame(r).askTotal == live.filter { $0.side == .ask }.map(\.notional).reduce(0, +))
    r.state.orderFlowDisplay.spot = false
    #expect(!frame(r).bands.contains { $0.order.product == .spot })
    #expect(frame(r).bands.count == 4)
    r.state.orderFlowDisplay = .all
    r.state.orderFlowDisplay.contract = false
    #expect(frame(r).bands.allSatisfy { $0.order.product == .spot })
    r.state.orderFlowDisplay = .all
    r.state.orderFlowDisplay.filledBid = false
    #expect(!frame(r).bands.contains { $0.order.status == .filled })
    r.state.orderFlowDisplay.cancelledAsk = false
    #expect(!frame(r).bands.contains { $0.order.status == .cancelled })
    #expect(frame(r).bands.count == 4)
  }

  @Test("十字线停在块上：那一块 1.0，图例出「币安 永续 卖 84,120 · 5.3M · 成交 38% · 12 分」")
  func hoverAndReadout() throws {
    var (r, orders) = Self.renderer()
    let coin = orders[3]
    r.state.crosshair = Crosshair(index: r.state.series.count - 1, price: coin.price)
    let f = frame(r)
    #expect(f.hovered == coin)
    #expect(f.bands.first { $0.order == coin }?.alpha == 1)

    var perp = Self.order(.usdtPerp, .ask, price: 84_120, firstSeen: 0, notional: 5_300_000, initial: 8_000_000,
                          filled: 2_014_000)
    #expect(ChartRenderer.orderFlowReadout(perp, decimals: 0, nowMs: 720_000)
      == "币安 永续 卖 84,120 · 5.3M · 成交 38% · 12 分")
    perp.filledNotional = 0
    #expect(ChartRenderer.orderFlowReadout(perp, decimals: 1, nowMs: 30_000) == "币安 永续 卖 84,120.0 · 5.3M · 不到 1 分")
    let done = Self.order(.coinPerp, .bid, price: 84_000, firstSeen: 0, end: 3_900_000, status: .cancelled,
                          notional: 6_000_000, initial: 6_000_000)
    #expect(ChartRenderer.orderFlowReadout(done, decimals: 0, nowMs: 99_000_000)
      == "币安 币本位 买 84,000 · 6.0M · 已撤销 · 1 时 5 分")
    var lost = done; lost.status = .lost
    #expect(ChartRenderer.orderFlowReadout(lost, decimals: 0, nowMs: 99_000_000)
      == "币安 币本位 买 84,000 · 6.0M · 断线 · 1 时 5 分")
  }

  @Test("失联结束：不描虚线、不打折，也不归已成交 / 已撤销开关管")
  func lost() throws {
    var (r, _) = Self.renderer()
    r.state.orderFlow?.orders[5].status = .lost
    let band = try #require(frame(r).bands.first { $0.order.bucket == 6 })
    #expect(!band.dashed && abs(band.alpha - 0.25) < 1e-9)
    r.state.orderFlowDisplay.cancelledAsk = false
    r.state.orderFlowDisplay.cancelledBid = false
    r.state.orderFlowDisplay.filledAsk = false
    r.state.orderFlowDisplay.filledBid = false
    #expect(frame(r).bands.contains { $0.order.bucket == 6 })
  }

  @Test("开关与内容变化脏哪几层；开着主力图例多留一行；拉快照中、别的品种不画")
  func invalidationAndInset() {
    let (r, _) = Self.renderer()
    var off = r.state; off.orderFlow = nil
    #expect(ChartView.changed(from: off, to: r.state) == .all)
    var moved = r.state; moved.orderFlow?.orders.removeLast()
    #expect(ChartView.changed(from: r.state, to: moved) == [.plot, .cross])
    var hidden = r.state; hidden.orderFlowDisplay.spot = false
    #expect(ChartView.changed(from: r.state, to: hidden) == [.plot, .cross])
    var hover = r.state; hover.crosshair = Crosshair(index: 3, price: 1)
    #expect(ChartView.changed(from: r.state, to: hover).contains(.plot))
    let plain = ChartRenderer(state: off)
    #expect(r.mainLegendInset(plotW: 300) == plain.mainLegendInset(plotW: 300) + 12)

    var loading = r
    loading.state.orderFlow = .loading(r.state.symbol.symbol)
    #expect(frame(loading).bands.isEmpty)
    var other = r
    other.state.orderFlow?.symbol = "ETHUSDT"
    #expect(frame(other).bands.isEmpty)
  }

  @Test("整帧绘制：色块真的落到像素上，比价模式不画")
  func pixels() throws {
    let (r, orders) = Self.renderer()
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size)
    var bytes = [UInt8](repeating: 0, count: 402 * 520 * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let ctx = try #require(CGContext(data: buffer.baseAddress, width: 402, height: 520,
        bitsPerComponent: 8, bytesPerRow: 402 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      UIGraphicsPushContext(ctx)
      #expect(r.drawOrderFlow(ctx, pane: L.main, range: range, L: L) == orders.count)
      UIGraphicsPopContext()
    }
    #expect(stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] >= 50 }.count > 500)
    let image = UIGraphicsImageRenderer(size: Self.size).image { context in
      r.draw(in: context.cgContext, size: Self.size, scale: 2)
    }
    #expect(image.cgImage != nil)
    var compare = r
    compare.state.percentAxis = true
    #expect(compare.orderFlowSnapshot == nil)
  }
  #if DEBUG
  /// 审查 32 的秤：十字线在主图上走 50 步、横穿好几块大单，底图（plot 层）真画了几次。
  /// 读 `ChartView.renderCounts`（DEBUG 才有）；每一步都 `redrawNow`，一步一帧。
  @discardableResult
  static func crosshairSweep(steps: Int = 50) -> (plot: Int, cross: Int, hovered: Int) {
    let (r, orders) = renderer()
    let view = ChartView(state: r.state)
    view.frame = CGRect(origin: .zero, size: size)
    view.layoutIfNeeded()
    view.redrawNow()
    let plot0 = view.renderCounts["plot"] ?? 0, cross0 = view.renderCounts["cross"] ?? 0
    let prices = orders.map(\.price)
    let lo = prices.min()!, hi = prices.max()!
    var hovered = 0
    for k in 0..<steps {
      let p = lo + (hi - lo) * Double(k) / Double(steps - 1)
      view.state?.crosshair = Crosshair(index: r.state.series.count - 1, price: p)
      view.redrawNow()
      if view.renderer?.orderFlowDiagnostics(size: size).hovered == true { hovered += 1 }
    }
    let plot = (view.renderCounts["plot"] ?? 0) - plot0, cross = (view.renderCounts["cross"] ?? 0) - cross0
    print("ORDERFLOW-REDRAW crosshair-\(steps) plot=\(plot) cross=\(cross) hovered=\(hovered)")
    return (plot, cross, hovered)
  }

  @Test("十字线在主图上走 50 步：读数（cross 层）每步都画")
  func crosshairSweepCounts() {
    let c = Self.crosshairSweep()
    #expect(c.cross == 50)
    #expect(c.hovered > 0, "扫一遍总该有几步停在大单上")
  }
  #endif
}
