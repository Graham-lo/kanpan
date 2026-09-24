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

  @Test("粗细：名义 ÷ 门槛半个倍频一档，3 / 4.5 / 6 / 7.5 / 9 / 10.5 / 12 pt 七档")
  func thickness() {
    let h = { (r: Double) in ChartRenderer.orderFlowBandHeight(notional: 5_000_000 * r, threshold: 5_000_000) }
    #expect(h(0.6) == 3, "撤单滞回留下的不到一倍也是最细一档")
    #expect(h(1) == 3)
    #expect(h(1.4) == 3)
    #expect(h(1.5) == 4.5)
    #expect(h(2) == 6)
    #expect(h(3) == 7.5)
    #expect(h(4) == 9)
    #expect(h(6) == 10.5)
    #expect(h(8) == 12)
    #expect(h(100) == 12)
    #expect(ChartRenderer.orderFlowBandHeight(notional: 1, threshold: 0) == 3)
    #expect((0..<BigOrder.thicknessTiers).map { ChartRenderer.orderFlowBandHeight(tier: $0) } == [3, 4.5, 6, 7.5, 9, 10.5, 12])
    let (r, _) = Self.renderer()
    #expect(frame(r).bands.allSatisfy { $0.frame.height >= 3 && $0.frame.height <= 12 })
    // 10M ÷ 5M = 2 倍 → 第 2 档 6 pt。
    #expect(frame(r).bands.first { $0.order.bucket == 1 }?.frame.height == 6)
  }

  @Test("深浅：被吃过（成交名义 > 0）是本色，一口没成交往底色混 45%；撤单 / 失联不再另画")
  func shades() throws {
    let (r, _) = Self.renderer()
    let t = r.state.colors
    let f = frame(r)
    let fresh = try #require(f.bands.first { $0.order.bucket == 1 })
    #expect(!fresh.dark && fresh.color == mixHex(t.up, t.bg, 0.45))
    let coin = try #require(f.bands.first { $0.order.bucket == 4 })
    #expect(coin.dark && coin.color == t.down, "部分成交也是深色")
    let filled = try #require(f.bands.first { $0.order.bucket == 5 })
    #expect(filled.dark && filled.color == t.up)
    let cancelled = try #require(f.bands.first { $0.order.bucket == 6 })
    #expect(!cancelled.dark && cancelled.color == mixHex(t.down, t.bg, 0.45))
    var eaten = fresh.order; eaten.filledNotional = 1
    #expect(r.orderFlowColor(eaten) == t.up, "被吃一口就转深")
  }

  @Test("颜色：合约（三种）一律涨跌色、红涨绿跌跟着反；现货黄紫不随涨跌、按底色明暗两套")
  func colors() throws {
    for redUp in [false, true] {
      let (r, orders) = Self.renderer(redUp: redUp)
      let t = r.state.colors
      #expect(r.orderFlowBaseColor(orders[0]) == t.up)
      #expect(r.orderFlowBaseColor(orders[3]) == t.down, "币本位永续和 U 本位同一套")
      #expect(r.orderFlowBaseColor(orders[5]) == t.down, "交割同一套")
      #expect(r.orderFlowBaseColor(orders[1]) == "#B8A800", "浅色底：黄压暗")
      #expect(r.orderFlowBaseColor(orders[2]) == "#A806BC", "浅色底：紫压暗")
    }
    #expect(Self.renderer(redUp: true).0.state.colors.up == Palette.chart(Palette.lightSeed, redUp: true).up)
    // 六套皮肤按底色分两套：浅色三套压暗、深色三套用 CoinAnk 原色；浅色档和底色、和深色档都拉得开。
    for skin in Skin.allCases {
      for dark in [false, true] {
        var (r, orders) = Self.renderer()
        r.state.paletteSeed = Palette.seed(skin, dark: dark)
        #expect(r.orderFlowBaseColor(orders[1]) == (dark ? "#E1D610" : "#B8A800"), "\(skin) \(dark)")
        #expect(r.orderFlowBaseColor(orders[2]) == (dark ? "#CF09E7" : "#A806BC"), "\(skin) \(dark)")
        let bg = r.state.colors.bg
        for o in orders {
          var light = o; light.filledNotional = 0
          var deep = o; deep.filledNotional = 1
          let lc = r.orderFlowColor(light), dc = r.orderFlowColor(deep)
          #expect(Self.distance(lc, bg) > 0.12, "\(skin) \(dark) \(o.product) 浅色档要和底色拉开：\(lc.value) vs \(bg.value)")
          #expect(Self.distance(lc, dc) > 0.10, "\(skin) \(dark) \(o.product) 深浅两档要分得开")
        }
      }
    }
  }

  /// 两色在 RGB 里的欧氏距离（0…√3）。
  static func distance(_ a: Hex, _ b: Hex) -> Double {
    let x = a.rgba, y = b.rgba
    return ((x.r - y.r) * (x.r - y.r) + (x.g - y.g) * (x.g - y.g) + (x.b - y.b) * (x.b - y.b)).squareRoot()
  }

  @Test("显示开关：关现货 / 合约 / 已成交 / 已撤销各自只藏那一类；合计只算还挂着的")
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
    r.state.orderFlowDisplay.filled = false
    #expect(!frame(r).bands.contains { $0.order.status == .filled })
    r.state.orderFlowDisplay.cancelled = false
    #expect(!frame(r).bands.contains { $0.order.status == .cancelled })
    #expect(frame(r).bands.count == 4)
  }

  @Test("同一档价位上买卖两侧横向重叠：卖占中线以上、买占中线以下，各至少 3 pt；同侧不拆")
  func splitHalves() throws {
    var (r, orders) = Self.renderer()
    let price = orders[0].price
    // 同一档：U 本位买（10M，6 pt）+ 现货卖（1.5M ÷ 1M，3 pt）+ 另一家 U 本位买（同侧）。
    var ask = orders[2]; ask.price = price; ask.bucket = 1
    var twin = orders[0]; twin.venueID = "okx:usdtPerp:X"; twin.notional = 5_000_000
    r.state.orderFlow?.orders = [orders[0], ask, twin]
    let f = frame(r)
    let cy = KanpanCore.yOf(price, pane: r.layout(size: Self.size).main,
                            range: r.priceRange(size: Self.size), mode: r.state.effectivePriceMode)
    let bid = try #require(f.bands.first { $0.order.id == orders[0].id })
    let a = try #require(f.bands.first { $0.order.side == .ask })
    #expect(abs(bid.frame.minY - cy) < 1e-9 && abs(bid.frame.height - 3) < 1e-9, "买在中线以下、6 pt 让一半")
    #expect(abs(a.frame.maxY - cy) < 1e-9 && abs(a.frame.height - 3) < 1e-9, "卖在中线以上、3 pt 让一半后仍补足 3 pt")
    // 买卖不在同一档就不拆。
    r.state.orderFlow?.orders = [orders[0], orders[2]]
    #expect(frame(r).bands.allSatisfy { abs($0.frame.midY - KanpanCore.yOf($0.order.price, pane: r.layout(size: Self.size).main,
      range: r.priceRange(size: Self.size), mode: r.state.effectivePriceMode)) < 1e-9 })
  }

  @Test("点中判定：横向两头放 4 pt、竖向半高 + 8 pt；叠在一起取名义最大的")
  func hitTolerance() throws {
    let (r, _) = Self.renderer()
    let f = frame(r)
    let band = try #require(f.bands.first { $0.order.bucket == 1 })
    let x = band.frame.midX, mid = band.frame.midY, h = band.frame.height
    #expect(ChartRenderer.orderFlowHit(f.bands, x: x, y: mid)?.order == band.order)
    #expect(ChartRenderer.orderFlowHit([band], x: x, y: mid + h / 2 + 7.9)?.order == band.order)
    #expect(ChartRenderer.orderFlowHit([band], x: x, y: mid - h / 2 - 7.9)?.order == band.order)
    #expect(ChartRenderer.orderFlowHit([band], x: x, y: mid + h / 2 + 8.1) == nil)
    #expect(ChartRenderer.orderFlowHit([band], x: band.frame.minX - 3.9, y: mid)?.order == band.order)
    #expect(ChartRenderer.orderFlowHit([band], x: band.frame.minX - 4.1, y: mid) == nil)
    // 两条叠在一起：小的画在上面，但点中给名义大的。
    var small = band.order; small.venueID = "okx:usdtPerp:X"; small.notional = 5_500_000
    let smallBand = ChartRenderer.OrderFlowBand(order: small, frame: band.frame, color: band.color, dark: false)
    #expect(ChartRenderer.orderFlowHit([band, smallBand], x: x, y: mid)?.order == band.order)
    #expect(ChartRenderer.orderFlowHit([smallBand, band], x: x, y: mid)?.order == band.order)
    // 视图坐标版只认主图绘图区。
    #expect(r.orderFlowHit(at: CGPoint(x: x, y: mid), size: Self.size) == band.order)
    #expect(r.orderFlowHit(at: CGPoint(x: r.layout(size: Self.size).plotW + 5, y: mid), size: Self.size) == nil)
  }

  @Test("十字线停在带上：出选中（非点选），开高低收框让位；离开就没有")
  func hoverFocus() throws {
    var (r, orders) = Self.renderer()
    let coin = orders[3]
    r.state.crosshair = Crosshair(index: r.state.series.count - 1, price: coin.price)
    let focus = try #require(r.orderFlowFocus(size: Self.size))
    #expect(focus.order == coin && !focus.selected)
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size)
    #expect(r.orderFlowHoversBand(L: L, range: range))
    let lit = UIGraphicsImageRenderer(size: Self.size).image { context in
      #expect(r.drawOrderFlowHover(context.cgContext, pane: L.main, range: range, L: L))
    }
    #expect(lit.cgImage != nil)
    var away = r
    away.state.crosshair = Crosshair(index: 0, price: coin.price * 2)
    #expect(away.orderFlowFocus(size: Self.size) == nil)
    #expect(!away.orderFlowHoversBand(L: L, range: range))
    let scratch = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    #expect(!away.drawOrderFlowHover(scratch, pane: L.main, range: range, L: L))
  }

  @Test("轻点选中：选中出卡、再点同一条收起、点别的换过去、点空白收卡；选中时十字线收掉；金额跟着快照走")
  func selectAndDeselect() throws {
    let (r, orders) = Self.renderer()
    let view = ChartView(state: r.state)
    view.frame = CGRect(origin: .zero, size: Self.size)
    view.layoutIfNeeded()
    var reported: [ChartOrderFlowFocus?] = []
    view.onOrderFlowFocusChanged = { reported.append($0) }

    view.state?.crosshair = Crosshair(index: 3, price: 1)
    let before = try #require(view.state)
    view.selectOrderFlow(orders[0])
    #expect(view.state?.orderFlowSelected == orders[0])
    #expect(view.state?.crosshair == nil, "选中时十字线收掉")
    let first = try #require(reported.last ?? nil)
    #expect(first.order == orders[0] && first.selected)
    #expect(ChartView.changed(from: before, to: view.state!) == [.cross], "选中只脏 cross 层")

    // 快照更新了这一单的金额：卡片拿到新数。
    view.state?.orderFlow?.orders[0].notional = 12_345_678
    #expect((reported.last ?? nil)?.order.notional == 12_345_678)

    view.selectOrderFlow(orders[1])
    #expect((reported.last ?? nil)?.order == orders[1])
    view.selectOrderFlow(nil)
    #expect(view.state?.orderFlowSelected == nil)
    #expect(reported.last! == nil)

    // 开十字线（长按）会把选中清掉：卡片改由十字线停在哪条带上决定。
    view.selectOrderFlow(orders[0])
    view.state?.crosshair = Crosshair(index: r.state.series.count - 1, price: 1)
    #expect((reported.last ?? nil)?.selected != true)
  }

  @Test("失联结束：和撤单一样按深浅画，也不归已成交 / 已撤销开关管")
  func lost() throws {
    var (r, _) = Self.renderer()
    r.state.orderFlow?.orders[5].status = .lost
    let band = try #require(frame(r).bands.first { $0.order.bucket == 6 })
    #expect(!band.dark)
    r.state.orderFlowDisplay.cancelled = false
    r.state.orderFlowDisplay.filled = false
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
    // 金额在同一粗细档里抖（BTC 簿几乎每拍都这样）：底图不动，只有图例那一层重画（审查 31）。
    var jitter = r.state; jitter.orderFlow?.orders[0].notional += 1_000_000; jitter.orderFlow?.asOfMs += 500
    #expect(ChartView.changed(from: r.state, to: jitter) == [.cross], "2 倍 → 2.2 倍，同是第 2 档")
    var grew = r.state; grew.orderFlow?.orders[0].notional = 15_000_000  // 3 倍，升到第 3 档
    #expect(ChartView.changed(from: r.state, to: grew) == [.plot, .cross])
    var eaten = r.state; eaten.orderFlow?.orders[0].filledNotional = 1_000  // 被吃一口：浅转深
    #expect(ChartView.changed(from: r.state, to: eaten) == [.plot, .cross])
    var more = r.state; more.orderFlow?.orders[3].filledNotional += 1_000_000  // 已经深了再多吃：画出来一样
    #expect(ChartView.changed(from: r.state, to: more) == [.cross])
    var hover = r.state; hover.crosshair = Crosshair(index: 3, price: 1)
    #expect(ChartView.changed(from: r.state, to: hover) == [.cross])  // 选中的那一条叠在 cross 层（审查 32）
    var picked = r.state; picked.orderFlowSelected = picked.orderFlow?.orders[0]
    #expect(ChartView.changed(from: r.state, to: picked) == [.cross])
    let plain = ChartRenderer(state: off)
    #expect(r.mainLegendInset(plotW: 300) == plain.mainLegendInset(plotW: 300) + 12)

    var loading = r
    loading.state.orderFlow = .loading(r.state.symbol.symbol)
    #expect(frame(loading).bands.isEmpty)
    var other = r
    other.state.orderFlow?.symbol = "ETHUSDT"
    #expect(frame(other).bands.isEmpty)
  }

  @Test("整帧绘制：色带真的落到像素上、不透明，比价模式不画")
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

  // 下面这条秤读 `ChartView.renderCounts`，那份计数只在 DEBUG 下有存储：Release 里读不到，
  // 断言会直接红。所以圈进 DEBUG，并记在 `ReleaseTestRosterTests.debugOnly` 与 Makefile
  // 的 Release 差集清单上。同文件其余用例两种配置都跑。
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

  @Test("十字线在主图上走 50 步：读数（cross 层）每步都画，底图一次不画（审查 32）")
  func crosshairSweepCounts() {
    let c = Self.crosshairSweep()
    #expect(c.cross == 50)
    #expect(c.plot == 0)
    #expect(c.hovered > 0, "扫一遍总该有几步停在大单上")
  }
  #endif

  @Test("色块几何两层共用一份：十字线动不重算，快照一变才重算")
  func frameCache() {
    var (r, orders) = Self.renderer()
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size)
    _ = r.orderFlowFrame(pane: L.main, range: range, L: L)
    _ = r.orderFlowBands(pane: L.main, range: range, L: L)
    #expect(r.orderFlowCache.computed == 1)
    r.state.crosshair = Crosshair(index: r.state.series.count - 1, price: orders[3].price)
    #expect(r.orderFlowFocus(size: Self.size)?.order == orders[3])
    r.state.crosshair = nil
    r.state.orderFlowSelected = orders[0]
    #expect(r.orderFlowFocus(size: Self.size)?.order == orders[0])
    #expect(r.orderFlowCache.computed == 1, "十字线动、选中换都不重算几何")
    r.state.orderFlow?.orders.removeLast()
    _ = r.orderFlowFrame(pane: L.main, range: range, L: L)
    #expect(r.orderFlowCache.computed == 1, "快照变了换了新盒子，新盒子里算了一次")
    #expect(r.orderFlowFrame(pane: L.main, range: range, L: L).bands.count == orders.count - 1)
  }

}
