import Foundation
import Testing

@testable import KanpanCore

/// 平均 K 线（K 线设置·蜡烛画法）。
///
/// 两件事要守住：公式本身对，以及「只热身 200 根」和「从第 0 根全量算」给出同一条线。
/// 后者是滚动时每帧都吃的性能账，算错了不会崩，只会让蜡烛在拖动时悄悄跳一下。
@Suite("平均K线")
struct HeikinAshiTests {
  /// 逐根手算对账：`hc` 是四价均值，`ho` 是上一根 (ho+hc)/2，首根用 (o+c)/2。
  @Test("公式逐根对账")
  func formula() {
    let s = synthSeries(count: 60, seed: 31)
    let ha = HeikinAshi.slice(s, lo: 0, hi: s.count - 1, warmup: 0)
    #expect(ha.open.count == s.count)

    var po = Double.nan, pc = Double.nan
    for i in 0..<s.count {
      let hc = (s.open[i] + s.high[i] + s.low[i] + s.close[i]) / 4
      let ho = po.isFinite ? (po + pc) / 2 : (s.open[i] + s.close[i]) / 2
      #expect(ha.close[i] == hc, "第 \(i) 根 close")
      #expect(ha.open[i] == ho, "第 \(i) 根 open")
      #expect(ha.high[i] == max(s.high[i], max(ho, hc)), "第 \(i) 根 high")
      #expect(ha.low[i] == min(s.low[i], min(ho, hc)), "第 \(i) 根 low")
      po = ho; pc = hc
    }
  }

  /// `hh` / `hl` 必然能包住真实 high / low：`priceRange` 不把它们并进去就会裁掉一截。
  @Test("上下影包住真实高低")
  func extremesCoverReal() {
    let s = synthSeries(count: 200, seed: 5)
    let ha = HeikinAshi.slice(s, lo: 0, hi: s.count - 1, warmup: 0)
    for i in 0..<s.count {
      #expect(ha.high[i] >= s.high[i] && ha.low[i] <= s.low[i], "第 \(i) 根没包住")
      #expect(ha.high[i] >= max(ha.open[i], ha.close[i]))
      #expect(ha.low[i] <= min(ha.open[i], ha.close[i]))
    }
  }

  /// 热身 200 根 ≈ 全量：初值权重每根对折，2^-200 掉在 double 有效位以下。
  @Test("热身 200 根与全量等价")
  func warmupConverges() {
    let s = synthSeries(count: 900, seed: 17)
    let full = HeikinAshi.slice(s, lo: 0, hi: s.count - 1, warmup: 0)
    for (lo, hi) in [(400, 500), (700, 899), (250, 260)] {
      let part = HeikinAshi.slice(s, lo: lo, hi: hi, warmup: 200)
      #expect(part.open.count == hi - lo + 1)
      for k in part.open.indices {
        let i = lo + k
        #expect(abs(part.open[k] - full.open[i]) <= 1e-9, "open 第 \(i) 根漂了")
        #expect(abs(part.high[k] - full.high[i]) <= 1e-9, "high 第 \(i) 根漂了")
        #expect(abs(part.low[k] - full.low[i]) <= 1e-9, "low 第 \(i) 根漂了")
        #expect(part.close[k] == full.close[i], "close 第 \(i) 根不该有误差")
      }
    }
  }

  /// 热身根数给得比 `lo` 还大就等于全量，两条路必须逐位相同。
  @Test("热身盖过起点等于全量")
  func hugeWarmupIsExact() {
    let s = synthSeries(count: 300, seed: 99)
    let full = HeikinAshi.slice(s, lo: 0, hi: 299, warmup: 0)
    let part = HeikinAshi.slice(s, lo: 120, hi: 200, warmup: 10_000)
    for k in part.open.indices {
      #expect(part.open[k] == full.open[120 + k])
      #expect(part.high[k] == full.high[120 + k])
      #expect(part.low[k] == full.low[120 + k])
    }
  }

  /// 空序列、下标越界、颠倒的 lo/hi 都不能崩。
  @Test("边界输入")
  func edges() {
    let empty = BarSeries(symbol: "X", interval: .h1, bars: [])
    let e = HeikinAshi.slice(empty, lo: 0, hi: 10)
    #expect(e.open.isEmpty && e.high.isEmpty && e.low.isEmpty && e.close.isEmpty)

    let s = synthSeries(count: 20, seed: 3)
    let over = HeikinAshi.slice(s, lo: -5, hi: 999)
    #expect(over.open.count == 20)
    let flipped = HeikinAshi.slice(s, lo: 15, hi: 3)
    #expect(flipped.open.count == 1, "lo > hi 时只给一根，不能算出负长度")
  }
}
