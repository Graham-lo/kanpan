import KanpanCore

struct IndicatorDraft {
  /// 均线 / EMA / 强弱 / 均量最多几条。和 `IndicatorParamRule.sanitize` 的 `prefix(20)` 是同一个数：
  /// 界面上加不出第 21 条，存档里塞进来的第 21 条也会被砍掉。
  static let maxPeriods = 20

  var id: IndicatorID
  var params: [Int]
  var colors: [Int: Hex]
  init(id: IndicatorID, prefs: Prefs) {
    self.id = id; params = prefs.params(for: id)
    colors = prefs.indicatorColors[id] ?? [:]
  }
  /// 落进偏好。**和出厂一样的项写回出厂的样子（多半是 nil），不留一份「等于默认」的副本。**
  ///
  /// 原来点开编辑页、什么都不改、按「保存」，也会把参数、配色两张表各写一条进去：
  /// 这几个字段被当成「用户改过」记脏、推上云端；更要命的是参数被钉成了当时的出厂值，
  /// 以后出厂参数再调，这个人永远吃不到。做法照 `OrderFlowEditor` 的 override：
  /// 等于默认就清掉，读的那一侧（`Prefs.params(for:)` 等）缺项自己退回默认。
  func save(into prefs: inout Prefs) {
    let clean = IndicatorParamRule.sanitize(params, for: id)
    // 出厂表里本来就带着的那几把（均线 / EMA / 均量 / MACD）写回出厂表那一项，
    // 其余的清掉——两种都是「和 `Prefs.defaults` 一模一样」。
    prefs.params[id] = clean == id.defaultParams ? IndicatorID.factoryParams[id] : clean
    prefs.indicatorColors[id] = colors.isEmpty ? nil : colors
  }

  var outputs: [String] {
    switch id {
    case .macd: return ["DIF", "DEA", "MACD柱"]
    case .vol: return id.lineNames(params: params) + ["成交量柱"]
    default: return id.lineNames(params: params)
    }
  }
}
