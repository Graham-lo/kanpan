import CoreGraphics
import Foundation
import KanpanCore
import UIKit

/// 图上大单与爆仓气泡（2026-10-08 定版「统一透明泡」，三端规格 `docs/design/大单爆仓气泡-三端规格-2026-10-08.md`）：
/// 把 `state.bigTrades` 的大单分钟账与爆仓分钟账按本图 K 线并成每根向上（大买 + 空单爆仓）/ 向下（大卖 + 多单爆仓），
/// 最近 300 根定点线 / 泡线，交给 `BigTradeBubbles.plan` 摆好（躲图例那一带、画线文字、主图上下沿），
/// 画在底图里画线之上。
///
/// 两只缓存盒子：
/// - `BigTradeBarsCache`：每根的向上 / 向下与门槛，只认「序列身份 + 分钟账」，拖图、捏合不重算；
/// - `BigTradeBubbleCache`：这一屏摆好的点与泡，`recalc` 跟订单流色带同一套失效（输入 / 视野 / 画线变了换盒子），
///   十字线动不换——底图、点击、动效三处取的是同一份。
extension ChartRenderer {
  final class BigTradeBarsCache {
    var key: (revision: UInt64, tape: BigTradeTape)?
    var up: [Double] = []
    var down: [Double] = []
    var tiers: BigTradeTiers?
    /// 真算了几次（测试核对）。
    var computed = 0
  }

  final class BigTradeBubbleCache {
    var entries: [(plotW: Double, paneY: Double, paneH: Double, items: [BigTradeBubble])] = []
  }

  /// 泡上的字：11 号半粗、等宽数字。
  static let bigTradeFont = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
  /// 图例那一带的高度：点与泡一律不进去。
  static let bigTradeLegendBand = 24.0
  /// 泡的填充（浅色 / 深色皮肤）、描边、点的不透明度、柄。
  static let bubbleFillAlpha: CGFloat = 0.16
  static let bubbleFillAlphaDark: CGFloat = 0.22
  static let bubbleStrokeWidth: CGFloat = 1.4
  static let bigTradeDotAlpha: CGFloat = 0.85
  static let bubbleStemWidth: CGFloat = 1.2
  static let bubbleStemAlpha: CGFloat = 0.6
  /// 泡内数字垫底那圈图底色描边，按字号的百分比（11pt × 24% ≈ 2.6pt 总宽，往外约 1.3pt）。
  static let bubbleTextHaloPercent: CGFloat = 24

  /// 分钟以下的周期（秒线）不出：分钟账并不进去。大单与爆仓有一样就画。
  var bigTradeActive: Bool {
    guard let tape = state.bigTrades, !state.percentAxis, !state.series.isEmpty else { return false }
    return state.series.step >= BigTradeFlow.minuteMs && !tape.isEmpty
  }

  /// 每根的向上 / 向下与门槛（按序列身份 + 分钟账缓存）。
  func bigTradeBars() -> (up: [Double], down: [Double], tiers: BigTradeTiers?)? {
    guard bigTradeActive, let tape = state.bigTrades else { return nil }
    let s = state.series
    let box = bigTradeBarsCache
    if let k = box.key, k.revision == s.revision, k.tape == tape { return (box.up, box.down, box.tiers) }
    var opens = [Int64](repeating: 0, count: s.count)
    for i in 0..<s.count { opens[i] = s.time(at: i) }
    let end = s.lastTime + s.step
    let trades = tape.bars(opens: opens, lastEnd: end)
    var up = trades.buy, down = trades.sell
    if !tape.liqMinutes.isEmpty {
      let liq = tape.liqBars(opens: opens, lastEnd: end)
      for i in 0..<s.count {
        up[i] += liq.short[i]
        down[i] += liq.long[i]
      }
    }
    let from = max(0, s.count - BigTradeBubbles.tierBars)
    var vals: [Double] = []
    vals.reserveCapacity(s.count - from)
    for i in from..<s.count { vals.append(max(up[i], down[i])) }
    box.key = (s.revision, tape)
    box.up = up; box.down = down
    box.tiers = BigTradeBubbles.tiers(vals, floor: tape.floor)
    box.computed += 1
    return (up, down, box.tiers)
  }

  /// 这一屏摆好的点与泡（视图坐标）。
  public func bigTradeBubbles(size: CGSize) -> [BigTradeBubble] {
    guard bigTradeActive else { return [] }
    let L = layout(size: size)
    return bigTradeBubbles(pane: L.main, range: priceRange(size: size), L: L)
  }

  func bigTradeBubbles(pane: Pane, range: PriceRange, L: Layout) -> [BigTradeBubble] {
    guard bigTradeActive else { return [] }
    if let hit = bigTradeBubbleCache.entries.first(where: { $0.plotW == L.plotW && $0.paneY == pane.y && $0.paneH == pane.h }) {
      return hit.items
    }
    let items = computeBigTradeBubbles(pane: pane, range: range, L: L)
    if bigTradeBubbleCache.entries.count >= 3 { bigTradeBubbleCache.entries.removeFirst() }
    bigTradeBubbleCache.entries.append((L.plotW, pane.y, pane.h, items))
    return items
  }

  private func computeBigTradeBubbles(pane: Pane, range: PriceRange, L: Layout) -> [BigTradeBubble] {
    guard let bars = bigTradeBars(), let tiers = bars.tiers else { return [] }
    let s = state.series
    let (lo, hi) = visibleRange(view: state.view, series: s)
    guard lo <= hi, s.close.indices.contains(lo), s.close.indices.contains(hi) else { return [] }
    let mode = state.effectivePriceMode
    let heikinOn = state.options.kind == .heikin
    var inputs: [BigTradeBubbleInput] = []
    for i in lo...hi where bars.up[i] > 0 || bars.down[i] > 0 {
      let t = s.time(at: i)
      let x = CGFloat(state.view.x(Double(t), plotW: L.plotW))
      guard x >= 0, x <= CGFloat(L.plotW) else { continue }
      var h = s.high[i], l = s.low[i]
      if heikinOn, let ha = heikin?.bar(i) { h = max(h, ha.h); l = min(l, ha.l) }
      inputs.append(BigTradeBubbleInput(
        index: i, t: t, x: x,
        hiY: CGFloat(KanpanCore.yOf(h, pane: pane, range: range, mode: mode)),
        loY: CGFloat(KanpanCore.yOf(l, pane: pane, range: range, mode: mode)),
        up: bars.up[i], down: bars.down[i]))
    }
    guard !inputs.isEmpty else { return [] }
    let env = BigTradeBubbleEnv(
      tiers: tiers,
      spacing: CGFloat(state.view.barSpacing(step: s.step, plotW: L.plotW)),
      top: CGFloat(pane.y + max(Self.bigTradeLegendBand, mainLegendInset(plotW: L.plotW))),
      bottom: CGFloat(pane.y + pane.h),
      plotW: CGFloat(L.plotW),
      avoid: drawingLabelBoxes(pane: pane, range: range, L: L),
      measure: { $0.width(Self.bigTradeFont) })
    return BigTradeBubbles.plan(inputs, env: env)
  }

  /// 底图上画点与泡（画线之上、最新价之下）：柄全部先画，再画点，泡压在最上。返回画了几枚。
  @discardableResult
  func drawBigTrades(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Int {
    let items = bigTradeBubbles(pane: pane, range: range, L: L)
    guard !items.isEmpty else { return 0 }
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    let colors = state.colors, dark = state.dark
    for b in items where b.isBubble { Self.paintBigTradeStem(ctx, b, colors: colors) }
    for b in items where !b.isBubble { Self.paintBigTradeBubble(ctx, b, colors: colors, dark: dark, scale: 1) }
    for b in items where b.isBubble { Self.paintBigTradeBubble(ctx, b, colors: colors, dark: dark, scale: 1) }
    return items.count
  }

  static func bigTradeColor(_ b: BigTradeBubble, colors: ChartColors) -> Hex { b.up ? colors.up : colors.down }

  /// 柄：锚点到泡近边，1.2 宽、.6 透明、方向色。
  static func paintBigTradeStem(_ ctx: CGContext, _ b: BigTradeBubble, colors: ChartColors) {
    let color = Paint.cg(bigTradeColor(b, colors: colors))
    let (p0, p1) = b.stem
    guard abs(p1.y - p0.y) > 0.5 else { return }
    ctx.setStrokeColor(color.copy(alpha: bubbleStemAlpha) ?? color)
    ctx.setLineWidth(bubbleStemWidth)
    ctx.beginPath()
    ctx.move(to: p0); ctx.addLine(to: p1)
    ctx.strokePath()
  }

  /// 画一枚点或泡（底图与点击放大的那一下共用，不含柄）。`scale` 以圆心为原点放大。
  static func paintBigTradeBubble(_ ctx: CGContext, _ b: BigTradeBubble, colors: ChartColors, dark: Bool, scale k: CGFloat) {
    let bg = colors.bg
    let hex = bigTradeColor(b, colors: colors)
    let color = Paint.cg(hex)
    ctx.saveGState()
    defer { ctx.restoreGState() }
    if k != 1 {
      let c = b.center
      ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: -c.x, y: -c.y)
    }
    guard b.isBubble else {
      ctx.setFillColor(color.copy(alpha: bigTradeDotAlpha) ?? color)
      ctx.fillEllipse(in: b.bounds)
      return
    }
    // 描边压在圆周上：填充按整圆，描边往里收半个线宽，外沿正好落在半径上。
    ctx.setFillColor(color.copy(alpha: dark ? bubbleFillAlphaDark : bubbleFillAlpha) ?? color)
    ctx.fillEllipse(in: b.bounds)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(bubbleStrokeWidth)
    ctx.strokeEllipse(in: b.bounds.insetBy(dx: bubbleStrokeWidth / 2, dy: bubbleStrokeWidth / 2))
    // 数字底下先垫一圈图底色的细描边：泡是透明的，同色的 K 线实体穿过数字时会糊成一片（真图实测）。
    // 不占地方、不改几何，只多画一遍字（一屏最多 6 枚）。
    let s = ChartFont.measure(b.text, bigTradeFont)
    let origin = CGPoint(x: b.center.x - s.width / 2, y: b.center.y - s.height / 2)
    (b.text as NSString).draw(at: origin, withAttributes: [
      .font: bigTradeFont, .strokeColor: UIColor(cgColor: Paint.cg(bg)), .strokeWidth: bubbleTextHaloPercent,
    ])
    b.text.drawCentered(at: b.center, font: bigTradeFont, color: hex)
  }

  /// 点在哪枚泡上（视图坐标；只认泡，44 × 44 热区，取最近）。
  public func bigTradeHit(at p: CGPoint, size: CGSize) -> BigTradeBubble? {
    let items = bigTradeBubbles(size: size)
    guard items.contains(where: \.isBubble) else { return nil }
    let L = layout(size: size)
    guard p.x >= 0, Double(p.x) <= L.plotW, Double(p.y) >= L.main.y - 22, Double(p.y) <= L.main.y + L.main.h + 22
    else { return nil }
    return BigTradeBubbles.hit(p, in: items)
  }

  /// 读屏一句：「10-08 12:30 向上 1.2M」。
  public func bigTradeAccessibilityLabel(_ b: BigTradeBubble) -> String {
    BigTradeBubbles.accessibilityLabel(
      b, time: fmtFull(ms: Double(b.t), offsetMinutes: state.timezone.offsetMinutes), amount: Self.orderFlowAmount(b.usd))
  }

  /// 正在走那一根最近一笔大单那一侧的点或泡（光环挂在它上面）；那一侧没画就取这根的另一侧。
  public func bigTradeLiveBubble(size: CGSize) -> BigTradeBubble? {
    let last = state.series.count - 1
    let items = bigTradeBubbles(size: size).filter { $0.index == last }
    let up = state.bigTrades?.lastBigBuy ?? true
    return items.first { $0.up == up } ?? items.first
  }
}
