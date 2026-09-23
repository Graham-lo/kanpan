import KanpanCore

/// 自动收藏建议仅映射粗粒度文件夹；品种事实分类由Core独立提供。
/// 只在首次收藏/迁移未归类成员时使用，不覆盖用户主动移动过的分类。
enum FavoriteCategory {
  /// 这个代号我们**知道**它是什么吗？
  ///
  /// 判据只有两条，和 `SymbolClassifier` 逐字一致（审查 B-04）：交易所的
  /// `underlyingType` 说了，或者基础资产本身就是 ISO 贵金属代码。既没有目录行、
  /// 又没有 `underlyingType` 时一律算「不知道」——这儿原来靠 `SymbolClassifier`
  /// 里那张写死的代号白名单兜底（BTC/ETH/… 当加密），一个新上的股票代号只要没进
  /// 白名单就会被塞进「加密」分类里。不知道就不编，交给调用方决定放哪儿。
  static func knows(symbol: String, info: SymbolInfo?) -> Bool {
    if let info, info.underlyingType != nil { return true }
    let key = SymbolPrefs.key(symbol)
    let base = info?.base ?? SymbolInfo.placeholder(symbol: key).base
    // 名单只有 `SymbolClassifier.preciousMetals` 一份：XAU/XAG/XPT/XPD 本身就是资产代码，不是猜。
    return SymbolClassifier.isPreciousMetal(base: base)
  }

  /// 只在 `knows(symbol:info:) == true` 时才有意义；不知道的一律落到「其他」，
  /// 调用方应当先问 `knows` 再决定要不要用这个名字（见 `SymbolPickerModel.addFavorite`）。
  static func name(symbol: String, info: SymbolInfo?) -> String {
    let key = SymbolPrefs.key(symbol)
    let base = SymbolInfo.placeholder(symbol: key).base
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
