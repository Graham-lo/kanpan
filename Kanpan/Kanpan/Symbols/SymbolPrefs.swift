import Foundation
import KanpanCore

// ============================================================ 自选 / 最近
//
// A5.8 自选：加 / 删 / 拖排序，杀 app 重开保留。
// A5.9 最近：打开过的品种按时间倒序，最多 10 个，自动去重（§10.5）。
//
// 原型把自选放在 localStorage 的 `kanpan.v3` 里（字段 `watch`，纯数组，
// 加自选是 push 到末尾），没有「最近」这一档——原型那一栏是
// 「原型带了数据的」，是内嵌快照的产物。真 app 里那一栏就是最近。
// 差异记在 docs/acceptance/M5/品种页.md。

/// 自选与最近两份列表。纯值，全部操作都在这上面做，方便单测。
/// 解不开的那一项只丢它自己，不带垮整个数组 / 字典。
///
/// 数组里混进一个类型不对的元素（`favorites` 里躺着一个数字、`groups` 里躺着一个字符串），
/// `JSONDecoder` 默认是让**整个数组**解码失败的；这份档案里整个数组失败就等于
/// 「用户的自选整份消失」。套上这一层之后，坏的那一项解出 `nil`，别的照常。
private struct Lenient<T: Decodable>: Decodable {
  let value: T?
  init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct FavoriteGroup: Codable, Sendable, Equatable, Identifiable {
  var id: String
  var name: String

  init(id: String, name: String) { self.id = id; self.name = name }

  private enum CodingKeys: String, CodingKey { case id, name }

  /// 逐字段容错，和 `SymbolPrefs.init(from:)` 一个姿态。
  ///
  /// 这儿原来用的是**合成的 Codable**，于是 `name` 是必需的：老存档里只要有一项
  /// 缺 `name`（或者写成了别的类型），整个 `[FavoriteGroup]` 就解不开，连带整份
  /// `SymbolPrefs` 解码失败，`SymbolPrefsStore.load()` 再把失败当空档返回——
  /// 用户的自选就整份没了（B-01）。一个坏分组只该丢它自己那点东西。
  ///
  /// 名字缺了拿 `id` 顶上，不把这一类整个丢掉：`SymbolPrefs.init` 会滤掉空名的分类，
  /// 而滤掉一类等于把用户分好的那一摊自选打散，比顶一个难看的名字严重得多。
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let rawID = ((try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil) ?? ""
    let rawName = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
    id = rawID
    name = rawName.isEmpty ? rawID : rawName
  }
}

/// 一条刚被移除的自选，连同它原来站在哪儿。
///
/// 只为「已移除 · 撤销」那五秒活着：不落盘、不进同步白名单，撤销完或者提示条过期
/// 就没人再引用它。`Codable` 只是为了和这个文件里别的值类型一样好测。
struct FavoriteSnapshot: Codable, Sendable, Equatable {
  /// 已经规范化过的代号（`SymbolPrefs.key`）。
  var symbol: String
  /// 在全局 `favorites` 数组里的下标——自定义顺序的真身就是这个数组。
  var index: Int
  /// 原来属于哪一类。`nil` = 未分类。
  var group: String?
}

struct SymbolPrefs: Codable, Sendable, Equatable {
  /// 自选，用户自己的顺序（拖排序改的就是它）。
  var favorites: [String] = []
  /// 最近打开，**时间倒序**：下标 0 是最新打开的那个。
  var recents: [String] = []
  var groups: [FavoriteGroup] = []
  var groupForSymbol: [String: String] = [:]
  /// 老存档里那个「停在哪个分类」。**真身 2026-09-19 搬去了 `Prefs.favoritesGroup`**，
  /// 跟着账号走（换台设备登同一个账号，自选页还停在同一个分类上）。
  ///
  /// 这儿只剩一个读得懂老存档的壳：JSON 键仍然是 `selectedGroupID`（动了老存档就读不出来），
  /// 迁移在 `AppAccountBridge.prepare(_:)` 里做一次——搬到 `Prefs` 上，然后清空这儿。
  /// 属性名换成 `legacySelectedGroup` 是为了让下一个人一眼看出它不是真身，别再往里写。
  var legacySelectedGroup: String?
  /// 「看得勤不勤」的分数表，键是品种代号。见 `noteDwell(_:)`。
  var viewScores: [String: Double] = [:]
  /// `viewScores` 上一次衰减到的时刻（Unix 秒）。0 表示还没记过。
  var scoredAt: Double = 0

  /// 最近分区的容量（§10.5「最近分区最多 10 个」/ A5.9）。
  static let recentLimit = 10
  /// 分数的半衰期：14 天前看得再多，今天也只值一半。
  static let scoreHalfLife: Double = 14 * 86_400
  /// 分数表最多留这么多个品种，超了把最低的丢掉——它只服务「常看」那一小列。
  static let scoreCapacity = 60
  /// 低于这个分就不值得留了（约等于 14 天 × 6 个半衰期没再看过）。
  static let scoreFloor = 0.02

  init(favorites: [String] = [], recents: [String] = [], groups: [FavoriteGroup] = [],
       groupForSymbol: [String: String] = [:],
       legacySelectedGroup: String? = nil,
       viewScores: [String: Double] = [:], scoredAt: Double = 0) {
    self.viewScores = viewScores.reduce(into: [:]) { out, pair in
      let key = Self.key(pair.key)
      guard !key.isEmpty, pair.value.isFinite, pair.value > 0 else { return }
      out[key, default: 0] += pair.value
    }
    self.scoredAt = scoredAt.isFinite && scoredAt > 0 ? scoredAt : 0
    self.favorites = Self.clean(favorites)
    self.recents = Array(Self.clean(recents).prefix(Self.recentLimit))
    var seen = Set<String>()
    self.groups = groups.filter { !$0.id.isEmpty && !$0.name.isEmpty && seen.insert($0.id).inserted }
    self.groupForSymbol = InstrumentID.migrate(groupForSymbol).filter { self.favorites.contains($0.key) && seen.contains($0.value) }
    // 老存档里那个分类可能早就被删了，读进来就洗掉——免得迁移把一个指向空气的
    // id 搬进 `Prefs.favoritesGroup`。
    self.legacySelectedGroup = legacySelectedGroup.flatMap { seen.contains($0) ? $0 : nil }
  }

  private enum CodingKeys: String, CodingKey {
    // `pinned` 2026-09-24 两端删掉（界面上早就没有置顶的入口，`setPinned` 没有调用方，小组件读到的永远是空表）。老存档里
    // 那个键读的时候直接忽略，写回去就没了。
    case favorites, recents, groups, groupForSymbol, viewScores, scoredAt
    /// ⚠️ 键名不是属性名。老存档里写的是 `selectedGroupID`，不能改；
    /// 属性叫 `legacySelectedGroup`，见上面那段说明。`SymbolFieldPlan.codingKey(forProperty:)`
    /// 记着这一处错位，穷举守卫靠它对账。
    case legacySelectedGroup = "selectedGroupID"
  }
  /// **一个坏字段只丢它自己。**
  ///
  /// 原来这儿是「顶层缺 key 能容忍，类型不对就整份抛」：`scoredAt` 写成字符串、
  /// 或者 `groups` 里一项缺 `name`，`init(from:)` 就抛；`SymbolPrefsStore.load()`
  /// 又把抛当空档返回，`AppAccountBridge.prepare` 再拿这份空档把 `symbols.json`
  /// 回写一遍——用户的自选、分类全没了，而且盘上的原件也被盖掉（B-01）。
  ///
  /// 设置那一份（`PrefsCodec` 里的 `Prefs.init(from:)`）一直是逐字段容错的：
  /// 从默认值起步，每一项 `try?` 取，取不到就留默认。自选这一份是漏网的，
  /// 现在补齐成同一个姿态，数组 / 字典再往里套一层 `Lenient` 做到元素级。
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    /// 取一项：缺了、或者类型不对，都退回 `fallback`，绝不让它带垮整份档案。
    func field<T: Decodable>(_ key: CodingKeys, or fallback: T) -> T {
      ((try? values.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
    /// 取一串代号：坏的那一项跳过，剩下的一个不少。
    func list(_ key: CodingKeys) -> [String] {
      field(key, or: [Lenient<String>]()).compactMap(\.value)
    }
    /// 取一张表：值坏了的那一条跳过，剩下的一个不少。
    func table<T: Decodable>(_ key: CodingKeys, of: T.Type) -> [String: T] {
      field(key, or: [String: Lenient<T>]()).compactMapValues(\.value)
    }
    self.init(favorites: list(.favorites),
              recents: list(.recents),
              groups: field(.groups, or: [Lenient<FavoriteGroup>]()).compactMap(\.value),
              groupForSymbol: table(.groupForSymbol, of: String.self),
              legacySelectedGroup: field(.legacySelectedGroup, or: String?.none),
              viewScores: table(.viewScores, of: Double.self),
              scoredAt: field(.scoredAt, or: 0))
  }

  // ---------------------------------------------------------------- 自选

  func isFavorite(_ symbol: String) -> Bool {
    favorites.contains(Self.key(symbol))
  }

  /// 原型 `toggleWatch()`：在里面就删掉，不在就 **push 到末尾**。
  mutating func toggleFavorite(_ symbol: String, in group: String? = nil) {
    let s = Self.key(symbol)
    guard !s.isEmpty else { return }
    if favorites.contains(s) { removeFavorite(s) } else { addFavorite(s, in: group) }
  }

  /// 加一条自选，落进 `group` 那一类。
  ///
  /// `group` 就是「自选页此刻停在哪一类」，它 2026-09-19 从这份档案搬去了
  /// `Prefs.favoritesGroup`，所以由调用方灌进来。传 `nil`（或者传的那一类已经没了）
  /// 时退回第一个分类——和搬家之前 `selectedGroupID ?? groups.first?.id` 逐字同义。
  mutating func addFavorite(_ symbol: String, in group: String? = nil) {
    let s = Self.key(symbol)
    guard !s.isEmpty, !favorites.contains(s) else { return }
    favorites.append(s)
    if let group = self.group(group) { groupForSymbol[s] = group }
  }

  mutating func removeFavorite(_ symbol: String) {
    favorites.removeAll { $0 == Self.key(symbol) }
    groupForSymbol.removeValue(forKey: Self.key(symbol))
  }

  /// 移除之前先拍一张快照：它站在第几位、属于哪一类。
  ///
  /// `removeFavorite` 一次抹掉两处（全局顺序、分组归属），而 `addFavorite`
  /// 只会把它 append 到最末、分组还按「当前停在哪一类」重写——原样放回去这两样都得
  /// 事先记下来。没这个品种就返回 nil（没被移除的东西没有快照）。
  func snapshot(of symbol: String) -> FavoriteSnapshot? {
    let s = Self.key(symbol)
    guard let index = favorites.firstIndex(of: s) else { return nil }
    return FavoriteSnapshot(symbol: s, index: index,
                            group: groupForSymbol[s])
  }

  /// 照快照把它们放回原来的位置和分组（「已移除 · 撤销」走这条路）。
  ///
  /// 按下标从小到大插：快照里的下标是「移除之前」那一刻的，批量删掉三个再一起撤销时
  /// 从小到大插回去，每一个都正好落回自己原来那一格。分类可能在这五秒里被删掉了，
  /// 认不出来就让它回到「未分类」，而不是指向一个不存在的分类 id。
  mutating func restore(_ items: [FavoriteSnapshot]) {
    for item in items.sorted(by: { $0.index < $1.index }) {
      let s = Self.key(item.symbol)
      guard !s.isEmpty, !favorites.contains(s) else { continue }
      favorites.insert(s, at: min(max(item.index, 0), favorites.count))
      if let group = item.group, groups.contains(where: { $0.id == group }) {
        groupForSymbol[s] = group
      } else {
        groupForSymbol.removeValue(forKey: s)
      }
    }
  }

  /// `List.onMove` 的口径（IndexSet + 目标下标，目标是「插到原下标 destination 之前」）。
  ///
  /// SwiftUI 的 `move(fromOffsets:toOffset:)` 长在 SwiftUI 里，这个包不吃 SwiftUI，
  /// 所以自己实现一遍，语义与之相同。
  mutating func moveFavorites(from source: IndexSet, to destination: Int) {
    let valid = source.filter { $0 >= 0 && $0 < favorites.count }
    guard !valid.isEmpty else { return }
    let moving = valid.map { favorites[$0] }          // IndexSet 升序迭代，顺序不乱
    let before = valid.filter { $0 < destination }.count
    var rest = favorites
    for i in valid.sorted(by: >) { rest.remove(at: i) }
    let at = min(max(0, destination - before), rest.count)
    rest.insert(contentsOf: moving, at: at)
    favorites = rest
  }

  /// 长按拖动落点的口径：把 `symbol` 挪到 `target` 所在的位置。
  /// 往下拖时落在 target 之后，往上拖时落在 target 之前——和手指看到的一致。
  mutating func moveFavorite(_ symbol: String, onto target: String) {
    let s = Self.key(symbol), t = Self.key(target)
    guard s != t,
          let from = favorites.firstIndex(of: s),
          let to = favorites.firstIndex(of: t) else { return }
    favorites.remove(at: from)
    favorites.insert(s, at: to)
  }

  // ---------------------------------------------------------------- 自选分类

  /// 按名字取一类，没有就新开。`after` 给了而且那一类在：新开的这一类紧跟在它后面
  /// （交易所那一类要排在「美股」之后），否则排在最后。已有的分类不挪位置。
  @discardableResult
  mutating func createGroup(_ name: String, after anchor: String? = nil) -> String? {
    let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
    guard !trimmed.isEmpty else { return nil }
    if let existing = groups.first(where: { $0.name == trimmed }) { return existing.id }
    let id = UUID().uuidString
    if let anchor, let at = groups.firstIndex(where: { $0.name == anchor }) {
      groups.insert(.init(id: id, name: trimmed), at: at + 1)
    } else {
      groups.append(.init(id: id, name: trimmed))
    }
    return id
  }

  /// 删掉一类。`selected` 是删之前自选页停在哪一类。
  ///
  /// 删掉的**正好是选中的那一类**时，落单的成员进第一个分类——这一条以前靠
  /// 「`selectedGroupID == id` 就清空」实现，现在由 `group(_:)` 在读的时候接住：
  /// 那个 id 已经不在 `groups` 里了，`group(_:)` 自己就退回第一个。行为逐字不变，
  /// 而且顺带修掉了原来那条路的隐患——清空的是这份档案里的字段，调用方手里那份
  /// 「选中的分类」并不知道。
  mutating func deleteGroup(_ id: String, selected: String? = nil) {
    groups.removeAll { $0.id == id }
    groupForSymbol = groupForSymbol.filter { $0.value != id }
    classifyUnassigned(into: selected)
  }

  /// 去掉虚拟默认分类后，旧未归类成员进入当前/首个实际分类；没有分类时原样保留。
  mutating func classifyUnassigned(into group: String? = nil) {
    guard let group = self.group(group) else { return }
    for symbol in favorites where groupForSymbol[symbol] == nil { groupForSymbol[symbol] = group }
  }

  /// 「此刻该看哪一类」的唯一解法：他挑的那一类还在就是它，不在（或者还没挑过）
  /// 就是第一类，一个分类都没有就是 `nil`。
  ///
  /// 选中的分类现在存在 `Prefs.favoritesGroup` 里，而那份存档管不着这边的分类有没有被删，
  /// 所以「存回来的 id 可能已经不存在」这件事必须在**读的时候**兜住，不能指望删除那一刻
  /// 去把它清掉。空串按「还没挑过」算（`Prefs.favoritesGroup` 的出厂值就是空串）。
  func group(_ preferred: String?) -> String? {
    if let preferred, !preferred.isEmpty, groups.contains(where: { $0.id == preferred }) { return preferred }
    return groups.first?.id
  }

  mutating func assign(_ symbol: String, to group: String?) {
    let symbol = Self.key(symbol)
    guard favorites.contains(symbol) else { return }
    if let group, groups.contains(where: { $0.id == group }) { groupForSymbol[symbol] = group }
    else { groupForSymbol.removeValue(forKey: symbol) }
  }

  func favorites(in group: String?) -> [String] {
    favorites.filter { groupForSymbol[$0] == group }
  }

  /// 可见行可能按行情排序或属于某一分类，不能直接把显示索引写入全量收藏。
  mutating func moveVisible(_ visible: [String], from source: IndexSet, to destination: Int) {
    var ordered = SymbolPrefs(favorites: visible.map(Self.key).filter { favorites.contains($0) })
    ordered.moveFavorites(from: source, to: destination)
    let members = Set(ordered.favorites)
    var iterator = ordered.favorites.makeIterator()
    favorites = favorites.map { members.contains($0) ? iterator.next()! : $0 }
  }

  // ---------------------------------------------------------------- 最近

  /// 打开过一个品种：去重后插到队首，超出 10 个丢掉最旧的。
  mutating func visit(_ symbol: String) {
    let s = Self.key(symbol)
    guard !s.isEmpty else { return }
    recents.removeAll { $0 == s }
    recents.insert(s, at: 0)
    if recents.count > Self.recentLimit { recents.removeLast(recents.count - Self.recentLimit) }
  }

  // ---------------------------------------------------------------- 常看

  /// 「真的在这张图上待了一会儿」记一分。
  ///
  /// 为什么不直接拿 `recents` 当「常看」：`recents` 是**时间**倒序，搜索里滑过、
  /// 点错一下、随手翻两眼，都会把真正天天盯的那几个顶出前排；用户要的是
  /// 「哪些品种经常看，说明更有画线的需求」——那是**次数**，不是最后一次什么时候。
  ///
  /// 所以另记一份分数：看一次加 1 分，全表按 14 天半衰期衰减。半衰期是为了让口味
  /// 能变——上个月天天看的东西，这个月不看了就会自己沉下去，不必让用户去清。
  /// 调用方负责判断「待了一会儿」（见 `MainScreen` 里的停留计时），这里只管记账。
  mutating func noteDwell(_ symbol: String, now: Double = Date().timeIntervalSince1970) {
    let s = Self.key(symbol)
    guard !s.isEmpty, now.isFinite, now > 0 else { return }
    decayScores(to: now)
    viewScores[s, default: 0] += 1
    guard viewScores.count > Self.scoreCapacity else { return }
    let keep = viewScores.sorted { $0.value > $1.value }.prefix(Self.scoreCapacity)
    viewScores = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
  }

  /// 常看的品种，分数从高到低；同分按最近打开过的排前面。
  func frequent(limit: Int = 12, now: Double = Date().timeIntervalSince1970) -> [String] {
    var scores = viewScores
    Self.decay(&scores, from: scoredAt, to: now)
    let recency = Dictionary(uniqueKeysWithValues: recents.enumerated().map { ($1, $0) })
    return scores.sorted {
      if $0.value != $1.value { return $0.value > $1.value }
      return (recency[$0.key] ?? .max) < (recency[$1.key] ?? .max)
    }.prefix(limit).map(\.key)
  }

  private mutating func decayScores(to now: Double) {
    Self.decay(&viewScores, from: scoredAt, to: now)
    scoredAt = now
  }

  /// 按半衰期把整张表往下压一档，压到地板以下的直接丢掉。
  /// 时钟倒退（改过系统时间、跨设备同步）时 `elapsed <= 0`，什么都不做——
  /// 宁可这一次不衰减，也不要把分数**放大**回去。
  private static func decay(_ scores: inout [String: Double], from: Double, to now: Double) {
    let elapsed = now - from
    guard from > 0, elapsed > 0, elapsed.isFinite else { return }
    let factor = pow(0.5, elapsed / scoreHalfLife)
    guard factor.isFinite, factor < 1 else { return }
    for (key, value) in scores {
      let next = value * factor
      if next < scoreFloor { scores.removeValue(forKey: key) } else { scores[key] = next }
    }
  }

  // ---------------------------------------------------------------- 归一

  static func key(_ symbol: String) -> String {
    InstrumentID.canonical(symbol)
  }

  /// 大写 + 去空 + 去重（保序）。老存档里可能有脏数据，读进来就洗一遍。
  private static func clean(_ list: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for raw in list {
      let s = key(raw)
      guard !s.isEmpty, seen.insert(s).inserted else { continue }
      out.append(s)
    }
    return out
  }
}

// ============================================================ 落盘

/// `UserDefaults` 的最小切面，单测里换成内存假货。
protocol SymbolPrefsStorage: AnyObject {
  func symbolPrefsData(forKey key: String) -> Data?
  func setSymbolPrefsData(_ data: Data?, forKey key: String)
  /// 这个柜子是不是**测试专用的隔离仓**。
  ///
  /// 只有一处要它：UI 测试用环境变量灌自选的那条路（`SymbolPrefsStore.testSeed`）。
  /// 默认 `false`——「不写就不是隔离仓」是安全的那一侧，新写的柜子忘了表态
  /// 只会让种子不生效，而不是让种子去顶真实档案。
  var isIsolatedForTests: Bool { get }
}
extension SymbolPrefsStorage { var isIsolatedForTests: Bool { false } }

extension UserDefaults: SymbolPrefsStorage {
  func symbolPrefsData(forKey key: String) -> Data? { data(forKey: key) }
  func setSymbolPrefsData(_ data: Data?, forKey key: String) { set(data, forKey: key) }
}

/// 自选 / 最近的持久化。
///
/// **旧版落盘位置**：`UserDefaults.standard`，现行键 **`kanpan.symbols.v2`**，
/// 值是 `SymbolPrefs` 的 JSON（`{"favorites":[...],"recents":[...]}`）。
/// 分类字段增量解码，保留旧自选与最近；未分类的品种进入默认分类。
///
/// 任务书 §4.4 说设置 / 自选走「JSON + Codable 放 Application Support」。
/// 这里先落在 UserDefaults：两份列表加起来不到 1 KB，UserDefaults 本身就是
/// Application Support 下的 plist，不额外占地方，也省掉一套文件读写的错误分支。
/// 真要换成独立文件，只需给 `SymbolPrefsStorage` 换个实现。
@MainActor
final class SymbolPrefsStore {
  static let defaultsKey = "kanpan.symbols.v2"
  static let legacyDefaultsKey = "kanpan.symbols.v1"

  private let storage: SymbolPrefsStorage
  private let key: String

  /// 这台机器上这份自选档案该落在哪。**存哪儿必须在建 store 的地方写出来。**
  ///
  /// 以前 `storage` 是可选的、缺省落 `UserDefaults.standard`，于是 `SymbolPrefsStore()`
  /// 看着像「用默认的」，实际是「悄悄换了个柜子」——档案真身早就搬进了账号目录里的
  /// `symbols.json`，写在文件里、读在 UserDefaults 里，两条道（R3-1：新装机每次冷启动
  /// 都开 BTCUSDT，老用户永远停在升级那一刻的品种上）。这种「不写参数就静默换存储」
  /// 的缺省值是那个 bug 能长期不被发现的原因，所以整类去掉。
  ///
  /// 测试档那条岔路**只存在于 DEBUG**（审查 C-02）。从前它不受编译边界保护，
  /// 于是同一个 Release 包被注入 `KANPAN_TEST_PROFILE=1` 就会静默换成内存存储——
  /// 那样跑出来的绿证明的是另一套存储的行为，不是用户手上那个包的行为。
  /// 隔离真档案靠的是独立的测试安装沙盒，不是正式二进制里留一条口子。
  static func deviceStorage() -> SymbolPrefsStorage {
    #if DEBUG
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1" { return MemoryPrefsStorage() }
    #endif
    return UserDefaults.standard
  }

  init(storage: SymbolPrefsStorage, key: String = SymbolPrefsStore.defaultsKey) {
    self.storage = storage
    self.key = key
  }

  /// 读不动的档案。
  enum StoreError: Error, Equatable { case unreadable }

  /// 读。**「柜子里没有」和「有但解不动」是两件事**，这儿分开。
  ///
  /// - 柜子里压根没有这份档案（新装、还没存过、`clear()` 过）→ 合法的空档，返回 `SymbolPrefs()`。
  /// - 有档案但解不动 → 抛 `StoreError.unreadable`。
  ///
  /// 以前这两种都当「空档」返回，于是 `AppAccountBridge.prepare` 拿着一份凭空造出来的
  /// 空自选，编码之后发现和盘上的字节不一样，就把它回写进 `symbols.json`——
  /// 用户的自选被一份空档永久盖掉，而且过程里一个字的痕迹都没有（B-01）。
  /// 画线那一侧 `try drawStore.read()` 一直是抛的，能把 `prepare` 整段中断；
  /// 自选这一侧现在补齐成同一个姿态。
  ///
  /// 注意：解码本身已经是**逐字段容错**的（见 `SymbolPrefs.init(from:)`），
  /// 所以能走到这个 `throw` 的只剩「根本不是一份 JSON 对象」「零字节」这类
  /// 整份读不动的档案；局部坏只丢局部，不会连累别的字段。
  func read() throws -> SymbolPrefs {
    #if DEBUG
    if let seeded = Self.testSeed(isolated: storage.isIsolatedForTests) { return seeded }
    #endif
    guard let data = storage.symbolPrefsData(forKey: key) ?? (key == Self.defaultsKey ? storage.symbolPrefsData(forKey: Self.legacyDefaultsKey) : nil) else { return SymbolPrefs() }
    // 零字节不是「没有档案」：文件在，只是写到一半断电了。当解不动处理，
    // 免得拿空档把它盖掉之后连挽回的机会都没有。
    guard !data.isEmpty, let prefs = try? JSONDecoder().decode(SymbolPrefs.self, from: data) else {
      throw StoreError.unreadable
    }
    // 过一遍 init 的清洗（去重、大写、截断到 10）。
    return SymbolPrefs(favorites: prefs.favorites, recents: prefs.recents,
                       groups: prefs.groups, groupForSymbol: prefs.groupForSymbol,
                       legacySelectedGroup: prefs.legacySelectedGroup,
                       viewScores: prefs.viewScores, scoredAt: prefs.scoredAt)
  }

  /// 读不出来就当空档。
  ///
  /// **只给「没有档案也得开得起来」的地方用**——`SymbolPickerModel.init` 手上那份
  /// 落在本机 `UserDefaults` 的占位档案就是（真身要等 `AppAccountBridge` 把账号目录
  /// 换进来）。凡是**接下来要回写磁盘**的调用方，一律走 `read()`，
  /// 把「解不动」当异常处理，绝不能拿空档去覆盖。
  func load() -> SymbolPrefs { (try? read()) ?? SymbolPrefs() }

  #if DEBUG
  /// UI 测试沙盒里用环境变量灌进来的那份自选。
  ///
  /// 三道闸，缺一不给种子：
  /// 1. `#if DEBUG`——种子是测试脚手架，Release 包里连这段代码都不该存在。
  /// 2. 进程确实处在测试模式（`KANPAN_TEST_PROFILE=1`）。
  /// 3. **这一份档案落在隔离仓上**（`storage.isIsolatedForTests`）：内存仓，或者
  ///    `accounts/tests/<uuid>` 那棵测试子树里的档案仓。
  ///
  /// 第 3 条是这轮补的（A-07）。原来只看两个环境变量，于是「测试种子生效」和
  /// 「账号目录隔离生效」由两组互不相干的开关各自决定：桥挂在**真账号目录**上时
  /// 种子照样生效，几串环境变量就能顶掉这个账号真实的自选——而 `read()` 的结果
  /// 接着会被 `AppAccountBridge.prepare` 当成「盘上那份的最新值」回写进 `symbols.json`，
  /// 用户的自选就此被一份种子永久盖掉。现在种子只认隔离仓。
  static func testSeed(environment: [String: String] = ProcessInfo.processInfo.environment,
                       isolated: Bool) -> SymbolPrefs? {
    guard environment["KANPAN_TEST_PROFILE"] == "1", isolated,
          let seed = environment["KANPAN_TEST_FAVORITES"] else { return nil }
    return SymbolPrefs(favorites: seed.split(separator: ",").map(String.init))
  }
  #endif

  func save(_ prefs: SymbolPrefs) {
    guard let data = try? JSONEncoder().encode(prefs) else { return }
    storage.setSymbolPrefsData(data, forKey: key)
  }

  func clear() {
    storage.setSymbolPrefsData(nil, forKey: key)
    if key == Self.defaultsKey { storage.setSymbolPrefsData(nil, forKey: Self.legacyDefaultsKey) }
  }
}

/// 内存版存档，预览与单测用（不落真 UserDefaults）。
final class MemoryPrefsStorage: SymbolPrefsStorage {
  /// 内存仓天然隔离：它只活在这个进程里，谁也够不着别人的档案。
  var isIsolatedForTests: Bool { true }
  private var box: [String: Data] = [:]
  init(_ seed: [String: Data] = [:]) { box = seed }
  func symbolPrefsData(forKey key: String) -> Data? { box[key] }
  func setSymbolPrefsData(_ data: Data?, forKey key: String) { box[key] = data }
  /// 磁盘上到底躺着什么，单测里直接看。
  var raw: [String: Data] { box }
}
