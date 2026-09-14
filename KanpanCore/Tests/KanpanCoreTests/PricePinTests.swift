import Foundation
import Testing

@testable import KanpanCore

/// 手动定标：价格轴钉在一段**绝对**区间上，横向平移/缩放一个像素都不许动。
///
/// 为什么要有这一档：`zoom` / `shift` 是「自动贴合结果上的相对量」，而贴合每帧都按可见
/// K 线的高低重算——于是左右拖一下，极值一进一出，用户刚调好的价格刻度就又跑了。
///
/// AiCoin 桌面版实测（1920×975 原生截图，逐字读轴标签）：
///   · 「自动」开着（默认）时横拖一次，价格轴从 1349.58…1262.36 变成 1344.15…1262.51；
///   · 竖拖一次价格轴切进手动（跨度 81.6 → 102.8）之后，再横拖两次，七个标签
///     1354.74 / 1339.55 / 1324.53 / 1309.68 / 1294.99 / 1280.47 / 1266.11 **逐字不变**。
/// 这一套测试钉的就是后半句。
@Suite("价格轴手动定标")
struct PricePinTests {
  static let style = CandleStyle.default
  static let pane = Pane(indicator: nil, y: 12, h: 480)

  // MARK: - 钉住之后横向怎么动都不动

  @Test("钉住后横向平移 / 缩放，区间逐比特不变", arguments: PriceMode.allCases)
  func pinSurvivesHorizontal(_ mode: PriceMode) {
    let s = synthSeries(count: 1200)
    let t0 = Double(s.t0), step = Double(s.step)
    let start = ViewWindow(from: t0 + step * 400, to: t0 + step * 600)
    var t = PriceTransform(mode: mode)
    t.pinned = (lo: 91.5, hi: 108.25)
    let want = priceRange(view: start, series: s, style: Self.style, transform: t)
    #expect(want.lo == 91.5 && want.hi == 108.25, "钉住的区间没被原样返回")

    // 平移、缩放、两者混合——极值进出最频繁的一批窗口。
    let mid = (start.from + start.to) / 2
    for i in 0...80 {
      let f = 0.2 * pow(30, Double(i) / 80)
      let half = start.span / 2 * f
      let shift = step * Double(i - 40) * 5
      let v = ViewWindow(from: mid - half + shift, to: mid + half + shift)
      let got = priceRange(view: v, series: s, style: Self.style, transform: t)
      // 逐比特，不是「误差够小」：钉住就是钉住。
      #expect(got.lo == want.lo && got.hi == want.hi,
        "\(mode.rawValue) 第 \(i) 帧价格轴跑了：\(got.lo)…\(got.hi)")
    }
  }

  /// 对照组：同样这批窗口，**不**钉住的话轴会跑多少。
  /// 留着这条是为了让「修好了」有个可量的对比数，而不是只知道现在是零。
  @Test("对照：不钉住时横向平移会把轴带跑多少")
  func withoutPinItDrifts() {
    let s = synthSeries(count: 1200)
    let t0 = Double(s.t0), step = Double(s.step)
    let start = ViewWindow(from: t0 + step * 400, to: t0 + step * 600)
    let id = PriceTransform(mode: .linear)
    let want = priceRange(view: start, series: s, style: Self.style, transform: id)
    let span = want.hi - want.lo
    var worst = 0.0
    for i in 0...80 {
      let shift = step * Double(i - 40) * 5
      let v = ViewWindow(from: start.from + shift, to: start.to + shift)
      let got = priceRange(view: v, series: s, style: Self.style, transform: id)
      worst = max(worst, max(abs(got.lo - want.lo), abs(got.hi - want.hi)) / span)
    }
    #expect(worst > 0.1, "对照组没跑起来，这条测试就失去意义了（实测跑了 \(worst) 个窗高）")
  }

  /// `base`（百分比档的基准）**不**跟着钉：它按定义就是可见区第一根的收盘，
  /// 该跟着视野走。它也不影响 y 映射——`u = (p-lo)/(hi-lo)` 里 base 会约掉。
  @Test("钉住不影响 base 跟着视野走")
  func baseStillTracksWindow() {
    let s = synthSeries(count: 600)
    let t0 = Double(s.t0), step = Double(s.step)
    var t = PriceTransform(mode: .percent)
    t.pinned = (lo: 80, hi: 120)
    let a = priceRange(view: ViewWindow(from: t0 + step * 100, to: t0 + step * 200),
                       series: s, style: Self.style, transform: t)
    let b = priceRange(view: ViewWindow(from: t0 + step * 300, to: t0 + step * 400),
                       series: s, style: Self.style, transform: t)
    #expect(a.lo == b.lo && a.hi == b.hi, "区间该钉住")
    #expect(a.base != b.base, "base 该跟着视野走")
  }

  /// 退化的钉子要被忽略，回落到自动贴合——别把图画成一条线。
  @Test("退化区间不生效")
  func degeneratePinIgnored() {
    let s = synthSeries(count: 300)
    let v = ViewWindow(from: Double(s.t0) + Double(s.step) * 50,
                       to: Double(s.t0) + Double(s.step) * 150)
    let auto = priceRange(view: v, series: s, style: Self.style, transform: PriceTransform())
    for bad in [(lo: 100.0, hi: 100.0), (lo: 100.0, hi: 90.0),
                (lo: Double.nan, hi: 100.0), (lo: 100.0, hi: Double.infinity)] {
      var t = PriceTransform()
      t.pinned = bad
      let got = priceRange(view: v, series: s, style: Self.style, transform: t)
      #expect(got.lo == auto.lo && got.hi == auto.hi, "退化钉子 \(bad) 没被忽略")
    }
  }

  /// 默认 `pinned == nil` 时输出必须和加这个字段之前**逐比特相同**——
  /// A3.11 的 176 张像素基线全压在这条上。
  @Test("不钉住时与自动贴合逐比特相同", arguments: PriceMode.allCases)
  func nilPinIsIdentity(_ mode: PriceMode) {
    let s = synthSeries(count: 900, seed: 17)
    let t0 = Double(s.t0), step = Double(s.step)
    for i in 0...20 {
      let v = ViewWindow(from: t0 + step * Double(i * 20), to: t0 + step * Double(i * 20 + 180))
      for zoom in [0.5, 1.0, 2.0] {
        for shift in [-0.3, 0.0, 0.4] {
          var t = PriceTransform(mode: mode, zoom: zoom, shift: shift)
          let a = priceRange(view: v, series: s, style: Self.style, transform: t)
          t.pinned = nil
          let b = priceRange(view: v, series: s, style: Self.style, transform: t)
          #expect(a.lo == b.lo && a.hi == b.hi && a.base == b.base)
        }
      }
    }
  }

  // MARK: - pin：缩放时按下那一点不动

  @Test("pin：缩放后锚点价格停在原来那个 y 上", arguments: PriceMode.allCases)
  func pinKeepsAnchor(_ mode: PriceMode) {
    var r = Rng(UInt64(mode.rawValue.count * 104_729))
    var worst = 0.0
    for _ in 0..<4000 {
      let lo = pow(10, r.d(-2, 4))
      let hi = lo * r.d(1.01, 3)
      let range = PriceRange(lo: lo, hi: hi, base: r.d(lo, hi))
      let p = r.d(lo, hi)
      let y = yOf(p, pane: Self.pane, range: range, mode: mode)
      let factor = exp(r.d(-1.2, 1.2))
      guard let pin = PriceAnchor.pin(
        range: range, factor: factor, keeping: p, at: y, pane: Self.pane, mode: mode)
      else { continue }
      let after = PriceRange(lo: pin.lo, hi: pin.hi, base: range.base)
      let y2 = yOf(p, pane: Self.pane, range: after, mode: mode)
      worst = max(worst, abs(y2 - y))
      // 缩放方向：factor > 1 ＝ 区间变窄 ＝ 看得更细（和 `zoom(from:dy:)` 同一套语义）。
      let s0 = mode.forward(range.hi, base: range.base) - mode.forward(range.lo, base: range.base)
      let s1 = mode.forward(after.hi, base: after.base) - mode.forward(after.lo, base: after.base)
      #expect(abs(s1 * factor / s0 - 1) < 1e-9, "\(mode.rawValue) 缩放倍率不对")
    }
    // 亚像素的万分之一。解析解，不是二分逼近，所以这里可以卡得很死。
    #expect(worst < 1e-6, "\(mode.rawValue) 锚点最大偏移 \(worst) pt")
  }

  @Test("pin：退化输入返回 nil")
  func pinRefusesGarbage() {
    let r = PriceRange(lo: 100, hi: 200, base: 150)
    #expect(PriceAnchor.pin(range: r, factor: 0, keeping: 150, at: 200,
                            pane: Self.pane, mode: .linear) == nil)
    #expect(PriceAnchor.pin(range: r, factor: .nan, keeping: 150, at: 200,
                            pane: Self.pane, mode: .linear) == nil)
    #expect(PriceAnchor.pin(range: PriceRange(lo: 100, hi: 100, base: 100), factor: 2,
                            keeping: 100, at: 200, pane: Self.pane, mode: .linear) == nil)
    #expect(PriceAnchor.pin(range: r, factor: 2, keeping: 150, at: 200,
                            pane: Pane(indicator: nil, y: 0, h: 0), mode: .linear) == nil)
    // 对数档把 lo 推到 0 以下要拒掉，不能返回一个画不出来的区间。
    #expect(PriceAnchor.pin(range: PriceRange(lo: 100, hi: 200, base: 150), factor: 1e-9,
                            keeping: 150, at: 200, pane: Self.pane, mode: .log) == nil)
  }

  // MARK: - pan：竖拖整段跟手

  @Test("pan：拖多少像素，图就跟着走多少像素", arguments: PriceMode.allCases)
  func panFollowsFinger(_ mode: PriceMode) {
    var r = Rng(UInt64(mode.rawValue.count * 15_485_863))
    var worst = 0.0
    for _ in 0..<4000 {
      let lo = pow(10, r.d(-1, 4))
      let hi = lo * r.d(1.05, 3)
      let range = PriceRange(lo: lo, hi: hi, base: r.d(lo, hi))
      let p = r.d(lo, hi)
      let y = yOf(p, pane: Self.pane, range: range, mode: mode)
      let dy = r.d(-200, 200)
      guard let pan = PriceAnchor.pan(range: range, dy: dy, pane: Self.pane, mode: mode)
      else { continue }
      let after = PriceRange(lo: pan.lo, hi: pan.hi, base: range.base)
      let y2 = yOf(p, pane: Self.pane, range: after, mode: mode)
      // 手指往下拖 dy，同一个价格就该往下走 dy。
      worst = max(worst, abs((y2 - y) - dy))
      // 跨度不变：平移不是缩放。
      let s0 = mode.forward(range.hi, base: range.base) - mode.forward(range.lo, base: range.base)
      let s1 = mode.forward(after.hi, base: after.base) - mode.forward(after.lo, base: after.base)
      #expect(abs(s1 / s0 - 1) < 1e-9, "\(mode.rawValue) 平移把跨度改了")
    }
    #expect(worst < 1e-6, "\(mode.rawValue) 跟手最大误差 \(worst) pt")
  }

  @Test("pan：对数档不许把下沿推到 0 以下")
  func panRefusesNonPositiveLog() {
    let range = PriceRange(lo: 100, hi: 200, base: 150)
    // 往上抬得足够狠，正向（log）空间里 lo 会跌穿 0。
    #expect(PriceAnchor.pan(range: range, dy: 1e6, pane: Self.pane, mode: .log) == nil)
    // 线性档同样不许翻过零点。
    #expect(PriceAnchor.pan(range: range, dy: 1e12, pane: Self.pane, mode: .linear) != nil)
  }

  // MARK: - isManual / reset

  @Test("isManual 与 reset")
  func manualFlag() {
    var t = PriceTransform()
    #expect(!t.isManual)
    t.zoom = 1.5
    #expect(t.isManual)
    t.reset()
    #expect(!t.isManual && t.zoom == 1 && t.shift == 0 && t.pinned == nil)
    t.pinned = (lo: 1, hi: 2)
    #expect(t.isManual)
    t.reset()
    #expect(t.pinned == nil, "reset 没把钉子拔掉")
  }

  @Test("相等判定把 pinned 算进去")
  func equality() {
    var a = PriceTransform()
    var b = PriceTransform()
    #expect(a == b)
    a.pinned = (lo: 1, hi: 2)
    #expect(a != b)
    b.pinned = (lo: 1, hi: 2)
    #expect(a == b)
    b.pinned = (lo: 1, hi: 2.5)
    #expect(a != b)
  }
}
