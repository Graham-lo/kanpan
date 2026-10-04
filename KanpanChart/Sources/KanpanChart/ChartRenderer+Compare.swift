import CoreGraphics
import Foundation
import KanpanCore
import UIKit

extension ChartRenderer {
  /// 在主品种原始价格空间内归一化；所有主图坐标消费者仍共用同一个 PriceRange。
  func compareRange(view: ViewWindow, transform: PriceTransform, paneHeight: Double, topInset: Double) -> PriceRange {
    let base = state.compareBase(view: view)
    var extra = [base]
    for line in compareLines(view: view) {
      for case let point? in line.percents { extra.append((1 + point.percent / 100) * base) }
    }
    // 线性空间与百分比空间仅差一个正的常数因子；留白、反转、手动缩放保持现有算法。
    var linear = transform; linear.mode = .linear
    var result = KanpanCore.priceRange(view: view, series: state.series, transform: linear,
      extraPrices: extra + (heikin?.extremes ?? []), bias: state.options.bias,
      paneHeight: paneHeight, topInset: topInset, anchorPrice: transform.isManual ? state.axisScaleAnchor : nil)
    result.base = base
    return result
  }

  func mainPriceTicks(range: PriceRange, paneHeight: Double) -> [Double] {
    var ticks = priceTicks(range: range, mode: state.effectivePriceMode, paneH: paneHeight)
    if state.percentAxis, range.lo <= range.base, range.hi >= range.base {
      // 0% 必须有一格；删掉离它不足一行字的邻刻度，避免两个标签叠在一起。
      let span = (range.hi - range.lo) / range.base * 100
      ticks.removeAll { abs($0) / max(span, 1e-12) * paneHeight < 14 }
      ticks.append(0); ticks.sort()
    }
    return ticks
  }

  /// 一条比价线在某个视野里的样子：它自己的基准根、从哪根起画、逐根的涨跌幅（缺根为 nil）。
  struct CompareLine {
    var series: CompareSeries
    /// 这条线的 0% 落在哪一根（见 `CompareSeries.baseIndex`）。
    var baseIndex: Int
    /// 从哪一根起有资格画：基准就是主品种那一根时从可见段最左（含左侧护栏根）起，
    /// 基准往后挪了就从基准那根起——基准之前没有「相对于它」的涨跌可言。
    var from: Int
    /// 可见段 `lo...hi` 上逐根的读数，`from` 之前与缺根处为 nil。
    var percents: [(index: Int, percent: Double)?]
  }

  /// 价格区间、画线、图例共用的一份比价几何：三处各算各的就会出现「线画在 A 基准上、
  /// 图例报 B 基准」这种对不上（审查 B·P1-2）。
  func compareLines(view: ViewWindow? = nil) -> [CompareLine] {
    guard !state.series.isEmpty else { return [] }
    let view = view ?? state.view
    let bounds = visibleRange(view: view, series: state.series)
    return state.compare.map { series in
      let anchor = compareAnchor(series, view: view)
      let percents: [(index: Int, percent: Double)?] = (bounds.lo...bounds.hi).map { i in
        guard let anchor, i >= anchor.from,
              let value = series.percent(at: i, baseIndex: anchor.baseIndex) else { return nil }
        return (i, value)
      }
      return CompareLine(series: series, baseIndex: anchor?.baseIndex ?? bounds.hi + 1,
                         from: anchor?.from ?? bounds.hi + 1, percents: percents)
    }
  }

  /// 一条比价线的基准根与起画根；可见段里它一根开盘价都没有时给 nil（整条不画）。
  func compareAnchor(_ series: CompareSeries, view: ViewWindow? = nil) -> (baseIndex: Int, from: Int)? {
    guard !state.series.isEmpty else { return nil }
    let view = view ?? state.view
    let bounds = visibleRange(view: view, series: state.series)
    let mainBase = state.compareBaseIndex(view: view)
    guard let base = series.baseIndex(from: mainBase, through: bounds.hi) else { return nil }
    return (base, base == mainBase ? bounds.lo : base)
  }

  /// 每条比价线断成的若干段折线（屏幕坐标）。`drawCompare` 照它画，测试照它量。
  func compareSegments(pane: Pane, r: PriceRange, L: Layout) -> [[[CGPoint]]] {
    let map = PriceMapping(range: r, mode: .percent)
    return compareLines().map { line in
      var segments: [[CGPoint]] = []
      var current: [CGPoint] = []
      var previousTime: Int64?
      for entry in line.percents {
        guard let entry else {
          if !current.isEmpty { segments.append(current); current = [] }
          previousTime = nil; continue
        }
        let i = entry.index, percent = entry.percent
        let time = state.series.time(at: i)
        // 主序列自己有缺根时，也不能把这段时间跨过去连线。
        if let previousTime, !compareAdjacent(previousTime, time), !current.isEmpty {
          segments.append(current); current = []
        }
        current.append(CGPoint(x: state.view.x(Double(time), plotW: L.plotW),
                               y: map.y((1 + percent / 100) * r.base, pane: pane)))
        previousTime = time
      }
      if !current.isEmpty { segments.append(current) }
      return segments
    }
  }

  func drawCompare(_ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout) {
    ctx.saveGState(); defer { ctx.restoreGState() }
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    ctx.setLineWidth(1); ctx.setLineJoin(.round)
    for (series, segments) in zip(state.compare, compareSegments(pane: pane, r: r, L: L)) {
      var pen = PolylinePen(ctx, color: Paint.cg(series.color))
      for segment in segments {
        for point in segment { pen.add(point) }
        pen.lift()
      }
      pen.finish()
    }
  }

  private func compareAdjacent(_ before: Int64, _ after: Int64) -> Bool {
    let interval = state.series.interval
    return interval.advancing(before, by: 1) == after
  }

  public var compareLegend: [(name: String, value: Double?, color: Hex)] {
    guard state.percentAxis, !state.series.isEmpty else { return [] }
    let index = legendIndex
    let main = (state.series.close[index] / state.compareBase() - 1) * 100
    return [(state.symbol.base, main, state.colors.text)] + state.compare.map { series in
      // 十字线停在这条线的基准之前：那一根没有「相对于它」的涨跌，报「—」。
      let anchor = compareAnchor(series)
      let value = anchor.flatMap { index >= $0.from ? series.percent(at: index, baseIndex: $0.baseIndex) : nil }
      return (series.name, value, series.color)
    }
  }

  func compareLegendInset(plotW: Double) -> Double {
    var x = 8.0, rows = 1.0
    for entry in compareLegend {
      // 宽度只依赖品种名，十字线读数变化不触发几何重建。
      let width = Double((entry.name + " −999.99%").width(ChartFont.axis)) + 8
      if x + width > plotW - 4 { rows += 1; x = 8 }
      x += min(width, plotW - 12)
    }
    return max(AICoinBehavior.mainTopInset, rows * 12 + 12)
  }

  func drawCompareLegend(_ ctx: CGContext, pane: Pane, L: Layout) {
    var x = 8.0, y = pane.y + 9
    ctx.saveGState(); defer { ctx.restoreGState() }
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: mainLegendInset(plotW: L.plotW)))
    for entry in compareLegend {
      let width = Double((entry.name + " −999.99%").width(ChartFont.axis)) + 8
      if x + width > L.plotW - 4 { x = 8; y += 12 }
      (entry.name + " " + ChartState.comparePercentLabel(entry.value))
        .drawLeft(at: CGPoint(x: x, y: y), font: ChartFont.axis, color: entry.color)
      x += min(width, L.plotW - 12)
    }
  }
}
