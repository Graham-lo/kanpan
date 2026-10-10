import CoreGraphics
import Foundation
import KanpanCore

// 公允价值缺口（自动分析层，`AutoLayer.fvg`）：三根 K 线留下的失衡缺口，只画几何事实、不下判定。
//
// - 算法与参数全在 KanpanCore（`fvgZones` / `Analysis/fvg.json`），三端同一份黄金样例；这里只把盒子落到像素上。
// - 层级：垫在 K 线下面、压在主力订单流上面（订单流是预混的不透明色块，缺口是少量真透明，叠在它上面还透得出来）。
// - 盒子从中间那根的左缘一直延伸到主图右缘；不画边框。中线（原始缺口的 50%）被回补过就不画。
// - 不撑价格区间（`overlayLines()` 不看它）；对比态（百分比轴）不画；没有命中、没有十字线读数。
// - 颜色不用涨跌色（会和订单流的买卖墙撞色）：多头用 BOLL 的 `band`、空头用 BOLL 的 `amber`，三套皮肤各自的那一对。
extension ChartRenderer {
  /// 缺口区间的缓存：按「序列身份戳 + 根数 + 已收线根数」认。十字线动、拖图、捏合都不重算；
  /// 来一笔 tick（末根被覆盖，戳就换了）才重扫一遍——只扫最近 500 根，微秒级。
  /// 戳是全局唯一的（`SeriesStamp`），所以盒子长驻在渲染器上、跨副本共用也不会串。
  final class FVGCache {
    var key: (revision: UInt64, count: Int, closed: Int)?
    var zones: [FVGZone] = []
    /// 真算了几次（测试核对缓存有没有生效）。
    var computed = 0
  }

  /// 盒子填充的不透明度（三套皮肤同一个数，经典白底上也看得出又不发脏）。
  static let fvgFillAlpha: CGFloat = 0.12
  /// 中线：0.5 pt 虚线。
  static let fvgMidAlpha: CGFloat = 0.35
  static let fvgMidWidth: CGFloat = 0.5
  static let fvgMidDash: [CGFloat] = [3, 3]

  /// 这一帧画不画缺口：开关开着、不在对比态、有 K 线。
  var fvgActive: Bool {
    state.autoLayers.contains(.fvg) && !state.percentAxis && state.compare.isEmpty && !state.series.isEmpty
  }

  /// 此刻还在的缺口（`fvgActive` 不成立时是空的，也不进缓存）。
  func fvgCurrentZones() -> [FVGZone] {
    guard fvgActive else { return [] }
    let s = state.series, closed = state.closedBarCount
    if let k = fvgCache.key, k.revision == s.revision, k.count == s.count, k.closed == closed {
      return fvgCache.zones
    }
    let zones = KanpanCore.fvgZones(series: s, closedCount: closed)
    fvgCache.key = (s.revision, s.count, closed)
    fvgCache.zones = zones
    fvgCache.computed += 1
    return zones
  }

  /// 在 plotLayer 上画缺口（`drawOrderFlow` 之后、`drawCandles` 之前）。返回画了几个盒子（给测试核对）。
  @discardableResult
  func drawFVG(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Int {
    let zones = fvgCurrentZones()
    guard !zones.isEmpty else { return 0 }
    let rects = fvgRects(zones, pane: pane, range: range, plotW: L.plotW)
    guard !rects.isEmpty else { return 0 }
    let t = state.colors
    ctx.saveGState()
    defer { ctx.restoreGState() }
    // 和订单流同一块画布范围：图例那几行以下（缺口的价位落进图例时不从字中间穿过去）。
    ctx.clip(to: orderFlowPlotClip(pane: pane, plotW: L.plotW))
    for item in rects {
      let color = Paint.cg(item.zone.side == .bull ? t.band : t.amber)
      ctx.setFillColor(color.copy(alpha: Self.fvgFillAlpha) ?? color)
      ctx.fill(item.box)
      if let midY = item.midY {
        ctx.setStrokeColor(color.copy(alpha: Self.fvgMidAlpha) ?? color)
        ctx.setLineWidth(Self.fvgMidWidth)
        ctx.setLineDash(phase: 0, lengths: Self.fvgMidDash)
        ctx.move(to: CGPoint(x: item.box.minX, y: midY))
        ctx.addLine(to: CGPoint(x: item.box.maxX, y: midY))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
      }
    }
    return rects.count
  }

  /// 每个缺口在这一屏的盒子（视图坐标）与中线高度；整个落在视野外的不给。
  func fvgRects(_ zones: [FVGZone], pane: Pane, range: PriceRange, plotW: Double)
    -> [(zone: FVGZone, box: CGRect, midY: Double?)] {
    let spacing = state.view.barSpacing(step: state.series.step, plotW: plotW)
    let mode = state.effectivePriceMode
    let clip = orderFlowPlotClip(pane: pane, plotW: plotW)
    var out: [(zone: FVGZone, box: CGRect, midY: Double?)] = []
    for z in zones {
      guard let bar = orderFlowBarX(z.startMs, spacing: spacing, plotW: plotW) else { continue }
      // 起点那根已经滑出左缘：从 0 画起；起点在右缘以外：这一屏还看不到它。
      let x0 = bar.left.isFinite ? max(0, bar.left) : 0
      guard x0 < plotW else { continue }
      let yA = KanpanCore.yOf(z.top, pane: pane, range: range, mode: mode)
      let yB = KanpanCore.yOf(z.bottom, pane: pane, range: range, mode: mode)
      guard yA.isFinite, yB.isFinite else { continue }
      let lo = min(yA, yB), hi = max(yA, yB)
      guard hi >= Double(clip.minY), lo <= Double(clip.maxY) else { continue }
      // 被回补到极薄也留一根发丝那么高，不至于画了个看不见的盒子。
      let box = CGRect(x: x0, y: lo, width: plotW - x0, height: max(hi - lo, 0.5))
      var midY: Double?
      if z.midVisible {
        let y = KanpanCore.yOf(z.mid, pane: pane, range: range, mode: mode)
        if y.isFinite { midY = y }
      }
      out.append((z, box, midY))
    }
    return out
  }

  /// 此刻画出来的缺口（视图坐标）。只给 DEBUG 诊断与测试用。
  func fvgDiagnostics(size: CGSize) -> [(zone: FVGZone, box: CGRect)] {
    guard fvgActive else { return [] }
    let L = layout(size: size)
    return fvgRects(fvgCurrentZones(), pane: L.main, range: priceRange(size: size), plotW: L.plotW).map { ($0.zone, $0.box) }
  }
}
