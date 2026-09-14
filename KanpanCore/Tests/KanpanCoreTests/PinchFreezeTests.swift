import Foundation
import Testing

@testable import KanpanCore

/// 双指缩放时价格框要钉死不动（用户反馈「缩放 k 线会自动上下跳」）。
///
/// 病根：`priceRange` 每帧都按**当前可见** K 线的高低重新贴合。捏合时可见根数一直在变，
/// 极值一进一出，贴合出来的区间就跟着变，整张图被上下拽。AiCoin 是框固定、内容在框里
/// 缩放，松手才重新贴合——`PriceAnchor.freeze` 解的就是「框固定」这一半。
@Suite("捏合价格框冻结")
struct PinchFreezeTests {
  static let style = CandleStyle.default

  /// 把一次完整的捏合走一遍：每一帧解一次 `freeze`，再问一次 `priceRange`，
  /// 看解完之后的区间是不是还等于捏合开始那一刻的区间。
  private func sweep(
    mode: PriceMode, series: BarSeries, start: ViewWindow,
    factors: [Double], line: SourceLocation = #_sourceLocation
  ) {
    let t0 = PriceTransform(mode: mode, zoom: 1, shift: 0)
    let want = priceRange(view: start, series: series, style: Self.style, transform: t0)
    let mid = (start.from + start.to) / 2
    var worst = 0.0
    var solved = 0
    for f in factors {
      // 以窗口中点为轴缩放，和 `ViewMath.pinch` 手指落在正中央时是一回事。
      let half = start.span / 2 * f
      let v = ViewWindow(from: mid - half, to: mid + half)
      let raw = priceRange(view: v, series: series, style: Self.style, transform: t0)
      guard let t = PriceAnchor.freeze(target: want, raw: raw, mode: mode) else { continue }
      solved += 1
      let got = priceRange(view: v, series: series, style: Self.style, transform: t)
      let span = want.hi - want.lo
      worst = max(worst, max(abs(got.lo - want.lo), abs(got.hi - want.hi)) / span)
    }
    #expect(solved >= factors.count - 2, "\(mode.rawValue) 只解出 \(solved)/\(factors.count) 帧",
      sourceLocation: line)
    // 相对窗高的误差。1e-12 已经比一个设备像素小十个数量级。
    #expect(worst <= 1e-12, "\(mode.rawValue) 最差偏移 \(worst) 个窗高", sourceLocation: line)
  }

  @Test("一路捏开再捏拢，框一动不动", arguments: PriceMode.allCases)
  func freezeHolds(_ mode: PriceMode) {
    let s = synthSeries(count: 1200)
    let t0 = Double(s.t0), step = Double(s.step)
    let start = ViewWindow(from: t0 + step * 400, to: t0 + step * 600)
    // 捏开到 6 倍窗宽、捏拢到 1/5，中间连续取值——极值进出最频繁的就是这一段。
    var f = [Double]()
    for i in 0...60 { f.append(0.2 * pow(30, Double(i) / 60)) }
    sweep(mode: mode, series: s, start: start, factors: f)
  }

  /// 手指落在偏一侧（`shift` 要解出非零值）也一样钉得住。
  @Test("窗口偏在序列一头也钉得住", arguments: PriceMode.allCases)
  func freezeOffCenter(_ mode: PriceMode) {
    let s = synthSeries(count: 800, seed: 31)
    let t0 = Double(s.t0), step = Double(s.step)
    let start = ViewWindow(from: t0 + step * 20, to: t0 + step * 120)
    sweep(mode: mode, series: s, start: start, factors: [0.5, 0.8, 1.0, 1.5, 2.5, 4.0])
  }

  /// 解不出来的时候要老实返回 `nil`，不能塞一个按不住的 `zoom` 进去——
  /// `priceRange` 里有 `max(0.15, zoom)` 的下限，低于它框就按不住了。
  @Test("按不住就返回 nil")
  func refusesWhenUnpinnable() {
    let raw = PriceRange(lo: 100, hi: 101, base: 100)
    // 目标窗高是 raw 的 20 倍 → zoom = 0.05 < 0.15，按不住。
    #expect(PriceAnchor.freeze(
      target: PriceRange(lo: 90, hi: 110, base: 100), raw: raw, mode: .linear) == nil)
    // 退化区间。
    #expect(PriceAnchor.freeze(
      target: PriceRange(lo: 100, hi: 100, base: 100), raw: raw, mode: .linear) == nil)
    #expect(PriceAnchor.freeze(
      target: raw, raw: PriceRange(lo: 100, hi: 100, base: 100), mode: .linear) == nil)
  }

  /// 框没变的时候解出来就该是「什么都不做」，别引入一点点抖。
  @Test("同一个窗口解出恒等变换", arguments: PriceMode.allCases)
  func identity(_ mode: PriceMode) {
    let s = synthSeries(count: 500, seed: 5)
    let v = ViewWindow(from: Double(s.t0) + Double(s.step) * 100,
                       to: Double(s.t0) + Double(s.step) * 300)
    let r = priceRange(view: v, series: s, style: Self.style,
                       transform: PriceTransform(mode: mode, zoom: 1, shift: 0))
    let t = PriceAnchor.freeze(target: r, raw: r, mode: mode)
    #expect(t != nil)
    #expect(abs((t?.zoom ?? 0) - 1) < 1e-12)
    #expect(abs(t?.shift ?? 1) < 1e-12)
  }

  /// 捏合期间**不**冻结会跳多少——这条是对照，用来证明这个 bug 是真的存在、
  /// 也给「修好了」一个可量的对比数（不是零就行，得知道原来有多糟）。
  @Test("对照：不冻结时框会跳多少")
  func withoutFreezeItJumps() {
    let s = synthSeries(count: 1200)
    let t0 = Double(s.t0), step = Double(s.step)
    let start = ViewWindow(from: t0 + step * 400, to: t0 + step * 600)
    let id = PriceTransform(mode: .linear, zoom: 1, shift: 0)
    let want = priceRange(view: start, series: s, style: Self.style, transform: id)
    let mid = (start.from + start.to) / 2
    let span = want.hi - want.lo
    var worst = 0.0
    for i in 0...60 {
      let f = 0.2 * pow(30, Double(i) / 60)
      let half = start.span / 2 * f
      let v = ViewWindow(from: mid - half, to: mid + half)
      let got = priceRange(view: v, series: s, style: Self.style, transform: id)
      worst = max(worst, max(abs(got.lo - want.lo), abs(got.hi - want.hi)) / span)
    }
    // 不冻结时上下沿能跑出好几个窗高——这就是用户看到的「上下跳」。
    #expect(worst > 1, "不冻结只跳了 \(worst) 个窗高，这条对照失去意义")
  }
}
