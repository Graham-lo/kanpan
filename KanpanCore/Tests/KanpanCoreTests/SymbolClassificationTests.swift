import Foundation
import Testing
@testable import KanpanCore

@Suite("品种事实分类")
struct SymbolClassificationTests {
  @Test func metadataRetainsFacets() {
    let info = SymbolInfo(symbol: "NEWUSDT", base: "NEW", pricePrecision: 2, tickSize: 0.01,
                          underlyingType: "KR_EQUITY", underlyingSubTypes: ["TradFi", "ETF", "ETF"])
    let result = SymbolClassifier.classify(info)
    #expect(result.asset == .equity && result.region == .kr)
    #expect(result.source == .exchangeMetadata)
    #expect(result.tags == ["etf", "tradfi"])
    #expect(result.ruleVersion == SymbolClassifier.ruleVersion)
  }
  @Test func unknownDoesNotBecomeCryptoOrUSStock() {
    let info = SymbolInfo(symbol: "NEWUSDT", base: "NEW", pricePrecision: 2, tickSize: 0.01, underlyingType: "FUTURE_ASSET_KIND")
    #expect(SymbolClassifier.classify(info).asset == .other)
    #expect(SymbolClassifier.classify(info).source == .unknown)
  }
  @Test func olderCatalogRemainsDecodable() throws {
    let data = Data(#"{"symbol":"BTCUSDT","base":"BTC","quote":"USDT","pricePrecision":2,"quantityPrecision":3,"tickSize":0.01}"#.utf8)
    let info = try JSONDecoder().decode(SymbolInfo.self, from: data)
    #expect(info.underlyingType == nil && info.underlyingSubTypes == nil)
    // 旧盘上的缓存没有 status，解出来当「正常挂牌」，不能因此整张表解不开。
    #expect(info.status == .tradable)
  }

  /// B-04：缺 `underlyingType` 不再按写死的代号白名单猜，连 BTC 也不例外。
  @Test func missingUnderlyingTypeIsNotGuessed() {
    for base in ["BTC", "ETH", "SOL", "XRP", "DOGE", "AAPL", "NVDA", "SKHYNIX", "NEW"] {
      let info = SymbolInfo(symbol: base + "USDT", base: base, pricePrecision: 2, tickSize: 0.01)
      let c = SymbolClassifier.classify(info)
      #expect(c.asset == .other, "\(base) 缺类型时必须判成 other")
      #expect(c.source == .unknown)
    }
  }

  /// B-04：贵金属是按 ISO 资产代码认的，不算猜，缺类型也保留。
  @Test func preciousMetalsStayRecognizedWithoutType() {
    for base in ["XAU", "XAG", "XPT", "XPD"] {
      let info = SymbolInfo(symbol: base + "USDT", base: base, pricePrecision: 2, tickSize: 0.01)
      #expect(SymbolClassifier.classify(info).asset == .preciousMetal)
    }
    #expect(SymbolClassifier.preciousMetals == ["XAU", "XAG", "XPT", "XPD"])
  }

  /// 链上的金子代币照交易所算加密：币安给的是 `COIN` + `[RWA, Crypto]`
  /// （KanpanData 夹具 catalog-classification-2026-09-15.json）。只有徽章按材料画金锭。
  @Test func goldTokensAreCryptoPerExchange() {
    for base in ["XAUT", "PAXG"] {
      let info = SymbolInfo(symbol: base + "USDT", base: base, pricePrecision: 2, tickSize: 0.01,
                            underlyingType: "COIN", underlyingSubTypes: ["RWA", "Crypto"],
                            contractType: "PERPETUAL")
      #expect(SymbolClassifier.classify(info).asset == .crypto)
      #expect(!SymbolClassifier.isPreciousMetal(base: base))
    }
  }

  /// B-T12（Swift 半边）：网关合成出来的 OKX 行带上 `underlyingType: "COIN"` 之后，
  /// 客户端必须判成加密——这一行原来是靠白名单才对的，现在靠字段。
  @Test func gatewaySyntheticRowWithCoinTypeIsCrypto() {
    let info = SymbolInfo(symbol: "ADA-USDT-SWAP", base: "ADA", quote: "USDT",
                          pricePrecision: 4, tickSize: 0.0001,
                          underlyingType: "COIN", contractType: "PERPETUAL")
    let c = SymbolClassifier.classify(info)
    #expect(c.asset == .crypto)
    #expect(c.source == .exchangeMetadata)
    #expect(MarketSector.market(info) == "crypto")
  }
}
