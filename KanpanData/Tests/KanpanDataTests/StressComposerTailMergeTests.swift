import Foundation
import Testing
@testable import KanpanData
import KanpanCore

// 压测 · 对表 / 补缺只拆尾巴：结果和原来「整条拆进字典、排序、整条重建」逐位一致，碰的根数只和尾巴有关。

private struct SplitMix: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

private func bar(_ t: Int64, _ px: Double) -> Bar {
  Bar(openTime: t, open: px, high: px + 1, low: px - 1, close: px + 0.5, volume: 10, takerBuy: 4)
}

/// 原来的 `merge`（新鲜 composer：`lastClosedTime == 0`，封没封只看是不是早于末根）。
private func reference(_ s: BarSeries, _ bars: [Bar], preservingLiveTail: Bool) -> BarSeries {
  var m: [Int64: Bar] = [:]
  for i in 0..<s.count { m[s.time(at: i)] = s.bar(at: i) }
  let live = bars.map(\.openTime).max()
  for b in bars {
    if preservingLiveTail, b.openTime == s.lastTime { continue }
    if b.openTime == live, m[b.openTime] != nil, b.openTime < s.lastTime { continue }
    m[b.openTime] = b
  }
  return BarSeries(symbol: s.symbol, interval: s.interval, bars: m.keys.sorted().map { m[$0]! })
}

@Suite("压测 · 对表与补缺只拆尾巴")
struct StressComposerTailMergeTests {
  @Test("只拆尾巴的 merge 与整条重建逐位一致（等距、带洞、1M 不等距；尾巴重叠、填洞、续接、整段更早）")
  func tailMergeMatchesWholeRebuild() {
    var rng = SplitMix(state: 20_260_926)
    for round in 0..<600 {
      let interval: Interval = round % 3 == 2 ? .mo1 : .m1
      let step: Int64 = interval == .mo1 ? 31 * 86_400_000 : 60_000
      let n = Int.random(in: 1...120, using: &rng)
      let base: Int64 = 1_700_000_000_000 / step * step
      var times = (0..<n).map { base + Int64($0) * step + (interval == .mo1 ? Int64($0 % 3) * 86_400_000 : 0) }
      if round % 3 == 1, n > 4 {
        for _ in 0..<Int.random(in: 1...3, using: &rng) { times.remove(at: Int.random(in: 1..<(times.count - 1), using: &rng)) }
      }
      let series = BarSeries(symbol: "BTCUSDT", interval: interval,
                             bars: times.map { bar($0, Double.random(in: 90...110, using: &rng)) })
      var incoming: [Bar] = []
      for _ in 0..<Int.random(in: 1...8, using: &rng) {
        let t: Int64
        switch Int.random(in: 0..<4, using: &rng) {
        case 0: t = times[Int.random(in: 0..<times.count, using: &rng)]                     // 重叠
        case 1: t = base + Int64(Int.random(in: 0..<(n + 2), using: &rng)) * step           // 填洞 / 续接
        case 2: t = times.last! + Int64(Int.random(in: 1...4, using: &rng)) * step          // 末根之后（可能隔一段）
        default: t = base - Int64(Int.random(in: 1...3, using: &rng)) * step                // 整段更早
        }
        incoming.append(bar(t, Double.random(in: 90...110, using: &rng)))
      }
      let preserving = Bool.random(using: &rng)
      var composer = FeedComposer(series: series)
      composer.merge(incoming, preservingLiveTail: preserving)
      let expected = reference(series, incoming, preservingLiveTail: preserving)
      #expect(composer.series == expected, "第 \(round) 轮")
      #expect(composer.series.openTime.isEmpty == expected.openTime.isEmpty, "第 \(round) 轮：省列的不变量")
      #expect(composer.series.t0 == expected.t0, "第 \(round) 轮")
      if composer.series != expected { break }
    }
  }

  /// 往回翻出 6 万根之后，对表改末尾三根：只拆这三根，前面五万九千多根一根不碰。
  @Test("对表改末尾三根只拆三根，和序列多长无关")
  func reconcileTouchesOnlyTheTail() {
    let n = 60_000
    let series = BarSeries(symbol: "BTCUSDT", interval: .m1,
                           bars: (0..<n).map { bar(Int64($0) * 60_000, 100) })
    var composer = FeedComposer(series: series)
    let tail = ((n - 3)..<n).map { bar(Int64($0) * 60_000, 101) }
    let changed = composer.reconcile(tail)
    #expect(changed)
    #expect(composer.lastMergeSpan == 3)
    #expect(composer.series.count == n)
    #expect(composer.series.openTime.isEmpty, "仍然严格等距，列照旧省掉")
    #expect(composer.series.bar(at: 0) == series.bar(at: 0))
    #expect(composer.series.close[n - 2] == 101.5)
  }
}
