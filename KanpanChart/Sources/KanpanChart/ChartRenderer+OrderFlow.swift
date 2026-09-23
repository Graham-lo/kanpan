import CoreGraphics
import Foundation
import KanpanCore
import UIKit

// 主力订单流 · 图表这一层。
//
// 只画、不判定：拿到的是 `state.orderFlow`（KanpanData 的 OrderFlowFeed 算好的当前大单集合），
// 这里只管换算成色带、右端标签、图例「主力」一行与十字线读数。
//
// 层序：`draw` 在叠加线之后、画线之前调 `drawOrderFlow`，所以色带压在蜡烛上、画线和
// 最新价（liveLayer）盖在色带上。图例那一行画在 crossLayer（跟十字线读数同层）。
// 比价（百分比坐标）与横屏画线台不画——后者由 app 把 `orderFlow` 置空。
extension ChartRenderer {
  /// 一条要画的色带（连同它的右端标签）。
  struct OrderFlowBand: Equatable {
    let order: BigOrder
    let frame: CGRect
    let color: Hex
    let alpha: Double
    /// 标签中心的 y（错开之后）。
    let labelY: Double
    let amount: String
    /// 「 · 38%」；成交不足一成时为 nil。
    let fill: String?
  }

  struct OrderFlowFrame: Equatable {
    var bands: [OrderFlowBand] = []
    /// 可视区里各侧全部大单的合计（含没画出来的第七条以后）。
    var bidTotal = 0.0
    var askTotal = 0.0
    var hovered: BigOrder?
  }

  static let orderFlowMaxPerSide = 6
  static let orderFlowLabelGap = 10.0

  /// 这一帧要不要画主力订单流：快照属于当前品种、不在比价模式。
  var orderFlowSnapshot: OrderFlowSnapshot? {
    guard let flow = state.orderFlow, !state.percentAxis,
          InstrumentID.canonical(flow.symbol) == InstrumentID.canonical(state.symbol.symbol) else { return nil }
    return flow
  }

  /// 色带几何。纯函数：同一份 state、同一套 pane / range / layout 给同一个结果。
  func orderFlowFrame(pane: Pane, range: PriceRange, L: Layout) -> OrderFlowFrame {
    guard let flow = orderFlowSnapshot, flow.phase == .ready, !flow.orders.isEmpty,
          !state.series.isEmpty, L.plotW > 0 else { return OrderFlowFrame() }
    let mode = state.effectivePriceMode
    let y = { (p: Double) in KanpanCore.yOf(p, pane: pane, range: range, mode: mode) }
    let spacing = state.view.barSpacing(step: state.series.step, plotW: L.plotW)

    struct Candidate { let order: BigOrder; let cy: Double; let h: Double; let x0: Double }
    var visible: [Candidate] = []
    var frame = OrderFlowFrame()
    for order in flow.orders {
      let cy = y(order.center)
      guard cy.isFinite, cy >= pane.y, cy <= pane.y + pane.h else { continue }
      let x0 = max(0, orderFlowStartX(order.firstSeenMs, spacing: spacing, plotW: L.plotW))
      guard x0 < L.plotW else { continue }
      let px = abs(y(order.low) - y(order.low + order.width))
      let h = min(6, max(2, px.isFinite ? px : 2))
      visible.append(Candidate(order: order, cy: cy, h: h, x0: x0))
      if order.side == .bid { frame.bidTotal += order.notional } else { frame.askTotal += order.notional }
    }
    // 同侧最多六条，取名义最大的六条；合计仍算全部。
    let drawn = [BookSide.bid, .ask].flatMap { side in
      visible.filter { $0.order.side == side }.sorted { $0.order.notional > $1.order.notional }
        .prefix(Self.orderFlowMaxPerSide)
    }
    guard !drawn.isEmpty else { return frame }

    // 十字线停在哪条上：只看主图、只看画出来的那几条，取最近的一条。
    var hovered: String?
    if let cross = state.crosshair, cross.pane == nil {
      let i = min(max(0, cross.index), state.series.count - 1)
      let cy = y(cross.price ?? state.series.close[i])
      let cx = state.view.x(Double(state.series.time(at: i)), plotW: L.plotW)
      hovered = drawn
        .filter { cx >= $0.x0 - 2 && abs(cy - $0.cy) <= $0.h / 2 + 3 }
        .min { abs(cy - $0.cy) < abs(cy - $1.cy) }?.order.id
    }
    frame.hovered = drawn.first { $0.order.id == hovered }?.order

    let largest = drawn.map(\.order.notional).max() ?? 0
    let colors = state.colors
    // 标签：贴在带右端上方 2 pt；相邻的竖向撞上就错开 10 pt。
    let labelH = Double(ChartFont.axis.lineHeight)
    var placed: [(Candidate, Double)] = drawn
      .map { ($0, $0.cy - $0.h / 2 - 2 - labelH / 2) }
      .sorted { $0.1 < $1.1 }
    for k in placed.indices.dropFirst() where placed[k].1 - placed[k - 1].1 < Self.orderFlowLabelGap {
      placed[k].1 = placed[k - 1].1 + Self.orderFlowLabelGap
    }
    frame.bands = placed.map { c, labelY in
      let order = c.order
      let alpha: Double = order.id == hovered ? 0.9
        : drawn.count == 1 ? 0.45
        : 0.22 + 0.33 * (largest > 0 ? sqrt(max(0, order.notional) / largest) : 0)
      return OrderFlowBand(
        order: order,
        frame: CGRect(x: c.x0, y: c.cy - c.h / 2, width: L.plotW - c.x0, height: c.h),
        color: order.side == .bid ? colors.up : colors.down,
        alpha: alpha, labelY: labelY, amount: Self.orderFlowAmount(order.notional),
        fill: order.fillRatio >= 0.1 ? " · \(Int((order.fillRatio * 100).rounded()))%" : nil)
    }
    return frame
  }

  /// 首次过门槛那根 K 线的左缘。蜡烛中心落在 openTime 上（见 `drawCandles`），左缘再退半根。
  private func orderFlowStartX(_ firstSeenMs: Int64, spacing: Double, plotW: Double) -> Double {
    let b = state.series
    let t = Double(firstSeenMs)
    guard t >= Double(b.firstTime) else { return -.infinity }
    var i = b.index(atTime: t)
    if Double(b.time(at: i)) > t, i > 0 { i -= 1 }
    return state.view.x(Double(b.time(at: i)), plotW: plotW) - spacing / 2
  }

  /// 此刻主图上画着的色带（视图坐标）与有没有一条被十字线点亮。只给 DEBUG 诊断（UI 取证）用。
  func orderFlowDiagnostics(size: CGSize) -> (bands: [OrderFlowBand], hovered: Bool) {
    guard !state.series.isEmpty else { return ([], false) }
    let L = layout(size: size)
    let frame = orderFlowFrame(pane: L.main, range: priceRange(size: size), L: L)
    return (frame.bands, frame.hovered != nil)
  }

  /// 在 plotLayer 上画色带与右端标签。返回画了几条（给测试核对）。
  @discardableResult
  func drawOrderFlow(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Int {
    let frame = orderFlowFrame(pane: pane, range: range, L: L)
    guard !frame.bands.isEmpty else { return 0 }
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    for band in frame.bands {
      ctx.setAlpha(band.alpha)
      ctx.setFillColor(Paint.cg(band.color))
      ctx.fill(band.frame)
    }
    ctx.setAlpha(1)
    let font = ChartFont.axis
    let right = L.plotW - 3
    for band in frame.bands {
      let fillW = band.fill.map { Double($0.width(font)) } ?? 0
      let amountW = Double(band.amount.width(font))
      band.amount.drawLeft(at: CGPoint(x: right - fillW - amountW, y: band.labelY), font: font, color: band.color)
      band.fill?.drawLeft(at: CGPoint(x: right - fillW, y: band.labelY), font: font, color: state.colors.text)
    }
    ctx.restoreGState()
    return frame.bands.count
  }

  /// 图例「主力」那一行：跟在叠加指标的图例后面另起一行。`x`、`y` 是前面那几段画完停在哪儿。
  func drawOrderFlowLegend(_ ctx: CGContext, pane: Pane, L: Layout, x: Double, y: Double) {
    guard let flow = orderFlowSnapshot else { return }
    let y = x > 8 ? y + 12 : y
    guard y < pane.y + min(pane.h - 6, mainLegendInset(plotW: L.plotW) - 4) else { return }
    let t = state.colors
    var x = 8.0
    let put = { (text: String, color: Hex) in
      text.drawLeft(at: CGPoint(x: x, y: y), font: ChartFont.axis, color: color)
      x += Double(text.width(ChartFont.axis)) + 4
    }
    guard flow.phase == .ready else { put("主力 …", t.text); return }
    let frame = orderFlowFrame(pane: pane, range: priceRange(size: CGSize(width: L.W, height: L.H)), L: L)
    if let order = frame.hovered {
      put(Self.orderFlowReadout(order, decimals: state.decimals, nowMs: flow.asOfMs),
          order.side == .bid ? t.up : t.down)
      return
    }
    guard frame.bidTotal > 0 || frame.askTotal > 0 else { put("主力 暂无", t.text); return }
    put("主力", t.text)
    if frame.bidTotal > 0 { put("买 " + Self.orderFlowAmount(frame.bidTotal), t.up) }
    if frame.bidTotal > 0, frame.askTotal > 0 { put("·", t.text) }
    if frame.askTotal > 0 { put("卖 " + Self.orderFlowAmount(frame.askTotal), t.down) }
  }

  /// 「卖 78,450 · 5.3M · 成交 38% · 12 分」；成交不足一成时不显示成交那一段。
  static func orderFlowReadout(_ order: BigOrder, decimals: Int, nowMs: Int64) -> String {
    // 桶宽 8 bps，桶价只精确到桶宽那一位：78,450 而不是 78,450.35。
    let digits = order.width > 0 ? max(0, min(decimals, 1 - Int(floor(log10(order.width))))) : decimals
    var parts = [(order.side == .bid ? "买 " : "卖 ") + grouped(fmtPrice(order.center, decimals: digits)),
                 orderFlowAmount(order.notional)]
    if order.fillRatio >= 0.1 { parts.append("成交 \(Int((order.fillRatio * 100).rounded()))%") }
    let minutes = max(0, nowMs - order.firstSeenMs) / 60_000
    parts.append(minutes >= 60 ? "\(minutes / 60) 时 \(minutes % 60) 分" : minutes < 1 ? "不到 1 分" : "\(minutes) 分")
    return parts.joined(separator: " · ")
  }

  /// 名义金额：K / M / B 一位小数。
  static func orderFlowAmount(_ value: Double) -> String {
    let a = abs(value)
    if a >= 1e9 { return toFixed(value / 1e9, 1) + "B" }
    if a >= 1e6 { return toFixed(value / 1e6, 1) + "M" }
    if a >= 1e3 { return toFixed(value / 1e3, 1) + "K" }
    return toFixed(value, 0)
  }

  /// 整数部分加千分位逗号。
  private static func grouped(_ text: String) -> String {
    let negative = text.hasPrefix("-")
    let body = negative ? String(text.dropFirst()) : text
    let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    var digits = Array(parts[0])
    var k = digits.count - 3
    while k > 0 { digits.insert(",", at: k); k -= 3 }
    let head = (negative ? "-" : "") + String(digits)
    return parts.count > 1 ? head + "." + parts[1] : head
  }
}
