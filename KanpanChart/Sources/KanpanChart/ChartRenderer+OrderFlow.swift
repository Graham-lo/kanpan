import CoreGraphics
import Foundation
import KanpanCore
import UIKit

// 主力订单流 · 图表这一层（照 CoinAnk「主力大额挂单」的逐单画法，2026-09-24 改粗横带）。
//
// 只画、不判定：拿到的是 `state.orderFlow`（KanpanData 的 OrderFlowFeed 算好的大单集合，
// 还挂着的 + 已结束的），这里只管换算成一单一条横向价格带、图例「主力」一行，以及轻点 / 十字线
// 选中的那一单（描边 + 交给 app 出详情卡）。
//
// 一单一条带：
//   - 左缘 = 首次过门槛那根 K 线的左缘；右缘 = 结束那根的右缘，还挂着就画到主图右缘。
//   - 粗细按名义 ÷ 门槛分七档（`BigOrder.thicknessTier`，半个倍频一档）：3 / 4.5 / 6 / 7.5 / 9 / 10.5 / 12 pt。
//     刚过门槛 3 pt，门槛 8 倍及以上封顶 12 pt——17 Pro Max 上最细的一条也一眼看得见。
//   - **不透明**。颜色只分深浅两档：被吃过（成交名义 > 0）是深色 = 本色；一口没成交的是浅色 =
//     本色往图区底色混 45%。撤单 / 成交 / 失联不再靠虚线、透明度区分——详情卡上写着。
//   - 本色：合约（U 本位永续、币本位永续、交割）一律皮肤涨跌色（跟着红涨绿跌走），产品由详情卡写明；
//     现货买黄、卖紫（CoinAnk 的现货配色，不随红涨绿跌）：深色底 #E1D610 / #CF09E7，浅色底压暗成
//     #B8A800 / #A806BC——亮黄在白底上发虚。
//   - 同一档价位（bucket）上买卖两侧横向重叠时各让一半：卖占中线以上、买占中线以下。
//     同一侧叠在一起的不混色，照画的先后盖（结束的垫底、名义大的先画、挂着的最后）。
//   - 显示开关（`state.orderFlowDisplay`）只管画不画：关掉现货 / 合约 / 已成交 / 已撤销（四个）。
//
// 选中（`ChartOrderFlowFocus`）：十字线停在一条带上（主图，半高 + 8 pt 以内），或者轻点选中了一条
// （`state.orderFlowSelected`，同样的容差，叠在一起取名义最大的）。选中的那条在 crossLayer 上重画
// 一遍并描 1 pt 正文色边，app 按它出详情卡；这时图里的开高低收框不画，免得两块框叠在一起。
//
// 层序：`draw` 在叠加线之后、画线之前调 `drawOrderFlow`，所以色带压在蜡烛上、画线和
// 最新价（liveLayer）盖在色带上。图例那一行与选中那一条画在 crossLayer（跟十字线读数同层）。
// 色带几何（`orderFlowFrame`）按（快照、显示开关、视野、布局）缓存一份，两层共用（`OrderFlowCache`）。
// 比价（百分比坐标）与横屏画线台不画——后者由 app 把 `orderFlow` 置空。

/// 此刻被选中的那一单，交给 app 出详情卡。坐标都是图表视图坐标（pt）。
public struct ChartOrderFlowFocus: Sendable, Equatable {
  /// 最新快照里的这一单（金额、状态随快照更新）。
  public var order: BigOrder
  /// true = 轻点选中；false = 十字线停在上面。
  public var selected: Bool
  /// 卡片躲开的横坐标：十字线的 x，或选中那条带可见段的中点。
  public var anchorX: Double
  /// 这条带的中线 y。
  public var bandY: Double
  public var plotW: Double
  /// 主图里能摆卡片的那一段：上沿是图例下沿 + 4，下沿是主图下沿（都是图坐标 y）。
  public var mainTop: Double
  public var mainBottom: Double
  /// 快照时刻（还挂着的单算持续时长用）。
  public var asOfMs: Int64

  public init(order: BigOrder, selected: Bool, anchorX: Double, bandY: Double, plotW: Double,
              mainTop: Double, mainBottom: Double, asOfMs: Int64) {
    self.order = order; self.selected = selected; self.anchorX = anchorX; self.bandY = bandY
    self.plotW = plotW; self.mainTop = mainTop; self.mainBottom = mainBottom; self.asOfMs = asOfMs
  }
}

extension ChartRenderer {
  /// 一条要画的大单。
  struct OrderFlowBand: Equatable {
    let order: BigOrder
    let frame: CGRect
    let color: Hex
    /// 深色（被吃过）还是浅色（一口没成交）。
    let dark: Bool
  }

  struct OrderFlowFrame: Equatable {
    /// 画的先后排好的色带。
    var bands: [OrderFlowBand] = []
    /// 可视区里还挂着（且开着显示）的大单各侧合计。
    var bidTotal = 0.0
    var askTotal = 0.0
  }

  /// 按 pane / 价格区间 / 主图宽记一份色带几何（不含十字线与选中）。盒子在 `recalc` 里随输入、视野、
  /// 快照、显示开关一起换新，十字线动、选中换只换 `state.overlay`、盒子留着——plot 与 cross
  /// 两层画同一帧时也只算一遍。
  final class OrderFlowCache {
    var entries: [(pane: Pane, range: PriceRange, plotW: Double, frame: OrderFlowFrame)] = []
    /// 真算了几次（测试核对缓存有没有生效）。
    var computed = 0
  }

  /// 现货买、卖的颜色（CoinAnk）：深色底一套、浅色底压暗一套。
  static let orderFlowSpotBid: Hex = "#E1D610"
  static let orderFlowSpotAsk: Hex = "#CF09E7"
  static let orderFlowSpotBidOnLight: Hex = "#B8A800"
  static let orderFlowSpotAskOnLight: Hex = "#A806BC"
  /// 浅色档（一口没成交）往图区底色混的比例。
  static let orderFlowLightMix = 0.45
  /// 粗细：最细一档 3 pt，每升一档 +1.5 pt，七档封顶 12 pt。
  static let orderFlowMinHeight = 3.0
  static let orderFlowTierStep = 1.5
  /// 点选 / 十字线的竖向容差：离带中线不超过半高 + 8 pt；横向两头各放 4 pt。
  static let orderFlowHitSlop = 8.0
  static let orderFlowHitSlopX = 4.0

  /// 这一帧要不要画主力订单流：快照属于当前品种、不在比价模式。
  var orderFlowSnapshot: OrderFlowSnapshot? {
    guard let flow = state.orderFlow, !state.percentAxis,
          InstrumentID.canonical(flow.symbol) == InstrumentID.canonical(state.symbol.symbol) else { return nil }
    return flow
  }

  /// 一档的粗细（pt）。
  static func orderFlowBandHeight(tier: Int) -> Double {
    orderFlowMinHeight + orderFlowTierStep * Double(min(max(0, tier), BigOrder.thicknessTiers - 1))
  }

  /// 一单的粗细（pt）。
  static func orderFlowBandHeight(notional: Double, threshold: Double) -> Double {
    orderFlowBandHeight(tier: BigOrder.thicknessTier(notional: notional, threshold: threshold))
  }

  /// 一单的本色（深色档）：现货黄紫，合约涨跌色。
  func orderFlowBaseColor(_ order: BigOrder) -> Hex {
    let t = state.colors
    guard order.product == .spot else { return order.side == .bid ? t.up : t.down }
    let light = Self.isLightBackground(t.bg)
    return order.side == .bid ? (light ? Self.orderFlowSpotBidOnLight : Self.orderFlowSpotBid)
                              : (light ? Self.orderFlowSpotAskOnLight : Self.orderFlowSpotAsk)
  }

  /// 一单画出来的颜色：被吃过是本色，一口没成交往图区底色混 45%。
  func orderFlowColor(_ order: BigOrder) -> Hex {
    let base = orderFlowBaseColor(order)
    return order.hasFill ? base : mixHex(base, state.colors.bg, Self.orderFlowLightMix)
  }

  /// 图区底色是不是浅色（按亮度，不认皮肤名：六套种子各自的底色说了算）。
  static func isLightBackground(_ bg: Hex) -> Bool {
    let v = bg.rgba
    return 0.2126 * v.r + 0.7152 * v.g + 0.0722 * v.b > 0.5
  }

  /// 色带几何。同一份 state、同一套 pane / range / layout 给同一个结果。
  func orderFlowFrame(pane: Pane, range: PriceRange, L: Layout) -> OrderFlowFrame {
    orderFlowBands(pane: pane, range: range, L: L)
  }

  /// 色带几何，按 pane / range / plotW 走缓存。
  func orderFlowBands(pane: Pane, range: PriceRange, L: Layout) -> OrderFlowFrame {
    let cache = orderFlowCache
    if let hit = cache.entries.first(where: { $0.pane == pane && $0.range == range && $0.plotW == L.plotW }) {
      return hit.frame
    }
    let value = computeOrderFlowBands(pane: pane, range: range, L: L)
    cache.computed += 1
    if cache.entries.count >= 4 { cache.entries.removeFirst() }
    cache.entries.append((pane, range, L.plotW, value))
    return value
  }

  /// 一个点落在哪条带上：横向落在带里（两头各放 4 pt）、竖向离带中线不超过半高 + 8 pt；
  /// 同时落在好几条上取名义最大的（名义一样取 id 小的，结果稳定）。
  static func orderFlowHit(_ bands: [OrderFlowBand], x: Double, y: Double) -> OrderFlowBand? {
    bands
      .filter {
        x >= $0.frame.minX - orderFlowHitSlopX && x <= $0.frame.maxX + orderFlowHitSlopX
          && abs(y - $0.frame.midY) <= $0.frame.height / 2 + orderFlowHitSlop
      }
      .max { a, b in
        a.order.notional != b.order.notional ? a.order.notional < b.order.notional : a.order.id > b.order.id
      }
  }

  /// 轻点这一下落在哪一单上（视图坐标）。只认主图的绘图区。
  public func orderFlowHit(at point: CGPoint, size: CGSize) -> BigOrder? {
    guard orderFlowSnapshot != nil, !state.series.isEmpty else { return nil }
    let L = layout(size: size)
    let x = Double(point.x), y = Double(point.y)
    guard x >= 0, x <= L.plotW, y >= L.main.y, y <= L.main.y + L.main.h else { return nil }
    let frame = orderFlowBands(pane: L.main, range: priceRange(size: size), L: L)
    return Self.orderFlowHit(frame.bands, x: x, y: y)?.order
  }

  /// 十字线停在哪条带上：只看主图，十字线交点用 `orderFlowHit` 同样的容差。
  func orderFlowHovered(_ bands: [OrderFlowBand], pane: Pane, range: PriceRange, L: Layout) -> OrderFlowBand? {
    guard let cross = state.crosshair, cross.pane == nil, !bands.isEmpty, !state.series.isEmpty else { return nil }
    let i = min(max(0, cross.index), state.series.count - 1)
    let cy = KanpanCore.yOf(cross.price ?? state.series.close[i], pane: pane, range: range, mode: state.effectivePriceMode)
    let cx = state.view.x(Double(state.series.time(at: i)), plotW: L.plotW)
    return Self.orderFlowHit(bands, x: cx, y: cy)
  }

  /// 此刻被选中的那一条（十字线在主图上就看十字线，否则看轻点选中的那一单）及其画出来的样子。
  /// 选中的单不在这一屏的带里（滚出去了、被显示开关关掉）时 `band` 为空，单子取快照里的最新一份。
  func orderFlowFocusBand(pane: Pane, range: PriceRange, L: Layout) -> (order: BigOrder, band: OrderFlowBand?, hovered: Bool)? {
    guard let flow = orderFlowSnapshot, flow.phase == .ready else { return nil }
    let frame = orderFlowBands(pane: pane, range: range, L: L)
    if let cross = state.crosshair {
      guard cross.pane == nil, let band = orderFlowHovered(frame.bands, pane: pane, range: range, L: L) else { return nil }
      return (band.order, band, true)
    }
    guard let selected = state.orderFlowSelected else { return nil }
    if let band = frame.bands.first(where: { $0.order.id == selected.id }) { return (band.order, band, false) }
    return (flow.orders.first { $0.id == selected.id } ?? selected, nil, false)
  }

  /// 交给 app 的选中单（出详情卡用）。没选中返回 nil。
  public func orderFlowFocus(size: CGSize) -> ChartOrderFlowFocus? {
    guard !state.series.isEmpty, let flow = orderFlowSnapshot else { return nil }
    let L = layout(size: size), range = priceRange(size: size)
    guard let hit = orderFlowFocusBand(pane: L.main, range: range, L: L) else { return nil }
    let anchorX: Double
    let bandY: Double
    if hit.hovered, let cross = state.crosshair {
      let i = min(max(0, cross.index), state.series.count - 1)
      anchorX = state.view.x(Double(state.series.time(at: i)), plotW: L.plotW)
    } else if let band = hit.band {
      anchorX = Double(band.frame.midX)
    } else {
      anchorX = L.plotW / 2
    }
    if let band = hit.band { bandY = Double(band.frame.midY) }
    else { bandY = KanpanCore.yOf(hit.order.price, pane: L.main, range: range, mode: state.effectivePriceMode) }
    return ChartOrderFlowFocus(order: hit.order, selected: !hit.hovered, anchorX: anchorX, bandY: bandY,
                               plotW: L.plotW, mainTop: L.main.y + mainLegendInset(plotW: L.plotW) + 4,
                               mainBottom: L.main.y + L.main.h, asOfMs: flow.asOfMs)
  }

  private func computeOrderFlowBands(pane: Pane, range: PriceRange, L: Layout) -> OrderFlowFrame {
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
      let h = Self.orderFlowBandHeight(tier: order.thicknessTier)
      bands.append((order, CGRect(x: left, y: cy - h / 2, width: right - left, height: h)))
      if order.isLive {
        if order.side == .bid { frame.bidTotal += order.notional } else { frame.askTotal += order.notional }
      }
    }
    guard !bands.isEmpty else { return frame }

    // 同一档价位上买卖两侧横向重叠：各让一半，卖在中线以上、买在中线以下（每半至少 3 pt）。
    var byBucket: [Int64: [Int]] = [:]
    for (k, band) in bands.enumerated() { byBucket[band.order.bucket, default: []].append(k) }
    var rects = bands.map(\.rect)
    for (_, members) in byBucket where members.count > 1 {
      for k in members {
        let a = bands[k]
        let clash = members.contains { j in
          j != k && bands[j].order.side != a.order.side
            && bands[j].rect.minX < a.rect.maxX && bands[j].rect.maxX > a.rect.minX
        }
        guard clash else { continue }
        let half = max(a.rect.height / 2, Self.orderFlowMinHeight), cy = a.rect.midY
        rects[k] = CGRect(x: a.rect.minX, y: a.order.side == .ask ? cy - half : cy, width: a.rect.width, height: half)
      }
    }

    // 画的先后：结束的垫底、挂着的在上；同一层里名义大的先画、小的盖在上面，
    // 免得几家在同一价位的单叠成一条时，小的整个被大的吞掉看不见。
    let order = bands.indices.sorted { i, j in
      let a = bands[i].order, b = bands[j].order
      if a.isLive != b.isLive { return !a.isLive }
      if a.notional != b.notional { return a.notional > b.notional }
      return a.id < b.id
    }
    frame.bands = order.map { k in
      let o = bands[k].order
      return OrderFlowBand(order: o, frame: rects[k], color: orderFlowColor(o), dark: o.hasFill)
    }
    return frame
  }

  /// 某一时刻落在哪根 K 线上，那根的左右缘。蜡烛中心落在 openTime 上（见 `drawCandles`），左右各半根。
  /// 早于整段序列的给左右都是负无穷：首见早于序列就从最左画起（夹到 0），结束早于序列就整条不画。
  private func orderFlowBarX(_ ms: Int64, spacing: Double, plotW: Double) -> (left: Double, right: Double)? {
    let b = state.series
    let t = Double(ms)
    guard t >= Double(b.firstTime) else { return (-.infinity, -.infinity) }
    var i = b.index(atTime: t)
    if Double(b.time(at: i)) > t, i > 0 { i -= 1 }
    let cx = state.view.x(Double(b.time(at: i)), plotW: plotW)
    return (cx - spacing / 2, cx + spacing / 2)
  }

  /// 此刻主图上画着的色带（视图坐标）、十字线有没有停在一条上、选中的是哪一单。只给 DEBUG 诊断与测试用。
  func orderFlowDiagnostics(size: CGSize) -> (bands: [OrderFlowBand], hovered: Bool, focus: ChartOrderFlowFocus?) {
    guard !state.series.isEmpty else { return ([], false, nil) }
    let L = layout(size: size)
    let focus = orderFlowFocus(size: size)
    let frame = orderFlowFrame(pane: L.main, range: priceRange(size: size), L: L)
    return (frame.bands, focus.map { !$0.selected } ?? false, focus)
  }

  /// 在 plotLayer 上画色带。返回画了几条（给测试核对）。
  @discardableResult
  func drawOrderFlow(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Int {
    let frame = orderFlowBands(pane: pane, range: range, L: L)
    guard !frame.bands.isEmpty else { return 0 }
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    for band in frame.bands {
      ctx.setFillColor(Paint.cg(band.color))
      ctx.fill(band.frame)
    }
    ctx.restoreGState()
    return frame.bands.count
  }

  /// 在 crossLayer 上把选中的那一条再画一遍（压过盖在它上面的别家）并描 1 pt 正文色边。返回画了没有。
  @discardableResult
  func drawOrderFlowHover(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Bool {
    guard let band = orderFlowFocusBand(pane: pane, range: range, L: L)?.band else { return false }
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    ctx.setFillColor(Paint.cg(band.color))
    ctx.fill(band.frame)
    ctx.setStrokeColor(Paint.cg(state.colors.text))
    ctx.setLineWidth(1)
    ctx.stroke(band.frame.insetBy(dx: -0.5, dy: -0.5))
    ctx.restoreGState()
    return true
  }

  /// 十字线正停在一条带上（这时详情卡顶替图里的开高低收框）。
  func orderFlowHoversBand(L: Layout, range: PriceRange) -> Bool {
    orderFlowFocusBand(pane: L.main, range: range, L: L)?.hovered == true
  }

  /// 图例「主力」那一行：跟在叠加指标的图例后面另起一行。`x`、`y` 是前面那几段画完停在哪儿。
  /// 选中的那一单写在详情卡上，图例这一行始终是「主力 买 X · 卖 Y」。
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
    guard frame.bidTotal > 0 || frame.askTotal > 0 else { put("主力 暂无", t.text); return }
    put("主力", t.text)
    if frame.bidTotal > 0 { put("买 " + Self.orderFlowAmount(frame.bidTotal), t.up) }
    if frame.bidTotal > 0, frame.askTotal > 0 { put("·", t.text) }
    if frame.askTotal > 0 { put("卖 " + Self.orderFlowAmount(frame.askTotal), t.down) }
  }

  /// 名义金额：K / M / B 一位小数。
  static func orderFlowAmount(_ value: Double) -> String {
    let a = abs(value)
    if a >= 1e9 { return toFixed(value / 1e9, 1) + "B" }
    if a >= 1e6 { return toFixed(value / 1e6, 1) + "M" }
    if a >= 1e3 { return toFixed(value / 1e3, 1) + "K" }
    return toFixed(value, 0)
  }
}
