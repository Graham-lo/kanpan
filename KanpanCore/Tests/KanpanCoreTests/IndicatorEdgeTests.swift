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
    let s = stochRsi(Self.flat, 14, 14, 3, 3)
    let tail = s.k.dropFirst(35)
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

func nanArrayTest(_ n: Int) -> [Double] { [Double](repeating: .nan, count: n) }

extension Collection where Element == Double {
  /// `allSatisfy` 在 `#expect` 里会被当成能抛的闭包，自己写一个不抛的。
  func allSatisfy2(_ f: (Double) -> Bool) -> Bool {
    for x in self where !f(x) { return false }
    return true
  }
}
