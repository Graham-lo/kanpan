import Foundation

// MARK: - 自选档案里哪些跟着人走

/// `SymbolPrefs` 的一个存储字段跟着谁走。
///
/// ## 判据（和 `PrefsFieldPlan` 是同一条，别再发明第二条）
///
/// **用手改出来的习惯 → 跟着人走；自动累积的统计 / 这台机器的属性 → 留在本机。**
///
/// 为什么这张表不和 `PrefsFieldPlan` 合成一张：`SymbolPrefs` 住在 `KanpanSymbols` 包里，
/// 那个包只依赖 `KanpanCore`，**看不见 `KanpanSettings`**；反过来把它放进设置包，
/// 设置包就得认识自选档案，方向更糟。所以按依赖方向，表跟着被它描述的那个类型走：
/// `Prefs` 的表在 `Kanpan/Settings/Model/PrefsFieldPlan.swift`，这一张在自选这边。
/// 两张表各有一条穷举守卫钉着（`PrefsFieldPlanTests` / `SymbolFieldPlanTests`）。
enum SymbolFieldClass: String, Sendable, CaseIterable {
  /// 随账号同步。**服务端存的不是这个字段本身**——自选与分类在线上是
  /// `favorites` / `groups` 两张表（一条自选一个对象），见 `PersonalSyncCodec.symbols`。
  /// 这一档的意思是「云端那几张表能把它整份重建出来」。
  case synced
  /// 留在本机：云端没有它，同步重建这份档案时必须从本机那一份原样抄回去
  /// （`AppAccountBridge.applyPending`），否则每来一次同步就把它清零。
  case localOnly
}

/// **`SymbolPrefs` 的每一个存储字段归哪一类，只在这儿写一次。**
///
/// 存在的理由和 `PrefsFieldPlan` 一样：这件事以前散在几处手抄的清单里，两天里咬了两次
/// （提交 `a161bb0`、`0f09f7e`）。这儿最要命的一处是 `AppAccountBridge.applyPending` 里
/// 那行手写的 `SymbolPrefs(favorites:recents:groups:…)`——少抄一个本机字段，
/// 症状是「每同步一次，常看/最近就被清空一次」，而且不会有任何报错。
enum SymbolFieldPlan {
  /// **键是 JSON 里的键名**（`SymbolPrefs` 的 `CodingKeys`），不是存储属性名。
  /// 两者今天只有一处对不上，见 `codingKey(forProperty:)`。
  static let table: [String: SymbolFieldClass] = [
    // ---------------------------------------------------------------- 跟着人走
    // 他收藏了哪些、分成哪几类、哪个在哪一类——全是用手摆出来的。
    // （`pinned` 2026-09-24 两端删掉：没有入口，线上的 `favorites` 对象也不再带它。）
    "favorites": .synced, "groups": .synced, "groupForSymbol": .synced,

    // ---------------------------------------------------------------- 留在这台机器上
    // 「最近打开过哪些品种」：每开一张图就变一次的流水，不是他摆出来的样子。
    // 跟着人走意味着每点一个品种就生成一条同步操作，代价远大于收益。
    "recents": .localOnly,
    // 「哪些品种看得勤」的分数表和它的衰减时刻：**自动累积的统计**，同上。
    // 它俩还有一条额外的理由——分数是按「在这台设备上待了多久」记的，
    // 把 A 手机的停留时长搬到 B 手机上，得到的是一份谁也不认识的排行。
    "viewScores": .localOnly, "scoredAt": .localOnly,
    // 老存档里那个「停在哪个分类」。2026-09-19 真身搬去了 `Prefs.favoritesGroup`
    // （跟着账号走），这儿只剩一个**读得懂老存档**的壳：迁移在
    // `AppAccountBridge.prepare` 里把它搬到 `Prefs` 上并清空。
    // 它留在 `localOnly` 而不是删掉，是因为迁移发生之前它得能被读出来；
    // 真删掉这个键，升级那一刻用户停在哪一类就丢了。
    "selectedGroupID": .localOnly,
  ]

  /// 这一类的全部键名。
  static func names(_ kind: SymbolFieldClass) -> Set<String> {
    Set(table.compactMap { $0.value == kind ? $0.key : nil })
  }

  /// 存储属性名 → JSON 键名。
  ///
  /// `legacySelectedGroup` 是唯一一个对不上的：属性改了名字（好让人一眼看出它是老存档的
  /// 遗留物），**键名一个字都不能动**——动了老存档里那个值就读不出来了。
  static func codingKey(forProperty property: String) -> String {
    property == "legacySelectedGroup" ? "selectedGroupID" : property
  }
}

extension SymbolPrefs {
  /// 云端重建这份档案时，**从本机那一份原样抄回去**的那些键。
  static let localOnlyFieldNames: Set<String> = SymbolFieldPlan.names(.localOnly)

  /// 把 `fields` 这几个键从 `local` 抄回 `incoming` 那一份上。
  ///
  /// 和 `Prefs.keeping(_:of:over:)` 是同一个写法：**在 JSON 键上覆盖**，而不是手写一串
  /// 赋值。清单只有 `SymbolFieldPlan` 那一张，下一个往这份档案里加本机字段的人
  /// 不必记得回 `AppAccountBridge` 补一行——他记不住，穷举守卫会替他记。
  static func keeping(_ fields: Set<String>, of local: SymbolPrefs, over incoming: SymbolPrefs) -> SymbolPrefs {
    guard !fields.isEmpty else { return incoming }
    var target = fieldMap(incoming)
    let source = fieldMap(local)
    guard !target.isEmpty, !source.isEmpty else { return incoming }
    // 本机那份缺这个键（可选字段是 nil，`encodeIfPresent` 不写它），就把云端那份上的
    // 同名键也去掉——「本机没有」和「本机是 nil」在这儿是同一件事。
    for name in fields { target[name] = source[name] }
    guard let data = try? JSONSerialization.data(withJSONObject: target),
          let value = try? JSONDecoder().decode(SymbolPrefs.self, from: data) else { return incoming }
    return value
  }

  private static func fieldMap(_ prefs: SymbolPrefs) -> [String: Any] {
    guard let data = try? JSONEncoder().encode(prefs) else { return [:] }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
  }
}
