import Foundation
import Testing

@testable import KanpanCore

/// A1.8 的后半段：`Aggregator.bucket` 从 1M 聚年线，覆盖闰年、跨年、当年未走完那根。
@Suite("聚合")
struct AggregatorTests {
  /// 真实的 UTC 月初，2019-01 到 2026-09（含 2020 / 2024 两个闰年，末年只走到 9 月）。
  private func monthlySeries() -> BarSeries {
    var bars: [Bar] = []
    var v = 100.0
    for y in 2019...2026 {
      for m in 1...12 {
        if y == 2026 && m > 9 { break }
        let t = Aggregator.utcMs(year: y, month: m, day: 1)
        // 造一组彼此不同、好手算的值：开=v，收=v+3，高=v+9，低=v-4，量=y*100+m。
        bars.append(Bar(openTime: t, open: v, high: v + 9, low: v - 4, close: v + 3,
                        volume: Double(y * 100 + m)))
        v += 7
      }
    }
    return BarSeries(symbol: "BTCUSDT", interval: .mo1, bars: bars)
  }

  @Test("月线聚年线：每桶的开高低收量")
  func monthlyToYearly() {
    let m = monthlySeries()
    #expect(m.count == 12 * 7 + 9)
    let y = Aggregator.bucket(series: m, into: .y1)
    #expect(y.interval == .y1)
    #expect(y.count == 8, "2019…2026 共 8 根，得到 \(y.count)")

    // 逐年手算比对
    var idx = 0
    for (k, year) in (2019...2026).enumerated() {
      let months = year == 2026 ? 9 : 12
      let first = idx, last = idx + months - 1
      #expect(y.openTime[k] == Aggregator.utcMs(year: year, month: 1, day: 1),
              "\(year) 的 openTime 应是 1 月 1 日 00:00 UTC")
      #expect(y.open[k] == m.open[first], "\(year) 开盘取该年第一根的 open")
      #expect(y.close[k] == m.close[last], "\(year) 收盘取该年最后一根的 close")
      #expect(y.high[k] == m.high[first...last].max()!)
      #expect(y.low[k] == m.low[first...last].min()!)
      #expect(abs(y.volume[k] - m.volume[first...last].reduce(0, +)) < 1e-9)
      idx += months
    }
  }

  /// 当年未走完那根：只聚已有的月，收盘跟着最后一根月线走；再来一根新月线就要更新。
  @Test("当年未定稿那根")
  func partialLastYear() {
    var m = monthlySeries()
    let y1 = Aggregator.bucket(series: m, into: .y1)
    #expect(y1.close.last! == m.close.last!)
    let volBefore = y1.volume.last!

    // 10 月到货
    m.append(Bar(openTime: Aggregator.utcMs(year: 2026, month: 10, day: 1),
                 open: 1, high: 999, low: 0.5, close: 42, volume: 1000))
    let y2 = Aggregator.bucket(series: m, into: .y1)
    #expect(y2.count == y1.count, "还在同一年，不该多出一根")
    #expect(y2.close.last! == 42)
    #expect(y2.high.last! == 999)
    #expect(y2.low.last! == 0.5)
    #expect(abs(y2.volume.last! - (volBefore + 1000)) < 1e-9)
    #expect(y2.open.last! == y1.open.last!, "开盘还是 1 月那根")

    // 跨到 2027 才添新根
    m.append(Bar(openTime: Aggregator.utcMs(year: 2027, month: 1, day: 1),
                 open: 7, high: 8, low: 6, close: 7.5, volume: 5))
    let y3 = Aggregator.bucket(series: m, into: .y1)
    #expect(y3.count == y1.count + 1)
    #expect(y3.open.last! == 7 && y3.close.last! == 7.5)
    #expect(y3.openTime.last! == Aggregator.utcMs(year: 2027, month: 1, day: 1))
  }

  /// 闰年：2020 和 2024 的 2 月有 29 天，2 月 29 日必须落进当年、当月那个桶。
  @Test("闰年与月末落桶")
  func leapAndMonthEnd() {
    let feb29_2020 = Aggregator.utcMs(year: 2020, month: 2, day: 29)
    #expect(Aggregator.bucketStart(ms: feb29_2020, interval: .mo1)
            == Aggregator.utcMs(year: 2020, month: 2, day: 1))
    #expect(Aggregator.bucketStart(ms: feb29_2020, interval: .y1)
            == Aggregator.utcMs(year: 2020, month: 1, day: 1))
    // 2 月 29 日 23:59:59.999 还在 2 月
    #expect(Aggregator.bucketStart(ms: feb29_2020 + 86_399_999, interval: .mo1)
            == Aggregator.utcMs(year: 2020, month: 2, day: 1))
    // 平年的 3 月 1 日紧接 2 月 28 日
    #expect(Aggregator.bucketStart(ms: Aggregator.utcMs(year: 2023, month: 2, day: 28) + 86_400_000,
                                   interval: .mo1) == Aggregator.utcMs(year: 2023, month: 3, day: 1))
    // 跨年边界：12-31 23:59:59.999 归旧年，01-01 00:00 归新年
    let ny = Aggregator.utcMs(year: 2025, month: 1, day: 1)
    #expect(Aggregator.bucketStart(ms: ny - 1, interval: .y1) == Aggregator.utcMs(year: 2024, month: 1, day: 1))
    #expect(Aggregator.bucketStart(ms: ny, interval: .y1) == ny)
    // 闰年 366 天、平年 365 天
    #expect(Aggregator.utcMs(year: 2025, month: 1, day: 1) - Aggregator.utcMs(year: 2024, month: 1, day: 1)
            == 366 * 86_400_000)
    #expect(Aggregator.utcMs(year: 2024, month: 1, day: 1) - Aggregator.utcMs(year: 2023, month: 1, day: 1)
            == 365 * 86_400_000)
    // 世纪闰年规则
    #expect(Aggregator.utcMs(year: 2000, month: 3, day: 1) - Aggregator.utcMs(year: 2000, month: 2, day: 1)
            == 29 * 86_400_000)
    #expect(Aggregator.utcMs(year: 1900, month: 3, day: 1) - Aggregator.utcMs(year: 1900, month: 2, day: 1)
            == 28 * 86_400_000)
  }

  /// `utcMs` 与系统日历对拍，顺带覆盖纪元之前。
  @Test("utcMs 与系统日历一致")
  func utcMsMatchesCalendar() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var r = Rng(2048)
    for _ in 0..<3000 {
      let y = r.i(1900, 2100), mo = r.i(1, 12)
      let d = r.i(1, 28)
      let ms = Aggregator.utcMs(year: y, month: mo, day: d)
      var c = DateComponents()
      c.year = y; c.month = mo; c.day = d
      let want = Int64((cal.date(from: c)!.timeIntervalSince1970 * 1000).rounded())
      #expect(ms == want, "\(y)-\(mo)-\(d)：自己算 \(ms)，系统 \(want)")
      // 来回一趟
      let p = DateParts(ms: Double(ms), offsetMinutes: 0)
      #expect(p.year == y && p.month == mo && p.day == d && p.hour == 0 && p.minute == 0)
    }
  }

  /// 周线桶：币安的周线是周一 00:00 UTC 起。
  @Test("周线桶落在周一零点")
  func weeklyBuckets() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var r = Rng(99)
    for _ in 0..<2000 {
      let ms = Int64(r.d(-3e11, 2.2e12))
      let s = Aggregator.bucketStart(ms: ms, interval: .w1)
      #expect(s <= ms && ms - s < 7 * 86_400_000)
      let d = Date(timeIntervalSince1970: Double(s) / 1000)
      let c = cal.dateComponents([.weekday, .hour, .minute, .second], from: d)
      #expect(c.weekday == 2, "周日历的 weekday=2 才是周一，得到 \(c.weekday!)")
      #expect(c.hour == 0 && c.minute == 0 && c.second == 0)
    }
  }

  /// 日线聚周线：桶数、边界、量合计都要对。
  @Test("日线聚周线")
  func dailyToWeekly() {
    // 2024-01-01 是周一，连续 70 天 → 正好 10 周
    let t0 = Aggregator.utcMs(year: 2024, month: 1, day: 1)
    var bars: [Bar] = []
    for i in 0..<70 {
      let v = Double(i)
      bars.append(Bar(openTime: t0 + Int64(i) * 86_400_000,
                      open: v, high: v + 2, low: v - 1, close: v + 1, volume: 1))
    }
    let d = BarSeries(symbol: "X", interval: .d1, bars: bars)
    let w = Aggregator.bucket(series: d, into: .w1)
    #expect(w.count == 10)
    for k in 0..<10 {
      #expect(w.openTime[k] == t0 + Int64(k * 7) * 86_400_000)
      #expect(w.open[k] == Double(k * 7))
      #expect(w.close[k] == Double(k * 7 + 6) + 1)
      #expect(w.high[k] == Double(k * 7 + 6) + 2)
      #expect(w.low[k] == Double(k * 7) - 1)
      #expect(w.volume[k] == 7)
    }
    // 日线聚月线：1 月 31 根、2 月 29 根（2024 闰年）、3 月 10 根
    let mo = Aggregator.bucket(series: d, into: .mo1)
    #expect(mo.count == 3)
    #expect(mo.volume == [31, 29, 10])
  }

  /// 聚出来的序列自己也要能查下标（不等距路径）。
  @Test("聚合结果可索引")
  func aggregatedIsIndexable() {
    let y = Aggregator.bucket(series: monthlySeries(), into: .y1)
    #expect(!y.openTime.isEmpty, "1y 必须带 openTime 表")
    for i in 0..<y.count {
      #expect(y.index(atTime: Double(y.openTime[i])) == i)
      #expect(y.time(at: i) == y.openTime[i])
    }
    #expect(y.index(atTime: -1e15) == 0)
    #expect(y.index(atTime: 1e15) == y.count - 1)
  }

  /// 细度不够就聚不出来：从 1d 要 1h 只能返回空，让调用方去拉网络。
  @Test("聚不出来就给空")
  func cannotUpsample() {
    let d = BarSeries(symbol: "X", interval: .d1, bars: [
      Bar(openTime: 0, open: 1, high: 2, low: 0, close: 1.5, volume: 3),
    ])
    let h = Aggregator.bucket(series: d, into: .h1)
    #expect(h.isEmpty && h.interval == .h1)
    // 空进空出
    let empty = BarSeries(symbol: "X", interval: .m1, bars: [])
    #expect(Aggregator.bucket(series: empty, into: .h1).isEmpty)
    // 同周期聚同周期是恒等
    let same = Aggregator.bucket(series: d, into: .d1)
    #expect(same.count == 1 && same.close == d.close && same.openTime == [0])
  }

  /// 分桶的通用性质：桶单调、不丢根、量守恒、极值不越界。
  @Test("分桶性质")
  func bucketInvariants() {
    var r = Rng(31337)
    for target in [Interval.h4, .d1, .w1, .mo1, .y1] {
      let src: Interval = target == .y1 ? .mo1 : (target == .mo1 || target == .w1 ? .d1 : .m15)
      let n = r.i(40, 400)
      var bars: [Bar] = []
      var t = Aggregator.bucketStart(ms: Int64(r.d(1.4e12, 1.7e12)), interval: src)
      for _ in 0..<n {
        let o = r.d(10, 1000), c = r.d(10, 1000)
        bars.append(Bar(openTime: t, open: o, high: max(o, c) + r.d(0, 5),
                        low: min(o, c) - r.d(0, 5), close: c, volume: r.d(0, 1e6)))
        // 月线源要按真实月初走，别用名义步长
        if src == .mo1 {
          let p = DateParts(ms: Double(t), offsetMinutes: 0)
          t = p.month == 12 ? Aggregator.utcMs(year: p.year + 1, month: 1, day: 1)
                            : Aggregator.utcMs(year: p.year, month: p.month + 1, day: 1)
        } else {
          t += src.stepMs
        }
      }
      let s = BarSeries(symbol: "X", interval: src, bars: bars)
      let g = Aggregator.bucket(series: s, into: target)

      #expect(g.count >= 1 && g.count <= s.count)
      #expect(abs(g.volume.reduce(0, +) - s.volume.reduce(0, +)) < 1e-6, "\(target) 量没守恒")
      #expect(g.open[0] == s.open[0] && g.close.last! == s.close.last!)
      #expect(g.high.max()! == s.high.max()! && g.low.min()! == s.low.min()!)
      for k in 1..<g.count { #expect(g.openTime[k] > g.openTime[k - 1], "\(target) 桶没递增") }
      for k in 0..<g.count {
        #expect(g.high[k] >= max(g.open[k], g.close[k]) && g.low[k] <= min(g.open[k], g.close[k]))
        #expect(Aggregator.bucketStart(ms: g.openTime[k], interval: target) == g.openTime[k],
                "\(target) 的桶起点没对齐")
      }
    }
  }

  /// 14 档周期表要和原型 `ALL_PERIODS` 对得上：有 1y，没有 3d。
  @Test("周期表与原型一致")
  func periodTable() {
    #expect(Interval.allCases.map(\.rawValue) == [
      "1m", "3m", "5m", "15m", "30m", "1h", "2h", "4h", "6h", "12h", "1d", "1w", "1M", "1y",
    ])
    #expect(Interval.allCases.count == 14)
    // 出厂把周期条那六格放满（2026-09-21）：`Prefs.maxQuick` 是 6，出厂 = 满钉。
    #expect(Interval.quick.map(\.rawValue) == ["5m", "30m", "1h", "4h", "1d", "1w"])
    // 哪一档要自己聚是各家交易所的能力（`ProviderCapabilities.aggregatedFrom`），
    // 那张表在 KanpanNetwork 的 ProviderCapabilitiesTests 里核。
    #expect(Interval.y1.isIrregular && Interval.mo1.isIrregular)
    #expect(!Interval.w1.isIrregular, "周线是等距的（周一 00:00 UTC）")
    // 名义步长单调递增
    let steps = Interval.allCases.map(\.stepMs)
    for i in 1..<steps.count { #expect(steps[i] > steps[i - 1]) }
  }
}
