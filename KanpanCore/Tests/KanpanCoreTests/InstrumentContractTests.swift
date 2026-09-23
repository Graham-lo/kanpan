import Foundation
import Testing

@testable import KanpanCore

/// 品种命名的跨端契约：`Backend/kanpan-api/contract/instruments.json`。
///
/// 计价资产、剥后缀的顺序、周期、永续判定、裸代号归哪一家——这几张表客户端与服务端各有
/// 一份常量（Swift 的在 `QuoteAssets` / `Interval` / `SymbolInfo.perpetualContractTypes` /
/// `InstrumentID.defaultMarketKey`，Rust 的在 `src/instruments.rs`），两边都逐项对着这份
/// 手工维护的 JSON 比；Rust 那一半是 `instruments::tests::the_contract_file_is_what_both_sides_use`。
/// 任何一边单独改表，自己那一侧的这条用例就红。
@Suite("品种命名契约（instruments.json）")
struct InstrumentContractTests {
  struct Contract: Decodable {
    struct Market: Decodable { var venue: String; var market: String; var key: String }
    var defaultMarket: Market
    var quoteAssets: [String]
    var quoteSuffixes: [String]
    var baseCases: [[String]]
    var intervals: [String]
    var legacyIntervals: [String]
    var perpetualContractTypes: [String]
  }

  static func load() throws -> Contract {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("Backend/kanpan-api/contract/instruments.json")
    return try JSONDecoder().decode(Contract.self, from: Data(contentsOf: url))
  }

  @Test("计价资产与剥后缀顺序")
  func quoteTables() throws {
    let c = try Self.load()
    #expect(QuoteAssets.tradable == c.quoteAssets)
    #expect(QuoteAssets.suffixes == c.quoteSuffixes)
  }

  @Test("同一批代号两端剥出同一个 base")
  func baseCases() throws {
    let c = try Self.load()
    #expect(!c.baseCases.isEmpty)
    for pair in c.baseCases {
      #expect(pair.count == 2)
      #expect(QuoteAssets.base(of: pair[0]) == pair[1], "\(pair[0])")
      // 占位品种信息走的是同一个拆法。
      #expect(SymbolInfo.placeholder(symbol: pair[0]).base == pair[1], "\(pair[0])")
    }
  }

  @Test("周期条就是契约里那张表；旧周期客户端已经选不到")
  func intervals() throws {
    let c = try Self.load()
    #expect(Interval.allCases.map(\.rawValue) == c.intervals)
    for legacy in c.legacyIntervals { #expect(Interval(rawValue: legacy) == nil, "\(legacy)") }
  }

  @Test("永续判定与裸代号的默认交易所")
  func perpetualAndDefaultMarket() throws {
    let c = try Self.load()
    #expect(SymbolInfo.perpetualContractTypes == c.perpetualContractTypes)
    #expect(InstrumentID.defaultVenue == c.defaultMarket.venue)
    #expect(InstrumentID.defaultMarket == c.defaultMarket.market)
    #expect(InstrumentID.defaultMarketKey == c.defaultMarket.key)
    #expect(InstrumentID("BTCUSDT").isDefaultMarket)
  }
}
