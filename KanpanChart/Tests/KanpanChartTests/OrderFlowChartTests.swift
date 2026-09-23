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

  /// 最新价上下各摆几档大单：买七条（第七条最小，只进合计不画）、卖一条。
  static func renderer(redUp: Bool = false, firstSeenBack: Int = 10) -> (ChartRenderer, [BigOrder]) {
    var r = AxisWidthTests.renderer()
    let b = r.state.series
    let price = b.close.last!
    let width = price * 0.0008
    let seen = b.time(at: b.count - firstSeenBack) + 1
    var orders: [BigOrder] = (1...7).map { k in
      let low = price - Double(k) * width * 3
      return BigOrder(side: .bid, bucketIndex: Int64(k), low: low, width: width,
                      notional: Double(8 - k) * 1_000_000, initialNotional: Double(8 - k) * 1_000_000,
                      filledNotional: 0, firstSeenMs: seen)
    }
    orders.append(BigOrder(side: .ask, bucketIndex: 100, low: price + width * 4, width: width,
                           notional: 5_300_000, initialNotional: 8_000_000, filledNotional: 3_040_000,
                           firstSeenMs: b.firstTime - 60_000))
    r.state.redUp = redUp
    r.state.orderFlow = OrderFlowSnapshot(symbol: r.state.symbol.symbol, phase: .ready, orders: orders,
                                          asOfMs: seen + 12 * 60_000)
    return (r, orders)
  }

  @Test("色带：同侧最多六条、高度 2–6 pt、从首见那根左缘画到主图右缘、透明度按开方")
  func bands() throws {
    let (r, orders) = Self.renderer()
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size)
    let frame = r.orderFlowFrame(pane: L.main, range: range, L: L)
    let bids = frame.bands.filter { $0.order.side == .bid }
    #expect(bids.count == 6)
    #expect(!bids.contains { $0.order.bucketIndex == 7 })
    #expect(frame.bands.count == 7)
    // 合计仍算全部七条买单。
    #expect(frame.bidTotal == orders.filter { $0.side == .bid }.map(\.notional).reduce(0, +))
    #expect(frame.askTotal == 5_300_000)
    #expect(frame.bands.allSatisfy { $0.frame.height >= 2 && $0.frame.height <= 6 })
    #expect(frame.bands.allSatisfy { abs($0.frame.maxX - L.plotW) < 0.001 })
    // 起点：首见那根的左缘；卖单首见早于整段序列，从 0 画起。
    let b = r.state.series
    let spacing = r.state.view.barSpacing(step: b.step, plotW: L.plotW)
    let left = r.state.view.x(Double(b.time(at: b.count - 10)), plotW: L.plotW) - spacing / 2
    #expect(bids.allSatisfy { abs($0.frame.minX - max(0, left)) < 0.001 })
    let ask = try #require(frame.bands.first { $0.order.side == .ask })
    #expect(ask.frame.minX == 0)
    // 透明度：最大的一条 0.55，其余按开方比例落在 0.22–0.55。
    let top = try #require(frame.bands.first { $0.order.notional == 7_000_000 })
    #expect(abs(top.alpha - 0.55) < 1e-9)
    #expect(abs(ask.alpha - (0.22 + 0.33 * sqrt(5.3 / 7))) < 1e-9)
    #expect(frame.bands.allSatisfy { $0.alpha >= 0.22 && $0.alpha <= 0.55 })
    // 颜色：买涨色、卖跌色；标签「5.3M · 38%」。
    #expect(bids.allSatisfy { $0.color == r.state.colors.up })
    #expect(ask.color == r.state.colors.down)
    #expect(ask.amount == "5.3M" && ask.fill == " · 38%")
    #expect(top.fill == nil)
    // 标签竖向不撞：相邻至少隔 10 pt。
    let ys = frame.bands.map(\.labelY).sorted()
    #expect(zip(ys, ys.dropFirst()).allSatisfy { $1 - $0 >= 10 - 1e-9 })
  }

  @Test("红涨绿跌打开时色带跟着反")
  func redUpFlips() {
    let (r, _) = Self.renderer(redUp: true)
    let L = r.layout(size: Self.size)
    let frame = r.orderFlowFrame(pane: L.main, range: r.priceRange(size: Self.size), L: L)
    #expect(frame.bands.filter { $0.order.side == .bid }.allSatisfy { $0.color == r.state.colors.up })
    #expect(r.state.colors.up == Palette.chart(Palette.lightSeed, redUp: true).up)
  }

  @Test("只有一条时 0.45；十字线停在带上提到 0.9 并出读数")
  func singleAndHover() throws {
    var (r, orders) = Self.renderer()
    let ask = orders.last!
    r.state.orderFlow?.orders = [ask]
    let L = r.layout(size: Self.size)
    var frame = r.orderFlowFrame(pane: L.main, range: r.priceRange(size: Self.size), L: L)
    #expect(frame.bands.count == 1 && abs(frame.bands[0].alpha - 0.45) < 1e-9)
    r.state.crosshair = Crosshair(index: r.state.series.count - 1, price: ask.center)
    frame = r.orderFlowFrame(pane: L.main, range: r.priceRange(size: Self.size), L: L)
    #expect(frame.hovered == ask)
    #expect(abs(frame.bands[0].alpha - 0.9) < 1e-9)
    let text = ChartRenderer.orderFlowReadout(ask, decimals: 2, nowMs: ask.firstSeenMs + 12 * 60_000)
    #expect(text.hasPrefix("卖 "))
    #expect(text.hasSuffix(" · 5.3M · 成交 38% · 12 分"))
    var fresh = ask; fresh.filledNotional = 0
    #expect(!ChartRenderer.orderFlowReadout(fresh, decimals: 2, nowMs: ask.firstSeenMs).contains("成交"))
    #expect(ChartRenderer.orderFlowReadout(
      BigOrder(side: .ask, bucketIndex: 0, low: 78_418.6, width: 62.76, notional: 5_300_000,
               initialNotional: 5_300_000, filledNotional: 0, firstSeenMs: 0), decimals: 1, nowMs: 720_000)
      == "卖 78,450 · 5.3M · 12 分")
  }

  @Test("开关与内容变化脏哪几层；开着主力图例多留一行；拉快照中不画带")
  func invalidationAndInset() {
    let (r, _) = Self.renderer()
    var off = r.state; off.orderFlow = nil
    #expect(ChartView.changed(from: off, to: r.state) == .all)
    var moved = r.state; moved.orderFlow?.orders.removeLast()
    #expect(ChartView.changed(from: r.state, to: moved) == [.plot, .cross])
    var hover = r.state; hover.crosshair = Crosshair(index: 3, price: 1)
    #expect(ChartView.changed(from: r.state, to: hover).contains(.plot))
    let plain = ChartRenderer(state: off)
    #expect(r.mainLegendInset(plotW: 300) == plain.mainLegendInset(plotW: 300) + 12)

    var loading = r
    loading.state.orderFlow = .loading(r.state.symbol.symbol)
    let L = loading.layout(size: Self.size)
    #expect(loading.orderFlowFrame(pane: L.main, range: loading.priceRange(size: Self.size), L: L).bands.isEmpty)
    // 别的品种的快照（切品种那一拍）不画。
    var other = r
    other.state.orderFlow?.symbol = "ETHUSDT"
    #expect(other.orderFlowFrame(pane: L.main, range: other.priceRange(size: Self.size), L: L).bands.isEmpty)
  }

  @Test("整帧绘制：色带真的落到像素上，比价模式不画")
  func pixels() throws {
    let (r, _) = Self.renderer()
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size)
    var bytes = [UInt8](repeating: 0, count: 402 * 520 * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let ctx = try #require(CGContext(data: buffer.baseAddress, width: 402, height: 520,
        bitsPerComponent: 8, bytesPerRow: 402 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      UIGraphicsPushContext(ctx)
      #expect(r.drawOrderFlow(ctx, pane: L.main, range: range, L: L) == 7)
      UIGraphicsPopContext()
    }
    #expect(stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] >= 50 }.count > 1_000)
    let image = UIGraphicsImageRenderer(size: Self.size).image { context in
      r.draw(in: context.cgContext, size: Self.size, scale: 2)
    }
    #expect(image.cgImage != nil)
    var compare = r
    compare.state.percentAxis = true
    #expect(compare.orderFlowSnapshot == nil)
  }
}
