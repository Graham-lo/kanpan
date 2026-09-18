import Foundation
import Testing

@testable import KanpanCore

/// 板块口径层：目录、中位数聚合与它的旁证（广度 / 前沿 / 删一）、上场名单。
///
/// 对数材料是 `Fixtures/sectors.json`——2026-09-18 币安真实快照，
/// 从定版原型 `proto2/data.json` 抽出来的。原型侧的 median 存的是
/// 四舍五入到 2 位小数的值，所以容差取 0.0051（半个末位再放一点点）。
///
/// 归类一改，对得上数的就只剩没动过的那些段：2026-09-18 晚美股这边重分了几刀
/// （「软件」拆出「模型与应用」、「电力」拆出「服务器与电力」，MRVL 与 CRDO 归光通信、
/// TSM 归设备与材料，一度分出的「硬件」当日又按用户要求并回「算力芯片」），被动过那几段
/// 的行是拿同一批 quotes 按同样的公式重算后写回夹具的，其余各段和快照里一个字都没变。
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
  ///
  /// 默认全都上得了场（`eligible`）：这一组用例要钉的是排序、陪衬与归一，
  /// 「成员太少不上场」另有专门的用例。
  static func fakes(_ pcts: [Double], fallback: [Double] = [],
                    ineligible: [Double] = []) -> [SectorStat] {
    var out = pcts.enumerated().map { i, p in
      SectorStat(id: "s\(i)", name: "板块\(i)", market: .crypto, pct: p,
                 memberCount: 3, quoteVolume: 1, isFallback: false)
    }
    out += fallback.enumerated().map { i, p in
      SectorStat(id: "fb-\(i)", name: "兜底\(i)", market: .crypto, pct: p,
                 memberCount: 3, quoteVolume: 1, isFallback: true)
    }
    out += ineligible.enumerated().map { i, p in
      SectorStat(id: "tiny\(i)", name: "小板块\(i)", market: .crypto, pct: p,
                 memberCount: 1, quoteVolume: 1, isFallback: false, eligible: false)
    }
    return out
  }

  /// 只给这几个 base 行情，其余品种当没行情——市场池就是它们自己，
  /// 于是「相对池基准」在用例里算得出来。
  static func aggregate(_ pcts: [String: Double]) -> [SectorStat] {
    var quotes: [String: SectorQuote] = [:]
    for (base, pct) in pcts {
      quotes[base] = SectorQuote(base: base, pct: pct, quoteVolume: 1, price: 1)
    }
    return SectorAggregator.stats(market: .crypto, quotes: quotes, fallbackBuckets: [])
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

  /// 顺序也是被钉住的：产业链从芯片往上走——算力芯片、存储、制造与封装、
  /// 光、云、算力、机器、供电，然后才是端侧、机器人和跑在上面的软件与模型。
  /// 「软件」是应用层的下一级，所以它排在「模型与应用」前面。
  @Test func usHasTheTwelveMediumSegments() {
    let want = ["gpu", "mem", "equip", "optic", "hyper", "neo", "server",
                "power", "edge", "robot", "software", "app"]
    #expect(SectorCatalog.sectors(.us).map(\.id) == want)
    // 「硬件」是 2026-09-18 多分出来的一格，同日按用户要求并回「算力芯片」。
    #expect(SectorCatalog.sector(id: "hardware") == nil)
    #expect(SectorCatalog.sector(id: "gpu")?.members.count == 10)
    for b in ["ARM", "AVGO", "ALAB"] {
      #expect(SectorCatalog.sector(id: "gpu")?.members.contains(b) == true, "\(b) 要在算力芯片里")
    }
  }

  @Test func catalogIsCryptoThenUSAndIDsAreUnique() {
    let all = SectorCatalog.all
    #expect(all.count == 36)
    #expect(all.prefix(24).allSatisfy { $0.market == .crypto })
    #expect(all.suffix(12).allSatisfy { $0.market == .us })
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
    // 板块读的是正股强弱，混一只两倍做多进去就能把中位数拽歪。
    //
    // 2026-09-18 放行了两个：`CRWD` 进「软件」（原来按 `NON_AI` 剔的，
    // 但软件板块要的就是这批卖订阅的公司），`SKHY` 进「存储」——它不是
    // `SKHYNIX` 的旧代号，币安上是两个各自在交易的合约，正股与 ADR 各一档。
    let banned = [
      "SOXL", "SOXS", "TQQQ", "SQQQ", "NVDL", "UVXY", "CSOPSAMSUNG2L",  // ETP
      "QQQ", "SPY", "SMH", "IWM", "BITO", "DRAM", "BOT",                // ETF
      "STRC",                                                            // OTHER
      "COIN", "MSTR", "TSM_X", "NFLX", "LLY", "UBER", "PYPL",            // 非 AI
      "HK0700", "PAYP",                                                  // DEDUP 的旧代号
      "SKDD", "SKUU", "MUU", "SNXX", "MVLL", "RAM", "CSOPSKHYNIX2L",     // 存储那批杠杆/衍生品
    ]
    let inTable = Set(SectorCatalog.sectors(.us).flatMap(\.members))
    for b in banned { #expect(!inTable.contains(b), "\(b) 不该出现在美股板块表里") }
    #expect(inTable.count == 94, "美股 94 只进 AI 板块")
    // DEDUP 归并后的正名在表里；SK 海力士的正股与 ADR 两档都在存储里。
    #expect(inTable.contains("SKHYNIX") && inTable.contains("TENCENT"))
    #expect(inTable.contains("SKHY"))
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

  // MARK: - 2. 中位数口径拿快照对数

  @Test(arguments: [SectorMarket.crypto, .us])
  func aggregatesMatchTheSnapshot(market: SectorMarket) throws {
    let snap = try Self.snapshot(market == .crypto ? "crypto" : "us")
    let want = Dictionary(uniqueKeysWithValues: snap.rows.map { ($0.id, $0) })

    let got = SectorAggregator.stats(market: market, quotes: snap.quotes,
                                     fallbackBuckets: snap.buckets)
    for s in got {
      guard let w = want[s.id] else {
        // desci 只有 BIO 一个成员，原型那版把它丢进了 misc 兜底桶，快照里没有这一段。
        #expect(s.id == "desci", "快照里没有 \(s.id)")
        continue
      }
      #expect(abs(s.pct - w.median) < Self.tol, "\(s.id): 算出 \(s.pct)，快照 \(w.median)")
      #expect(s.memberCount == w.n, "\(s.id) 成员数对不上")
      #expect(abs(s.quoteVolume - w.vol) <= abs(w.vol) * 1e-9 + 1e-6, "\(s.id) 成交额对不上")
      #expect(s.isFallback == w.fallback)
    }
  }

  @Test func snapshotCoverageIsComplete() throws {
    let snap = try Self.snapshot("crypto")
    let got = SectorAggregator.stats(market: .crypto, quotes: snap.quotes,
                                     fallbackBuckets: snap.buckets)
    // 24 个板块全有行情 + 4 个兜底桶。
    #expect(got.filter { !$0.isFallback }.count == 24)
    #expect(got.filter(\.isFallback).count == 4)
    // 目录顺序在前、兜底桶在后。
    #expect(got.firstIndex(where: \.isFallback) == 24)
    let us = try Self.snapshot("us")
    // 12 个板块，一个不落——「软件」在这份快照里只有 4 家有行情（那 9 家是
    // 2026-09-18 之后才收进来的，快照没抓到），但 4 家也够上场；拆出来的「电力」5 家
    // 也够，段数是 12。
    #expect(SectorAggregator.stats(market: .us, quotes: us.quotes, fallbackBuckets: []).count == 12)
  }

  /// 板块只有中位数一个口径（2026-09-18 起均值 / 成交额加权整个撤掉）。
  @Test func medianBehavesOnHandPickedNumbers() {
    #expect(SectorAggregator.median([3, 1, 2]) == 2)
    // 偶数个取中间两个的平均。
    #expect(SectorAggregator.median([4, 1, 2, 3]) == 2.5)
    #expect(SectorAggregator.median([7]) == 7)
    // 抗单只暴涨：均值会被 100 拉到 26.5，中位数不动。
    #expect(SectorAggregator.median([1, 2, 3, 100]) == 2.5)
  }

  @Test func sectorsWithoutAnyQuoteDisappearInsteadOfShowingZero() {
    let quotes = ["SOL": SectorQuote(base: "SOL", pct: 2, quoteVolume: 10, price: 1)]
    let got = SectorAggregator.stats(market: .crypto, quotes: quotes, fallbackBuckets: [])
    #expect(Set(got.map(\.id)) == ["sol-eco", "l1"])
    #expect(got.allSatisfy { $0.memberCount == 1 && $0.pct == 2 })
    #expect(SectorAggregator.stats(market: .crypto, quotes: [:], fallbackBuckets: []).isEmpty)
  }

  @Test func duplicateMembersAndNonFiniteQuotesAreDropped() {
    // 故意用目录里不存在的代号，免得连带聚出真板块来。
    let quotes = ["ZZA": SectorQuote(base: "ZZA", pct: 5, quoteVolume: 1, price: 1),
                  "ZZB": SectorQuote(base: "ZZB", pct: .nan, quoteVolume: 1, price: 1)]
    let bucket = SectorFallbackBucket(id: "fb-x", name: "其他", members: ["ZZA", "zza", "ZZB", "ZZC"])
    let got = SectorAggregator.stats(market: .crypto, quotes: quotes, fallbackBuckets: [bucket])
    // 去重后 3 个登记成员（`zza` 是 `ZZA` 的重复），其中只有一个有能用的行情。
    #expect(got == [SectorStat(id: "fb-x", name: "其他", market: .crypto, pct: 5,
                               memberCount: 1, staticCount: 3, quoteVolume: 1, isFallback: true,
                               breadth: 0, upCount: 1, frontier: [], jackknife: nil,
                               eligible: false)])
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
    // 尺子是全场 |pct| 的最大值，兜底桶那 ±99 不算数。
    #expect(sel.scalePct == 3)
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
    #expect(sel.scalePct == 13)
    #expect(sel.upCount == 13 && sel.downCount == 0)
  }

  @Test func fillerIndicesAreEvenlySpaced() {
    // 30 段、N=5 → midPool 有 20 个（名次 5…24）、M=3。
    // idx = clamp(round((i+.5)*20/3)-1, 0, 19) = round(3.33)-1, round(10)-1, round(16.67)-1 = 2, 9, 16
    let sel = SectorSelector.select(Self.fakes((0..<30).map { Double(30 - $0) }), n: 5, m: 3)
    let fillers = sel.picks.filter { $0.side == .filler }
    #expect(fillers.map(\.rank) == [5 + 2, 5 + 9, 5 + 16])
    #expect(fillers.map(\.slot) == [0, 1, 2])
    // 尺子看的是全场 30 段（不只是上场那 13 颗）里最大的那个。
    #expect(sel.scalePct == 30)
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
    #expect(none.picks.isEmpty && none.total == 0 && none.scalePct == 0.01)
    #expect(none.upCount == 0 && none.downCount == 0)
    #expect(none == SectorSelection.empty)

    // 1 段：N=0，midPool 是全部，M=min(3,1)=1 → 唯一那段当陪衬上场。
    let one = SectorSelector.select(Self.fakes([2]), n: 5, m: 3)
    #expect(one.picks.count == 1)
    #expect(one.picks[0].side == .filler && one.picks[0].rank == 0 && one.picks[0].slot == 0)
    #expect(one.scalePct == 2)

    // 2 段：N=1，两头各一颗，midPool 空，一个陪衬也排不出来。
    let two = SectorSelector.select(Self.fakes([2, -4]), n: 5, m: 3)
    #expect(two.picks.map(\.side) == [.strong, .weak])
    #expect(two.picks.map(\.rank) == [0, 1])
    #expect(two.scalePct == 4)

    // M=0：只有两头。
    let noFill = SectorSelector.select(Self.fakes((0..<20).map { Double(20 - $0) }), n: 5, m: 0)
    #expect(noFill.picks.count == 10)
    #expect(noFill.picks.filter { $0.side == .filler }.isEmpty)

    // 极小的涨跌幅也不能把分母压成 0。
    let flat = SectorSelector.select(Self.fakes([0, 0, 0, 0]), n: 1, m: 1)
    #expect(flat.scalePct == SectorSelector.minScalePct)
    #expect(flat.upCount == 4 && flat.downCount == 0)
  }

  // MARK: - 4. 全场同号时球身仍分两色

  @Test func isUpSideSplitsTheBoardEvenWhenEveryoneIsGreen() throws {
    let snap = try Self.snapshot("crypto")
    let stats = SectorAggregator.stats(market: .crypto, quotes: snap.quotes,
                                       fallbackBuckets: snap.buckets)
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

  // MARK: - 5. 主数字之外的旁证：广度 / 前沿 / 删一

  /// 五个成员 `−2, −1, 0, +1, +300`：整体没动，一只在爆。
  /// 中位数照样是 0，把「谁在爆」交给前沿，把「这个 0 稳不稳」交给删一区间。
  @Test func oneRunawayMemberShowsInTheFrontierNotInTheMedian() throws {
    let stats = Self.aggregate(["ADA": -2, "ALGO": -1, "APT": 0, "ATOM": 1, "AVAX": 300])
    let l1 = try #require(stats.first { $0.id == "l1" })
    #expect(l1.pct == 0)
    #expect(l1.memberCount == 5)
    // 绝对上涨 2 家（+1 与 +300），跑赢池基准的只有 1 家——两个数说的不是一件事。
    #expect(l1.upCount == 2)
    #expect(l1.outperformCount == 1)
    #expect(l1.breadth == 0.2)
    #expect(l1.frontier == ["AVAX"])
    // 删掉任意一个成员，中位数在 ±0.5 之间摆——0 不是一个孤零零的巧合。
    #expect(try #require(l1.jackknife) == -0.5...0.5)
    #expect(l1.eligible)
  }

  /// 全部相同：没人跑赢谁，前沿是空的，删一区间塌成一个点。
  @Test func anIdenticalBoardHasNoBreadthNoFrontierAndAFlatJackknife() throws {
    let stats = Self.aggregate(["ADA": 3, "ALGO": 3, "APT": 3, "ATOM": 3, "AVAX": 3])
    let l1 = try #require(stats.first { $0.id == "l1" })
    #expect(l1.pct == 3)
    #expect(l1.upCount == 5)
    // 平盘（`e_i == 0`）不算跑赢。
    #expect(l1.breadth == 0 && l1.outperformCount == 0)
    #expect(l1.frontier.isEmpty)
    #expect(try #require(l1.jackknife) == 3...3)
  }

  /// 1–2 个有行情的成员：删一区间缺省，也上不了气泡场。
  @Test func oneOrTwoQuotedMembersAreNotASector() throws {
    let single = try #require(Self.aggregate(["ADA": 5]).first { $0.id == "l1" })
    #expect(single.memberCount == 1 && single.pct == 5)
    #expect(single.jackknife == nil && !single.eligible)

    let pair = try #require(Self.aggregate(["ADA": 5, "ALGO": 1]).first { $0.id == "l1" })
    #expect(pair.memberCount == 2 && pair.pct == 3)
    #expect(pair.jackknife == nil && !pair.eligible)

    let trio = try #require(Self.aggregate(["ADA": 5, "ALGO": 1, "APT": 3]).first { $0.id == "l1" })
    #expect(trio.memberCount == 3 && trio.eligible && trio.jackknife != nil)

    // 上不了场的不进球场，也不参与排序和归一。
    let sel = SectorSelector.select(Self.aggregate(["ADA": 5, "ALGO": 1]), market: .crypto)
    #expect(sel.picks.isEmpty && sel.total == 0)
  }

  /// 缺成员：登记了 60 个、只有 3 个有行情，聚合按有行情的那 3 个算。
  @Test func membersWithoutQuotesDoNotDragTheMedian() throws {
    let stats = Self.aggregate(["ADA": 4, "ALGO": 2, "APT": 6])
    let l1 = try #require(stats.first { $0.id == "l1" })
    let def = try #require(SectorCatalog.sectors(.crypto).first { $0.id == "l1" })
    #expect(l1.memberCount == 3)
    #expect(l1.staticCount == Set(def.members).count)
    #expect(l1.staticCount > l1.memberCount)
    // 没行情的既不当 0 参与中位数，也不摊薄广度。
    #expect(l1.pct == 4)
    #expect(l1.quoteVolume == 3)
    #expect(l1.breadth * Double(l1.memberCount) == Double(l1.outperformCount))
  }

  /// 全场价格统一乘一个常数：主数字跟着抬，广度与前沿一个都不动。
  ///
  /// 这正是「相对池基准」的意义——大盘整体上浮不该让每个板块都变成「跑赢」。
  @Test func multiplyingEveryPriceByAConstantMovesTheMedianOnly() throws {
    let raw: [String: Double] = ["ADA": -2, "ALGO": -1, "APT": 0, "ATOM": 1, "AVAX": 300]
    let lifted = raw.mapValues { ((1 + $0 / 100) * 1.05 - 1) * 100 }
    let before = try #require(Self.aggregate(raw).first { $0.id == "l1" })
    let after = try #require(Self.aggregate(lifted).first { $0.id == "l1" })
    #expect(after.frontier == before.frontier)
    #expect(abs(after.breadth - before.breadth) < 1e-12)
    #expect(after.pct > before.pct)
    // 绝对涨跌家数当然会变：统一上浮 5% 之后人人翻红。
    #expect(before.upCount == 2 && after.upCount == 5)
  }

  @Test func quantileInterpolatesBetweenNeighbours() {
    #expect(SectorAggregator.quantile([1, 2, 3, 4], 0.9) == 3.7)
    #expect(SectorAggregator.quantile([1, 2], 0.5) == 1.5)
    #expect(SectorAggregator.quantile([7], 0.95) == 7)
    // 两头钉死，越界的 p 也夹回来。
    #expect(SectorAggregator.quantile([1, 2, 3, 4], 0) == 1)
    #expect(SectorAggregator.quantile([1, 2, 3, 4], 1) == 4)
    #expect(SectorAggregator.quantile([1, 2, 3, 4], 2) == 4)
  }

  // MARK: - 6. 尺子：全场最大值 + 迟滞

  @Test func theScaleIsTheWholeBoardMaximumAndHoldsStillUntilItReallyMoves() {
    let board = Self.fakes((1...20).map(Double.init))
    let base = SectorSelector.select(board, n: 5, m: 3)
    // 分母取全场最大：最大的那颗球就是幅度最大的板块。
    #expect(base.scalePct == 20)
    // 上场的只有 13 颗，但没上场的那几段也算进分母。
    #expect(base.picks.count == 13 && base.total == 20)

    // 抖一下：最大值 20 → 21，差 1，不到旧尺子的 20%（4）→ 沿用旧值，
    // 整屏球不跟着呼吸一次。
    let nudged = Self.fakes((1...19).map(Double.init) + [21])
    #expect(SectorSelector.select(nudged, n: 5, m: 3).scalePct == 21)
    #expect(SectorSelector.select(nudged, n: 5, m: 3, previousScale: base.scalePct).scalePct == 20)

    // 真的换了一档就认新的：一颗 +300% 进场，差 280 ≥ 4。
    let spiked = Self.fakes((1...20).map(Double.init) + [300])
    let sel = SectorSelector.select(spiked, n: 5, m: 3, previousScale: base.scalePct)
    #expect(sel.scalePct == 300)

    // 负的一头也算绝对值；超出分母的球面积截到 1（数字仍按真值显示）。
    #expect(SectorSelector.select(Self.fakes([2, -40]), n: 1, m: 0).scalePct == 40)
    #expect(sel.norm(300) == 1)
    #expect(sel.norm(-600) == 1)
    #expect(sel.norm(150) == 0.5)
    #expect(sel.norm(.nan) == 0)
  }

  @Test func ineligibleSectorsAreDroppedBeforeRankingAndScaling() {
    // 上不了场的那两段 pct 最极端，没被摘掉的话既上场又把尺子撑大。
    let sel = SectorSelector.select(Self.fakes([3, 1, -2], ineligible: [99, -99]), n: 5, m: 3)
    #expect(sel.total == 3)
    #expect(Set(sel.picks.map(\.id)) == ["s0", "s1", "s2"])
    #expect(sel.scalePct == 3)
    #expect(sel.upCount == 2 && sel.downCount == 1)
  }

  // MARK: - 7. 同一个 base 挂着两张合约时留哪一张

  @Test func quoteAssetRankOutranksVolume() {
    let usdt = SectorQuotePreference.rank("USDT")
    let usdc = SectorQuotePreference.rank("USDC")
    // USDT 那张成交额只有 USDC 的十分之一，照样留 USDT。
    #expect(SectorQuotePreference.prefers(rank: usdt, volume: 1, over: (usdc, 10)))
    #expect(!SectorQuotePreference.prefers(rank: usdc, volume: 10, over: (usdt, 1)))
    // 同一档才比成交额，平手不换（免得两张来回顶替）。
    #expect(SectorQuotePreference.prefers(rank: usdt, volume: 2, over: (usdt, 1)))
    #expect(!SectorQuotePreference.prefers(rank: usdt, volume: 1, over: (usdt, 1)))
    // 固定档次：USDT > USDC > FDUSD > 其它，表外的一律垫底。
    #expect(SectorQuotePreference.rank("usdt") == 0)
    #expect(usdc == 1)
    #expect(SectorQuotePreference.rank("FDUSD") == 2)
    #expect(SectorQuotePreference.rank("BTC") == SectorQuotePreference.quoteAssets.count)
  }
}

/// 乙版：日线 5 日 / 20 日那一段窗口。
///
/// 口径和今日**完全是同一套**——给每个成员一个收益值，再算中位数 / 广度 / 领涨 /
/// 删一。这一组用例钉的是那个收益值怎么来、以及「这段数据不够就不上场」那条门槛。
@Suite("板块窗口")
struct SectorWindowTests {
  /// 挑一个成员够多的真板块来搭台。用例不写死 id，免得分类表一调就红。
  static let sector = SectorCatalog.sectors(.crypto).max { $0.members.count < $1.members.count }!

  /// 全市场只有这个板块的成员有行情：池基准就是它们自己，用例里算得出来。
  static func quotes(_ bases: [String], price: Double) -> [String: SectorQuote] {
    var out: [String: SectorQuote] = [:]
    for base in bases {
      out[base] = SectorQuote(base: base, pct: 1, quoteVolume: 1, price: price)
    }
    return out
  }

  static func history(_ bases: [String], c5: Double?, c20: Double? = nil,
                      asof: String = "2026-09-18") -> SectorHistory {
    var closes: [String: SectorCloses] = [:]
    for base in bases { closes[base] = SectorCloses(c5: c5, c20: c20) }
    return SectorHistory(asof: asof, closes: closes)
  }

  // MARK: - 收益值本身

  @Test func fiveDayIsTheLivePriceOverTheClose() {
    let q = SectorQuote(base: "BTC", pct: 1, quoteVolume: 1, price: 110)
    let closes = SectorCloses(c5: 100, c20: 50)
    func near(_ got: Double?, _ want: Double) -> Bool { abs((got ?? .nan) - want) < 1e-9 }
    #expect(SectorAggregator.windowReturn(q, window: .today, closes: closes) == 1)
    #expect(near(SectorAggregator.windowReturn(q, window: .d5, closes: closes), 10))
    #expect(near(SectorAggregator.windowReturn(q, window: .d20, closes: closes), 120))
    // 现价一动，5 日跟着动——它不是一天只变一次的死数。
    let moved = SectorQuote(base: "BTC", pct: 1, quoteVolume: 1, price: 121)
    #expect(near(SectorAggregator.windowReturn(moved, window: .d5, closes: closes), 21))
  }

  @Test func aMissingCloseIsAbsentNotZero() {
    let q = SectorQuote(base: "BTC", pct: 1, quoteVolume: 1, price: 110)
    // 这一档没有 → 没有这个成员，而不是 0（`last/0` 是 +∞，一个就够毁掉中位数）。
    #expect(SectorAggregator.windowReturn(q, window: .d5, closes: SectorCloses(c20: 50)) == nil)
    #expect(SectorAggregator.windowReturn(q, window: .d5, closes: nil) == nil)
    #expect(SectorAggregator.windowReturn(q, window: .d5, closes: SectorCloses(c5: 0)) == nil)
    #expect(SectorAggregator.windowReturn(q, window: .d5, closes: SectorCloses(c5: -1)) == nil)
    let dead = SectorQuote(base: "BTC", pct: 1, quoteVolume: 1, price: .nan)
    #expect(SectorAggregator.windowReturn(dead, window: .d5, closes: SectorCloses(c5: 1)) == nil)
  }

  // MARK: - 一段窗口的成员集与门槛

  @Test func aWindowWithoutHistoryHasNothingOnTheField() {
    let members = Self.sector.members
    let quotes = Self.quotes(members, price: 110)
    // 服务端还没采这个市场的日线（美股此刻就是这样）：5 日一个板块都排不出来，
    // 于是页面上连那行药丸都不出现。
    let five = SectorAggregator.stats(market: .crypto, quotes: quotes, fallbackBuckets: [],
                                      window: .d5, history: .empty)
    #expect(five.isEmpty)
    #expect(!SectorAggregator.hasEligible(market: .crypto, quotes: quotes,
                                          window: .d5, history: .empty))
    #expect(SectorAggregator.hasEligible(market: .crypto, quotes: quotes,
                                         window: .today, history: .empty))
  }

  @Test func shortCoverageStaysOffTheFieldButKeepsItsRow() {
    let members = Self.sector.members
    let quotes = Self.quotes(members, price: 110)
    // 只有一半成员有 5 日收盘：这一半的中位数不是这个板块的 5 日强弱。
    let half = Array(members.prefix(members.count / 2))
    let thin = SectorAggregator.stats(market: .crypto, quotes: quotes, fallbackBuckets: [],
                                      window: .d5, history: Self.history(half, c5: 100))
    let row = thin.first { $0.id == Self.sector.id }
    #expect(row != nil, "覆盖不够也还在「全部板块」里，只是不上场")
    #expect(row?.memberCount == half.count)
    #expect(row?.eligible == false)

    // 八成以上就上得了场。
    let wide = Array(members.prefix(Int((0.9 * Double(members.count)).rounded(.up))))
    let full = SectorAggregator.stats(market: .crypto, quotes: quotes, fallbackBuckets: [],
                                      window: .d5, history: Self.history(wide, c5: 100))
    #expect(full.first { $0.id == Self.sector.id }?.eligible == true)
  }

  @Test func theMedianAndBreadthComeFromTheWindowNotFromToday() {
    let members = Array(Self.sector.members.prefix(4))
    var quotes: [String: SectorQuote] = [:]
    var closes: [String: SectorCloses] = [:]
    // 今日全是 +1%，5 日却是 +10 / +20 / −10 / −20：两档读出来必须不一样。
    let fiveDay = [10.0, 20, -10, -20]
    for (index, base) in members.enumerated() {
      quotes[base] = SectorQuote(base: base, pct: 1, quoteVolume: 1, price: 100 + fiveDay[index])
      closes[base] = SectorCloses(c5: 100, c20: 80)
    }
    let history = SectorHistory(asof: "2026-09-18", closes: closes)
    let today = SectorAggregator.stats(market: .crypto, quotes: quotes, fallbackBuckets: [],
                                       window: .today, history: history)
      .first { $0.id == Self.sector.id }
    let five = SectorAggregator.stats(market: .crypto, quotes: quotes, fallbackBuckets: [],
                                      window: .d5, history: history)
      .first { $0.id == Self.sector.id }
    #expect(abs((today?.pct ?? 0) - 1) < 1e-9)
    #expect(abs((five?.pct ?? 0) - 0) < 1e-9)
    // 今日人人齐平，谁也没跑赢池基准；5 日有两只跑赢。
    #expect(today?.outperformCount == 0)
    #expect(five?.outperformCount == 2)
    // 头部那句「20 日 …」走的是同一套，只换一段窗口。
    let d20 = SectorAggregator.windowMedian(members: members, quotes: quotes,
                                            history: history, window: .d20)
    #expect(d20 != nil)
    #expect(abs((d20 ?? 0) - 25) < 1e-9)
    // 没有 20 日收盘就没有这一句——不写「暂无」。
    let only5 = SectorHistory(asof: "2026-09-18",
                              closes: closes.mapValues { SectorCloses(c5: $0.c5) })
    #expect(SectorAggregator.windowMedian(members: members, quotes: quotes,
                                          history: only5, window: .d20) == nil)
  }

  // MARK: - 取历史失败不碰今日

  @Test func todayIsUntouchedWhenTheHistoryRequestFails() throws {
    let snap = try SectorTests.snapshot("crypto")
    let withHistory = SectorAggregator.stats(market: .crypto, quotes: snap.quotes,
                                             fallbackBuckets: snap.buckets,
                                             window: .today,
                                             history: Self.history(["BTC"], c5: 1, c20: 2))
    // 历史整个取不回来（`.empty`）时，今日那一档和带着历史时一模一样，
    // 也和不传窗口的老写法一模一样。
    let blind = SectorAggregator.stats(market: .crypto, quotes: snap.quotes,
                                       fallbackBuckets: snap.buckets,
                                       window: .today, history: .empty)
    let legacy = SectorAggregator.stats(market: .crypto, quotes: snap.quotes,
                                        fallbackBuckets: snap.buckets)
    #expect(withHistory == blind)
    #expect(blind == legacy)
  }

  // MARK: - 同一天的那份不重算

  @Test func theSameAsofDoesNotSupersede() {
    let held = SectorHistory(asof: "2026-09-18", closes: ["BTC": SectorCloses(c5: 1, c20: 2)])
    // 每小时问一趟，回来的还是同一天：不赋值，整页不重算。
    #expect(!SectorHistory(asof: "2026-09-18", closes: ["BTC": SectorCloses(c5: 9)])
      .supersedes(held))
    // 换了天就认。
    #expect(SectorHistory(asof: "2026-09-19", closes: ["BTC": SectorCloses(c5: 1)])
      .supersedes(held))
    // 手上还没有：任何一份都认（磁盘上那份就是这么顶上来的）。
    #expect(held.supersedes(.empty))
  }
}
