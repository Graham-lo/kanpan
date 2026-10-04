import Foundation
import Testing

@testable import KanpanCore

/// 指标的边界：数据不够、价格一动不动、参数是脏的。
///
/// 这些情形线上一定会遇到——新上市的品种只有几根、横盘时 high == low、
/// 用户把参数调成 1 或者 0。原型在这些地方给的是 NaN 或者恒定值，不是崩溃，
/// 也不是 0；画出来应当是「这段没有线」而不是「贴地一条直线」。
@Suite("指标边界")
struct IndicatorEdgeTests {
  static let flat = [Double](repeating: 100, count: 60)
  static let ramp = (0..<60).map { Double($0) + 1 }

  @Test("数据不够时整列 NaN")
  func tooShort() {
    for n in [5, 20, 99] {
      let short = Array(Self.ramp.prefix(n - 1))
      #expect(sma(short, n).filter(\.isFinite).isEmpty, "SMA\(n) 在 \(n - 1) 根上不该有值")
      #expect(ema(short, n).filter(\.isFinite).isEmpty)
      #expect(rma(short, n).filter(\.isFinite).isEmpty)
    }
    #expect(sma([], 5).isEmpty && ema([], 5).isEmpty)
  }

  @Test("前导 NaN 的位置")
  func warmupPositions() {
    let n = 7
    let s = sma(Self.ramp, n)
    #expect(s.prefix(n - 1).filter(\.isNaN).count == n - 1)
    #expect(s[n - 1].isFinite, "第 n 根就该出第一个值")
    let e = ema(Self.ramp, n)
    #expect(e.prefix(n - 1).filter(\.isNaN).count == n - 1)
    #expect(e[n - 1] == Self.ramp.prefix(n).reduce(0, +) / Double(n), "EMA 用前 n 根均值起步")
    // 全都有值以后不能再冒出 NaN
    #expect(s.dropFirst(n - 1).filter(\.isNaN).isEmpty)
    #expect(e.dropFirst(n - 1).filter(\.isNaN).isEmpty)
  }

  @Test("参数非法就整列 NaN，不要崩")
  func badParams() {
    for n in [0, -1, -100] {
      #expect(sma(Self.ramp, n).filter(\.isFinite).isEmpty, "n=\(n)")
      #expect(ema(Self.ramp, n).filter(\.isFinite).isEmpty, "n=\(n)")
      #expect(rma(Self.ramp, n).filter(\.isFinite).isEmpty, "n=\(n)")
      #expect(rsi(Self.ramp, n).count == Self.ramp.count)
    }
    // n = 1 是退化但合法：均线就是价格本身
    #expect(sma(Self.ramp, 1) == Self.ramp)
    #expect(ema(Self.ramp, 1) == Self.ramp)
  }

  /// 横盘：RSI 的分母是 0。原型走的是「涨跌都没有 → 50」还是 100，以实现为准，
  /// 但绝不能是 NaN 或者 inf——画出来会断线。
  @Test("横盘时不出 NaN / inf")
  func flatMarket() {
    let r = rsi(Self.flat, 14)
    let tail = r.dropFirst(20)
    #expect(tail.filter { $0.isNaN || $0.isInfinite }.isEmpty, "横盘 RSI 出了 \(Array(tail.prefix(3)))")
    #expect(tail.allSatisfy2 { $0 >= 0 && $0 <= 100 })

    let k = kdj(Self.flat, Self.flat, Self.flat, 9, 3, 3)
    #expect(k.k.dropFirst(12).filter { $0.isNaN || $0.isInfinite }.isEmpty, "high == low 时 KDJ 炸了")

    let b = boll(Self.flat, 20, 2)
    // 标准差为 0，三条带重合
    #expect(b.up[30] == b.mid[30] && b.dn[30] == b.mid[30])
    #expect(b.mid[30] == 100)

    let a = atr(Self.flat, Self.flat, Self.flat, 14)
    #expect(a[30] == 0, "完全不动的行情 ATR 就是 0")
  }

  /// 单边上涨 RSI 顶到 100、单边下跌到 0。
  @Test("单边行情的 RSI 极值")
  func rsiExtremes() {
    let up = rsi(Self.ramp, 14)
    #expect(abs(up[40] - 100) < 1e-9, "连涨 RSI 应当是 100，得到 \(up[40])")
    let down = rsi(Self.ramp.reversed().map { $0 }, 14)
    #expect(abs(down[40]) < 1e-9, "连跌 RSI 应当是 0，得到 \(down[40])")
    for v in up.dropFirst(14) { #expect(v >= 0 && v <= 100) }
  }

  /// StochRSI 的窗口全等时分母为 0，同样不能出 NaN。
  @Test("StochRSI 分母为零")
  func stochRsiFlat() {
    let n = Self.flat.count
    let series = BarSeries(symbol: "X", interval: .h1, t0: 0, open: Self.flat, high: Self.flat, low: Self.flat,
                           close: Self.flat, volume: [Double](repeating: 1, count: n))
    var e = IndicatorEngine()
    e.ensure(series: series, wanted: [.srsi], params: [.srsi: [14, 14, 3, 3]], dataKey: "flat")
    let tail = e[.srsi]!.lines[0].dropFirst(35)
    #expect(!tail.isEmpty)
    #expect(tail.filter { $0.isNaN || $0.isInfinite }.isEmpty)
    #expect(tail.allSatisfy2 { $0 >= 0 && $0 <= 100 })
  }

  /// KDJ 的 J 可以冲出 0–100，这是它本来的样子，别夹。
  @Test("J 线允许越界")
  func jLineOvershoots() {
    var c = Self.ramp
    c[30] = 1000   // 一根插针
    let k = kdj(c.map { $0 + 5 }, c.map { $0 - 5 }, c, 9, 3, 3)
    let j = k.j.dropFirst(12).filter(\.isFinite)
    #expect(!j.isEmpty)
    #expect(j.contains { $0 > 100 } || j.contains { $0 < 0 }, "J 线被夹在 0–100 里了")
    // K、D 不越界
    for v in k.k.dropFirst(12) where v.isFinite { #expect(v >= -1e-9 && v <= 100 + 1e-9) }
  }

  /// `smaSkip` 要跳过前导 NaN（MACD 的 DEA、StochRSI 的 K 都靠它）。
  @Test("smaSkip 跳过前导 NaN")
  func skipLeadingNaN() {
    var src = nanArrayTest(5) + (1...10).map(Double.init)
    let out = smaSkip(src, 3)
    #expect(out.count == src.count)
    #expect(out.prefix(7).filter(\.isFinite).isEmpty, "前 5 个 NaN 加 2 根热身")
    #expect(abs(out[7] - 2) < 1e-12, "1,2,3 的均值")
    // 全是 NaN 就全给 NaN
    src = nanArrayTest(10)
    #expect(smaSkip(src, 3).filter(\.isFinite).isEmpty)
  }

  /// MACD 的三条线长度一致、柱 = (dif - dea) * 2。
  @Test("MACD 柱是差值的两倍")
  func macdHistogram() {
    let m = macd(Self.ramp, 12, 26, 9)
    #expect(m.dif.count == Self.ramp.count && m.dea.count == m.dif.count && m.hist.count == m.dif.count)
    for i in 0..<m.hist.count where m.hist[i].isFinite {
      #expect(abs(m.hist[i] - (m.dif[i] - m.dea[i]) * 2) < 1e-9, "第 \(i) 根")
    }
  }

  /// ATR 的真实波幅要把跳空算进去（不只是当根的 high - low）。
  @Test("ATR 算上跳空")
  func atrGaps() {
    // 第 20 根整体跳空到上面，high - low 很小但 TR 很大
    var h = [Double](repeating: 101, count: 40)
    var l = [Double](repeating: 99, count: 40)
    var c = [Double](repeating: 100, count: 40)
    for i in 20..<40 { h[i] += 50; l[i] += 50; c[i] += 50 }
    let a = atr(h, l, c, 14)
    #expect(a[19] == 2, "平稳段 TR 就是 high - low")
    #expect(a[20] > 2, "跳空那根应当把 ATR 抬起来，得到 \(a[20])")
  }

  /// 引擎在空序列、缺参数、换参数时的行为。
  @Test("引擎在空数据和换参时不乱")
  func engineEdges() {
    let empty = BarSeries(symbol: "X", interval: .h1, bars: [])
    var e = IndicatorEngine()
    let first = e.ensure(series: empty, wanted: IndicatorID.allCases, dataKey: "k")
    #expect(first)
    #expect(e.values.count == IndicatorID.allCases.count)
    for (id, r) in e.values {
      #expect(r.lines.count == id.lineNames(params: id.defaultParams).count, "\(id.rawValue)")
      #expect(r.lines.filter { !$0.isEmpty }.isEmpty, "\(id.rawValue) 空序列上不该有点")
    }
    // 空序列上更新末根不能崩
    e.updateTail(series: empty, dataKey: "k")

    // 换参数要重算
    let s = synthSeries(count: 100, seed: 3)
    var e2 = IndicatorEngine()
    e2.ensure(series: s, wanted: [.ma], dataKey: "k")
    let a = e2.values[.ma]!.lines[0]
    let changed = e2.ensure(series: s, wanted: [.ma], params: [.ma: [3, 4, 5]], dataKey: "k")
    #expect(changed, "换参数必须重算")
    #expect(e2.values[.ma]!.lines[0] != a)
    #expect(e2.values[.ma]!.lines.count == 3)
  }
}

@Suite("抛物线转向")
struct SARReversalTests {
  static func sar(_ s: BarSeries) -> IndicatorResult {
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: [.sar], dataKey: "sar")
    return e.values[.sar]!
  }

  @Test("翻转那一根的点落在这根 K 线之外，不画进影线里")
  func reversalBarSitsOutsideTheBar() {
    // 一路上涨六根，第七根先冲到 120、再砸到 80：同一根既创新高又跌破轨。
    var o = [89.5], h = [91.0], l = [89.0], c = [90.0]
    for k in 1...5 {
      let base = 90.0 + 2 * Double(k)
      o.append(base); h.append(base + 2); l.append(base); c.append(base + 1.5)
    }
    o.append(101); h.append(120); l.append(80); c.append(82)
    let s = BarSeries(symbol: "BTCUSDT", interval: .h1, t0: 1_700_000_000_000,
                      open: o, high: h, low: l, close: c, volume: Array(repeating: 1, count: o.count))
    let r = Self.sar(s)
    let last = s.count - 1
    #expect(r.dir?[last] == -1, "这一根翻空")
    #expect(r.lines[0][last] >= h[last], "翻空那一根的点要在最高价之上，实际 \(r.lines[0][last])")
  }

  @Test("随机序列：每一根的点都在这根之外（多头在最低价之下，空头在最高价之上）")
  func everyBarOutsideItsRange() {
    for seed in [UInt64(3), 11, 29, 47] {
      let s = synthSeries(count: 1500, seed: seed)
      let r = Self.sar(s)
      let out = r.lines[0], dir = r.dir ?? []
      var flips = 0
      for i in 1..<s.count {
        if dir[i] != dir[i - 1] { flips += 1 }
        if dir[i] > 0 {
          #expect(out[i] <= s.low[i], "seed \(seed) 第 \(i) 根多头点进了 K 线")
        } else {
          #expect(out[i] >= s.high[i], "seed \(seed) 第 \(i) 根空头点进了 K 线")
        }
      }
      #expect(flips > 10, "随机序列里得真的翻过几次才算测到")
    }
  }
}

@Suite("累计周期的锚")
struct AnchorPeriodTests {
  static func series(_ interval: Interval, _ times: [Int64]) -> BarSeries {
    BarSeries(symbol: "X", interval: interval, bars: times.map {
      Bar(openTime: $0, open: 10, high: 12, low: 8, close: 11, volume: 5, takerBuy: 3)
    })
  }
  static func ms(_ y: Int, _ m: Int, _ d: Int) -> Int64 { Aggregator.utcMs(year: y, month: m, day: d) }

  @Test("周线、月线按自然年归零，年线不归零")
  func weeklyMonthlyAnchorToYear() {
    // 12-16、12-23、12-30 在 2024 年，01-06 进了 2025。
    let w = Self.series(.w1, [Self.ms(2024, 12, 16), Self.ms(2024, 12, 23), Self.ms(2024, 12, 30), Self.ms(2025, 1, 6)])
    #expect((0..<4).map { startsAnchorPeriod(w, $0) } == [true, false, false, true])
    let mo = Self.series(.mo1, [Self.ms(2024, 11, 1), Self.ms(2024, 12, 1), Self.ms(2025, 1, 1), Self.ms(2025, 2, 1)])
    #expect((0..<4).map { startsAnchorPeriod(mo, $0) } == [true, false, true, false])
    let y = Self.series(.y1, [Self.ms(2021, 1, 1), Self.ms(2022, 1, 1), Self.ms(2023, 1, 1)])
    #expect((0..<3).map { startsAnchorPeriod(y, $0) } == [true, false, false])
    // 日线照旧按自然月。
    let d = Self.series(.d1, [Self.ms(2025, 1, 30), Self.ms(2025, 1, 31), Self.ms(2025, 2, 1)])
    #expect((0..<3).map { startsAnchorPeriod(d, $0) } == [true, false, true])
  }

  @Test("月线上的 VWAP / CVD 真的在累计，不是每根各算各的")
  func monthlyCumulates() {
    let times = (1...6).map { Self.ms(2025, $0, 1) }
    let s = BarSeries(symbol: "X", interval: .mo1, bars: times.enumerated().map { i, t in
      let p = 100 + Double(i) * 10
      return Bar(openTime: t, open: p, high: p + 6, low: p - 3, close: p + 3, volume: 10, takerBuy: 7)
    })
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: [.vwap, .cvd], dataKey: "mo")
    let vwap = e.values[.vwap]!.lines[0], cvd = e.values[.cvd]!.lines[0]
    let last = s.count - 1
    let typical = (s.high[last] + s.low[last] + s.close[last]) / 3
    #expect(vwap[last] < typical, "半年的量价都算进来，VWAP 落在末根典型价下面")
    #expect(cvd[last] == 6 * (2 * 7 - 10), "CVD 是六根净额的累计")
  }

  @Test("VWAP 碰上一根量不是有限数：只空这一根，后面照常累计，增量与全量一致")
  func vwapSkipsNonFiniteVolume() {
    var bars = (0..<48).map { i in
      Bar(openTime: Self.ms(2025, 3, 3) + Int64(i) * 3_600_000, open: 100, high: 101 + Double(i % 3),
          low: 99, close: 100.5, volume: 10 + Double(i))
    }
    bars[5].volume = .nan
    let s = BarSeries(symbol: "X", interval: .h1, bars: bars)
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: [.vwap], dataKey: "v")
    let line = e.values[.vwap]!.lines[0]
    #expect(line[5].isNaN, "那一根留白")
    #expect(line[6...23].allSatisfy2(\.isFinite), "同一天后面的线还在")
    #expect(line[24...].allSatisfy2(\.isFinite))
    // 改末根走增量，结果要和新引擎全量一致。
    var tail = bars; tail[47].close = 100.9
    let s2 = BarSeries(symbol: "X", interval: .h1, bars: tail)
    e.updateTail(series: s2, dataKey: "v")
    var fresh = IndicatorEngine()
    fresh.ensure(series: s2, wanted: [.vwap], dataKey: "v")
    let a = e.values[.vwap]!.lines[0], b = fresh.values[.vwap]!.lines[0]
    #expect(a.count == b.count)
    #expect(zip(a, b).allSatisfy { $0 == $1 || ($0.isNaN && $1.isNaN) })
  }
}

func nanArrayTest(_ n: Int) -> [Double] { [Double](repeating: .nan, count: n) }

extension Collection where Element == Double {
  /// `allSatisfy` 在 `#expect` 里会被当成能抛的闭包，自己写一个不抛的。
  func allSatisfy2(_ f: (Double) -> Bool) -> Bool {
    for x in self where !f(x) { return false }
    return true
  }
}
