import Foundation
import KanpanCore
import KanpanAccount

/// Explicit allowlist shared by cloud preferences and review chart snapshots.
enum PersonalSyncCodec {
  /// 随账号同步的字段清单。
  ///
  /// 真身 2026-09-19 搬去了 `Prefs.syncedFieldNames`（设置包里）：脏标识要按这张表
  /// 计字段，而脏标识做在 `PrefsStore` 那一层（包里，M1 抽 `PersonalStore` 时整块搬走），
  /// 包看不见 app 靶子里的这个文件。**一份清单，两处用**——别在这儿再抄一份。
  static var fields: Set<String> { Prefs.syncedFieldNames }
  static let nested: Set<String> = ["params", "indicatorColors", "hiddenOutputs", "subHeights", "subHeightOverrides", "styles"]
  static func flatten(_ value: [String: KanpanAccount.JSONValue]) -> [String: KanpanAccount.JSONValue] {
    var result: [String: KanpanAccount.JSONValue] = [:]
    for (key, value) in value {
      if nested.contains(key), case .object(let children) = value {
        for (child, content) in children {
          if key == "indicatorColors", case .object(let outputs) = content {
            for (output, color) in outputs { result[key + "/" + child + "/" + output] = color }
          } else { result[key + "/" + child] = content }
        }
      } else { result[key] = value }
    }
    return result
  }
  static func expand(_ value: [String: KanpanAccount.JSONValue]) -> [String: KanpanAccount.JSONValue] {
    var result: [String: KanpanAccount.JSONValue] = [:]
    for (path, value) in value {
      let keys = path.split(separator: "/").map(String.init)
      if keys.count == 1 { if value != .null { result[path] = value }; continue }
      var children: [String: KanpanAccount.JSONValue] = [:]
      if case .object(let old) = result[keys[0]] { children = old }
      if keys.count == 2 { if value != .null { children[keys[1]] = value } }
      else if keys.count == 3 {
        var outputs: [String: KanpanAccount.JSONValue] = [:]
        if case .object(let old) = children[keys[1]] { outputs = old }
        if value != .null { outputs[keys[2]] = value }; children[keys[1]] = .object(outputs)
      }
      result[keys[0]] = .object(children)
    }
    return result
  }
  static func settings(_ prefs: Prefs) throws -> SyncObject {
    let all = try JSONDecoder().decode([String: KanpanAccount.JSONValue].self, from: PrefsCodec.encode(prefs))
    var object = SyncObject(collection: "settings", id: "chart")
    object.body = flatten(all.filter { fields.contains($0.key) })
    object.body["rsiRange"] = .array([.number(prefs.rsiLower), .number(prefs.rsiUpper)])
    return object
  }
  static func apply(_ object: SyncObject, to local: Prefs) throws -> Prefs {
    var all = try JSONDecoder().decode([String: KanpanAccount.JSONValue].self, from: PrefsCodec.encode(local))
    let values = expand(object.body)
    for key in fields where values[key] != nil { all[key] = values[key] }
    if case .array(let range) = values["rsiRange"], range.count == 2 { all["rsiLower"] = range[0]; all["rsiUpper"] = range[1] }
    return try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(all))
  }
  /// 换档案（登录 / 退登 / 切账号）时，从内存里那份**留在本机**、不被新档案覆盖的字段。
  ///
  /// 判据只有一条：**这是不是「这台机器自己的属性」**。行情域名与线路（`apiHost` /
  /// `streamHost` / `smartMarketRoute`）是这台手机所处网络的属性，本机缓存
  /// `launchSnapshot` 更是只对这台机器有意义，它们留在这里是对的。
  ///
  /// `interval`（周期）和 `keepAwake`（屏幕常亮）**2026-09-19 从这张表里拿掉了**：
  /// 早先把它们当成本机设置，结果是「换台设备登同一个账号，周期回到出厂 1h」。
  /// 按「用户用手改过的一切状态都跟着人走，无论怎么切换」这条规矩，看哪个周期、
  /// 要不要常亮都是他的习惯而不是这台手机的属性，所以两项改成随账号同步
  /// （已进 `fields`），不再在换档案时被上一份内存值盖住。
  ///
  /// 实现从「手抄四行赋值」改成了**按 `deviceOnly` 表在 JSON 键上覆盖**：清单只有
  /// `PrefsFieldPlan` 那一张，这儿加不加字段不再取决于下一个人记不记得回来改这里。
  static func keepDeviceFields(_ source: Prefs, in target: inout Prefs) {
    target = Prefs.keeping(Prefs.deviceOnlyFieldNames, of: source, over: target)
  }
  static func snapshot(_ prefs: Prefs) throws -> Data {
    // Format marker distinguishes the allowlisted snapshot from legacy full-Prefs drafts.
    try JSONEncoder().encode(ChartSnapshot(version: 1, fields: settings(prefs).body))
  }
  struct ChartSnapshot: Codable { var version: Int; var fields: [String: KanpanAccount.JSONValue] }
  static func snapshotPrefs(_ data: Data, base: Prefs = .defaults) throws -> Prefs {
    let value = try JSONDecoder().decode(ChartSnapshot.self, from: data)
    guard value.version == 1 else { throw AccountError.invalidResponse }
    var object = SyncObject(collection: "settings", id: "chart"); object.body = value.fields
    return try apply(object, to: base)
  }
  static func drawings(_ archive: DrawArchive) throws -> [SyncObject] {
    var output: [SyncObject] = []
    var preferences = SyncObject(collection: "drawingPreferences", id: "tools")
    preferences.body = flatten(try KanpanAccount.JSONValue.encode(archive.preferences).decode([String: KanpanAccount.JSONValue].self)); output.append(preferences)
    for (symbol, drawings) in archive.bySymbol {
      for drawing in drawings {
        var object = SyncObject(collection: "drawings", id: "binance/usd_m/" + symbol + "/" + drawing.id)
        var value = try KanpanAccount.JSONValue.encode(drawing).decode([String: KanpanAccount.JSONValue].self)
        value.removeValue(forKey: "id"); value["anchors"] = value.removeValue(forKey: "points")
        value["symbol"] = .string(symbol); value["market"] = .string("usd_m"); value["venue"] = .string("binance")
        object.body = value; output.append(object)
      }
    }
    return output
  }
  static func drawing(_ object: SyncObject) throws -> Drawing {
    var value = object.body; value["id"] = .string(String(object.id.split(separator: "/").last ?? "")); value["points"] = value.removeValue(forKey: "anchors")
    return try KanpanAccount.JSONValue.object(value).decode(Drawing.self)
  }
  static func symbols(_ prefs: SymbolPrefs) -> [SyncObject] {
    var objects: [SyncObject] = []
    for (order, group) in prefs.groups.enumerated() {
      var value = SyncObject(collection: "groups", id: group.id); value.body = ["name": .string(group.name), "order": .number(Double(order))]; objects.append(value)
    }
    for (order, symbol) in prefs.favorites.enumerated() {
      var value = SyncObject(collection: "favorites", id: "binance/usd_m/" + symbol)
      value.body = ["symbol": .string(symbol), "market": .string("usd_m"), "venue": .string("binance"), "groupId": prefs.groupForSymbol[symbol].map(KanpanAccount.JSONValue.string) ?? .null, "order": .number(Double(order)), "pinned": .bool(prefs.pinned.contains(symbol))]
      objects.append(value)
    }
    return objects
  }
}
