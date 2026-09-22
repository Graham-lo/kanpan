import Foundation

/// 品种事实分类，与用户文件夹独立。细分标签、地区和规则来源用于现行分类与筛选。
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
    // 没有 `underlyingType` 就是**不知道**，不猜（审查 B-04）。
    //
    // 这里原来挂着一张写死的代号白名单（BTC/ETH/SOL… 当加密，AAPL/NVDA… 当美股），
    // 猜错的代价是不对称的：合约表里有三分之一不是币，一个新上的股票代号只要没进白名单
    // 就会被当成加密，于是「总市值 = 总供应量 × 现价」这类按币的口径算的数字会给出一个
    // 错的值；而判成 `.other` 只是让它进「其他」分类、该留空的地方留空。
    // 所以缺字段一律 `.other` / `.unknown`；唯一的例外是上面那条按 ISO 资产代码认的贵金属，
    // 那不是猜——XAU/XAG/XPT/XPD 本身就是代号。
    case nil: return result(.other, .unspecified, .unknown)
    }
  }
}
