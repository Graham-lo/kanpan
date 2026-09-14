import Foundation

/// 价格轴的三种模式（§5.4）。
public enum PriceMode: String, Sendable, Codable, CaseIterable {
  case linear, log, percent

  public var display: String {
    switch self {
    case .linear: "常规"
    case .log: "对数"
    case .percent: "百分比"
    }
  }

  /// 前向变换：画之前把价格换到线性空间。
  public func forward(_ p: Double, base: Double) -> Double {
    switch self {
    case .linear: p
    case .log: Foundation.log(max(1e-12, p))
    case .percent: (p / base - 1) * 100
    }
  }

  /// 逆变换。
  public func inverse(_ f: Double, base: Double) -> Double {
    switch self {
    case .linear: f
    case .log: exp(f)
    case .percent: (f / 100 + 1) * base
    }
  }
}

/// 当前可见价格区间。`base` 是百分比模式的基准（可见区第一根的收盘）。
public struct PriceRange: Sendable, Equatable {
  public var lo: Double
  public var hi: Double
  public var base: Double
  public init(lo: Double, hi: Double, base: Double) { self.lo = lo; self.hi = hi; self.base = base }
}

/// 用户拖价格轴产生的缩放与平移。
public struct PriceTransform: Sendable, Equatable {
  public var mode: PriceMode = .linear
  public var zoom: Double = 1      // ≥ 0.15
  public var shift: Double = 0
  public init(mode: PriceMode = .linear, zoom: Double = 1, shift: Double = 0) {
    self.mode = mode; self.zoom = zoom; self.shift = shift
  }
  public mutating func reset() { zoom = 1; shift = 0 }
}

/// 可见区间的下标范围（原型 `visible()`）：左右各多算一根，边上的线不缺。
public func visibleRange(view: ViewWindow, series: BarSeries) -> (lo: Int, hi: Int) {
  guard series.count > 0 else { return (0, 0) }
  if series.openTime.isEmpty {
    let step = Double(series.step)
    let t0 = Double(series.t0)
    let lo = max(0, Int(floor((view.from - t0) / step)) - 1)
    let hi = min(series.count - 1, Int(ceil((view.to - t0) / step)) + 1)
    return (lo, max(lo, hi))
  }
  // 1M 这种不等距周期没法用除法推下标，查表。
  let lo = max(0, series.index(atTime: view.from) - 1)
  let hi = min(series.count - 1, series.index(atTime: view.to) + 1)
  return (lo, max(lo, hi))
}

/// 可见价格区间（§5.4，原型 `priceRange`）。
///
/// 并入主图叠加指标（MA / EMA / BOLL 上下轨）与画线端点，再加风格表的上下留白，
/// 最后叠加用户拖价格轴的 zoom / shift。
public func priceRange(
  view: ViewWindow, series: BarSeries, style: CandleStyle,
  overlayValues: [[Double]] = [], drawingPrices: [Double] = [],
  transform: PriceTransform = PriceTransform()
) -> PriceRange {
  let (lo, hi) = visibleRange(view: view, series: series)
  var minV = Double.infinity, maxV = -Double.infinity
  if series.count > 0 {
    for i in lo...hi {
      if series.high[i] > maxV { maxV = series.high[i] }
      if series.low[i] < minV { minV = series.low[i] }
    }
    for arr in overlayValues {
      for i in lo...min(hi, arr.count - 1) where arr[i].isFinite {
        if arr[i] > maxV { maxV = arr[i] }
        if arr[i] < minV { minV = arr[i] }
      }
    }
  }
  for p in drawingPrices {
    if p > maxV { maxV = p }
    if p < minV { minV = p }
  }
  if !minV.isFinite || !maxV.isFinite { minV = 0; maxV = 1 }
  if maxV == minV {                     // 十字星 / 停牌：退化处理，和原型一致
    maxV = minV * 1.001 + 1
    minV = minV * 0.999 - 1
  }
  let padf = style.pad
  let a = minV - (maxV - minV) * padf
  let z = maxV + (maxV - minV) * padf
  let mid = (a + z) / 2
  let half = ((z - a) / 2) / max(0.15, transform.zoom)
  let off = half * 2 * transform.shift
  let base = series.count > 0 ? series.close[lo] : 1
  return PriceRange(lo: mid - half + off, hi: mid + half + off, base: base)
}

/// 价格 → y（在 pane 内）。
public func yOf(_ p: Double, pane: Pane, range: PriceRange, mode: PriceMode) -> Double {
  let a = mode.forward(range.lo, base: range.base)
  let z = mode.forward(range.hi, base: range.base)
  let f = mode.forward(p, base: range.base)
  return pane.y + pane.h - ((f - a) / (z - a)) * pane.h
}

/// y → 价格。
public func pOf(_ y: Double, pane: Pane, range: PriceRange, mode: PriceMode) -> Double {
  let a = mode.forward(range.lo, base: range.base)
  let z = mode.forward(range.hi, base: range.base)
  let f = a + ((pane.y + pane.h - y) / pane.h) * (z - a)
  return mode.inverse(f, base: range.base)
}

/// 副图的值 → y（线性，区间由指标自己定）。
public func yOfValue(_ v: Double, pane: Pane, lo: Double, hi: Double) -> Double {
  guard hi > lo else { return pane.y + pane.h / 2 }
  return pane.y + pane.h - ((v - lo) / (hi - lo)) * pane.h
}
