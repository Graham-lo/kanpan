import CoreGraphics
import Foundation
import KanpanCore

/// 取证探针：把一帧画出来的几何量出来（A3.2 / A3.10）。
///
/// 单独一个 extension 文件，**不动** `ChartRenderer` 既有的绘制与脏位逻辑。这里的
/// 每个数都必须和 `drawCandles` 里那几行用同一个函数算出来（`candleMetrics` /
/// `snap` / `hairline` 全在 `KanpanCore`），否则量的就不是真画出来的东西了。
///
/// 单位一律 pt；比对原型时乘 scale 换成设备像素，A3.2 的容差是 ±1 设备像素。

/// A3.2 的 7 项几何，外加几个方便对账的参考量。
public struct ChartProbe: Sendable, Equatable {
  /// 右侧价格轴宽。
  public var axisW: Double
  /// 时间轴高。
  public var timeH: Double
  /// 单个副图高。
  public var subH: Double
  /// 根间距。
  public var spacing: Double
  /// 实体宽。
  public var bodyW: Double
  /// 影线宽。
  public var wickW: Double
  /// 上留白比例：可见最高价（并入主图叠加线）离主图顶的距离 ÷ 主图高。
  public var padTop: Double
  /// 下留白比例，口径同上。
  public var padBottom: Double

  // ---- 参考量，A3.2 不判定，写进证据表方便人看 ----
  public var plotW: Double
  public var mainH: Double
  public var thin: Bool
  public var minBody: Double
  public var outline: Double
  public var rangeLo: Double
  public var rangeHi: Double
  public var rangeBase: Double
  public var visibleLo: Int
  public var visibleHi: Int
  public var viewFrom: Double
  public var viewTo: Double

  public var metrics: [String: Double] {
    ["axisW": axisW, "timeH": timeH, "subH": subH, "spacing": spacing,
     "bodyW": bodyW, "wickW": wickW, "padTop": padTop]
  }
}

/// 一根蜡烛落在画布上的位置（A3.10 的断言对象，也是 A3.3 的取样坐标来源）。
///
/// 每个数都按 `drawCandles` 里的同一行算，别处不许再推一遍。
public struct CandleXProbe: Sendable, Equatable {
  public var index: Int
  /// 根中心，未对齐——它本来就允许落在像素中间。
  public var center: Double
  /// `drawCandles` 里实体的左缘：`snap(center - bodyW / 2)`。
  public var bodyLeft: Double
  /// 影线矩形的左缘：`snap(center - wickW / 2)`。
  public var wickLeft: Double
  /// round 端头时影线描边走的中线：`hairline(center)`。
  public var wickHair: Double

  /// 收 ≥ 开。
  public var up: Bool
  /// 影线上下端（high / low 的 y）。
  public var wickTop: Double
  public var wickBottom: Double
  /// 实体顶与实体高（已经套过 `minBody`）。
  public var bodyTop: Double
  public var bodyHeight: Double
  /// 这根会不会走「描边挖空」那条分支（`hollowShape && drawHollow && 尺寸够`）。
  public var hollow: Bool
}

extension ChartRenderer {
  /// 量一帧。`size` / `scale` 必须和真画的时候传的一样。
  public func probe(size: CGSize, scale: CGFloat) -> ChartProbe {
    let L = layout(size: size)
    let r = priceRange(size: size)
    let b = state.series
    let s = Double(scale)
    let spacing = state.view.barSpacing(step: b.step, plotW: L.plotW)
    let m = candleMetrics(spacing: spacing, scale: s)
    let (lo, hi) = visibleRange(view: state.view, series: b)
    let pane = L.main

    // 进价格区间的那几条线，和 `priceRange(size:)` 用的是同一份（见 overlayLines）。
    var hiP = -Double.infinity, loP = Double.infinity
    if !b.isEmpty {
      // 收盘价画法只按收盘撑区间（`priceRange(closeOnly:)`），留白也按收盘量。
      let closeOnly = state.options.kind == .line
      for i in lo...hi {
        let h = closeOnly ? b.close[i] : b.high[i], l = closeOnly ? b.close[i] : b.low[i]
        if h > hiP { hiP = h }
        if l < loP { loP = l }
      }
      for arr in probeOverlayLines() where arr.count > lo {
        for i in lo...min(hi, arr.count - 1) where arr[i].isFinite {
          if arr[i] > hiP { hiP = arr[i] }
          if arr[i] < loP { loP = arr[i] }
        }
      }
      // 平均 K 线的 hh/hl 必然在真实 high/low 之外，量留白得按真正画出来的那一根量。
      for p in heikin?.extremes ?? [] where p.isFinite {
        if p > hiP { hiP = p }
        if p < loP { loP = p }
      }
    }
    let yHi = KanpanCore.yOf(hiP, pane: pane, range: r, mode: state.effectivePriceMode)
    let yLo = KanpanCore.yOf(loP, pane: pane, range: r, mode: state.effectivePriceMode)

    return ChartProbe(
      axisW: L.axisW,
      timeH: AICoinBehavior.timeHeight,
      subH: L.subH,
      spacing: spacing,
      bodyW: m.bodyW,
      wickW: m.wickW,
      padTop: (yHi - pane.y) / pane.h,
      padBottom: (pane.y + pane.h - yLo) / pane.h,
      plotW: L.plotW,
      mainH: L.mainH,
      thin: m.thin,
      minBody: m.minBody,
      outline: m.outline,
      rangeLo: r.lo, rangeHi: r.hi, rangeBase: r.base,
      visibleLo: lo, visibleHi: hi,
      viewFrom: state.view.from, viewTo: state.view.to)
  }

  /// `drawCandles` 真正用到的那几个 x，逐根列出来（A3.10）。
  ///
  /// 跳过的根和画的时候一样：`xc < -4 || xc > plotW + 4` 不画。
  public func candleXs(size: CGSize, scale: CGFloat) -> [CandleXProbe] {
    let L = layout(size: size)
    let b = state.series
    // 收盘价画法一根蜡烛都不画，照实报空。
    guard !b.isEmpty, state.options.kind != .line else { return [] }
    let s = Double(scale)
    let r = priceRange(size: size)
    let pane = L.main
    let shape = state.effectiveShape
    let ha = heikin
    let spacing = state.view.barSpacing(step: b.step, plotW: L.plotW)
    let m = candleMetrics(spacing: spacing, scale: s)
    let minBodyH = max(m.wickW, snap(m.minBody, scale: s))
    let (lo, hi) = visibleRange(view: state.view, series: b)
    func y(_ p: Double) -> Double {
      KanpanCore.yOf(p, pane: pane, range: r, mode: state.effectivePriceMode)
    }
    var out: [CandleXProbe] = []
    out.reserveCapacity(hi - lo + 1)
    for i in lo...hi {
      let xc = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      if xc < -4 || xc > L.plotW + 4 { continue }
      let bar = ha?.bar(i) ?? (o: b.open[i], h: b.high[i], l: b.low[i], c: b.close[i])
      let up = bar.c >= bar.o
      let yo = y(bar.o), yc = y(bar.c)
      // 和 `drawCandles` 一样：上下边各自 snap，高度是两条对齐边之差。
      let top = snap(min(yo, yc), scale: s)
      let h = max(minBodyH, snap(max(yo, yc), scale: s) - top)
      out.append(
        CandleXProbe(
          index: i, center: xc,
          bodyLeft: snap(xc - m.bodyW / 2, scale: s),
          wickLeft: snap(xc - m.wickW / 2, scale: s),
          wickHair: hairline(xc, scale: s),
          up: up,
          wickTop: snap(y(bar.h), scale: s), wickBottom: snap(y(bar.l), scale: s),
          bodyTop: top, bodyHeight: h,
          hollow: shape == .hollowUp && up && h > m.outline * 2.2 && m.bodyW > m.outline * 2.2))
    }
    return out
  }

  /// 最新价线画在哪儿（A3.3 的 `lastLine` 取样行）。超出主图时返回 `nil`，和
  /// `drawLastPrice` 的提前返回一致。
  public func lastPriceY(size: CGSize) -> (y: Double, up: Bool)? {
    let b = state.series
    // 实时价格线关掉了就真的什么都没画，取证也得照实说没有。
    guard state.options.lastLine, !b.isEmpty else { return nil }
    let L = layout(size: size)
    let r = priceRange(size: size)
    let pane = L.main
    let i = b.count - 1
    let y = KanpanCore.yOf(b.close[i], pane: pane, range: r, mode: state.effectivePriceMode)
    if y < pane.y || y > pane.y + pane.h { return nil }
    return (y, b.close[i] >= b.open[i])
  }

  /// 价格网格线的 y（已经按 `drawPriceGrid` 的规则筛过边缘）。
  public func priceGridYs(size: CGSize) -> [Double] {
    let L = layout(size: size)
    let r = priceRange(size: size)
    let pane = L.main
    let mode = state.effectivePriceMode
    let a = mode.forward(r.lo, base: r.base), z = mode.forward(r.hi, base: r.base)
    var out: [Double] = []
    for f in priceTicks(range: r, mode: mode, paneH: pane.h) {
      let y = pane.y + pane.h - ((f - a) / (z - a)) * pane.h
      if y < pane.y + 6 || y > pane.y + pane.h - 2 { continue }
      out.append(y)
    }
    return out
  }

  /// 竖向细线的 x（价格轴分隔线 + `grid == .both` 时的时间网格线），已经 hairline 过。
  public func verticalHairlineXs(size: CGSize, scale: CGFloat) -> [Double] {
    let L = layout(size: size)
    let s = Double(scale)
    var out = [hairline(L.plotW, scale: s)]
    guard state.effectiveGrid == .both else { return out }
    for k in timeTicks(
      view: state.view, plotW: L.plotW, offsetMinutes: state.timezone.offsetMinutes)
    {
      let xx = state.view.x(k.t, plotW: L.plotW)
      if xx < 0 || xx > L.plotW { continue }
      out.append(hairline(xx, scale: s))
    }
    return out
  }

  /// 和 `ChartRenderer.overlayLines()` 同一口径：单线那几把全要，BOLL 只要上下轨。
  /// 两处必须一起改——这边喂的是十字线取数与自适应探针，那边喂的是真正的绘制。
  private func probeOverlayLines() -> [[Double]] {
    guard !state.percentAxis else { return [] }
    var out: [[Double]] = []
    for id in state.overlays {
      guard let v = engine[id] else { continue }
      switch id {
      case .ma, .ema, .vwap, .supertrend, .sar: out += v.lines
      case .boll: if v.lines.count >= 3 { out += [v.lines[1], v.lines[2]] }
      default: break
      }
    }
    return out
  }
}
