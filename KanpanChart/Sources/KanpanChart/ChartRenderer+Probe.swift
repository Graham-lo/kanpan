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
  public var radius: Double
  public var outline: Double
  public var rangeLo: Double
  public var rangeHi: Double
  public var rangeBase: Double
  public var visibleLo: Int
  public var visibleHi: Int
  public var viewFrom: Double
  public var viewTo: Double

  /// 按 A3.2 那一行的顺序取 7 项。
  public static let metricNames = ["axisW", "timeH", "subH", "spacing", "bodyW", "wickW", "padTop"]

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
    let m = candleMetrics(spacing: spacing, style: state.style, scale: s)
    let (lo, hi) = visibleRange(view: state.view, series: b)
    let pane = L.main

    // 进价格区间的那几条线，和 `priceRange(size:)` 用的是同一份（见 overlayLines）。
    var hiP = -Double.infinity, loP = Double.infinity
    if !b.isEmpty {
      for i in lo...hi {
        if b.high[i] > hiP { hiP = b.high[i] }
        if b.low[i] < loP { loP = b.low[i] }
      }
      for arr in probeOverlayLines() {
        for i in lo...min(hi, arr.count - 1) where arr[i].isFinite {
          if arr[i] > hiP { hiP = arr[i] }
          if arr[i] < loP { loP = arr[i] }
        }
      }
    }
    let yHi = KanpanCore.yOf(hiP, pane: pane, range: r, mode: state.price.mode)
    let yLo = KanpanCore.yOf(loP, pane: pane, range: r, mode: state.price.mode)

    return ChartProbe(
      axisW: L.axisW,
      timeH: L.H - L.timeY,
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
      radius: m.radius,
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
    guard !b.isEmpty else { return [] }
    let s = Double(scale)
    let r = priceRange(size: size)
    let pane = L.main
    let S = state.style
    let spacing = state.view.barSpacing(step: b.step, plotW: L.plotW)
    let m = candleMetrics(spacing: spacing, style: S, scale: s)
    let hollowShape = S.shape == .outline || S.shape == .hollowUp
    let (lo, hi) = visibleRange(view: state.view, series: b)
    func y(_ p: Double) -> Double {
      KanpanCore.yOf(p, pane: pane, range: r, mode: state.price.mode)
    }
    var out: [CandleXProbe] = []
    out.reserveCapacity(hi - lo + 1)
    for i in lo...hi {
      let xc = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      if xc < -4 || xc > L.plotW + 4 { continue }
      let up = b.close[i] >= b.open[i]
      let yo = y(b.open[i]), yc = y(b.close[i])
      let top = min(yo, yc)
      let h = max(m.minBody, abs(yc - yo))
      let drawHollow = S.shape == .outline || (S.shape == .hollowUp && up)
      out.append(
        CandleXProbe(
          index: i, center: xc,
          bodyLeft: snap(xc - m.bodyW / 2, scale: s),
          wickLeft: snap(xc - m.wickW / 2, scale: s),
          wickHair: hairline(xc, scale: s),
          up: up,
          wickTop: y(b.high[i]), wickBottom: y(b.low[i]),
          bodyTop: top, bodyHeight: h,
          hollow: hollowShape && drawHollow && h > m.outline * 2.2 && m.bodyW > m.outline * 2.2))
    }
    return out
  }

  /// 最新价线画在哪儿（A3.3 的 `lastLine` 取样行）。超出主图时返回 `nil`，和
  /// `drawLastPrice` 的提前返回一致。
  public func lastPriceY(size: CGSize) -> (y: Double, up: Bool)? {
    let b = state.series
    guard !b.isEmpty else { return nil }
    let L = layout(size: size)
    let r = priceRange(size: size)
    let pane = L.main
    let i = b.count - 1
    let y = KanpanCore.yOf(b.close[i], pane: pane, range: r, mode: state.price.mode)
    if y < pane.y || y > pane.y + pane.h { return nil }
    return (y, b.close[i] >= b.open[i])
  }

  /// 价格网格线的 y（已经按 `drawPriceGrid` 的规则筛过边缘）。
  public func priceGridYs(size: CGSize) -> [Double] {
    let L = layout(size: size)
    let r = priceRange(size: size)
    let pane = L.main
    let mode = state.price.mode
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
    guard state.style.grid == .both else { return out }
    for k in timeTicks(
      view: state.view, plotW: L.plotW, offsetMinutes: state.timezone.offsetMinutes)
    {
      let xx = state.view.x(k.t, plotW: L.plotW)
      if xx < 0 || xx > L.plotW { continue }
      out.append(hairline(xx, scale: s))
    }
    return out
  }

  /// 和 `ChartRenderer.overlayLines()` 同一口径：MA / EMA 全要，BOLL 只要上下轨。
  private func probeOverlayLines() -> [[Double]] {
    var out: [[Double]] = []
    for id in state.overlays {
      guard let v = engine[id] else { continue }
      switch id {
      case .ma, .ema: out += v.lines
      case .boll: if v.lines.count >= 3 { out += [v.lines[1], v.lines[2]] }
      default: break
      }
    }
    return out
  }
}
