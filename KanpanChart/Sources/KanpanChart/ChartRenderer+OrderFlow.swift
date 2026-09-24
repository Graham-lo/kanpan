import CoreGraphics
import Foundation
import KanpanCore
import UIKit

// 主力订单流 · 图表这一层（照 CoinAnk「主力大额挂单」的横向价格带；2026-09-24 晚改手机布局）。
//
// 只画、不判定：拿到的是 `state.orderFlow`（KanpanData 的 OrderFlowFeed 算好的逐单集合，
// 还挂着的 + 已结束的），这里只管换算成横向价格带、图例「主力」一行、带上的金额标签，
// 以及轻点 / 十字线选中的那一条（描边 + 交给 app 出详情卡）。
//
// 手机布局（用户：「都挤在一起，有没有适合手机的布局设计展示」——BTC 十三本簿同时出单，
// 一单一条在 1 分钟图右缘叠成一堵墙）：
//   1. **一堵墙一条**：同一价位桶、同一侧、同一类（现货 / 合约）、时间上连成一段的单合成一段；
//      四种合约（币安 U 本位 / 币本位 / 交割、OKX 永续）是一条「合约」带，三家现货是一条「现货」带。
//      时间上断开（空档超过 max(60 秒, 一根 K 线)）就另起一段——不把空档画成墙（`OrderFlowGroup.segments`）。
//      已结束、活不过一根 K 线的段去掉（碎屑；挂着的一律留）。再把同侧同类、桶号相邻、时间上连着的段并成一堵墙
//      （2026-09-25，`OrderFlowGroup.walls`）：ETH / SOL 一堵墙在簿上摊在相邻几个桶里，不再画成几条各写各的金额。
//      左缘 = 墙里最早首见那根 K 线的左缘；右缘 = 最晚结束那根的右缘，有一单还挂着就画到主图右缘。
//   2. **按屏内排名分主次**（2026-09-25，不按门槛倍数）：横向落在这一屏、价位落在主图里的墙按画法名义从大到小排
//      （一样的先起的在前）：前 6 名「主」——整条带（粗细五档 2 / 3 / 4.5 / 6 / 8 pt，最细 3 pt；跨几个桶的盖住
//      整个价位范围）+ 金额标签；第 7–18 名「次」——2 pt 线、不写金额；其余「底噪」——1 pt 线、35% 不透明、
//      不写金额。还挂着的墙升一级（底噪 → 次；主的名额不因挂着多给）。每帧现排，结果确定。
//      门槛调低、一屏几百条的时候，眼睛先看到的仍是这一屏最大的六堵。
//   3. **纵向去挤**（主、次）：按排名落带；一条带落下后，和它横向有交叠、纵向重叠（含 1 pt 间隙）的排名更后的带
//      压成 1.5 pt 细线——不平移、不改价位，仍然是本色深浅、仍然点得中。底噪不参与（本来就是 1 pt 淡线）。
//      画的先后：底噪 → 整条 → 细线（细线压在上面，不会被大的整个吞掉）。
//   4. **金额标签**：「主」里没被压细、宽 ≥ 48 pt 的带在右端内侧（挂着的贴主图右缘）放一枚带色小签，
//      写合并后的名义（「6.2M」，8.5 pt 等宽，字色取带色的对比色）；标签之间碰撞只留名义大的。
//      标签画在 crossLayer：金额每拍都在抖，不能拖着底图重画（审查 31）。
//   5. **颜色**：合约一律皮肤涨跌色（跟着红涨绿跌走），现货买黄、卖紫（CoinAnk；浅色底压暗成 #B8A800 / #A806BC）。
//      深浅两档：任何一单被吃过（成交名义 > 0）是本色；一口没成交往图区底色混 45%。主、次不透明，底噪 35%。
//   6. 显示开关（`state.orderFlowDisplay`）逐单过滤后再合并；图例「主力 买 X · 卖 Y」仍按逐单求和。
//
// 选中（`ChartOrderFlowFocus`）：十字线停在一条带上，或者轻点选中了一条（`state.orderFlowSelected`，
// 存的是那堵墙的 `OrderFlowGroupKey`——墙里最早那一段的键，含段的起点；墙续长、并进后来的段都不变，
// 并进更早的段按 `OrderFlowGroup.covers` 认回来）。选中的那条在 crossLayer 上重画一遍并描 1 pt 正文色边，
// app 按它出「一段一卡」的详情卡；这时图里的开高低收框不画。
//
// 层序：`draw` 在叠加线之后、画线之前调 `drawOrderFlow`，所以色带压在蜡烛上、画线和最新价（liveLayer）
// 盖在色带上。选中那一条、金额标签、图例画在 crossLayer。几何（`orderFlowFrame`）按（快照、显示开关、
// 视野、布局）缓存一份，两层共用（`OrderFlowCache`）。比价（百分比坐标）与横屏画线台不画。

/// 此刻被选中的那一条合并带，交给 app 出详情卡。坐标都是图表视图坐标（pt）。
public struct ChartOrderFlowFocus: Sendable, Equatable {
  /// 最新快照里的这一段（金额、状态随快照更新）。
  public var group: OrderFlowGroup
  /// true = 轻点选中；false = 十字线停在上面。
  public var selected: Bool
  /// 卡片躲开的横坐标：十字线的 x，或选中那条带可见段的中点。
  public var anchorX: Double
  /// 这条带的中线 y 与半高（卡片不能盖住它）。
  public var bandY: Double
  public var bandHalf: Double
  public var plotW: Double
  /// 主图里能摆卡片的那一段：上沿是图例下沿 + 4，下沿是主图下沿（都是图坐标 y）。
  public var mainTop: Double
  public var mainBottom: Double
  /// 主图整块的高（卡高上限按它的 55% 算）。
  public var mainHeight: Double
  /// 快照时刻（还挂着的单算持续时长用）。
  public var asOfMs: Int64

  public init(group: OrderFlowGroup, selected: Bool, anchorX: Double, bandY: Double, bandHalf: Double, plotW: Double,
              mainTop: Double, mainBottom: Double, mainHeight: Double, asOfMs: Int64) {
    self.group = group; self.selected = selected; self.anchorX = anchorX; self.bandY = bandY; self.bandHalf = bandHalf
    self.plotW = plotW; self.mainTop = mainTop; self.mainBottom = mainBottom; self.mainHeight = mainHeight
    self.asOfMs = asOfMs
  }

  /// 卡片最宽多少、摆在带上还是带下、最高多少（`OrderFlowCardBudget`）。
  public var cardMaxWidth: Double { OrderFlowCardBudget.maxWidth(plotW: plotW) }
  public var cardPlacement: (below: Bool, maxHeight: Double) {
    OrderFlowCardBudget.placement(bandY: bandY, bandHalf: bandHalf, top: mainTop, bottom: mainBottom, mainHeight: mainHeight)
  }
}

extension ChartRenderer {
  /// 一条要画的合并带。
  struct OrderFlowBand: Equatable {
    let group: OrderFlowGroup
    let frame: CGRect
    let color: Hex
    /// 深色（被吃过）还是浅色（一口没成交）。
    let dark: Bool
    /// 被更大的带挤成了 1.5 pt 细线。
    let thin: Bool
    /// 屏内排名的主次。
    let role: OrderFlowRole
    /// 不透明度（底噪 0.35，其余 1）。
    let alpha: Double
    var key: OrderFlowGroupKey { group.key }

    init(group: OrderFlowGroup, frame: CGRect, color: Hex, dark: Bool, thin: Bool, role: OrderFlowRole = .main,
         alpha: Double = 1) {
      self.group = group; self.frame = frame; self.color = color; self.dark = dark; self.thin = thin
      self.role = role; self.alpha = alpha
    }
  }

  /// 屏内排名的主次：前 6 名主、第 7–18 名次、其余底噪（还挂着的底噪升成次）。
  enum OrderFlowRole: String, Equatable {
    case main, secondary, noise
  }

  /// 带右端的金额小签。
  struct OrderFlowLabel: Equatable {
    let key: OrderFlowGroupKey
    let text: String
    let frame: CGRect
    let fill: Hex
    let ink: Hex
  }

  struct OrderFlowFrame: Equatable {
    /// 画的先后排好的色带：底噪在前，整条的其次（彼此不重叠），细线在后。
    var bands: [OrderFlowBand] = []
    var labels: [OrderFlowLabel] = []
    /// 可视区里还挂着（且开着显示）的大单各侧合计（逐单求和）。
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
  /// 粗细五档（pt）：名义 ÷ 门槛 1× / 2× / 4× / 8× / 16×。
  static let orderFlowHeights: [Double] = [2, 3, 4.5, 6, 8]
  /// 「主」带最细多少（五档里最细的 2 pt 在主里也画 3 pt，和次的 2 pt 线分得开）。
  static let orderFlowMainMinHeight = 3.0
  /// 「次」「底噪」的线高与底噪的不透明度。
  static let orderFlowSecondaryHeight = 2.0
  static let orderFlowNoiseHeight = 1.0
  static let orderFlowNoiseAlpha = 0.35
  /// 一屏几名「主」、主加次一共几名（第 7–18 名是次）。
  static let orderFlowMainCount = 6
  static let orderFlowRankedCount = 18
  /// 被挤成细线的高。
  static let orderFlowThinHeight = 1.5
  /// 判「纵向重叠」时两条带之间至少要留的空。
  static let orderFlowGap = 1.0
  /// 带宽到这么宽才写金额。
  static let orderFlowLabelMinWidth = 48.0
  /// 金额小签：8.5 pt 等宽（常驻一只实例，`ChartFont` 的缓存按字体身份做键）、高 11 pt、左右各留 3 pt、离带右端 1 pt。
  static let orderFlowLabelFont = UIFont.monospacedSystemFont(ofSize: 8.5, weight: .medium)
  static let orderFlowLabelHeight = 11.0
  static let orderFlowLabelPadX = 3.0
  static let orderFlowLabelInset = 1.0
  /// 点选 / 十字线的竖向容差：离带边不超过 8 pt；横向两头各放 4 pt。
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
    orderFlowHeights[min(max(0, tier), orderFlowHeights.count - 1)]
  }

  /// 一份名义的粗细（pt）。
  static func orderFlowBandHeight(notional: Double, threshold: Double) -> Double {
    orderFlowBandHeight(tier: BigOrder.thicknessTier(notional: notional, threshold: threshold))
  }

  /// 本色（深色档）：现货黄紫，合约涨跌色。
  func orderFlowBaseColor(side: BookSide, contract: Bool) -> Hex {
    let t = state.colors
    guard !contract else { return side == .bid ? t.up : t.down }
    let light = Self.isLightBackground(t.bg)
    return side == .bid ? (light ? Self.orderFlowSpotBidOnLight : Self.orderFlowSpotBid)
                        : (light ? Self.orderFlowSpotAskOnLight : Self.orderFlowSpotAsk)
  }

  func orderFlowBaseColor(_ order: BigOrder) -> Hex {
    orderFlowBaseColor(side: order.side, contract: order.product.isContract)
  }

  /// 画出来的颜色：被吃过是本色，一口没成交往图区底色混 45%。
  func orderFlowColor(side: BookSide, contract: Bool, hasFill: Bool) -> Hex {
    let base = orderFlowBaseColor(side: side, contract: contract)
    return hasFill ? base : mixHex(base, state.colors.bg, Self.orderFlowLightMix)
  }

  func orderFlowColor(_ order: BigOrder) -> Hex {
    orderFlowColor(side: order.side, contract: order.product.isContract, hasFill: order.hasFill)
  }

  func orderFlowColor(_ group: OrderFlowGroup) -> Hex {
    orderFlowColor(side: group.side, contract: group.contract, hasFill: group.hasFill)
  }

  /// 图区底色是不是浅色（按亮度，不认皮肤名：六套种子各自的底色说了算）。
  static func isLightBackground(_ bg: Hex) -> Bool {
    let v = bg.rgba
    return 0.2126 * v.r + 0.7152 * v.g + 0.0722 * v.b > 0.5
  }

  /// 小签上的字色：带色亮就用近黑，暗就用白。
  static func orderFlowLabelInk(_ fill: Hex) -> Hex {
    isLightBackground(fill) ? "#141414" : "#FFFFFF"
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

  /// 一个点落在哪条带上。横向落在带里（两头各放 4 pt）为前提：
  ///   1. 点在某条带画出来的范围里（上下各放 0.5 pt）：取画在最上面的那条（细线画在整条之后）；
  ///   2. 否则离带边不超过 8 pt 的里面取离得最近的；一样近取名义大的、再取 id 小的（结果稳定）。
  static func orderFlowHit(_ bands: [OrderFlowBand], x: Double, y: Double) -> OrderFlowBand? {
    let inX = { (b: OrderFlowBand) in
      x >= b.frame.minX - orderFlowHitSlopX && x <= b.frame.maxX + orderFlowHitSlopX
    }
    if let exact = bands.last(where: { inX($0) && y >= $0.frame.minY - 0.5 && y <= $0.frame.maxY + 0.5 }) {
      return exact
    }
    let gap = { (b: OrderFlowBand) in max(0, abs(y - b.frame.midY) - b.frame.height / 2) }
    return bands
      .filter { inX($0) && gap($0) <= orderFlowHitSlop }
      .min { a, b in
        let ga = gap(a), gb = gap(b)
        if ga != gb { return ga < gb }
        if a.group.drawNotional != b.group.drawNotional { return a.group.drawNotional > b.group.drawNotional }
        return a.key.id < b.key.id
      }
  }

  /// 轻点这一下落在哪条带上（视图坐标）。只认主图的绘图区。
  public func orderFlowHit(at point: CGPoint, size: CGSize) -> OrderFlowGroup? {
    guard orderFlowSnapshot != nil, !state.series.isEmpty else { return nil }
    let L = layout(size: size)
    let x = Double(point.x), y = Double(point.y)
    guard x >= 0, x <= L.plotW, y >= L.main.y, y <= L.main.y + L.main.h else { return nil }
    let frame = orderFlowBands(pane: L.main, range: priceRange(size: size), L: L)
    return Self.orderFlowHit(frame.bands, x: x, y: y)?.group
  }

  /// 十字线停在哪条带上：只看主图，十字线交点用 `orderFlowHit` 同样的容差。
  func orderFlowHovered(_ bands: [OrderFlowBand], pane: Pane, range: PriceRange, L: Layout) -> OrderFlowBand? {
    guard let cross = state.crosshair, cross.pane == nil, !bands.isEmpty, !state.series.isEmpty else { return nil }
    let i = min(max(0, cross.index), state.series.count - 1)
    let cy = KanpanCore.yOf(cross.price ?? state.series.close[i], pane: pane, range: range, mode: state.effectivePriceMode)
    let cx = state.view.x(Double(state.series.time(at: i)), plotW: L.plotW)
    return Self.orderFlowHit(bands, x: cx, y: cy)
  }

  /// 此刻被选中的那一条（十字线在主图上就看十字线，否则看轻点选中的那一堵）及其画出来的样子。
  /// 选中的墙不在这一屏的带里（滚出去了）时 `band` 为空，按整份快照把同侧同类的单现切一遍、并一遍墙找回那一堵；
  /// 快照里也没了就是 nil。认的顺序：键一样 → `covers`（键那一段在墙里）→ `looselyCovers`（键那一段被当碎屑去掉了，
  /// 但落在墙的桶范围与时间跨度里）。
  func orderFlowFocusBand(pane: Pane, range: PriceRange, L: Layout) -> (group: OrderFlowGroup, band: OrderFlowBand?, hovered: Bool)? {
    guard let flow = orderFlowSnapshot, flow.phase == .ready else { return nil }
    let frame = orderFlowBands(pane: pane, range: range, L: L)
    if let cross = state.crosshair {
      guard cross.pane == nil, let band = orderFlowHovered(frame.bands, pane: pane, range: range, L: L) else { return nil }
      return (band.group, band, true)
    }
    guard let key = state.orderFlowSelected else { return nil }
    if let band = frame.bands.first(where: { $0.key == key }) ?? frame.bands.first(where: { $0.group.covers(key) })
      ?? frame.bands.first(where: { $0.group.looselyCovers(key) }) {
      return (band.group, band, false)
    }
    let display = state.orderFlowDisplay
    let kind = flow.orders.filter { display.shows($0) && OrderFlowGroupKey($0).sameKind(key) }
    let walls = OrderFlowGroup.groups(kind, gapMs: orderFlowMergeGapMs, minLifeMs: orderFlowMinLifeMs,
                                      step: flow.thresholds.step)
    guard let group = walls.first(where: { $0.key == key }) ?? walls.first(where: { $0.covers(key) })
      ?? walls.first(where: { $0.looselyCovers(key) }) else { return nil }
    return (group, nil, false)
  }

  /// 这一周期的切段容差：max(60 秒, 一根 K 线)。并墙的时间容差也用它。
  var orderFlowMergeGapMs: Int64 { OrderFlowGroup.mergeGapMs(barMs: state.series.step) }

  /// 已结束的段活不过这么久就不画：一根 K 线。
  var orderFlowMinLifeMs: Int64 { max(0, state.series.step) }

  /// 这一条是不是此刻选中的那一条（选中存的键可能是墙起点前移之前的，按 `covers` 认；键那一段被当碎屑去掉了就按
  /// `looselyCovers`）。轻点同一条收起用。
  public func orderFlowIsSelected(_ group: OrderFlowGroup) -> Bool {
    state.orderFlowSelected.map { group.covers($0) || group.looselyCovers($0) } ?? false
  }

  /// 交给 app 的选中带（出详情卡用）。没选中返回 nil。
  public func orderFlowFocus(size: CGSize) -> ChartOrderFlowFocus? {
    guard !state.series.isEmpty, let flow = orderFlowSnapshot else { return nil }
    let L = layout(size: size), range = priceRange(size: size)
    guard let hit = orderFlowFocusBand(pane: L.main, range: range, L: L) else { return nil }
    let anchorX: Double
    if hit.hovered, let cross = state.crosshair {
      let i = min(max(0, cross.index), state.series.count - 1)
      anchorX = state.view.x(Double(state.series.time(at: i)), plotW: L.plotW)
    } else if let band = hit.band {
      anchorX = Double(band.frame.midX)
    } else {
      anchorX = L.plotW / 2
    }
    let bandY = hit.band.map { Double($0.frame.midY) }
      ?? KanpanCore.yOf(hit.group.price, pane: L.main, range: range, mode: state.effectivePriceMode)
    let bandHalf = hit.band.map { Double($0.frame.height) / 2 } ?? Self.orderFlowBandHeight(tier: hit.group.tier) / 2
    return ChartOrderFlowFocus(group: hit.group, selected: !hit.hovered, anchorX: anchorX, bandY: bandY,
                               bandHalf: bandHalf, plotW: L.plotW,
                               mainTop: L.main.y + mainLegendInset(plotW: L.plotW) + 4,
                               mainBottom: L.main.y + L.main.h, mainHeight: L.main.h, asOfMs: flow.asOfMs)
  }

  private func computeOrderFlowBands(pane: Pane, range: PriceRange, L: Layout) -> OrderFlowFrame {
    guard let flow = orderFlowSnapshot, flow.phase == .ready, !flow.orders.isEmpty,
          !state.series.isEmpty, L.plotW > 0 else { return OrderFlowFrame() }
    let mode = state.effectivePriceMode
    let y = { (p: Double) in KanpanCore.yOf(p, pane: pane, range: range, mode: mode) }
    let spacing = state.view.barSpacing(step: state.series.step, plotW: L.plotW)
    let display = state.orderFlowDisplay

    // 1. 逐单：过显示开关；图例合计只算还挂着、落在主图里、横向落在这一屏的单（逐单求和，不因合并变）。
    var frame = OrderFlowFrame()
    var shown: [BigOrder] = []
    shown.reserveCapacity(flow.orders.count)
    for order in flow.orders where display.shows(order) {
      shown.append(order)
      guard order.isLive else { continue }
      let cy = y(order.price)
      guard cy.isFinite, cy >= pane.y, cy <= pane.y + pane.h,
            let x0 = orderFlowBarX(order.firstSeenMs, spacing: spacing, plotW: L.plotW)?.left, x0 < L.plotW else { continue }
      if order.side == .bid { frame.bidTotal += order.notional } else { frame.askTotal += order.notional }
    }
    guard !shown.isEmpty else { return frame }

    // 2. 按「桶 × 侧 × 类 × 时间段」切段（切段只看时间与周期，不看这一屏：段的身份跨缩放、平移稳定），
    //    去掉活不过一根 K 线的已结束段，把相邻桶、时间连着的段并成墙；再按墙的时间跨度筛出横向落在这一屏的，
    //    只对它们建组。价位：单桶的墙按代表价、跨桶的按价位范围，落在主图里才算。
    //    横向范围：墙起点那根的左缘到墙结束那根的右缘，有一单还挂着就到主图右缘。
    let gap = orderFlowMergeGapMs
    let parts = OrderFlowGroup.dropShortLived(OrderFlowGroup.segments(shown, gapMs: gap), minLifeMs: orderFlowMinLifeMs)
    var visible: [(group: OrderFlowGroup, left: Double, right: Double)] = []
    for wall in OrderFlowGroup.walls(parts, gapMs: gap) {
      guard let x0 = orderFlowBarX(wall.startMs, spacing: spacing, plotW: L.plotW)?.left else { continue }
      let x1: Double
      if let end = wall.endMs {
        guard let bar = orderFlowBarX(end, spacing: spacing, plotW: L.plotW) else { continue }
        x1 = bar.right
      } else {
        x1 = L.plotW
      }
      let left = max(0, x0), right = min(L.plotW, max(x1, x0 + 1))
      guard right > left, left < L.plotW, let group = wall.group(step: flow.thresholds.step) else { continue }
      if group.isRange {
        let a = y(group.priceLow), b = y(group.priceHigh)
        guard a.isFinite, b.isFinite, max(a, b) >= pane.y, min(a, b) <= pane.y + pane.h else { continue }
      } else {
        let cy = y(group.price)
        guard cy.isFinite, cy >= pane.y, cy <= pane.y + pane.h else { continue }
      }
      visible.append((group, left, right))
    }
    guard !visible.isEmpty else { return frame }
    // 屏内排名：画法名义从大到小，一样的先起的在前，再按键（`drawOrder`，每帧现排、结果确定）。
    visible.sort { OrderFlowGroup.drawOrder($0.group, $1.group) }

    // 3. 按排名定主次与几何；主、次按排名落带，和已落下的（整条或细线）横向交叠、纵向重叠（含 1 pt 间隙）
    //    就压成细线。底噪不占位、不被压。
    var noise: [OrderFlowBand] = [], full: [OrderFlowBand] = [], thin: [OrderFlowBand] = []
    var occupied: [CGRect] = []
    for (rank, (group, left, right)) in visible.enumerated() {
      var role: OrderFlowRole = rank < Self.orderFlowMainCount ? .main
        : rank < Self.orderFlowRankedCount ? .secondary : .noise
      if role == .noise, group.isLive { role = .secondary }
      let cy = y(group.price)
      let color = orderFlowColor(group)
      if role == .noise {
        let rect = CGRect(x: left, y: cy - Self.orderFlowNoiseHeight / 2, width: right - left,
                          height: Self.orderFlowNoiseHeight)
        noise.append(OrderFlowBand(group: group, frame: rect, color: color, dark: group.hasFill, thin: false,
                                   role: .noise, alpha: Self.orderFlowNoiseAlpha))
        continue
      }
      let whole: CGRect
      if role == .main {
        let h = max(Self.orderFlowMainMinHeight, Self.orderFlowBandHeight(tier: group.tier))
        if group.isRange {
          // 跨几个桶：盖住整个价位范围（最低桶的桶价 … 最高桶的桶价 + 步长），至少一条单桶带那么粗。
          let a = y(group.priceLow), b = y(group.priceHigh)
          var top = min(a, b), bottom = max(a, b)
          if bottom - top < h { let mid = (top + bottom) / 2; top = mid - h / 2; bottom = mid + h / 2 }
          whole = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        } else {
          whole = CGRect(x: left, y: cy - h / 2, width: right - left, height: h)
        }
      } else {
        whole = CGRect(x: left, y: cy - Self.orderFlowSecondaryHeight / 2, width: right - left,
                       height: Self.orderFlowSecondaryHeight)
      }
      let clash = occupied.contains { r in
        r.minX < whole.maxX && r.maxX > whole.minX
          && whole.minY < r.maxY + Self.orderFlowGap && whole.maxY > r.minY - Self.orderFlowGap
      }
      let rect = clash
        ? CGRect(x: whole.minX, y: cy - Self.orderFlowThinHeight / 2, width: whole.width, height: Self.orderFlowThinHeight)
        : whole
      occupied.append(rect)
      let band = OrderFlowBand(group: group, frame: rect, color: color, dark: group.hasFill, thin: clash, role: role)
      if clash { thin.append(band) } else { full.append(band) }
    }
    frame.bands = noise + full + thin

    // 4. 金额小签：「主」里整条的、宽 ≥ 48 pt 的才写；按排名放，和已放下的签碰上就不放。
    var labels: [OrderFlowLabel] = []
    for band in full where band.role == .main && Double(band.frame.width) >= Self.orderFlowLabelMinWidth {
      let text = Self.orderFlowAmount(band.group.notional)
      let w = Double(text.width(Self.orderFlowLabelFont)) + 2 * Self.orderFlowLabelPadX
      let right = min(Double(band.frame.maxX), L.plotW) - Self.orderFlowLabelInset
      let h = Self.orderFlowLabelHeight
      let top = min(max(Double(band.frame.midY) - h / 2, pane.y), pane.y + pane.h - h)
      let rect = CGRect(x: max(Double(band.frame.minX), right - w), y: top, width: w, height: h)
      let clash = labels.contains { l in
        l.frame.minX < rect.maxX && l.frame.maxX > rect.minX
          && rect.minY < l.frame.maxY + Self.orderFlowGap && rect.maxY > l.frame.minY - Self.orderFlowGap
      }
      guard !clash else { continue }
      labels.append(OrderFlowLabel(key: band.key, text: text, frame: rect, fill: band.color,
                                   ink: Self.orderFlowLabelInk(band.color)))
    }
    frame.labels = labels
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

  /// 此刻主图上画着的色带与小签（视图坐标）、十字线有没有停在一条上、选中的是哪一桶。只给 DEBUG 诊断与测试用。
  func orderFlowDiagnostics(size: CGSize) -> (bands: [OrderFlowBand], labels: [OrderFlowLabel], hovered: Bool,
                                               focus: ChartOrderFlowFocus?) {
    guard !state.series.isEmpty else { return ([], [], false, nil) }
    let L = layout(size: size)
    let focus = orderFlowFocus(size: size)
    let frame = orderFlowFrame(pane: L.main, range: priceRange(size: size), L: L)
    return (frame.bands, frame.labels, focus.map { !$0.selected } ?? false, focus)
  }

  /// 在 plotLayer 上画色带（底噪、整条、细线依次）。返回画了几条（给测试核对）。
  @discardableResult
  func drawOrderFlow(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Int {
    let frame = orderFlowBands(pane: pane, range: range, L: L)
    guard !frame.bands.isEmpty else { return 0 }
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    for band in frame.bands {
      ctx.setAlpha(CGFloat(band.alpha))
      ctx.setFillColor(Paint.cg(band.color))
      ctx.fill(band.frame)
    }
    ctx.setAlpha(1)
    ctx.restoreGState()
    return frame.bands.count
  }

  /// 在 crossLayer 上画金额小签。返回画了几枚。
  @discardableResult
  func drawOrderFlowLabels(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Int {
    let frame = orderFlowBands(pane: pane, range: range, L: L)
    guard !frame.labels.isEmpty else { return 0 }
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    for label in frame.labels {
      ctx.setFillColor(Paint.cg(label.fill))
      ctx.addRoundRect(label.frame, radius: 2)
      ctx.fillPath()
      label.text.drawCentered(at: CGPoint(x: label.frame.midX, y: label.frame.midY), font: Self.orderFlowLabelFont,
                              color: label.ink)
    }
    ctx.restoreGState()
    return frame.labels.count
  }

  /// 在 crossLayer 上把选中的那一条再画一遍（压过盖在它上面的细线）并描 1 pt 正文色边。返回画了没有。
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
  /// 选中的那一条写在详情卡上，图例这一行始终是「主力 买 X · 卖 Y」（逐单求和，不因合并变）。
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
