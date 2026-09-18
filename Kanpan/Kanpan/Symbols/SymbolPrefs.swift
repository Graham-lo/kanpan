import Foundation

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
struct FavoriteGroup: Codable, Sendable, Equatable, Identifiable {
  var id: String
  var name: String
}

struct SymbolPrefs: Codable, Sendable, Equatable {
  /// 自选，用户自己的顺序（拖排序改的就是它）。
  var favorites: [String] = []
  /// 最近打开，**时间倒序**：下标 0 是最新打开的那个。
  var recents: [String] = []
  var groups: [FavoriteGroup] = []
  var groupForSymbol: [String: String] = [:]
  var pinned: [String] = []
  var selectedGroupID: String?
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
       groupForSymbol: [String: String] = [:], pinned: [String] = [], selectedGroupID: String? = nil,
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
    self.pinned = Self.clean(pinned).filter { self.favorites.contains($0) }
    self.groupForSymbol = groupForSymbol.filter { self.favorites.contains($0.key) && seen.contains($0.value) }
    self.selectedGroupID = selectedGroupID.flatMap { seen.contains($0) ? $0 : nil }
  }

  private enum CodingKeys: String, CodingKey {
    case favorites, recents, groups, groupForSymbol, pinned, selectedGroupID, viewScores, scoredAt
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(favorites: try values.decodeIfPresent([String].self, forKey: .favorites) ?? [],
              recents: try values.decodeIfPresent([String].self, forKey: .recents) ?? [],
              groups: try values.decodeIfPresent([FavoriteGroup].self, forKey: .groups) ?? [],
              groupForSymbol: try values.decodeIfPresent([String: String].self, forKey: .groupForSymbol) ?? [:],
              pinned: try values.decodeIfPresent([String].self, forKey: .pinned) ?? [],
              selectedGroupID: try values.decodeIfPresent(String.self, forKey: .selectedGroupID),
              viewScores: try values.decodeIfPresent([String: Double].self, forKey: .viewScores) ?? [:],
              scoredAt: try values.decodeIfPresent(Double.self, forKey: .scoredAt) ?? 0)
  }

  // ---------------------------------------------------------------- 自选

  func isFavorite(_ symbol: String) -> Bool {
    favorites.contains(Self.key(symbol))
  }

  /// 原型 `toggleWatch()`：在里面就删掉，不在就 **push 到末尾**。
  mutating func toggleFavorite(_ symbol: String) {
    let s = Self.key(symbol)
    guard !s.isEmpty else { return }
    if favorites.contains(s) { removeFavorite(s) } else { addFavorite(s) }
  }

  mutating func addFavorite(_ symbol: String) {
    let s = Self.key(symbol)
    guard !s.isEmpty, !favorites.contains(s) else { return }
    favorites.append(s)
    if let group = selectedGroupID ?? groups.first?.id { groupForSymbol[s] = group }
  }

  mutating func removeFavorite(_ symbol: String) {
    favorites.removeAll { $0 == Self.key(symbol) }
    groupForSymbol.removeValue(forKey: Self.key(symbol))
    pinned.removeAll { $0 == Self.key(symbol) }
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

  mutating func setPinned(_ symbol: String, _ on: Bool) {
    let symbol = Self.key(symbol)
    guard favorites.contains(symbol) else { return }
    pinned.removeAll { $0 == symbol }
    if on { pinned.append(symbol) }
  }

  // ---------------------------------------------------------------- 自选分类

  @discardableResult
  mutating func createGroup(_ name: String) -> String? {
    let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
    guard !trimmed.isEmpty else { return nil }
    if let existing = groups.first(where: { $0.name == trimmed }) { return existing.id }
    let id = UUID().uuidString
    groups.append(.init(id: id, name: trimmed))
    return id
  }

  mutating func renameGroup(_ id: String, name: String) {
    let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
    guard !trimmed.isEmpty, !groups.contains(where: { $0.id != id && $0.name == trimmed }),
          let index = groups.firstIndex(where: { $0.id == id }) else { return }
    groups[index].name = trimmed
  }

  mutating func deleteGroup(_ id: String) {
    groups.removeAll { $0.id == id }
    groupForSymbol = groupForSymbol.filter { $0.value != id }
    if selectedGroupID == id { selectedGroupID = nil }
    classifyUnassigned()
  }

  /// 去掉虚拟默认分类后，旧未归类成员进入当前/首个实际分类；没有分类时原样保留。
  mutating func classifyUnassigned() {
    guard let group = selectedGroupID ?? groups.first?.id else { return }
    for symbol in favorites where groupForSymbol[symbol] == nil { groupForSymbol[symbol] = group }
  }

  mutating func selectGroup(_ id: String) {
    guard groups.contains(where: { $0.id == id }) else { return }
    selectedGroupID = id
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
    var ordered = SymbolPrefs(favorites: visible.filter { favorites.contains($0) })
    ordered.moveFavorites(from: source, to: destination)
    let members = Set(ordered.favorites)
    var iterator = ordered.favorites.makeIterator()
    favorites = favorites.map { members.contains($0) ? iterator.next()! : $0 }
  }

  mutating func moveInGroup(_ group: String?, from source: IndexSet, to destination: Int) {
    let members = favorites(in: group)
    var scoped = SymbolPrefs(favorites: members)
    scoped.moveFavorites(from: source, to: destination)
    var ordered = scoped.favorites.makeIterator()
    let memberSet = Set(members)
    favorites = favorites.map { memberSet.contains($0) ? ordered.next()! : $0 }
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

  mutating func clearRecents() { recents.removeAll() }

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

  mutating func clearViewScores() { viewScores.removeAll(); scoredAt = 0 }

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
    symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
}

extension UserDefaults: SymbolPrefsStorage {
  func symbolPrefsData(forKey key: String) -> Data? { data(forKey: key) }
  func setSymbolPrefsData(_ data: Data?, forKey key: String) { set(data, forKey: key) }
}

/// 自选 / 最近的持久化。
///
/// **落盘位置**：`UserDefaults.standard`，键 **`kanpan.symbols.v1`**，
/// 值是 `SymbolPrefs` 的 JSON（`{"favorites":[...],"recents":[...]}`）。
/// 分类字段增量解码，保留旧自选与最近；未分类的品种进入默认分类。
///
/// 任务书 §4.4 说设置 / 自选走「JSON + Codable 放 Application Support」。
/// 这里先落在 UserDefaults：两份列表加起来不到 1 KB，UserDefaults 本身就是
/// Application Support 下的 plist，不额外占地方，也省掉一套文件读写的错误分支。
/// 真要换成独立文件，只需给 `SymbolPrefsStorage` 换个实现。
@MainActor
final class SymbolPrefsStore {
  static let defaultsKey = "kanpan.symbols.v1"

  private let storage: SymbolPrefsStorage
  private let key: String

  /// 这台机器上这份自选档案该落在哪。**存哪儿必须在建 store 的地方写出来。**
  ///
  /// 以前 `storage` 是可选的、缺省落 `UserDefaults.standard`，于是 `SymbolPrefsStore()`
  /// 看着像「用默认的」，实际是「悄悄换了个柜子」——档案真身早就搬进了账号目录里的
  /// `symbols.json`，写在文件里、读在 UserDefaults 里，两条道（R3-1：新装机每次冷启动
  /// 都开 BTCUSDT，老用户永远停在升级那一刻的品种上）。这种「不写参数就静默换存储」
  /// 的缺省值是那个 bug 能长期不被发现的原因，所以整类去掉。
  static func deviceStorage() -> SymbolPrefsStorage {
    ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1"
      ? MemoryPrefsStorage() : UserDefaults.standard
  }

  init(storage: SymbolPrefsStorage, key: String = SymbolPrefsStore.defaultsKey) {
    self.storage = storage
    self.key = key
  }

  /// 读不出来 / 解不动（老版本、被人手改坏）一律当空，绝不抛。
  func load() -> SymbolPrefs {
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1",
       let seed = ProcessInfo.processInfo.environment["KANPAN_TEST_FAVORITES"] {
      return SymbolPrefs(favorites: seed.split(separator: ",").map(String.init))
    }
    guard let data = storage.symbolPrefsData(forKey: key),
          let prefs = try? JSONDecoder().decode(SymbolPrefs.self, from: data) else { return SymbolPrefs() }
    // 过一遍 init 的清洗（去重、大写、截断到 10）。
    return SymbolPrefs(favorites: prefs.favorites, recents: prefs.recents,
                       groups: prefs.groups, groupForSymbol: prefs.groupForSymbol, pinned: prefs.pinned,
                       selectedGroupID: prefs.selectedGroupID,
                       viewScores: prefs.viewScores, scoredAt: prefs.scoredAt)
  }

  func save(_ prefs: SymbolPrefs) {
    guard let data = try? JSONEncoder().encode(prefs) else { return }
    storage.setSymbolPrefsData(data, forKey: key)
  }

  func clear() { storage.setSymbolPrefsData(nil, forKey: key) }
}

/// 内存版存档，预览与单测用（不落真 UserDefaults）。
final class MemoryPrefsStorage: SymbolPrefsStorage {
  private var box: [String: Data] = [:]
  init(_ seed: [String: Data] = [:]) { box = seed }
  func symbolPrefsData(forKey key: String) -> Data? { box[key] }
  func setSymbolPrefsData(_ data: Data?, forKey key: String) { box[key] = data }
  /// 磁盘上到底躺着什么，单测里直接看。
  var raw: [String: Data] { box }
}
