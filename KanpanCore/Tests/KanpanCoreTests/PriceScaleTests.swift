import Foundation
import Testing

@testable import KanpanCore

/// A1.9：三种价格模式来回换算不掉精度；极值要把叠加指标和画线端点一起算进去。
@Suite("价格轴")
struct PriceScaleTests {
  static let pane = Pane(indicator: nil, y: 12, h: 480)

  @Test("pOf(yOf(p)) == p", arguments: PriceMode.allCases)
  func roundTrip(_ mode: PriceMode) {
    var r = Rng(UInt64(mode.rawValue.count * 7919))
    var worst = 0.0
    for _ in 0..<20000 {
      let lo = pow(10, r.d(-4, 5))
      let hi = lo * r.d(1.0001, 4)
      let range = PriceRange(lo: lo, hi: hi, base: r.d(lo, hi))
      let p = r.d(lo, hi)
      let y = yOf(p, pane: Self.pane, range: range, mode: mode)
      let back = pOf(y, pane: Self.pane, range: range, mode: mode)
      worst = max(worst, abs(back - p) / max(1, abs(p)))
      #expect(abs(back - p) <= 1e-9 * max(1, abs(p)), "\(mode.rawValue) p=\(p) → y=\(y) → \(back)")
    }
    #expect(worst <= 1e-9, "\(mode.rawValue) 最差相对误差 \(worst)")
  }

  /// 上下边界正好落在 pane 的上下沿。
  @Test("边界对齐", arguments: PriceMode.allCases)
  func edges(_ mode: PriceMode) {
    let range = PriceRange(lo: 100, hi: 200, base: 150)
    let yLo = yOf(range.lo, pane: Self.pane, range: range, mode: mode)
    let yHi = yOf(range.hi, pane: Self.pane, range: range, mode: mode)
    #expect(abs(yLo - (Self.pane.y + Self.pane.h)) < 1e-9, "\(mode.rawValue) 下沿 \(yLo)")
    #expect(abs(yHi - Self.pane.y) < 1e-9, "\(mode.rawValue) 上沿 \(yHi)")
    // 价格越高 y 越小。
    #expect(yOf(150, pane: Self.pane, range: range, mode: mode) < yLo)
    #expect(yOf(150, pane: Self.pane, range: range, mode: mode) > yHi)
  }

  /// 百分比模式：基准价永远落在 0%。
  @Test("百分比以可见区首根收盘为基准")
  func percentBase() {
    let range = PriceRange(lo: 90, hi: 110, base: 100)
    #expect(PriceMode.percent.forward(100, base: 100) == 0)
    #expect(abs(PriceMode.percent.forward(110, base: 100) - 10) < 1e-12)
    #expect(abs(PriceMode.percent.inverse(-5, base: 100) - 95) < 1e-12)
    let y = yOf(100, pane: Self.pane, range: range, mode: .percent)
    #expect(abs(y - (Self.pane.y + Self.pane.h / 2)) < 1e-9, "0% 不在正中 \(y)")
  }

  /// 对数模式：等比的价格在屏幕上等距。
  @Test("对数模式等比等距")
  func logIsGeometric() {
    let range = PriceRange(lo: 10, hi: 1000, base: 100)
    let ys = [10.0, 100.0, 1000.0].map { yOf($0, pane: Self.pane, range: range, mode: .log) }
    #expect(abs((ys[0] - ys[1]) - (ys[1] - ys[2])) < 1e-9, "\(ys)")
  }

  /// 叠加指标与画线端点必须并进极值，不然 MA99 会画到框外面。
  @Test("极值并入叠加指标与画线")
  func rangeIncludesOverlaysAndDrawings() {
    let s = synthSeries(count: 400, seed: 55)
    let plotW = 390.0
    let v = ViewMath.reset(series: s, plotW: plotW, spacing: AICoinBehavior.initialSpacing)
    let style = CandleStyle.default
    let bare = priceRange(view: v, series: s)

    let (lo, hi) = visibleRange(view: v, series: s)
    // 一条比所有 high 都高的线，和一个比所有 low 都低的画线端点。
    let top = (lo...hi).map { s.high[$0] }.max()! * 1.5
    let bottom = (lo...hi).map { s.low[$0] }.min()! * 0.5
    var overlay = [Double](repeating: .nan, count: s.count)
    overlay[(lo + hi) / 2] = top
    let wide = priceRange(
      view: v, series: s, overlayValues: [overlay], drawingPrices: [bottom])
    #expect(wide.hi > bare.hi, "叠加指标没抬高上界")
    #expect(wide.lo < bare.lo, "画线端点没压低下界")
    #expect(wide.hi >= top, "上界 \(wide.hi) 没盖住 \(top)")
    #expect(wide.lo <= bottom, "下界 \(wide.lo) 没盖住 \(bottom)")

    // NaN 前导段不许污染极值。
    let allNaN = [Double](repeating: .nan, count: s.count)
    let withNaN = priceRange(view: v, series: s, overlayValues: [allNaN])
    #expect(withNaN.lo == bare.lo && withNaN.hi == bare.hi, "全 NaN 的线改变了区间")
  }

  /// 风格的 pad 决定上下留白比例。
  @Test("留白按风格 pad")
  func padding() {
    let s = synthSeries(count: 300, seed: 56)
    let v = ViewMath.reset(series: s, plotW: 390, spacing: 9.2)
    let (lo, hi) = visibleRange(view: v, series: s)
    let maxV = (lo...hi).map { s.high[$0] }.max()!
    let minV = (lo...hi).map { s.low[$0] }.min()!
    for st in CandleStyle.all {
      let r = priceRange(view: v, series: s)
      let top = AICoinBehavior.mainTopInset, bottom = AICoinBehavior.mainBottomInset
      let perPoint = (maxV - minV) / (300 - top - bottom)
      let want = perPoint * top
      #expect(abs((maxV + want) - r.hi) < 1e-9, "\(st.id) 上留白")
      #expect(abs((minV - perPoint * bottom) - r.lo) < 1e-9, "\(st.id) 下留白")
    }
  }

  /// 拖价格轴：zoom 只缩不移中心，shift 只移不缩。
  @Test("价格轴缩放与平移")
  func transform() {
    let s = synthSeries(count: 300, seed: 57)
    let v = ViewMath.reset(series: s, plotW: 390, spacing: 9.2)
    let st = CandleStyle.default
    let base = priceRange(view: v, series: s)
    let mid = (base.lo + base.hi) / 2

    let zoomed = priceRange(view: v, series: s, transform: PriceTransform(zoom: 2))
    #expect(abs((zoomed.lo + zoomed.hi) / 2 - mid) < 1e-9, "缩放挪了中心")
    #expect(abs((zoomed.hi - zoomed.lo) - (base.hi - base.lo) / 2) < 1e-9, "缩放比例不对")

    let shifted = priceRange(view: v, series: s, transform: PriceTransform(zoom: 2, centerFraction: 0.75))
    #expect(abs((shifted.hi - shifted.lo) - (base.hi - base.lo) / 2) < 1e-9, "平移改了高度")
    #expect(abs((shifted.lo + shifted.hi) / 2 - (mid + (base.hi - base.lo) * 0.25)) < 1e-9, "平移距离不对")

    // zoom 有下限 0.15，别让用户把价格轴拉成无限高。
    let crazy = priceRange(view: v, series: s, transform: PriceTransform(zoom: 0.0001))
    #expect(abs((crazy.hi - crazy.lo) - (base.hi - base.lo) / 0.03) < 1e-6, "zoom 下限没兜住")
  }

  /// 一字板：开高低收全一样也得给出有厚度的区间。
  @Test("十字星不塌成零高度")
  func flatSeries() {
    let n = 50
    let s = BarSeries(
      symbol: "FLAT", interval: .h1, t0: 1_700_000_000_000,
      open: .init(repeating: 100, count: n), high: .init(repeating: 100, count: n),
      low: .init(repeating: 100, count: n), close: .init(repeating: 100, count: n),
      volume: .init(repeating: 0, count: n))
    let v = ViewMath.reset(series: s, plotW: 390, spacing: 9.2)
    let r = priceRange(view: v, series: s)
    #expect(r.hi > r.lo, "塌成了 \(r)")
    for mode in PriceMode.allCases {
      let y = yOf(100, pane: Self.pane, range: r, mode: mode)
      #expect(y.isFinite, "\(mode.rawValue) 给出 \(y)")
    }
  }

  /// 副图值域映射。
  @Test("副图值 → y")
  func subPane() {
    let p = Pane(indicator: .rsi, y: 100, h: 80)
    #expect(abs(yOfValue(0, pane: p, lo: 0, hi: 100) - 180) < 1e-9)
    #expect(abs(yOfValue(100, pane: p, lo: 0, hi: 100) - 100) < 1e-9)
    #expect(abs(yOfValue(50, pane: p, lo: 0, hi: 100) - 140) < 1e-9)
    // 退化区间不许除零。
    #expect(yOfValue(5, pane: p, lo: 3, hi: 3) == 140)
  }
}
