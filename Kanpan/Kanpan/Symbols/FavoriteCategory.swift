import KanpanCore

/// 自动收藏建议仅映射粗粒度文件夹；品种事实分类由Core独立提供。
/// 只在首次收藏/迁移未归类成员时使用，不覆盖用户主动移动过的分类。
enum FavoriteCategory {
  static func name(symbol: String, info: SymbolInfo?) -> String {
    let key = SymbolPrefs.key(symbol)
    let base = key.hasSuffix("USDT") ? String(key.dropLast(4)) : key
    let info = info ?? SymbolInfo(symbol: key, base: base, pricePrecision: 2, tickSize: 0.01)
    let category = SymbolClassifier.classify(info)
    switch category.asset {
    case .crypto: return "加密"
    case .index where info.contractType == "PERPETUAL": return "加密"
    case .preciousMetal: return "贵金属"
    case .equity where category.region == .us: return "美股"
    case .equity where ["SKHY", "SKHYNIX"].contains(info.base.uppercased()): return "美股"
    default: return "其他"
    }
  }
}
