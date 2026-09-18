import Foundation

/// 上场的一颗球：哪个板块、落在哪一头、同侧第几个、全场第几名。
public struct SectorPick: Sendable, Equatable, Identifiable {
  /// 强端 / 弱端 / 陪衬。
  ///
  /// 陪衬球（filler）**没有任何特殊渲染**——同材质、同光学、同质量标准。
  /// 它看起来次要只因为它确实小、确实不在两头。
  public enum Side: Sendable, Equatable { case strong, weak, filler }
  public let stat: SectorStat
  public let side: Side
  /// 同侧内序号，0 起（原型里的 `o.k`）。
  public let slot: Int
  /// 全场按 pct 降序的名次，0 起（原型里的 `rk`）。
  public let rank: Int
  public var id: String { stat.id }
  public init(stat: SectorStat, side: Side, slot: Int, rank: Int) {
    self.stat = stat
    self.side = side
    self.slot = slot
    self.rank = rank
  }

  /// 球身用哪一头的色相：强端恒 true，弱端恒 false，陪衬看它落在排名的哪半边。
  ///
  /// **这不是涨跌正负。** 2026-09-18 那份快照 27 段中位数全是正的，
  /// 按正负上色会整屏一片绿，「一眼看出最强最弱」就没了。
  /// 讲正负的是球上那串数字，球身只讲「在哪一头」。
  public func isUpSide(total: Int) -> Bool {
    switch side {
    case .strong: return true
    case .weak: return false
    case .filler: return Double(rank) < Double(total) / 2
    }
  }
}

/// 一次选取的结果。`picks` 的顺序就是原型 `list` 的顺序，版面直接照它铺。
public struct SectorSelection: Sendable, Equatable {
  /// 顺序 = strong… + filler… + weak…
  public let picks: [SectorPick]
  /// 参与排序的板块总数（**不含**兜底桶）。
  public let total: Int
  /// 半径归一的分母，`>= 1e-6`。只看上场的那几颗，整屏一把尺子。
  public let maxAbsPct: Double
  /// `total` 里 pct >= 0 的个数。
  public let upCount: Int
  public let downCount: Int
  public init(picks: [SectorPick], total: Int, maxAbsPct: Double, upCount: Int, downCount: Int) {
    self.picks = picks
    self.total = total
    self.maxAbsPct = maxAbsPct
    self.upCount = upCount
    self.downCount = downCount
  }

  public static let empty = SectorSelection(picks: [], total: 0, maxAbsPct: 1e-6, upCount: 0, downCount: 0)
}

/// 上场名单。算法跟定版原型 `proto2/app.js` 的 `ranked()` / `cast()` / `layout()`
/// 逐行等价，一个细节都不能差——差一点球的大小和左右就跟用户看过的那版对不上了。
public enum SectorSelector {
  /// 两个市场各一套默认档：加密盘子大，两头各 5 颗 + 3 颗陪衬；美股只有 10 段，收到 3 + 2。
  public static func defaults(_ m: SectorMarket) -> (n: Int, m: Int) {
    switch m {
    case .crypto: return (5, 3)
    case .us: return (3, 2)
    }
  }

  /// - Parameters:
  ///   - stats: `isFallback` 的在排序和归一**之前**就被摘掉——兜底桶只活在「全部板块」里。
  ///   - n: 两头各取几颗（会被 `floor(总数/2)` 夹住）。
  ///   - m: 中间取几颗陪衬（会被剩下的颗数夹住）。
  public static func select(_ stats: [SectorStat], n: Int, m: Int) -> SectorSelection {
    let ranked = stats.filter { !$0.isFallback }.sorted { $0.pct > $1.pct }
    let count = ranked.count
    let capN = min(max(0, n), count / 2)
    let capM = min(max(0, m), max(0, count - 2 * capN))

    var picks: [SectorPick] = []
    picks.reserveCapacity(2 * capN + capM)

    for i in 0..<capN {
      picks.append(SectorPick(stat: ranked[i], side: .strong, slot: i, rank: i))
    }

    // 陪衬在两头之间等距抽，纯为构图，不含任何「热度 / 推荐」的意思。
    let midPool = capN < count - capN ? Array(ranked[capN..<(count - capN)]) : []
    if capM > 0 && !midPool.isEmpty {
      for i in 0..<capM {
        let raw = (Double(i) + 0.5) * Double(midPool.count) / Double(capM)
        let idx = min(max(Int(raw.rounded()) - 1, 0), midPool.count - 1)
        picks.append(SectorPick(stat: midPool[idx], side: .filler, slot: i, rank: capN + idx))
      }
    }

    for i in 0..<capN {
      picks.append(SectorPick(stat: ranked[count - capN + i], side: .weak, slot: i, rank: count - capN + i))
    }

    let maxAbs = max(1e-6, picks.map { abs($0.stat.pct) }.max() ?? 0)
    let up = ranked.reduce(into: 0) { acc, s in if s.pct >= 0 { acc += 1 } }
    return SectorSelection(picks: picks, total: count, maxAbsPct: maxAbs,
                           upCount: up, downCount: count - up)
  }

  /// 按市场默认档选。
  public static func select(_ stats: [SectorStat], market: SectorMarket) -> SectorSelection {
    let d = defaults(market)
    return select(stats, n: d.n, m: d.m)
  }
}
