import Foundation

/// Exchange market metadata. Independent of user-created favorite folders.
public enum MarketSector {
  public static func market(_ info: SymbolInfo) -> String {
    let c = SymbolClassifier.classify(info)
    switch c.asset {
    case .crypto: return "crypto"
    case .equity:
      switch c.region { case .us: return "us"; case .hk: return "hk"; case .kr: return "kr"; case .cn: return "cn"; default: return "equity" }
    case .preciousMetal: return "metals"
    case .commodity: return "commodities"
    case .index: return "index"
    case .preMarket: return "premarket"
    case .other: return "other"
    }
  }
  public static let order = ["crypto", "us", "hk", "kr", "cn", "equity", "metals", "commodities", "index", "premarket", "other"]
  public static func tags(_ info: SymbolInfo) -> [String] {
    Array(Set((info.underlyingSubTypes ?? []).map { $0.lowercased() })).filter { !["crypto", "tradfi"].contains($0) }.sorted()
  }
  public static func title(_ key: String) -> String {
    ["all": "全部市场", "crypto": "加密", "us": "美股", "hk": "港股", "kr": "韩股", "cn": "A股",
     "equity": "股票", "metals": "贵金属", "commodities": "大宗商品", "index": "指数", "premarket": "盘前", "other": "其他",
     "layer-1": "Layer 1", "layer-2": "Layer 2", "defi": "DeFi", "ai": "AI", "meme": "Meme", "nft": "NFT",
     "gaming": "游戏", "infrastructure": "基础设施", "storage": "存储", "payment": "支付", "metaverse": "元宇宙",
     "pow": "PoW", "rwa": "RWA", "etf": "ETF", "alpha": "Alpha", "chinese": "中国概念"][key] ?? key
  }
}
