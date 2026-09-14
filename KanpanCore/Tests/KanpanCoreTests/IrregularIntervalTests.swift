import Foundation
import Testing

@testable import KanpanCore

/// A1.8：1M 不等距。下标 ↔ 时间必须查表来回一致；1w 是等距的，推导值要和 openTime 对得上。
@Suite("不等距周期")
struct IrregularIntervalTests {
  /// 真实的月初 UTC 00:00，从 2019-01 起 84 根。
  static let monthStarts: [Int64] = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var out: [Int64] = []
    for k in 0..<84 {
      let c = DateComponents(year: 2019 + k / 12, month: k % 12 + 1, day: 1, hour: 0, minute: 0, second: 0)
      out.append(Int64(cal.date(from: c)!.timeIntervalSince1970 * 1000))
    }
    return out
  }()

  static var monthly: BarSeries {
    var s = synthSeries(count: monthStarts.count, interval: .mo1, t0: monthStarts[0], seed: 33)
    s.openTime = monthStarts
    return s
  }

  @Test("只有 1M / 1y 算不等距")
  func onlyMonthlyAndYearlyAreIrregular() {
    // 月长不等、闰年多一天；1w 是周一 00:00 UTC，等距。
    for iv in Interval.allCases {
      #expect(iv.isIrregular == (iv == .mo1 || iv == .y1), "\(iv.rawValue)")
    }
  }

  /// 每根的 openTime 喂回去必须还原成它自己。
  @Test("indexAt(openTime[i]) == i")
  func indexRoundTrip() {
    let s = Self.monthly
    for i in 0..<s.count {
      #expect(s.index(atTime: Double(s.openTime[i])) == i, "第 \(i) 根 \(s.openTime[i])")
      #expect(s.time(at: i) == Self.monthStarts[i], "第 \(i) 根 time(at:)")
    }
  }

  /// 过一遍屏幕坐标再回来，也得落回同一根。
  @Test("过一遍像素再回来还是同一根")
  func pixelRoundTrip() {
    let s = Self.monthly
    let plotW = 390.0
    let v = ViewWindow(from: Double(s.firstTime) - 1e9, to: Double(s.lastTime) + 1e9)
    for i in 0..<s.count {
      let t = Double(s.openTime[i])
      let x = v.x(t, plotW: plotW)
      #expect(s.index(atTime: v.t(atX: x, plotW: plotW)) == i, "第 \(i) 根 x=\(x)")
    }
  }

  /// 落在两根之间就近取，且永远不越界。
  @Test("就近取整与边界")
  func nearestAndBounds() {
    let s = Self.monthly
    #expect(s.index(atTime: Double(s.openTime[0]) - 1e12) == 0)
    #expect(s.index(atTime: Double(s.openTime[s.count - 1]) + 1e12) == s.count - 1)
    for i in 0..<(s.count - 1) {
      let a = Double(s.openTime[i]), b = Double(s.openTime[i + 1])
      #expect(s.index(atTime: a + (b - a) * 0.2) == i, "\(i) 偏左")
      #expect(s.index(atTime: a + (b - a) * 0.8) == i + 1, "\(i) 偏右")
    }
  }

  /// 月份长度真的不一样——别让这个用例退化成等距测试。
  @Test("月长确实不等")
  func monthsReallyDiffer() {
    let gaps = Set((1..<Self.monthStarts.count).map { Self.monthStarts[$0] - Self.monthStarts[$0 - 1] })
    #expect(gaps.count >= 3, "只出现了 \(gaps.count) 种月长")
  }

  /// 1w 是等距的：周一 00:00 UTC，推导值与 openTime 完全一致。
  @Test("1w 等距推导与 openTime 一致")
  func weeklyIsUniform() {
    let week: Int64 = 7 * 86_400_000
    // 1970-01-05 是星期一。
    let firstMonday: Int64 = 4 * 86_400_000
    let t0 = firstMonday + week * 2800
    let s = synthSeries(count: 300, interval: .w1, t0: t0, seed: 44)
    #expect(s.openTime.isEmpty, "等距周期不该存 openTime 表")
    for i in 0..<s.count {
      #expect(s.time(at: i) == t0 + Int64(i) * week, "第 \(i) 根")
      #expect(s.index(atTime: Double(t0 + Int64(i) * week)) == i, "第 \(i) 根反查")
      // 都得落在星期一 00:00 UTC。
      #expect((s.time(at: i) - firstMonday) % week == 0, "第 \(i) 根不在周一")
    }
  }

  /// 不等距序列上追加、可见区间计算都不能错位。
  @Test("追加与可见区间")
  func appendAndVisible() {
    var s = Self.monthly
    let next = Self.monthStarts[Self.monthStarts.count - 1] + 31 * 86_400_000
    s.append(Bar(openTime: next, open: 1, high: 2, low: 0.5, close: 1.5, volume: 10))
    #expect(s.lastTime == next)
    #expect(s.index(atTime: Double(next)) == s.count - 1)

    let v = ViewWindow(from: Double(s.openTime[10]), to: Double(s.openTime[20]))
    let r = visibleRange(view: v, series: s)
    #expect(r.lo <= 10 && r.hi >= 20, "可见区间 \(r) 没盖住 10…20")
    #expect(r.lo >= 9 && r.hi <= 21, "可见区间 \(r) 放太宽")
  }
}
