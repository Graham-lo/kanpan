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
  /// 参与排序的板块总数（**不含**兜底桶、不含上不了场的）。
  public let total: Int
  /// 半径归一的分母：**全场** `|pct|` 的最大值，下限 `0.01`。
  ///
  /// 最大的那颗球就是幅度最大的板块——定版原型就是这个读法，不换。
  /// 分位数分母试过一版，它会把领涨那一头前一两颗截成一样大，恰好在最需要认龙头的
  /// 那端把尺寸这条通道废掉。尺子的稳定交给调用方那道迟滞（差不到 20% 就沿用旧值）。
  ///
  /// 分母取的是**全场**（含没上场的），不是上场那几颗：否则换一次档、多进一颗球，
  /// 整屏尺寸就跟着重算一遍。
  public let scalePct: Double
  /// `total` 里 pct >= 0 的个数。
  public let upCount: Int
  public let downCount: Int
  public init(picks: [SectorPick], total: Int, scalePct: Double, upCount: Int, downCount: Int) {
    self.picks = picks
    self.total = total
    self.scalePct = scalePct
    self.upCount = upCount
    self.downCount = downCount
  }

  /// 归一到 `0…1`：`|pct| / scalePct`，**超过分母的截到 1**。
  /// 球最大就长这么大，数字照真值显示。
  public func norm(_ pct: Double) -> Double {
    guard pct.isFinite else { return 0 }
    return min(1, abs(pct) / max(SectorSelector.minScalePct, scalePct))
  }

  public static let empty = SectorSelection(picks: [], total: 0,
                                            scalePct: SectorSelector.minScalePct,
                                            upCount: 0, downCount: 0)
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

  /// 面积分母的下限。全场纹丝不动的时候也得有个尺子，否则半径要除以零。
  public static let minScalePct = 0.01

  /// - Parameters:
  ///   - stats: 上不了场的（`isFallback`，或有行情成员 < 3）在排序和归一**之前**
  ///     就被摘掉——它们只活在「全部板块」里。
  ///   - n: 两头各取几颗（会被 `floor(总数/2)` 夹住）。
  ///   - m: 中间取几颗陪衬（会被剩下的颗数夹住）。
  ///   - previousScale: 上一次算出来的 `scalePct`。新值跟它差不到 20% 就沿用旧值，
  ///     免得球场每来一批行情就整体呼吸一次。
  public static func select(_ stats: [SectorStat], n: Int, m: Int,
                            previousScale: Double? = nil) -> SectorSelection {
    // `pct` 非数的行直接不上场（审查 B-T20）：NaN 参与 `>` 比较会让排序谓词不再是严格弱序，
    // 排出来的名次就没定义了；infinite 还会把面积分母（`scalePct`）拉到无穷，整屏球缩成点。
    let ranked = stats.filter { !$0.isFallback && $0.eligible && $0.pct.isFinite }
      // 并列按 id 排。不这么钉，两个 pct 相同的板块会在每次刷新里互换位置。
      .sorted { $0.pct == $1.pct ? $0.id < $1.id : $0.pct > $1.pct }
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

    let scale = scalePct(ranked.map { abs($0.pct) }, previous: previousScale)
    let up = ranked.reduce(into: 0) { acc, s in if s.pct >= 0 { acc += 1 } }
    return SectorSelection(picks: picks, total: count, scalePct: scale,
                           upCount: up, downCount: count - up)
  }

  /// 按市场默认档选。
  public static func select(_ stats: [SectorStat], market: SectorMarket,
                            previousScale: Double? = nil) -> SectorSelection {
    let d = defaults(market)
    return select(stats, n: d.n, m: d.m, previousScale: previousScale)
  }

  /// 面积分母：全场 `|pct|` 的最大值，不低于 `minScalePct`；跟上一次差不到 20%
  /// 就原样沿用上一次的——行情一跳就整屏呼吸一次，比尺子偏一点难看得多。
  static func scalePct(_ absPcts: [Double], previous: Double?) -> Double {
    let raw = max(minScalePct, absPcts.filter(\.isFinite).max() ?? minScalePct)
    if let old = previous, old.isFinite, old >= minScalePct, abs(raw - old) < 0.2 * old {
      return old
    }
    return raw
  }
}
