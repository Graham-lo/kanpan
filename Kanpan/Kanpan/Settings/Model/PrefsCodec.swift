import Foundation
import KanpanCore

// MARK: - 落盘格式

/// 存档的读写与版本策略（A6.12 / A6.13）。
///
/// **键**：`kanpan.prefs.v1`。任务书 §3.2 与原型 `SAVE = 'kanpan.v3'` 是同一条规矩：
/// **改默认值就跳版本号**，免得老存档把新默认盖掉。
///
/// 跳版本号之后老存档不是被丢掉，而是**逐字段并进新默认**：
///
/// 1. 写只写当前键；
/// 2. 读先看当前键，没有就按 `legacyKeys` 从新到旧回落，读到哪个算哪个；
/// 3. 不论从哪个版本读出来，缺的字段、认不出来的字段、类型不对的字段，
///    一律取**新默认**，其余原样保留——不整体覆盖，也不整体作废。
///
/// 所以 A6.13 那条断言（旧版本存档 + 新默认）成立的前提就写在 `decode` 里：
/// 解码从 `Prefs.defaults` 起步，存档只负责往上盖它真有的那几项。
enum PrefsCodec {
  /// 当前存档版本。**改任何一个默认值都要把它 +1**。
  static let version = 1
  static let keyPrefix = "kanpan.prefs.v"

  /// 写进 `UserDefaults` 的那个键。
  static var key: String { key(version: version) }
  static func key(version: Int) -> String { "\(keyPrefix)\(version)" }

  /// 从新到旧的历史键。`version == 1` 时是空的。
  static var legacyKeys: [String] { legacyKeys(version: version) }
  static func legacyKeys(version: Int) -> [String] {
    guard version > 1 else { return [] }
    return (1..<version).reversed().map { key(version: $0) }
  }

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
    case priceMode, magnet, countdown, keepAwake, launchSnapshot, timeZone
    case overlays, subs, params, subHeights
    case apiHost, streamHost
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(PrefsCodec.version, forKey: .v)
    try c.encode(interval.rawValue, forKey: .interval)
    try c.encode(quickIntervals.map(\.rawValue), forKey: .quickIntervals)
    try c.encode(theme.rawValue, forKey: .theme)
    try c.encode(styleID, forKey: .styleID)
    try c.encode(redUp, forKey: .redUp)
    try c.encode(priceMode.rawValue, forKey: .priceMode)
    try c.encode(magnet, forKey: .magnet)
    try c.encode(countdown, forKey: .countdown)
    try c.encode(keepAwake, forKey: .keepAwake)
    try c.encode(launchSnapshot, forKey: .launchSnapshot)
    try c.encode(timeZone.rawValue, forKey: .timeZone)
    try c.encode(overlays.map(\.rawValue), forKey: .overlays)
    try c.encode(subs.map(\.rawValue), forKey: .subs)
    // 字典键是 enum，直接 encode 会变成交错数组；摊成 [String: …] 才是人能看懂的 JSON。
    try c.encode(Dictionary(uniqueKeysWithValues: params.map { ($0.key.rawValue, $0.value) }),
                 forKey: .params)
    try c.encode(Dictionary(uniqueKeysWithValues: subHeights.map { ($0.key.rawValue, $0.value.rawValue) }),
                 forKey: .subHeights)
    try c.encode(apiHost, forKey: .apiHost)
    try c.encode(streamHost, forKey: .streamHost)
  }

  init(from decoder: Decoder) throws {
    // 从新默认起步：存档只往上盖它真有的那几项（A6.13）。
    self = .defaults
    guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }

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
    // 认不出来的风格 id 退回「墩」，不是留着一个画不出来的名字。
    if let raw = str(.styleID), CandleStyle.all.contains(where: { $0.id == raw }) { styleID = raw }
    if let v = bool(.redUp) { redUp = v }

    if let raw = str(.priceMode), let v = PriceMode(rawValue: raw) { priceMode = v }
    if let v = bool(.magnet) { magnet = v }
    if let v = bool(.countdown) { countdown = v }
    if let v = bool(.keepAwake) { keepAwake = v }
    if let v = bool(.launchSnapshot) { launchSnapshot = v }
    if let raw = str(.timeZone), let v = TZChoice(rawValue: raw) { timeZone = v }

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

    if let raw = (try? c.decodeIfPresent([String: String].self, forKey: .subHeights)) ?? nil {
      var out: [IndicatorID: SubPaneHeight] = [:]
      for (k, v) in raw {
        guard let id = IndicatorID(rawValue: k), let h = SubPaneHeight(rawValue: v) else { continue }
        out[id] = h
      }
      subHeights = out
    }

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
