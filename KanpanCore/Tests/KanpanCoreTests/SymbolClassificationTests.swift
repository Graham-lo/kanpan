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
    #expect(SymbolClassifier.classify(info).source == .knownSymbol)
    #expect(SymbolClassifier.classify(info).asset == .crypto)
  }
}
