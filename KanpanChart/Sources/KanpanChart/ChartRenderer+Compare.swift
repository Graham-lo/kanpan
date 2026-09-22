import CoreGraphics
import Foundation
import KanpanCore
import UIKit

extension ChartRenderer {
  /// 在主品种原始价格空间内归一化；所有主图坐标消费者仍共用同一个 PriceRange。
  func compareRange(view: ViewWindow, transform: PriceTransform, paneHeight: Double, topInset: Double) -> PriceRange {
    let base = state.compareBase(view: view), index = state.compareBaseIndex(view: view)
    let bounds = visibleRange(view: view, series: state.series)
    var extra = [base]
    for series in state.compare {
      for i in bounds.lo...bounds.hi {
        if let value = series.percent(at: i, baseIndex: index) { extra.append((1 + value / 100) * base) }
      }
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

  func drawCompare(_ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout) {
    let bounds = visibleRange(view: state.view, series: state.series)
    let baseIndex = state.compareBaseIndex()
    let map = PriceMapping(range: r, mode: .percent)
    ctx.saveGState(); defer { ctx.restoreGState() }
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    ctx.setLineWidth(1); ctx.setLineJoin(.round)
    for series in state.compare {
      ctx.setStrokeColor(Paint.cg(series.color)); ctx.beginPath()
      var connected = false
      var previousTime: Int64?
      for i in bounds.lo...bounds.hi {
        guard let percent = series.percent(at: i, baseIndex: baseIndex) else {
          connected = false; previousTime = nil; continue
        }
        let time = state.series.time(at: i)
        // 主序列自己有缺根时，也不能把这段时间跨过去连线。
        if let previousTime, !compareAdjacent(previousTime, time) { connected = false }
        let point = CGPoint(x: state.view.x(Double(time), plotW: L.plotW),
          y: map.y((1 + percent / 100) * r.base, pane: pane))
        if connected { ctx.addLine(to: point) } else { ctx.move(to: point) }
        connected = true; previousTime = time
      }
      ctx.strokePath()
    }
  }

  private func compareAdjacent(_ before: Int64, _ after: Int64) -> Bool {
    let interval = state.series.interval
    guard interval.isIrregular else { return after - before == interval.stepMs }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = Date(timeIntervalSince1970: Double(before) / 1000)
    guard let next = calendar.date(byAdding: interval == .mo1 ? .month : .year, value: 1, to: date) else { return false }
    return Int64(next.timeIntervalSince1970 * 1000) == after
  }

  public var compareLegend: [(name: String, value: Double?, color: Hex)] {
    guard state.percentAxis, !state.series.isEmpty else { return [] }
    let index = legendIndex, baseIndex = state.compareBaseIndex()
    let main = (state.series.close[index] / state.compareBase() - 1) * 100
    return [(state.symbol.base, main, state.colors.text)] + state.compare.map {
      ($0.name, $0.percent(at: index, baseIndex: baseIndex), $0.color)
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
