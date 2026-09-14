import Foundation

/// 品种事实分类，与用户文件夹独立。细分标签、地区和规则来源供后续筛选扩展。
public struct SymbolClassification: Codable, Sendable, Equatable {
  public enum Asset: String, Codable, Sendable { case crypto, equity, preciousMetal, commodity, index, preMarket, other }
  public enum Region: String, Codable, Sendable { case us, hk, kr, cn, unspecified }
  public enum Source: String, Codable, Sendable { case exchangeMetadata, knownSymbol, unknown }
  public var asset: Asset
  public var region: Region
  public var tags: [String]
  public var source: Source
  public var ruleVersion: Int
}

public enum SymbolClassifier {
  public static let ruleVersion = 1

  public static func classify(_ info: SymbolInfo) -> SymbolClassification {
    let base = info.base.uppercased()
    let tags = Array(Set((info.underlyingSubTypes ?? []).map { $0.lowercased() })).sorted()
    func result(_ asset: SymbolClassification.Asset, _ region: SymbolClassification.Region = .unspecified,
                _ source: SymbolClassification.Source = .exchangeMetadata) -> SymbolClassification {
      SymbolClassification(asset: asset, region: region, tags: tags, source: source, ruleVersion: ruleVersion)
    }
    // 贵金属细分来自明确的ISO资产代码，原始COMMODITY标签仍保留在SymbolInfo。
    if ["XAU", "XAG", "XPT", "XPD"].contains(base) { return result(.preciousMetal, .unspecified, .knownSymbol) }
    switch info.underlyingType?.uppercased() {
    case "COIN": return result(.crypto)
    case "EQUITY": return result(.equity, .us)
    case "HK_EQUITY": return result(.equity, .hk)
    case "KR_EQUITY": return result(.equity, .kr)
    case "CN_EQUITY": return result(.equity, .cn)
    case "COMMODITY": return result(.commodity)
    case "INDEX": return result(.index)
    case "PREMARKET": return result(.preMarket)
    case .some: return result(.other, .unspecified, .unknown)
    case nil:
      if ["BTC", "ETH", "SOL", "XRP", "DOGE"].contains(base) { return result(.crypto, .unspecified, .knownSymbol) }
      if ["AAPL", "MSFT", "NVDA", "AMZN", "GOOGL", "META", "TSLA", "SNDK", "MU", "MRVL", "LITE", "AVGO", "SOXL", "SKHY"].contains(base) { return result(.equity, .us, .knownSymbol) }
      if base == "SKHYNIX" { return result(.equity, .kr, .knownSymbol) }
      return result(.other, .unspecified, .unknown)
    }
  }
}
