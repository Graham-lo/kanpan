import Foundation
import KanpanCore

// MARK: - 落盘格式

/// Current chart preferences only. Old prototype archives are not migrated.
enum PrefsCodec {
  /// 当前存档版本。**改任何一个默认值都要把它 +1**。
  static let version = 2
  static let keyPrefix = "kanpan.prefs.v"

  /// 写进 `UserDefaults` 的那个键。
  static var key: String { key(version: version) }
  static func key(version: Int) -> String { "\(keyPrefix)\(version)" }

  static func encode(_ prefs: Prefs) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    // Prefs 的 encode 不会抛（全是标准类型），真抛了就当没存档。
    return (try? encoder.encode(prefs)) ?? Data()
  }

  /// 永远给得出一份能用的设置：坏档、半截档、未来版本的档，都退回默认再往上并。
  static func decode(_ data: Data?) -> Prefs {
    guard let data, !data.isEmpty else { return .defaults }
    return (try? JSONDecoder().decode(Prefs.self, from: data)) ?? .defaults
  }
}

// MARK: - 容错解码

extension Prefs: Codable {
  enum CodingKeys: String, CodingKey {
    case v
    case interval, quickIntervals
    case theme, styleID, redUp
    case indicatorColors
    case ambientTheme
    case priceMode, magnet, countdown, keepAwake, launchSnapshot, timeZone, changeBasis
    case candleKind, gridChoice, bodyChoice, lastLine, showDrawings, sinceChange
    case viewAnchor, priceBias
    case dataDisplay, crossPrice, allowMainInversion, allowSubInversion
    case adaptiveIndicators, compactValues, portraitHeight, hiddenOutputs, rsiUpper, rsiLower
    case overlays, subs, params, subHeights, subHeightOverrides
    case apiHost, streamHost, smartMarketRoute
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(PrefsCodec.version, forKey: .v)
    try c.encode(interval.rawValue, forKey: .interval)
    try c.encode(quickIntervals.map(\.rawValue), forKey: .quickIntervals)
    try c.encode(theme.rawValue, forKey: .theme)
    try c.encode(ambientTheme, forKey: .ambientTheme)
    try c.encode(styleID, forKey: .styleID)
    try c.encode(redUp, forKey: .redUp)
    try c.encode(priceMode.rawValue, forKey: .priceMode)
    try c.encode(magnet, forKey: .magnet)
    try c.encode(countdown, forKey: .countdown)
    try c.encode(keepAwake, forKey: .keepAwake)
    try c.encode(launchSnapshot, forKey: .launchSnapshot)
    try c.encode(timeZone.rawValue, forKey: .timeZone)
    try c.encode(changeBasis.rawValue, forKey: .changeBasis)
    try c.encode(candleKind.rawValue, forKey: .candleKind)
    try c.encode(gridChoice.rawValue, forKey: .gridChoice)
    try c.encode(bodyChoice.rawValue, forKey: .bodyChoice)
    try c.encode(lastLine, forKey: .lastLine)
    try c.encode(showDrawings, forKey: .showDrawings)
    try c.encode(sinceChange, forKey: .sinceChange)
    try c.encode(viewAnchor.rawValue, forKey: .viewAnchor)
    try c.encode(priceBias.rawValue, forKey: .priceBias)
    try c.encode(dataDisplay, forKey: .dataDisplay)
    try c.encode(crossPrice, forKey: .crossPrice)
    try c.encode(allowMainInversion, forKey: .allowMainInversion)
    try c.encode(allowSubInversion, forKey: .allowSubInversion)
    try c.encode(adaptiveIndicators, forKey: .adaptiveIndicators)
    try c.encode(compactValues, forKey: .compactValues)
    try c.encode(portraitHeight, forKey: .portraitHeight)
    try c.encode(Dictionary(uniqueKeysWithValues: hiddenOutputs.map { ($0.key.rawValue, $0.value.sorted()) }), forKey: .hiddenOutputs)
    try c.encode(Dictionary(uniqueKeysWithValues: indicatorColors.map { ($0.key.rawValue, $0.value) }), forKey: .indicatorColors)
    try c.encode(rsiUpper, forKey: .rsiUpper)
    try c.encode(rsiLower, forKey: .rsiLower)
    try c.encode(overlays.map(\.rawValue), forKey: .overlays)
    try c.encode(subs.map(\.rawValue), forKey: .subs)
    // 字典键是 enum，直接 encode 会变成交错数组；摊成 [String: …] 才是人能看懂的 JSON。
    try c.encode(Dictionary(uniqueKeysWithValues: params.map { ($0.key.rawValue, $0.value) }),
                 forKey: .params)
    try c.encode(Dictionary(uniqueKeysWithValues: subHeightOverrides.map { ($0.key.rawValue, $0.value) }), forKey: .subHeightOverrides)
    try c.encode(Dictionary(uniqueKeysWithValues: subHeights.map { ($0.key.rawValue, $0.value.rawValue) }),
                 forKey: .subHeights)
    try c.encode(apiHost, forKey: .apiHost)
    try c.encode(streamHost, forKey: .streamHost)
    try c.encode(smartMarketRoute, forKey: .smartMarketRoute)
  }

  init(from decoder: Decoder) throws {
    // 从新默认起步：存档只往上盖它真有的那几项（A6.13）。
    self = .defaults
    guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
    if let version = try? c.decode(Int.self, forKey: .v), version != PrefsCodec.version { return }

    func str(_ k: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil }
    func bool(_ k: CodingKeys) -> Bool? { (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? nil }
    func strs(_ k: CodingKeys) -> [String]? { (try? c.decodeIfPresent([String].self, forKey: k)) ?? nil }

    if let raw = str(.interval), let v = Interval(rawValue: raw) { interval = v }

    if let raw = strs(.quickIntervals) {
      var seen: [Interval] = []
      for r in raw {
        guard let iv = Interval(rawValue: r), !seen.contains(iv) else { continue }
        seen.append(iv)
      }
      if !seen.isEmpty { quickIntervals = Array(seen.prefix(Prefs.maxQuick)) }
    }

    if let raw = str(.theme), let v = ThemeChoice(rawValue: raw) { theme = v }
    if let v = bool(.ambientTheme) { ambientTheme = v }
    // 认不出来的风格 id 退回「墩」，不是留着一个画不出来的名字。
    if let raw = str(.styleID), CandleStyle.all.contains(where: { $0.id == raw }) { styleID = raw }
    if let v = bool(.redUp) { redUp = v }

    if let raw = str(.priceMode), let v = PriceMode(rawValue: raw) { priceMode = v }
    if let v = bool(.magnet) { magnet = v }
    if let v = bool(.countdown) { countdown = v }
    if let v = bool(.keepAwake) { keepAwake = v }
    if let v = bool(.launchSnapshot) { launchSnapshot = v }
    if let raw = str(.changeBasis), let v = ChangeBasis(rawValue: raw) { changeBasis = v }
    if let raw = str(.timeZone), let v = TZChoice(rawValue: raw) { timeZone = v }

    // 「图表」面板那几项。认不出的字面量一律退回默认（多半是降级回旧版本，
    // 或者手改存档手抖），不能因为一个字符串就让整档作废。
    if let raw = str(.candleKind), let v = CandleKind(rawValue: raw) { candleKind = v }
    if let raw = str(.gridChoice), let v = GridChoice(rawValue: raw) { gridChoice = v }
    if let raw = str(.bodyChoice), let v = BodyChoice(rawValue: raw) { bodyChoice = v }
    if let v = bool(.lastLine) { lastLine = v }
    if let v = bool(.showDrawings) { showDrawings = v }
    if let v = bool(.sinceChange) { sinceChange = v }
    if let raw = str(.viewAnchor), let v = ViewAnchor(rawValue: raw) { viewAnchor = v }
    if let raw = str(.priceBias), let v = PriceBias(rawValue: raw) { priceBias = v }

    if let raw = str(.dataDisplay), let v = CandleDataDisplay(rawValue: raw) { dataDisplay = v }
    if let raw = str(.crossPrice), let v = CrossPriceMode(rawValue: raw) { crossPrice = v }
    if let v = bool(.allowMainInversion) { allowMainInversion = v }
    if let v = bool(.allowSubInversion) { allowSubInversion = v }
    if let v = bool(.adaptiveIndicators) { adaptiveIndicators = v }
    if let v = bool(.compactValues) { compactValues = v }
    if let v = try? c.decode(Double.self, forKey: .portraitHeight), v.isFinite { portraitHeight = min(1, max(0, v)) }
    if let v = try? c.decode(Double.self, forKey: .rsiUpper), v.isFinite { rsiUpper = min(100, max(1, v)) }
    if let v = try? c.decode(Double.self, forKey: .rsiLower), v.isFinite { rsiLower = min(rsiUpper - 1, max(0, v)) }
    if let raw = try? c.decode([String: [Int]].self, forKey: .hiddenOutputs) {
      for (key, values) in raw {
        if let id = IndicatorID(rawValue: key) { hiddenOutputs[id] = Set(values.filter { (0..<21).contains($0) }) }
      }
    }

    if let raw = try? c.decode([String: [Int: Hex]].self, forKey: .indicatorColors) {
      for (key, values) in raw {
        guard let id = IndicatorID(rawValue: key) else { continue }
        indicatorColors[id] = values.filter { (0..<21).contains($0.key) && $0.value.value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil }
      }
    }
    if let raw = strs(.overlays) {
      overlays = Prefs.ids(raw, placement: .main)
    }
    if let raw = strs(.subs) {
      subs = Array(Prefs.ids(raw, placement: .sub).prefix(Prefs.maxSubs))
    }

    if let raw = (try? c.decodeIfPresent([String: [Int]].self, forKey: .params)) ?? nil {
      var out: [IndicatorID: [Int]] = [:]
      for (k, v) in raw {
        guard let id = IndicatorID(rawValue: k) else { continue }   // 认不出的指标直接丢
        out[id] = IndicatorParamRule.sanitize(v, for: id)           // 越界的夹回来
      }
      params = out
    }

    if let raw = try? c.decode([String: Double].self, forKey: .subHeightOverrides) {
      for (key, scale) in raw {
        if let id = IndicatorID(rawValue: key), id.placement == .sub, scale.isFinite {
          subHeightOverrides[id] = min(2, max(0.5, scale))
        }
      }
    }
    if let raw = (try? c.decodeIfPresent([String: String].self, forKey: .subHeights)) ?? nil {
      var out: [IndicatorID: SubPaneHeight] = [:]
      for (k, v) in raw {
        guard let id = IndicatorID(rawValue: k), let h = SubPaneHeight(rawValue: v) else { continue }
        out[id] = h
      }
      subHeights = out
    }

    smartMarketRoute = (try? c.decode(Bool.self, forKey: .smartMarketRoute)) ?? true
    if let raw = str(.apiHost) { apiHost = APIHost.sanitize(raw) }
    if let raw = str(.streamHost) {
      let host = APIHost.normalize(raw)
      streamHost = APIHost.isValid(host) ? host : APIHost.defaultStream
    }
  }

  /// 一串 rawValue → 去重、去掉认不出的、去掉放错位置的指标。
  private static func ids(_ raw: [String], placement: IndicatorID.Where) -> [IndicatorID] {
    var out: [IndicatorID] = []
    for r in raw {
      guard let id = IndicatorID(rawValue: r), id.placement == placement, !out.contains(id) else { continue }
      out.append(id)
    }
    return out
  }
}
