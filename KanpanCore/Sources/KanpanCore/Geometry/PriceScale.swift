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
  public var inverted: Bool = false
  public init(lo: Double, hi: Double, base: Double) { self.lo = lo; self.hi = hi; self.base = base }
}

/// Manual Y state is relative to the current automatic range; no absolute pinned-price mode.
public struct PriceTransform: Sendable, Equatable {
  public var mode: PriceMode
  public var inverted = false
  public var zoom: Double
  public var centerFraction: Double
  public init(mode: PriceMode = .linear, zoom: Double = 1, centerFraction: Double = 0.5) {
    self.mode = mode; self.zoom = zoom; self.centerFraction = centerFraction
  }
  public mutating func reset() { zoom = 1; centerFraction = 0.5 }
  public var isManual: Bool { zoom != 1 }
  public static func clampedCenter(_ c: Double, zoom: Double) -> Double {
    guard zoom.isFinite, zoom > 0, abs(zoom - 1) > 0.02 else { return 0.5 }
    let h = 1 / (2 * zoom), margin = zoom <= 1 ? 3.0 : 0.75
    let a = h - margin, b = 1 - h + margin
    return max(min(a, b), min(max(a, b), c))
  }
}

/// 可见区间的下标范围（原型 `visible()`）：左右各多算一根，边上的线不缺。
public func visibleRange(view: ViewWindow, series: BarSeries) -> (lo: Int, hi: Int) {
  guard series.count > 0 else { return (0, 0) }
  if series.openTime.isEmpty {
    let step = Double(series.step)
    let t0 = Double(series.t0)
    let lo = min(series.count - 1, max(0, Int(floor((view.from - t0) / step)) - 1))
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
/// 并入主图叠加指标（MA / EMA / BOLL 上下轨）与画线端点，再加共用的像素留白，
/// 最后叠加用户拖价格轴的 zoom / centerFraction。
///
/// - Parameter extraPrices: 还要并进来的散价。平均 K 线的 `hh` / `hl` 走这条——
///   它们必然跑到真实 high / low 之外（`ho` 是上一根的均值），不并进去会被裁掉一截。
/// - Parameter bias: 蜡烛在主图区的上下位置。只改留白的上下分配，总量不变。
/// - Parameter closeOnly: 主图只画收盘价折线（`CandleKind.line`）时为真：K 线本身只按收盘价
///   撑区间，不画出来的高低点不占地方（AICoin 的收盘折线路径同样不用 high/low 撑范围，
///   见 `refs/aicoin/reports/REPORT-candle-axis.md`「AbstractC2759w0.java:323」）。
///   叠加指标、画线、散价照常并入。
public func priceRange(
  view: ViewWindow, series: BarSeries, overlayValues: [[Double]] = [], drawingPrices: [Double] = [],
  transform: PriceTransform = PriceTransform(),
  extraPrices: [Double] = [], bias: PriceBias = .center, paneHeight: Double = 300, topInset: Double = AICoinBehavior.mainTopInset, anchorPrice: Double? = nil,
  closeOnly: Bool = false
) -> PriceRange {
  let (lo, hi) = visibleRange(view: view, series: series)
  // Android y1.r/s: first intersecting column, not the extra render guard candle.
  let baseIndex = series.count > 0 ? series.index(atTime: view.from) : 0
  let candidateBase = series.count > 0 ? series.close[baseIndex] : 1
  let base = candidateBase.isFinite && candidateBase != 0 ? candidateBase : 1
  var minV = Double.infinity, maxV = -Double.infinity
  if series.count > 0 {
    if closeOnly {
      for i in lo...hi where series.close[i].isFinite {
        if series.close[i] > maxV { maxV = series.close[i] }
        if series.close[i] < minV { minV = series.close[i] }
      }
    } else {
      for i in lo...hi {
        if series.high[i] > maxV { maxV = series.high[i] }
        if series.low[i] < minV { minV = series.low[i] }
      }
    }
    for arr in overlayValues where arr.count > lo {
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
  for p in extraPrices where p.isFinite {
    if p > maxV { maxV = p }
    if p < minV { minV = p }
  }
  if !minV.isFinite || !maxV.isFinite { minV = 0; maxV = 1 }
  if maxV == minV {                     // 十字星 / 停牌：退化处理，和原型一致
    maxV = minV * 1.001 + 1
    minV = minV * 0.999 - 1
  }
  let height = paneHeight
  do {
    let mode = transform.mode
    if mode == .log { minV = max(minV, 1e-12); maxV = max(maxV, minV * 1.001) }
    let low = mode.forward(minV, base: base), high = mode.forward(maxV, base: base)
    let top = min(topInset, height * 0.4)
    let bottom = min(AICoinBehavior.mainBottomInset, height * 0.1)
    let content = max(1, height - top - bottom)
    let perPoint = (high - low) / content
    let totalInset = top + bottom
    let shiftInset = bias == .up ? totalInset * 0.25 : bias == .down ? -totalInset * 0.25 : 0
    let a = low - perPoint * (bottom + shiftInset)
    let z = high + perPoint * (top - shiftInset)
    let zoom = min(16, max(0.03, transform.zoom))
    let center = PriceTransform.clampedCenter(transform.centerFraction, zoom: zoom)
    let autoLow = mode.inverse(a, base: base), autoHigh = mode.inverse(z, base: base)
    // Android AbstractC2759w0: manual range operates in price space, even on log axes.
    let mid = zoom == 1 ? (autoLow + autoHigh) / 2 : (anchorPrice ?? (autoLow + (autoHigh - autoLow) * center))
    let half = (autoHigh - autoLow) / (2 * zoom)
    // Positive financial log axis: avoid the APK's discontinuous negative-log extension.
    let resultLow = mode == .log ? max(autoLow * 0.001, mid - half) : mid - half
    var result = PriceRange(lo: resultLow, hi: max(resultLow + max(abs(resultLow) * 1e-9, 1e-9), mid + half), base: base)
    result.inverted = transform.inverted
    return result
  }
}

/// 一帧里固定不变的那半个 `yOf`。
///
/// `yOf` 每次都要把区间上下沿再 `forward` 一遍——对数轴上就是两次 `log()`，
/// 而一根蜡烛要问四次 y（开高低收），一屏两百根就是一千六百次白算的 `log()`。
/// 区间和模式在一帧里是定死的，这里把 `a`/`z` 先算出来，剩下的算式和 `yOf`
/// 逐字一致（连括号顺序都没动），所以结果是逐位相同的，不是「近似相同」。
///
/// 只给热循环用；零星几处照旧调 `yOf` 就行。
public struct PriceMapping: Sendable {
  public let mode: PriceMode
  public let base: Double
  public let a: Double
  public let z: Double
  public let inverted: Bool

  public init(range: PriceRange, mode: PriceMode) {
    self.mode = mode
    self.base = range.base
    self.a = mode.forward(range.lo, base: range.base)
    self.z = mode.forward(range.hi, base: range.base)
    self.inverted = range.inverted
  }

  public func y(_ p: Double, pane: Pane) -> Double {
    let f = mode.forward(p, base: base)
    let fraction = (f - a) / (z - a)
    return pane.y + (inverted ? fraction : 1 - fraction) * pane.h
  }
}

/// 价格 → y（在 pane 内）。
public func yOf(_ p: Double, pane: Pane, range: PriceRange, mode: PriceMode) -> Double {
  let a = mode.forward(range.lo, base: range.base)
  let z = mode.forward(range.hi, base: range.base)
  let f = mode.forward(p, base: range.base)
  let fraction = (f - a) / (z - a)
  return pane.y + (range.inverted ? fraction : 1 - fraction) * pane.h
}

/// y → 价格。
public func pOf(_ y: Double, pane: Pane, range: PriceRange, mode: PriceMode) -> Double {
  let a = mode.forward(range.lo, base: range.base)
  let z = mode.forward(range.hi, base: range.base)
  let fraction = (y - pane.y) / pane.h
  let f = a + (range.inverted ? fraction : 1 - fraction) * (z - a)
  return mode.inverse(f, base: range.base)
}

/// 副图的值 → y（线性，区间由指标自己定）。
public func yOfValue(_ v: Double, pane: Pane, lo: Double, hi: Double) -> Double {
  guard hi > lo else { return pane.y + pane.h / 2 }
  return pane.y + pane.h - ((v - lo) / (hi - lo)) * pane.h
}
