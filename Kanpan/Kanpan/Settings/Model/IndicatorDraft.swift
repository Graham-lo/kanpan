import KanpanCore

struct IndicatorDraft {
  var id: IndicatorID
  var params: [Int]
  var colors: [Int: Hex]
  var hidden: Set<Int>
  var upper: Double
  var lower: Double
  init(id: IndicatorID, prefs: Prefs) {
    self.id = id; params = prefs.params(for: id)
    colors = prefs.indicatorColors[id] ?? [:]
    hidden = prefs.hiddenOutputs[id] ?? []
    upper = prefs.rsiUpper; lower = prefs.rsiLower
  }
  func save(into prefs: inout Prefs) {
    prefs.params[id] = IndicatorParamRule.sanitize(params, for: id)
    prefs.hiddenOutputs[id] = hidden
    prefs.indicatorColors[id] = colors
    if id == .rsi { prefs.rsiUpper = min(100, max(1, upper)); prefs.rsiLower = min(prefs.rsiUpper - 1, max(0, lower)) }
  }
  var outputs: [String] {
    switch id {
    case .macd: return ["DIF", "DEA", "MACD柱"]
    case .vol: return id.lineNames(params: params) + ["成交量柱"]
    default: return id.lineNames(params: params)
    }
  }
}
