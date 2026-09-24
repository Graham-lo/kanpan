import CoreGraphics
import Foundation
import KanpanCore
import UIKit

// 主力订单流 · 图表这一层（照 CoinAnk「主力大额挂单」的逐单画法）。
//
// 只画、不判定：拿到的是 `state.orderFlow`（KanpanData 的 OrderFlowFeed 算好的大单集合，
// 还挂着的 + 已结束的），这里只管换算成一单一块矩形、图例「主力」一行与十字线读数。
//
// 一单一块：
//   - 左缘 = 首次过门槛那根 K 线的左缘；右缘 = 结束那根的右缘，还挂着就画到主图右缘。
//   - 高度 = min(40, 名义 ÷ (门槛 ÷ 8)) × 0.25 pt，再夹到 1.5–10 pt：刚过门槛 2 pt，门槛五倍封顶 10 pt。
//   - 透明度 = 0.25 + 0.65 × 成交比例（0.25–0.9）：被吃得越多越实；已撤销再 × 0.45 并描虚线边；
//     十字线停在上面的那一块 1.0。
//   - 颜色：合约（U 本位永续、交割）用皮肤涨跌色（跟着红涨绿跌走）；现货买黄 #E1D610、卖紫 #CF09E7
//     （CoinAnk 的现货配色，不随红涨绿跌）；**币本位永续**用涨跌色往皮肤正文色混 40%——同一侧的颜色
//     发灰一档，和 U 本位一眼分得开，又不和现货的黄紫、也不和已撤销的虚线边撞。
//   - 显示开关（`state.orderFlowDisplay`）只管画不画：关掉现货 / 合约 / 已成交买卖 / 已撤销买卖。
//
// 层序：`draw` 在叠加线之后、画线之前调 `drawOrderFlow`，所以色块压在蜡烛上、画线和
// 最新价（liveLayer）盖在色块上。图例那一行画在 crossLayer（跟十字线读数同层）。
// 比价（百分比坐标）与横屏画线台不画——后者由 app 把 `orderFlow` 置空。
extension ChartRenderer {
  /// 一块要画的大单。
  struct OrderFlowBand: Equatable {
    let order: BigOrder
    let frame: CGRect
    let color: Hex
    let alpha: Double
    /// 已撤销：描虚线边。
    let dashed: Bool
  }

  struct OrderFlowFrame: Equatable {
    var bands: [OrderFlowBand] = []
    /// 可视区里还挂着（且开着显示）的大单各侧合计。
    var bidTotal = 0.0
    var askTotal = 0.0
    var hovered: BigOrder?
  }

  /// 现货买、卖的颜色（CoinAnk）。
  static let orderFlowSpotBid: Hex = "#E1D610"
  static let orderFlowSpotAsk: Hex = "#CF09E7"
  /// 币本位永续往正文色混的比例。
  static let orderFlowCoinMix = 0.4
  /// 高度：名义每「门槛 ÷ 8」一格，一格 0.25 pt，最多 40 格；再夹到 1.5–10 pt。
  static let orderFlowUnitPt = 0.25
  static let orderFlowMaxUnits = 40.0
  static let orderFlowHeight: ClosedRange<Double> = 1.5...10

  /// 这一帧要不要画主力订单流：快照属于当前品种、不在比价模式。
  var orderFlowSnapshot: OrderFlowSnapshot? {
    guard let flow = state.orderFlow, !state.percentAxis,
          InstrumentID.canonical(flow.symbol) == InstrumentID.canonical(state.symbol.symbol) else { return nil }
    return flow
  }

  /// 一单的高度（pt）。
  static func orderFlowBandHeight(notional: Double, threshold: Double) -> Double {
    guard threshold > 0, notional.isFinite else { return orderFlowHeight.lowerBound }
    let units = min(orderFlowMaxUnits, max(0, notional) / (threshold / 8))
    return min(orderFlowHeight.upperBound, max(orderFlowHeight.lowerBound, units * orderFlowUnitPt))
  }

  /// 一单的透明度（没被十字线点亮时）。
  static func orderFlowAlpha(_ order: BigOrder) -> Double {
    let base = min(0.9, max(0.25, 0.25 + 0.65 * order.fillRatio))
    return order.status == .cancelled ? base * 0.45 : base
  }

  /// 一单的颜色。
  func orderFlowColor(_ order: BigOrder) -> Hex {
    let t = state.colors
    switch order.product {
    case .spot: return order.side == .bid ? Self.orderFlowSpotBid : Self.orderFlowSpotAsk
    case .usdtPerp, .delivery: return order.side == .bid ? t.up : t.down
    case .coinPerp: return mixHex(order.side == .bid ? t.up : t.down, t.text, Self.orderFlowCoinMix)
    }
  }

  /// 色块几何。纯函数：同一份 state、同一套 pane / range / layout 给同一个结果。
  func orderFlowFrame(pane: Pane, range: PriceRange, L: Layout) -> OrderFlowFrame {
    guard let flow = orderFlowSnapshot, flow.phase == .ready, !flow.orders.isEmpty,
          !state.series.isEmpty, L.plotW > 0 else { return OrderFlowFrame() }
    let mode = state.effectivePriceMode
    let y = { (p: Double) in KanpanCore.yOf(p, pane: pane, range: range, mode: mode) }
    let spacing = state.view.barSpacing(step: state.series.step, plotW: L.plotW)
    let display = state.orderFlowDisplay

    var frame = OrderFlowFrame()
    var bands: [(order: BigOrder, rect: CGRect)] = []
    for order in flow.orders where display.shows(order) {
      let cy = y(order.price)
      guard cy.isFinite, cy >= pane.y, cy <= pane.y + pane.h else { continue }
      guard let x0 = orderFlowBarX(order.firstSeenMs, spacing: spacing, plotW: L.plotW)?.left else { continue }
      let x1: Double
      if let end = order.endMs {
        guard let bar = orderFlowBarX(end, spacing: spacing, plotW: L.plotW) else { continue }
        x1 = bar.right
      } else {
        x1 = L.plotW
      }
      let left = max(0, x0), right = min(L.plotW, max(x1, x0 + 1))
      guard right > left, left < L.plotW else { continue }
      let h = Self.orderFlowBandHeight(notional: order.notional, threshold: order.threshold)
      bands.append((order, CGRect(x: left, y: cy - h / 2, width: right - left, height: h)))
      if order.isLive {
        if order.side == .bid { frame.bidTotal += order.notional } else { frame.askTotal += order.notional }
      }
    }
    guard !bands.isEmpty else { return frame }
    // 画的先后：结束的垫底、挂着的在上；同一层里名义大的先画、小的盖在上面，
    // 免得几家在同一价位的单叠成一块时，小的整个被大的吞掉看不见。
    bands.sort { a, b in
      if a.order.isLive != b.order.isLive { return !a.order.isLive }
      if a.order.notional != b.order.notional { return a.order.notional > b.order.notional }
      return a.order.id < b.order.id
    }

    // 十字线停在哪一块上：只看主图，横向落在块里、竖向离块中线不超过半高 + 3 pt，取最近的一块。
    var hovered: String?
    if let cross = state.crosshair, cross.pane == nil {
      let i = min(max(0, cross.index), state.series.count - 1)
      let cy = y(cross.price ?? state.series.close[i])
      let cx = state.view.x(Double(state.series.time(at: i)), plotW: L.plotW)
      hovered = bands
        .filter { cx >= $0.rect.minX - 2 && cx <= $0.rect.maxX + 2 && abs(cy - $0.rect.midY) <= $0.rect.height / 2 + 3 }
        .min { abs(cy - $0.rect.midY) < abs(cy - $1.rect.midY) }?.order.id
    }
    frame.hovered = bands.first { $0.order.id == hovered }?.order
    frame.bands = bands.map { order, rect in
      OrderFlowBand(order: order, frame: rect, color: orderFlowColor(order),
                    alpha: order.id == hovered ? 1 : Self.orderFlowAlpha(order),
                    dashed: order.status == .cancelled)
    }
    return frame
  }

  /// 某一时刻落在哪根 K 线上，那根的左右缘。蜡烛中心落在 openTime 上（见 `drawCandles`），左右各半根。
  /// 早于整段序列的给左右都是负无穷：首见早于序列就从最左画起（夹到 0），结束早于序列就整块不画。
  private func orderFlowBarX(_ ms: Int64, spacing: Double, plotW: Double) -> (left: Double, right: Double)? {
    let b = state.series
    let t = Double(ms)
    guard t >= Double(b.firstTime) else { return (-.infinity, -.infinity) }
    var i = b.index(atTime: t)
    if Double(b.time(at: i)) > t, i > 0 { i -= 1 }
    let cx = state.view.x(Double(b.time(at: i)), plotW: plotW)
    return (cx - spacing / 2, cx + spacing / 2)
  }

  /// 此刻主图上画着的色块（视图坐标）与有没有一块被十字线点亮。只给 DEBUG 诊断（UI 取证）用。
  func orderFlowDiagnostics(size: CGSize) -> (bands: [OrderFlowBand], hovered: Bool) {
    guard !state.series.isEmpty else { return ([], false) }
    let L = layout(size: size)
    let frame = orderFlowFrame(pane: L.main, range: priceRange(size: size), L: L)
    return (frame.bands, frame.hovered != nil)
  }

  /// 在 plotLayer 上画色块。返回画了几块（给测试核对）。
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
    // 已撤销的描虚线边（不透明度跟着块走，但至少 0.6，免得虚线看不见）。
    let dashed = frame.bands.filter(\.dashed)
    if !dashed.isEmpty {
      ctx.setLineWidth(0.8)
      ctx.setLineDash(phase: 0, lengths: [3, 2])
      for band in dashed {
        ctx.setAlpha(max(0.6, band.alpha))
        ctx.setStrokeColor(Paint.cg(band.color))
        ctx.stroke(band.frame.insetBy(dx: 0.4, dy: 0.4))
      }
      ctx.setLineDash(phase: 0, lengths: [])
    }
    ctx.setAlpha(1)
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
      put(Self.orderFlowReadout(order, decimals: state.decimals, nowMs: flow.asOfMs), orderFlowColor(order))
      return
    }
    guard frame.bidTotal > 0 || frame.askTotal > 0 else { put("主力 暂无", t.text); return }
    put("主力", t.text)
    if frame.bidTotal > 0 { put("买 " + Self.orderFlowAmount(frame.bidTotal), t.up) }
    if frame.bidTotal > 0, frame.askTotal > 0 { put("·", t.text) }
    if frame.askTotal > 0 { put("卖 " + Self.orderFlowAmount(frame.askTotal), t.down) }
  }

  /// 「币安 永续 卖 84,120 · 5.3M · 成交 38% · 12 分」。已结束的补一段「已成交 / 已撤销」，
  /// 时长算到结束那一刻；成交不足一成时不显示成交那一段。
  static func orderFlowReadout(_ order: BigOrder, decimals: Int, nowMs: Int64) -> String {
    var parts = ["\(order.exchange) \(order.product.shortLabel) " + (order.side == .bid ? "买 " : "卖 ")
                   + grouped(fmtPrice(order.price, decimals: decimals)),
                 orderFlowAmount(order.status == .live ? order.notional : order.initialNotional)]
    if order.fillRatio >= 0.1 { parts.append("成交 \(Int((order.fillRatio * 100).rounded()))%") }
    switch order.status {
    case .live: break
    case .filled: parts.append("已成交")
    case .cancelled: parts.append("已撤销")
    }
    let minutes = max(0, (order.endMs ?? nowMs) - order.firstSeenMs) / 60_000
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
