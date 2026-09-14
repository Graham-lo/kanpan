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
  /// 手动定标：非 `nil` 时价格轴**钉死在这个绝对区间**上，不再按可见 K 线自动贴合，
  /// `zoom` / `shift` 一并失效。
  ///
  /// 为什么要有这个：`zoom` / `shift` 是**贴合结果上的相对量**，而贴合每帧都按可见 K 线的
  /// 高低重算——于是横向平移一下，极值一进一出，用户刚调好的价格刻度就又跑了。
  /// AiCoin 桌面版实测：价格轴右下角有「对数 / % / 自动」三个钮，默认「自动」＝每帧贴合；
  /// 一旦竖拖价格轴就切成手动，此后左右缩放**价格轴一个像素都不动**（同一段横向缩放，
  /// 自动档下轴从 1349.58…1262.36 跑到 1344.15…1262.51，手动档下前后逐字相同），
  /// 并在图区右上角给出一个复位钮。手机版把那个位置换成一个圈着的「R」。
  ///
  /// `base`（百分比档的基准）不钉：它是可见区第一根的收盘，按定义就该跟着视野走。
  public var pinned: (lo: Double, hi: Double)?
  public init(mode: PriceMode = .linear, zoom: Double = 1, shift: Double = 0) {
    self.mode = mode; self.zoom = zoom; self.shift = shift
  }
  public mutating func reset() { zoom = 1; shift = 0; pinned = nil }
  /// 是否偏离了「自动贴合」。UI 的复位钮（AiCoin 手机版那个「R」）按这个决定露不露面。
  public var isManual: Bool { pinned != nil || zoom != 1 || shift != 0 }

  public static func == (a: PriceTransform, b: PriceTransform) -> Bool {
    a.mode == b.mode && a.zoom == b.zoom && a.shift == b.shift
      && a.pinned?.lo == b.pinned?.lo && a.pinned?.hi == b.pinned?.hi
  }
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
///
/// - Parameter extraPrices: 还要并进来的散价。平均 K 线的 `hh` / `hl` 走这条——
///   它们必然跑到真实 high / low 之外（`ho` 是上一根的均值），不并进去会被裁掉一截。
/// - Parameter bias: 蜡烛在主图区的上下位置。只改留白的上下分配，总量不变。
public func priceRange(
  view: ViewWindow, series: BarSeries, style: CandleStyle,
  overlayValues: [[Double]] = [], drawingPrices: [Double] = [],
  transform: PriceTransform = PriceTransform(),
  extraPrices: [Double] = [], bias: PriceBias = .center
) -> PriceRange {
  let (lo, hi) = visibleRange(view: view, series: series)
  let base = series.count > 0 ? series.close[lo] : 1
  // 手动定标就此打住：区间钉死，一根 K 线都不用扫。`base` 照常跟着视野走，
  // 理由见 `PriceTransform.pinned`。
  if let pin = transform.pinned, pin.hi > pin.lo, pin.lo.isFinite, pin.hi.isFinite {
    return PriceRange(lo: pin.lo, hi: pin.hi, base: base)
  }
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
  for p in extraPrices where p.isFinite {
    if p > maxV { maxV = p }
    if p < minV { minV = p }
  }
  if !minV.isFinite || !maxV.isFinite { minV = 0; maxV = 1 }
  if maxV == minV {                     // 十字星 / 停牌：退化处理，和原型一致
    maxV = minV * 1.001 + 1
    minV = minV * 0.999 - 1
  }
  let padf = style.pad
  // 留白总量还是 `2 × padf`，`bias` 只决定它怎么分给上下两边：总量一动跨度就变，
  // 蜡烛会跟着缩放，而用户要的是「把蜡烛挪上去」不是「把蜡烛画小」。
  // `.center` 的 0.5 在 IEEE754 下是精确的（`x * padf * 2 * 0.5` 逐位等于 `x * padf`），
  // 所以默认档和改这段之前逐比特相同——A3.11 的基线靠这条。
  let share = bias.shares
  let a = minV - (maxV - minV) * padf * 2 * share.bottom
  let z = maxV + (maxV - minV) * padf * 2 * share.top
  let mid = (a + z) / 2
  let half = ((z - a) / 2) / max(0.15, transform.zoom)
  let off = half * 2 * transform.shift
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
