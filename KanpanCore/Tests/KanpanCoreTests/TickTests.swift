import Foundation
import Testing

@testable import KanpanCore

/// A1.6：`niceStep` / `timeStep` 与原型导出的 200 组输入输出全等。
@Suite("刻度")
struct TickTests {
  @Test("niceStep 与原型全等")
  func niceStepMatches() {
    var bad = 0
    var first = ""
    for row in Fx.nice {
      let got = niceStep(span: row[0], want: row[1])
      if abs(got - row[2]) > 1e-12 * max(1, abs(row[2])) {
        bad += 1
        if first.isEmpty { first = "span=\(row[0]) want=\(row[1]) 期望 \(row[2]) 得到 \(got)" }
      }
    }
    #expect(bad == 0, "\(Fx.nice.count) 组里 \(bad) 组不符，首个 \(first)")
    #expect(Fx.nice.count >= 200, "fixture 只有 \(Fx.nice.count) 组")
  }

  @Test("timeStep 与原型全等")
  func timeStepMatches() {
    var bad = 0
    var first = ""
    for row in Fx.time {
      let got = timeStep(spanMs: row[0], plotW: row[1], perLabelPx: row[2])
      if Double(got) != row[3] {
        bad += 1
        if first.isEmpty { first = "span=\(row[0]) plotW=\(row[1]) 期望 \(row[3]) 得到 \(got)" }
      }
    }
    #expect(bad == 0, "\(Fx.time.count) 组里 \(bad) 组不符，首个 \(first)")
    #expect(Fx.time.count >= 200, "fixture 只有 \(Fx.time.count) 组")
  }

  @Test("阶梯表：原型那一段原样，末尾补 2 / 5 / 10 年")
  func stepsTable() {
    let day = 86_400_000.0
    #expect(Array(timeSteps.map(Double.init).prefix(Fx.timeStepsJS.count)) == Fx.timeStepsJS)
    #expect(timeSteps.dropFirst(Fx.timeStepsJS.count).map(Double.init) == [730 * day, 1825 * day, 3650 * day])
  }

  /// `niceStep` 只允许 1 / 2 / 2.5 / 5 / 10 这五种尾数。
  @Test("niceStep 尾数只有五种")
  func niceStepMantissa() {
    var r = Rng(515)
    for _ in 0..<20000 {
      let span = pow(10, r.d(-6, 9))
      let want = Double(r.i(2, 16))
      let s = niceStep(span: span, want: want)
      #expect(s > 0 && s.isFinite, "span=\(span) 得到 \(s)")
      let m = s / pow(10, floor(log10(s)))
      let ok = [1.0, 2.0, 2.5, 5.0, 10.0].contains { abs($0 - m) < 1e-9 }
      #expect(ok, "span=\(span) want=\(want) 尾数 \(m)")
    }
    #expect(niceStep(span: 0, want: 5) == 1, "span=0 要有兜底")
    #expect(niceStep(span: -3, want: 5) == 1)
  }

  /// 标签数不能失控：`span/step` 落在 want 附近。
  @Test("刻度密度合理")
  func density() {
    var r = Rng(717)
    for _ in 0..<5000 {
      let span = pow(10, r.d(-4, 6))
      let want = Double(r.i(2, 14))
      let n = span / niceStep(span: span, want: want)
      #expect(n <= want * 2 + 1e-9, "span=\(span) want=\(want) 出了 \(n) 格")
      #expect(n >= want / 4 - 1e-9, "span=\(span) want=\(want) 只出了 \(n) 格")
    }
  }

  /// 时间刻度对齐到步长整数倍（按时区平移后）。
  @Test("时间刻度按时区对齐", arguments: TZChoice.allCases)
  func timeTicksAligned(_ tz: TZChoice) {
    var r = Rng(919)
    for _ in 0..<400 {
      let from = r.d(1.6e12, 1.8e12)
      let span = pow(10, r.d(5, 10.5))
      let plotW = r.d(120, 900)
      let v = ViewWindow(from: from, to: from + span)
      // 对齐用的是「这一屏右边缘那个时刻」的偏移（本地口径跨夏令时会变，见 TZOffset）。
      let off = Double(tz.offsetMinutes.minutes(at: v.to)) * 60_000
      let ticks = timeTicks(view: v, plotW: plotW, offsetMinutes: tz.offsetMinutes)
      for (t, step) in ticks {
        #expect(t >= v.from - 1 && t <= v.to + 1, "刻度跑到视野外 \(t)")
        #expect(Self.aligned(t, step: step, off: off), "\(tz.rawValue) 没对齐：\(t) step=\(step)")
      }
      let expected = floor(v.span / Double(ticks.first?.step ?? 1))
      #expect(Double(ticks.count) <= expected + 2, "刻度多了")
    }
  }

  /// 一天以内对齐到步长整倍数；周 / 两周落在周一零点；一月及以上落在某月 1 号零点，
  /// 且月份是档位的整倍数（季 1/4/7/10、年 1 月、2/5/10 年落在整除的年份）。
  static func aligned(_ t: Double, step: Int64, off: Double) -> Bool {
    let day = 86_400_000.0
    let local = t + off
    if let months = calendarMonths(step: step) {
      let p = DateParts(ms: t, offsetMinutes: Int(off / 60_000))
      return p.day == 1 && p.hour == 0 && p.minute == 0 && (p.year * 12 + p.month - 1) % months == 0
    }
    let s = Double(step)
    let anchor = step % Int64(7 * day) == 0 ? 4 * day : 0
    let m = (local - anchor).truncatingRemainder(dividingBy: s)
    return abs(m) < 1e-6 || abs(abs(m) - s) < 1e-6
  }

  /// 上海时区、按周一开盘的周线：7 天 / 14 天档的刻度都在周一 00:00（审查 B·P3-3）。
  @Test("周线刻度落在周一零点")
  func weeklyTicksLandOnMonday() {
    let shanghai = 480
    let off = Double(shanghai) * 60_000
    let day = 86_400_000.0
    // 2026-01-01 起：按 `timeStep` 的口径反推视野宽度（每格约 6 天 → 7 天档，约 12 天 → 14 天档），
    // 起点在一周里错开，保证每个宽度都真落在周档上。
    var hits = 0
    for (k, perTick) in [6.0, 12.0, 6.5, 11.0].enumerated() {
      for plotW in [180.0, 260, 350, 420] {
        let want = max(2, (plotW / Chart.timeLabelPx).rounded(.down))
        let from = 1_767_225_600_000.0 + Double(k * 3 + Int(plotW) % 7) * 0.9 * day
        let v = ViewWindow(from: from, to: from + want * perTick * day)
        let ticks = timeTicks(view: v, plotW: plotW, offsetMinutes: shanghai)
        guard let step = ticks.first?.step, step == Int64(7 * day) || step == Int64(14 * day) else { continue }
        hits += 1
        for (t, _) in ticks {
          // 1970-01-01（epoch）是周四；周一 = 第 4 天起每 7 天
          let localDays = Int(((t + off) / day).rounded(.down))
          #expect((localDays - 4) % 7 == 0, "刻度不在周一：本地第 \(localDays) 天")
          #expect((t + off).truncatingRemainder(dividingBy: day) == 0, "刻度不在零点")
          #expect(fmtTick(ms: t, step: Double(step), offsetMinutes: shanghai).count == 5)
        }
      }
    }
    #expect(hits > 5, "没有一个视野落在周档，用例白跑了")
  }

  /// 1M 序列 2017-08 至 2026-10、图宽 350：所有刻度在某月 1 号（年档时 1 月 1 号），
  /// 相邻刻度的间距放得下标签（9pt 等宽字一个字符按 6 点算，再留 4 点）。
  @Test("月线 / 长视野刻度落在 1 号且不挤", arguments: [350.0, 250, 600])
  func monthlyTicksLandOnFirst(_ plotW: Double) {
    let shanghai = 480
    let from = Double(daysFromCivil(year: 2017, month: 8, day: 1)) * 86_400_000 - 8 * 3_600_000
    let to = Double(daysFromCivil(year: 2026, month: 10, day: 1)) * 86_400_000
    let v = ViewWindow(from: from, to: to)
    let ticks = timeTicks(view: v, plotW: plotW, offsetMinutes: shanghai)
    #expect(ticks.count >= 2)
    for (t, step) in ticks {
      let p = DateParts(ms: t, offsetMinutes: shanghai)
      #expect(p.day == 1 && p.hour == 0 && p.minute == 0, "\(p) 不是 1 号零点")
      if step >= Int64(365 * 86_400_000) { #expect(p.month == 1, "年档刻度不在 1 月：\(p)") }
    }
    for (a, b) in zip(ticks, ticks.dropFirst()) {
      let gap = v.x(b.t, plotW: plotW) - v.x(a.t, plotW: plotW)
      let label = fmtTick(ms: b.t, step: Double(b.step), offsetMinutes: shanghai)
      #expect(gap > Double(label.count) * 6 + 4, "相邻刻度只隔 \(gap) 点，放不下「\(label)」")
    }
  }

  @Test("月 / 季 / 年档按日历推进，跨闰年与年末不漂")
  func calendarStepsAdvanceByMonths() {
    let day = 86_400_000.0
    // days_from_civil 与 DateParts 互逆
    for (y, m, d) in [(1970, 1, 1), (2000, 2, 29), (2024, 12, 31), (2026, 3, 1), (1969, 12, 31)] {
      let p = DateParts(ms: Double(daysFromCivil(year: y, month: m, day: d)) * day, offsetMinutes: 0)
      #expect(p.year == y && p.month == m && p.day == d)
    }
    #expect(daysFromCivil(year: 1970, month: 1, day: 5) == 4, "1970-01-05 是周一锚点")
    // 季档：刻度月份只有 1/4/7/10
    let v = ViewWindow(from: Double(daysFromCivil(year: 2019, month: 5, day: 17)) * day,
                       to: Double(daysFromCivil(year: 2024, month: 2, day: 3)) * day)
    for plotW in stride(from: 120.0, through: 900, by: 30) {
      let ticks = timeTicks(view: v, plotW: plotW, offsetMinutes: 0)
      for (t, step) in ticks {
        #expect(Self.aligned(t, step: step, off: 0), "plotW=\(plotW) step=\(step) 刻度 \(DateParts(ms: t, offsetMinutes: 0))")
      }
    }
    // 坏视野不死循环
    #expect(timeTicks(view: ViewWindow(from: .nan, to: 1), plotW: 300, offsetMinutes: 0).isEmpty)
  }

  /// 价格刻度在变换后的空间里等距，且都落在区间内。
  @Test("价格刻度等距", arguments: PriceMode.allCases)
  func priceTicksEven(_ mode: PriceMode) {
    var r = Rng(1213)
    for _ in 0..<600 {
      let lo = r.d(0.01, 90000)
      let range = PriceRange(lo: lo, hi: lo * r.d(1.001, 3), base: lo)
      let h = r.d(60, 700)
      let ts = priceTicks(range: range, mode: mode, paneH: h)
      guard ts.count >= 2 else { continue }
      let d0 = ts[1] - ts[0]
      for i in 1..<ts.count {
        #expect(abs((ts[i] - ts[i - 1]) - d0) <= 1e-9 * max(1, abs(d0)), "\(mode.rawValue) 第 \(i) 格不等距")
      }
      let a = mode.forward(range.lo, base: range.base), z = mode.forward(range.hi, base: range.base)
      #expect(ts.first! >= a - 1e-9 && ts.last! <= z + 1e-9, "\(mode.rawValue) 刻度出界")
      #expect(Double(ts.count) <= max(2, floor(h / Chart.priceLabelPx)) * 2 + 2, "\(mode.rawValue) 刻度太密")
    }
  }
}
