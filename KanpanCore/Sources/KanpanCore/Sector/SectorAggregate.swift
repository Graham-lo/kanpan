import Foundation

/// 一个品种在板块聚合里用到的那点行情。归类是静态的，这一半是实时的。
public struct SectorQuote: Sendable, Equatable {
  /// base 代号，大写。
  public let base: String
  /// 24h 涨跌幅，百分数（-3.42 就是跌 3.42%），不是小数。
  public let pct: Double
  /// 24h 成交额（计价币）。
  public let quoteVolume: Double
  public let price: Double
  public init(base: String, pct: Double, quoteVolume: Double, price: Double) {
    self.base = base
    self.pct = pct
    self.quoteVolume = quoteVolume
    self.price = price
  }
}

/// 板块涨跌幅的三种口径。默认中位数——它抗得住单只暴涨暴跌。
public enum SectorBasis: String, Codable, Sendable, CaseIterable {
  case median, mean, volumeWeighted
  public var title: String {
    switch self {
    case .median: return "中位数"
    case .mean: return "均值"
    case .volumeWeighted: return "成交额加权"
    }
  }
}

/// 一个板块此刻的统计。`pct` 已经按选定口径聚好。
public struct SectorStat: Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let market: SectorMarket
  /// 按 basis 聚合后的涨跌幅，百分数。
  public let pct: Double
  /// 有行情的成员数（没行情的成员不参与，也不计数）。
  public let memberCount: Int
  /// 成员成交额之和。
  public let quoteVolume: Double
  /// 兜底桶。兜底桶在气泡场的排序与归一之前就被摘掉，只活在「全部板块」里。
  public let isFallback: Bool
  public init(id: String, name: String, market: SectorMarket,
              pct: Double, memberCount: Int, quoteVolume: Double, isFallback: Bool) {
    self.id = id
    self.name = name
    self.market = market
    self.pct = pct
    self.memberCount = memberCount
    self.quoteVolume = quoteVolume
    self.isFallback = isFallback
  }
}

/// 没被任何板块收录的品种，按交易所自带 tag 兜底聚出来的桶。
///
/// 静态表管不着它们（TSV 里那 48 个 `NONE` 就是这一拨）：tag 是交易所给的，
/// 会随合约上下架变，所以由调用方在运行时组好了传进来。
public struct SectorFallbackBucket: Sendable, Equatable {
  /// 约定形如 `"fb-<tag>"`，跟静态板块 id 天然不撞。
  public let id: String
  public let name: String
  public let members: [String]
  public init(id: String, name: String, members: [String]) {
    self.id = id
    self.name = name
    self.members = members
  }
}

/// 把静态归类 × 实时行情聚成板块统计。
public enum SectorAggregator {
  /// - Parameters:
  ///   - quotes: 以**大写 base** 为键。
  ///   - fallbackBuckets: 兜底桶，聚出来的 `isFallback = true`。
  /// - Returns: 顺序 = 目录顺序在前、兜底桶按传入顺序在后。
  ///            **一个成员都没行情的板块直接不出现**（不是给个 0）。
  public static func stats(market: SectorMarket,
                           quotes: [String: SectorQuote],
                           basis: SectorBasis,
                           fallbackBuckets: [SectorFallbackBucket]) -> [SectorStat] {
    var out: [SectorStat] = []
    out.reserveCapacity(SectorCatalog.sectors(market).count + fallbackBuckets.count)
    for def in SectorCatalog.sectors(market) {
      if let s = stat(id: def.id, name: def.name, market: market,
                      members: def.members, quotes: quotes, basis: basis, isFallback: false) {
        out.append(s)
      }
    }
    for b in fallbackBuckets {
      if let s = stat(id: b.id, name: b.name, market: market,
                      members: b.members, quotes: quotes, basis: basis, isFallback: true) {
        out.append(s)
      }
    }
    return out
  }

  /// 单个桶的聚合。成员按 base 去重，没行情的跳过。
  private static func stat(id: String, name: String, market: SectorMarket,
                           members: [String], quotes: [String: SectorQuote],
                           basis: SectorBasis, isFallback: Bool) -> SectorStat? {
    var pcts: [Double] = []
    var vols: [Double] = []
    var seen = Set<String>()
    pcts.reserveCapacity(members.count)
    vols.reserveCapacity(members.count)
    for raw in members {
      let base = raw.uppercased()
      guard seen.insert(base).inserted, let q = quotes[base] else { continue }
      guard q.pct.isFinite else { continue }
      pcts.append(q.pct)
      vols.append(q.quoteVolume.isFinite ? q.quoteVolume : 0)
    }
    guard !pcts.isEmpty else { return nil }
    let volume = vols.reduce(0, +)
    return SectorStat(id: id, name: name, market: market,
                      pct: aggregate(pcts: pcts, vols: vols, basis: basis),
                      memberCount: pcts.count, quoteVolume: volume, isFallback: isFallback)
  }

  /// 三种口径的算术。`pcts` 非空。
  static func aggregate(pcts: [Double], vols: [Double], basis: SectorBasis) -> Double {
    switch basis {
    case .median:
      return median(pcts)
    case .mean:
      return pcts.reduce(0, +) / Double(pcts.count)
    case .volumeWeighted:
      let total = vols.reduce(0, +)
      // 全场零成交额时加权没有意义，退回均值，免得出一个 NaN 把归一带崩。
      guard total > 0 else { return pcts.reduce(0, +) / Double(pcts.count) }
      var acc = 0.0
      for (p, v) in zip(pcts, vols) { acc += p * v }
      return acc / total
    }
  }

  /// 偶数个取中间两个的平均——跟分类表 README 的口径一致。
  static func median(_ values: [Double]) -> Double {
    precondition(!values.isEmpty)
    let s = values.sorted()
    let n = s.count
    if n % 2 == 1 { return s[n / 2] }
    return (s[n / 2 - 1] + s[n / 2]) / 2
  }
}
