import Foundation
import Testing
import KanpanCore

@testable import KanpanSymbols

/// 方案第 3 节第一件：拼音 / 中文搜品种。
@Suite("中文与拼音搜品种")
struct SymbolAliasesTests {
  private let catalog = SymbolFixtures.catalog
  /// 美股那一侧的中文名来自 `SectorCatalog`，fixtures 里没有，现搭一行。
  private let tesla = SymbolInfo(symbol: "TSLAUSDT", base: "TSLA", pricePrecision: 2,
                                 tickSize: 0.01, underlyingType: "EQUITY")

  @Test("全拼与首字母是从中文名算出来的，不是抄的")
  func pinyinGeneration() throws {
    let btc = try #require(SymbolAliases.pinyin("比特币"))
    #expect(btc.full == "BITEBI")
    #expect(btc.initials == "BTB")
    let tsla = try #require(SymbolAliases.pinyin("特斯拉"))
    #expect(tsla.full == "TESILA")
    #expect(tsla.initials == "TSL")
    // 纯英文的「中文名」（AMD、Meta 这种）算不出拼音，也就不进索引——
    // 否则它会贡献一个一位的首字母，搜任何以 A 开头的词都要撞它一下。
    #expect(SymbolAliases.pinyin("AMD") == nil)
    // 混着拉丁时只算汉字那一段。
    #expect(SymbolAliases.pinyin("SK 海力士")?.initials == "HLS")
  }

  @Test("bitebi / btb / 比特币 都能搜到 BTC")
  func bitcoin() {
    #expect(SymbolQuery.match(catalog, query: "bitebi").first?.id == "BTCUSDT")
    #expect(SymbolQuery.match(catalog, query: "btb").first?.id == "BTCUSDT")
    #expect(SymbolQuery.match(catalog, query: "比特币").first?.id == "BTCUSDT")
    // 粘进来的中文带空格、带斜杠也照样认。
    #expect(SymbolQuery.match(catalog, query: " 比特币 ").first?.id == "BTCUSDT")
    #expect(SymbolQuery.match(catalog, query: "大饼").first?.id == "BTCUSDT")
  }

  @Test("tesila / tsl / 特斯拉 都能搜到特斯拉")
  func tesla_() {
    #expect(SymbolQuery.match(tesla, query: "TESILA")?.tier == .pinyinFull)
    #expect(SymbolQuery.match(tesla, query: "TSL")?.tier == .pinyinInitials)
    #expect(SymbolQuery.match(tesla, query: "特斯拉")?.tier == .exact)
    #expect(SymbolQuery.match(tesla, query: "特斯")?.tier == .pinyinFull)
  }

  @Test("名次：最匹配 → 全拼 → 首字母 → 字面前缀")
  func tiers() {
    #expect(SymbolMatch.Tier.exact < .pinyinFull)
    #expect(SymbolMatch.Tier.pinyinFull < .pinyinInitials)
    #expect(SymbolMatch.Tier.pinyinInitials < .basePrefix)
    let btc = SymbolFixtures.info("BTCUSDT")
    #expect(SymbolQuery.match(btc, query: "比特币")?.tier == .exact)
    #expect(SymbolQuery.match(btc, query: "BITEBI")?.tier == .pinyinFull)
    #expect(SymbolQuery.match(btc, query: "BTB")?.tier == .pinyinInitials)
    // 字面命中更靠前时以字面为准：搜 BTC 仍然是「最匹配」。
    #expect(SymbolQuery.match(btc, query: "BTC")?.tier == .exact)
    // 别名命中不在代号上划高亮（命中的是「比特币」那三个字）。
    #expect(SymbolQuery.match(btc, query: "BITEBI")?.highlight == nil)
  }

  @Test("倍数合约按去掉倍数的名字查：1000PEPE 就是佩佩")
  func multiplierContracts() {
    #expect(SymbolQuery.match(catalog, query: "佩佩").map(\.id) == ["1000PEPEUSDT"])
    #expect(SymbolQuery.match(catalog, query: "peipei").map(\.id) == ["1000PEPEUSDT"])
  }

  @Test("一个字母不走拼音，免得把整张表顶上来")
  func oneLetterIsNotPinyin() {
    #expect(SymbolAliases.tier(base: "BTC", query: "B") == nil)
    #expect(SymbolAliases.tier(base: "BTC", query: "BT") == .pinyinInitials)
    // 表里没有的代号一律没有别名。
    #expect(SymbolAliases.tier(base: "ETHFI", query: "YITAI") == nil)
    #expect(SymbolAliases.names(base: "ETH").contains("以太坊"))
  }

  @Test("中文没命中的词照旧一条都不出")
  func noFalsePositives() {
    #expect(SymbolQuery.match(catalog, query: "茅台").isEmpty)
    #expect(SymbolQuery.match(catalog, query: "zzzzz").isEmpty)
  }
}

/// 方案第 3 节第五件 d：输入格式容忍。
@Suite("搜索输入格式容忍")
struct SymbolQueryFormatTests {
  private let catalog = SymbolFixtures.catalog

  @Test("ETH/USDT、ethusdt、eth usdt、$ETH、ETH-USDT 都落到 ETHUSDT")
  func separators() {
    for raw in ["ETH/USDT", "ethusdt", "eth usdt", "$ETH", "ETH-USDT", "eth_usdt", "ETH：USDT"] {
      #expect(SymbolQuery.match(catalog, query: raw).first?.id == "ETHUSDT", "\(raw)")
    }
    #expect(SymbolQuery.normalize("ETH/USDT") == "ETHUSDT")
    #expect(SymbolQuery.normalize(" $eth ") == "ETH")
  }

  @Test("相似的名字不合并：ETHFI 还是 ETHFI")
  func doesNotMergeSimilarNames() {
    #expect(SymbolQuery.match(catalog, query: "ETH/USDT").map(\.id) == ["ETHUSDT"])
    #expect(SymbolQuery.match(catalog, query: "ETHFI").map(\.id) == ["ETHFIUSDT"])
    // 搜 ETH 时两个都在，但名次分得开。
    let eth = SymbolQuery.match(catalog, query: "eth")
    #expect(eth.first?.id == "ETHUSDT")
    #expect(eth.map(\.id).contains("ETHFIUSDT"))
  }
}
