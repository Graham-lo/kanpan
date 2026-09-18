import Foundation
import Testing

@testable import KanpanCore

/// 板块口径层：目录、三种聚合、上场名单。
///
/// 对数材料是 `Fixtures/sectors.json`——2026-09-18 币安真实快照，
/// 从定版原型 `proto2/data.json` 抽出来的。原型侧的 median/mean/vw 存的是
/// 四舍五入到 2 位小数的值，所以容差取 0.0051（半个末位再放一点点）。
@Suite("板块口径")
struct SectorTests {
  static let tol = 0.0051

  // MARK: - 夹具

  struct Snapshot: Sendable {
    struct Row: Sendable {
      var id: String, name: String, n: Int
      var median: Double, mean: Double, vw: Double, vol: Double, fallback: Bool
    }
    var quotes: [String: SectorQuote]
    var rows: [Row]
    var buckets: [SectorFallbackBucket]
  }

  static func snapshot(_ market: String) throws -> Snapshot {
    let root = try Fixture.dict("sectors")
    guard let markets = root["markets"] as? [String: Any],
          let m = markets[market] as? [String: Any],
          let rawQuotes = m["quotes"] as? [String: Any],
          let rawRows = m["sectors"] as? [[String: Any]],
          let rawBuckets = m["fallbackBuckets"] as? [[String: Any]]
    else { throw Fixture.Failure.shape("sectors/\(market)") }

    var quotes: [String: SectorQuote] = [:]
    for (base, any) in rawQuotes {
      guard let q = any as? [String: Any] else { continue }
      quotes[base] = SectorQuote(base: base,
                                 pct: q["chg"] as? Double ?? 0,
                                 quoteVolume: q["vol"] as? Double ?? 0,
                                 price: q["price"] as? Double ?? 0)
    }
    let rows = rawRows.map {
      Snapshot.Row(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "",
                   n: $0["n"] as? Int ?? 0, median: $0["median"] as? Double ?? 0,
                   mean: $0["mean"] as? Double ?? 0, vw: $0["vw"] as? Double ?? 0,
                   vol: $0["vol"] as? Double ?? 0, fallback: $0["fallback"] as? Bool ?? false)
    }
    let buckets = rawBuckets.map {
      SectorFallbackBucket(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "",
                           members: $0["members"] as? [String] ?? [])
    }
    return Snapshot(quotes: quotes, rows: rows, buckets: buckets)
  }

  /// 造一批只带 pct 的假统计，用来钉选取算法的边界。
  static func fakes(_ pcts: [Double], fallback: [Double] = []) -> [SectorStat] {
    var out = pcts.enumerated().map { i, p in
      SectorStat(id: "s\(i)", name: "板块\(i)", market: .crypto, pct: p,
                 memberCount: 1, quoteVolume: 1, isFallback: false)
    }
    out += fallback.enumerated().map { i, p in
      SectorStat(id: "fb-\(i)", name: "兜底\(i)", market: .crypto, pct: p,
                 memberCount: 1, quoteVolume: 1, isFallback: true)
    }
    return out
  }

  // MARK: - 1. 目录完整性

  @Test func cryptoHasExactlyTheTwentyFourDefinedIDs() {
    let want: Set<String> = [
      "btc-eco", "eth-eco", "sol-eco", "l1", "l2", "zk", "defi-blue", "perp-dex",
      "stable-yield", "rwa", "ai", "depin", "storage-data", "oracle-bridge", "privacy",
      "pow", "meme", "meme-cn", "gamefi", "nft-social", "metaverse", "payment",
      "fan-token", "desci",
    ]
    let got = Set(SectorCatalog.sectors(.crypto).map(\.id))
    #expect(got == want, "加密板块 id 只能是定义文件里那 24 个，不得自创")
    #expect(SectorCatalog.sectors(.crypto).count == 24)
  }

  @Test func usHasTheTenMediumSegments() {
    let want = ["gpu", "mem", "equip", "optic", "hyper", "neo", "server", "edge", "robot", "app"]
    #expect(SectorCatalog.sectors(.us).map(\.id) == want)
  }

  @Test func catalogIsCryptoThenUSAndIDsAreUnique() {
    let all = SectorCatalog.all
    #expect(all.count == 34)
    #expect(all.prefix(24).allSatisfy { $0.market == .crypto })
    #expect(all.suffix(10).allSatisfy { $0.market == .us })
    #expect(Set(all.map(\.id)).count == all.count)
    for d in all { #expect(SectorCatalog.sector(id: d.id) == d) }
    #expect(SectorCatalog.sector(id: "silicon") == nil, "粗段不是板块，不许进目录")
  }

  @Test func membersAreUppercaseAndDeduped() {
    for d in SectorCatalog.all {
      #expect(!d.members.isEmpty, "\(d.id) 没有成员")
      #expect(Set(d.members).count == d.members.count, "\(d.id) 成员有重复")
      for b in d.members {
        #expect(b == b.uppercased(), "\(d.id) 的 \(b) 不是全大写")
        #expect(!b.isEmpty)
      }
      #expect(!d.name.isEmpty)
    }
  }

  @Test func crossListingIsAllowedAndReverseLookupWorks() {
    // SOL 同时是 Solana 生态和公链；高通同时在算力芯片和端侧 AI。
    #expect(Set(SectorCatalog.sectors(for: "SOL", market: .crypto).map(\.id)) == ["sol-eco", "l1"])
    #expect(Set(SectorCatalog.sectors(for: "qcom", market: .us).map(\.id)) == ["gpu", "edge"])
    #expect(SectorCatalog.sectors(for: "BTC", market: .crypto).map(\.id) == ["btc-eco", "pow"])
    // 一个币最多 3 个板块。
    var counts: [String: Int] = [:]
    for d in SectorCatalog.sectors(.crypto) { for b in d.members { counts[b, default: 0] += 1 } }
    #expect((counts.values.max() ?? 0) <= 3)
    // 反查不到就是空，不许崩。
    #expect(SectorCatalog.sectors(for: "ANKR", market: .crypto).isEmpty, "TSV 标 NONE 的币不进任何板块")
    #expect(SectorCatalog.sectors(for: "SOL", market: .us).isEmpty, "反查要认市场")
  }

  @Test func excludedTickersNeverMadeItIntoTheUSTable() {
    // 杠杆/反向 ETP、宽基与行业 ETF、判为非 AI 的，一个都不许在表里。
    let banned = [
      "SOXL", "SOXS", "TQQQ", "SQQQ", "NVDL", "UVXY", "CSOPSAMSUNG2L",  // ETP
      "QQQ", "SPY", "SMH", "IWM", "BITO", "DRAM", "BOT",                // ETF
      "STRC",                                                            // OTHER
      "COIN", "MSTR", "TSM_X", "NFLX", "LLY", "UBER", "CRWD", "PYPL",    // 非 AI
      "SKHY", "HK0700", "PAYP",                                          // DEDUP 的旧代号
    ]
    let inTable = Set(SectorCatalog.sectors(.us).flatMap(\.members))
    for b in banned { #expect(!inTable.contains(b), "\(b) 不该出现在美股板块表里") }
    #expect(inTable.count == 84, "美股 84 只进 AI 板块")
    // DEDUP 归并后的正名在表里。
    #expect(inTable.contains("SKHYNIX") && inTable.contains("TENCENT"))
  }

  @Test func everyUSTickerHasAChineseName() {
    for b in Set(SectorCatalog.sectors(.us).flatMap(\.members)) {
      #expect(SectorCatalog.chineseName(base: b) != nil, "\(b) 缺中文名")
    }
    #expect(SectorCatalog.chineseName(base: "nvda") == "英伟达")
    #expect(SectorCatalog.chineseName(base: "SOL") == nil)
  }

  @Test func shortNamesExistForEverySector() {
    for d in SectorCatalog.all {
      #expect(!SectorCatalog.shortName(d.id).isEmpty)
    }
    #expect(SectorCatalog.shortName("l1") == "公链")
    #expect(SectorCatalog.shortName("不存在") == "不存在")
  }

  // MARK: - 2. 三种聚合口径拿快照对数

  @Test(arguments: [SectorMarket.crypto, .us])
  func aggregatesMatchTheSnapshot(market: SectorMarket) throws {
    let snap = try Self.snapshot(market == .crypto ? "crypto" : "us")
    let want = Dictionary(uniqueKeysWithValues: snap.rows.map { ($0.id, $0) })

    for (basis, pick) in [(SectorBasis.median, \Snapshot.Row.median),
                          (.mean, \Snapshot.Row.mean),
                          (.volumeWeighted, \Snapshot.Row.vw)] {
      let got = SectorAggregator.stats(market: market, quotes: snap.quotes,
                                       basis: basis, fallbackBuckets: snap.buckets)
      for s in got {
        guard let w = want[s.id] else {
          // desci 只有 BIO 一个成员，原型那版把它丢进了 misc 兜底桶，快照里没有这一段。
          #expect(s.id == "desci", "快照里没有 \(s.id)")
          continue
        }
        #expect(abs(s.pct - w[keyPath: pick]) < Self.tol,
                "\(basis) \(s.id): 算出 \(s.pct)，快照 \(w[keyPath: pick])")
        #expect(s.memberCount == w.n, "\(s.id) 成员数对不上")
        #expect(abs(s.quoteVolume - w.vol) <= abs(w.vol) * 1e-9 + 1e-6, "\(s.id) 成交额对不上")
        #expect(s.isFallback == w.fallback)
      }
    }
  }

  @Test func snapshotCoverageIsComplete() throws {
    let snap = try Self.snapshot("crypto")
    let got = SectorAggregator.stats(market: .crypto, quotes: snap.quotes,
                                     basis: .median, fallbackBuckets: snap.buckets)
    // 24 个板块全有行情 + 4 个兜底桶。
    #expect(got.filter { !$0.isFallback }.count == 24)
    #expect(got.filter(\.isFallback).count == 4)
    // 目录顺序在前、兜底桶在后。
    #expect(got.firstIndex(where: \.isFallback) == 24)
    let us = try Self.snapshot("us")
    #expect(SectorAggregator.stats(market: .us, quotes: us.quotes,
                                   basis: .mean, fallbackBuckets: []).count == 10)
  }

  @Test func medianMeanAndWeightingBehaveOnHandPickedNumbers() {
    #expect(SectorAggregator.median([3, 1, 2]) == 2)
    #expect(SectorAggregator.median([4, 1, 2, 3]) == 2.5)
    #expect(SectorAggregator.median([7]) == 7)
    // 中位数抗单只暴涨：均值被 100 拉飞，中位数不动。
    let pcts = [1.0, 2.0, 3.0, 100.0]
    #expect(SectorAggregator.aggregate(pcts: pcts, vols: [1, 1, 1, 1], basis: .median) == 2.5)
    #expect(SectorAggregator.aggregate(pcts: pcts, vols: [1, 1, 1, 1], basis: .mean) == 26.5)
    // 成交额加权：额全压在 100 那只上，结果贴近它。
    #expect(SectorAggregator.aggregate(pcts: pcts, vols: [0, 0, 0, 1], basis: .volumeWeighted) == 100)
    // 零成交额时退回均值，不许出 NaN。
    #expect(SectorAggregator.aggregate(pcts: pcts, vols: [0, 0, 0, 0], basis: .volumeWeighted) == 26.5)
  }

  @Test func sectorsWithoutAnyQuoteDisappearInsteadOfShowingZero() {
    let quotes = ["SOL": SectorQuote(base: "SOL", pct: 2, quoteVolume: 10, price: 1)]
    let got = SectorAggregator.stats(market: .crypto, quotes: quotes, basis: .median, fallbackBuckets: [])
    #expect(Set(got.map(\.id)) == ["sol-eco", "l1"])
    #expect(got.allSatisfy { $0.memberCount == 1 && $0.pct == 2 })
    #expect(SectorAggregator.stats(market: .crypto, quotes: [:], basis: .median, fallbackBuckets: []).isEmpty)
  }

  @Test func duplicateMembersAndNonFiniteQuotesAreDropped() {
    // 故意用目录里不存在的代号，免得连带聚出真板块来。
    let quotes = ["ZZA": SectorQuote(base: "ZZA", pct: 5, quoteVolume: 1, price: 1),
                  "ZZB": SectorQuote(base: "ZZB", pct: .nan, quoteVolume: 1, price: 1)]
    let bucket = SectorFallbackBucket(id: "fb-x", name: "其他", members: ["ZZA", "zza", "ZZB", "ZZC"])
    let got = SectorAggregator.stats(market: .crypto, quotes: quotes, basis: .mean, fallbackBuckets: [bucket])
    #expect(got == [SectorStat(id: "fb-x", name: "其他", market: .crypto, pct: 5,
                               memberCount: 1, quoteVolume: 1, isFallback: true)])
  }

  // MARK: - 3. 选取算法

  @Test func defaultsPerMarket() {
    #expect(SectorSelector.defaults(.crypto) == (5, 3))
    #expect(SectorSelector.defaults(.us) == (3, 2))
  }

  @Test func fallbackBucketsAreDroppedBeforeRankingAndNormalising() {
    // 兜底桶的 pct 是全场最极端的，如果没被摘掉，它会既上场又把尺子撑大。
    let stats = Self.fakes([3, 1, -2], fallback: [99, -99])
    let sel = SectorSelector.select(stats, n: 5, m: 3)
    #expect(sel.total == 3)
    #expect(sel.picks.allSatisfy { !$0.stat.isFallback })
    #expect(sel.maxAbsPct == 3)
    #expect(sel.upCount == 2 && sel.downCount == 1)
  }

  @Test func clampsNAndMOnASmallBoard() {
    // 10 段、默认加密档 (5,3)：N=min(5,5)=5，M=min(3, 10-10)=0。
    let sel = SectorSelector.select(Self.fakes((0..<10).map { Double(10 - $0) }), n: 5, m: 3)
    #expect(sel.picks.count == 10)
    #expect(sel.picks.filter { $0.side == .filler }.isEmpty)
    #expect(sel.picks.filter { $0.side == .strong }.count == 5)
    #expect(sel.picks.filter { $0.side == .weak }.count == 5)
  }

  @Test func ordersPicksStrongThenFillerThenWeak() {
    // 13 段，pct = 13…1；N=5，M=min(3, 3)=3，midPool = 名次 5…7。
    let sel = SectorSelector.select(Self.fakes((0..<13).map { Double(13 - $0) }), n: 5, m: 3)
    #expect(sel.total == 13)
    #expect(sel.picks.map(\.side) == Array(repeating: .strong, count: 5)
            + Array(repeating: .filler, count: 3) + Array(repeating: .weak, count: 5))
    #expect(sel.picks.map(\.slot) == [0, 1, 2, 3, 4, 0, 1, 2, 0, 1, 2, 3, 4])
    // 等距抽：midPool.count=3、M=3 → idx = round(0.5)-1, round(1.5)-1, round(2.5)-1 = 0,1,2
    #expect(sel.picks.map(\.rank) == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
    #expect(sel.maxAbsPct == 13)
    #expect(sel.upCount == 13 && sel.downCount == 0)
  }

  @Test func fillerIndicesAreEvenlySpaced() {
    // 30 段、N=5 → midPool 有 20 个（名次 5…24）、M=3。
    // idx = clamp(round((i+.5)*20/3)-1, 0, 19) = round(3.33)-1, round(10)-1, round(16.67)-1 = 2, 9, 16
    let sel = SectorSelector.select(Self.fakes((0..<30).map { Double(30 - $0) }), n: 5, m: 3)
    let fillers = sel.picks.filter { $0.side == .filler }
    #expect(fillers.map(\.rank) == [5 + 2, 5 + 9, 5 + 16])
    #expect(fillers.map(\.slot) == [0, 1, 2])
    // 半径归一只看上场那几颗，全场最大绝对值恰好就是第一名。
    #expect(sel.maxAbsPct == 30)
  }

  @Test func halfUpRoundingMatchesTheJavaScript() {
    // Math.round 是「四舍五入向上」，Swift 的 rounded() 在正数上等价。
    // midPool.count=4、M=8 → raw = .25,.75,1.25,… idx = round(raw)-1 再夹到 0…3
    let sel = SectorSelector.select(Self.fakes((0..<14).map { Double(14 - $0) }), n: 5, m: 8)
    // N=min(5,7)=5，M=min(8, 14-10)=4，midPool.count=4 → idx = round(.5*4/4)... 逐个算
    let fillers = sel.picks.filter { $0.side == .filler }
    #expect(fillers.count == 4)
    #expect(fillers.map(\.rank) == [5 + 0, 5 + 1, 5 + 2, 5 + 3])
  }

  @Test func handlesEmptyAndTinyBoards() {
    let none = SectorSelector.select([], n: 5, m: 3)
    #expect(none.picks.isEmpty && none.total == 0 && none.maxAbsPct == 1e-6)
    #expect(none.upCount == 0 && none.downCount == 0)
    #expect(none == SectorSelection.empty)

    // 1 段：N=0，midPool 是全部，M=min(3,1)=1 → 唯一那段当陪衬上场。
    let one = SectorSelector.select(Self.fakes([2]), n: 5, m: 3)
    #expect(one.picks.count == 1)
    #expect(one.picks[0].side == .filler && one.picks[0].rank == 0 && one.picks[0].slot == 0)
    #expect(one.maxAbsPct == 2)

    // 2 段：N=1，两头各一颗，midPool 空，一个陪衬也排不出来。
    let two = SectorSelector.select(Self.fakes([2, -4]), n: 5, m: 3)
    #expect(two.picks.map(\.side) == [.strong, .weak])
    #expect(two.picks.map(\.rank) == [0, 1])
    #expect(two.maxAbsPct == 4)

    // M=0：只有两头。
    let noFill = SectorSelector.select(Self.fakes((0..<20).map { Double(20 - $0) }), n: 5, m: 0)
    #expect(noFill.picks.count == 10)
    #expect(noFill.picks.filter { $0.side == .filler }.isEmpty)

    // 极小的涨跌幅也不能把分母压成 0。
    let flat = SectorSelector.select(Self.fakes([0, 0, 0, 0]), n: 1, m: 1)
    #expect(flat.maxAbsPct == 1e-6)
    #expect(flat.upCount == 4 && flat.downCount == 0)
  }

  // MARK: - 4. 全场同号时球身仍分两色

  @Test func isUpSideSplitsTheBoardEvenWhenEveryoneIsGreen() throws {
    let snap = try Self.snapshot("crypto")
    let stats = SectorAggregator.stats(market: .crypto, quotes: snap.quotes,
                                       basis: .median, fallbackBuckets: snap.buckets)
    // 2026-09-18 这天全线飘绿：非兜底的板块中位数没有一个是负的。
    #expect(stats.filter { !$0.isFallback }.allSatisfy { $0.pct > 0 })

    let sel = SectorSelector.select(stats, market: .crypto)
    #expect(sel.upCount == sel.total && sel.downCount == 0, "这份快照就是全场同号")

    let up = sel.picks.filter { $0.isUpSide(total: sel.total) }
    let down = sel.picks.filter { !$0.isUpSide(total: sel.total) }
    #expect(!up.isEmpty && !down.isEmpty, "全场同号也必须分出强弱两色，否则整屏一片绿")
    #expect(down.count >= 5, "弱端 5 颗一颗都不能被染成强端色")
    // 强端恒 true、弱端恒 false，跟涨跌正负无关。
    #expect(sel.picks.filter { $0.side == .strong }.allSatisfy { $0.isUpSide(total: sel.total) })
    #expect(sel.picks.filter { $0.side == .weak }.allSatisfy { !$0.isUpSide(total: sel.total) })
  }

  @Test func fillerTakesItsColourFromWhichHalfItRanksIn() {
    // 21 段：N=5，midPool 名次 5…15（11 个），M=3 → idx = round(1.83)-1, round(5.5)-1, round(9.17)-1 = 1, 5, 8
    let sel = SectorSelector.select(Self.fakes((0..<21).map { Double(21 - $0) }), n: 5, m: 3)
    let fillers = sel.picks.filter { $0.side == .filler }
    #expect(fillers.map(\.rank) == [6, 10, 13])
    // total=21，分界线 10.5：名次 6、10 算强端那半，13 算弱端那半。
    #expect(fillers.map { $0.isUpSide(total: sel.total) } == [true, true, false])
    // 全跌的一屏同理，强端那 5 颗照样是「强端色」。
    let allRed = SectorSelector.select(Self.fakes((0..<21).map { -Double($0 + 1) }), n: 5, m: 3)
    #expect(allRed.upCount == 0 && allRed.downCount == 21)
    #expect(allRed.picks.filter { $0.side == .strong }.allSatisfy { $0.isUpSide(total: 21) })
  }
}
