import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 5 日那一档覆盖不够的板块（有 5 根日线的成员不到有行情成员的八成）不算数：
/// 照样列着、点得进去，但不拿那几只的中位数和覆盖足的板块一起排。
@Suite("板块 5 日 · 覆盖不够不算数")
struct SectorCoverageTests {
  private let def = SectorCatalog.sectors(.crypto).first { Set($0.members.map { $0.uppercased() }).count >= 10 }!
  private var bases: [String] { Array(NSOrderedSet(array: def.members.map { $0.uppercased() })) as! [String] }

  private func quotes() -> [String: SectorQuote] {
    Dictionary(uniqueKeysWithValues: bases.map {
      ($0, SectorQuote(base: $0, pct: 1, quoteVolume: 1_000, price: 100))
    })
  }

  private func history(coveredCount: Int, close: Double) -> SectorHistory {
    SectorHistory(asof: "2026-09-18",
                  closes: Dictionary(uniqueKeysWithValues: bases.prefix(coveredCount).map { ($0, SectorCloses(c5: close)) }))
  }

  @Test("只有一半有 5 日收盘：板块照列，强弱是「没有」，成员再多也排在每个算得出数的板块后面")
  func thinCoverageCarriesNoValue() throws {
    // 有收盘的那一半五天涨了 900%：原来它们的中位数就是整个板块的「5 日强弱」，
    // 而且这一半已经够 `minEligibleMembers` 只，照样和覆盖足的板块一起排。
    let half = bases.count / 2
    #expect(half >= SectorAggregator.minEligibleMembers)
    let stats = SectorAggregator.stats(market: .crypto, quotes: quotes(), fallbackBuckets: [],
                                       window: .d5, history: history(coveredCount: half, close: 10))
    let stat = try #require(stats.first { $0.id == def.id })
    #expect(stat.pct.isNaN)
    #expect(stat.memberCount == half)           // 成员数照实记，和网页版同一口径
    #expect(!SectorSubtitle.counts(stat))
    #expect(SectorSubtitle.row(stat) == "")     // 不写「0/5 跑赢大盘」
    #expect(SectorPctTone.of(stat.pct) == .neutral)
    // 排在所有算得出强弱的板块后面。
    let sorted = SectorBoardOrder.sorted(stats)
    let index = try #require(sorted.firstIndex { $0.id == def.id })
    let counted = sorted.filter { SectorSubtitle.counts($0) }.count
    #expect(index >= counted)
  }

  @Test("覆盖够了照常算")
  func fullCoverageStillCounts() throws {
    let stats = SectorAggregator.stats(market: .crypto, quotes: quotes(), fallbackBuckets: [],
                                       window: .d5, history: history(coveredCount: def.members.count, close: 50))
    let stat = try #require(stats.first { $0.id == def.id })
    #expect(abs(stat.pct - 100) < 1e-9)
    #expect(stat.memberCount == bases.count)
    #expect(SectorSubtitle.counts(stat))
  }
}
