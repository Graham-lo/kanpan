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

  /// 最近分区的容量（§10.5「最近分区最多 10 个」/ A5.9）。
  static let recentLimit = 10

  init(favorites: [String] = [], recents: [String] = [], groups: [FavoriteGroup] = [],
       groupForSymbol: [String: String] = [:], pinned: [String] = [], selectedGroupID: String? = nil) {
    self.favorites = Self.clean(favorites)
    self.recents = Array(Self.clean(recents).prefix(Self.recentLimit))
    var seen = Set<String>()
    self.groups = groups.filter { !$0.id.isEmpty && !$0.name.isEmpty && seen.insert($0.id).inserted }
    self.pinned = Self.clean(pinned).filter { self.favorites.contains($0) }
    self.groupForSymbol = groupForSymbol.filter { self.favorites.contains($0.key) && seen.contains($0.value) }
    self.selectedGroupID = selectedGroupID.flatMap { seen.contains($0) ? $0 : nil }
  }

  private enum CodingKeys: String, CodingKey { case favorites, recents, groups, groupForSymbol, pinned, selectedGroupID }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(favorites: try values.decodeIfPresent([String].self, forKey: .favorites) ?? [],
              recents: try values.decodeIfPresent([String].self, forKey: .recents) ?? [],
              groups: try values.decodeIfPresent([FavoriteGroup].self, forKey: .groups) ?? [],
              groupForSymbol: try values.decodeIfPresent([String: String].self, forKey: .groupForSymbol) ?? [:],
              pinned: try values.decodeIfPresent([String].self, forKey: .pinned) ?? [],
              selectedGroupID: try values.decodeIfPresent(String.self, forKey: .selectedGroupID))
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

  init(storage: SymbolPrefsStorage? = nil, key: String = SymbolPrefsStore.defaultsKey) {
    self.storage = storage ?? (ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1"
      ? MemoryPrefsStorage() : UserDefaults.standard)
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
                       groups: prefs.groups, groupForSymbol: prefs.groupForSymbol, pinned: prefs.pinned, selectedGroupID: prefs.selectedGroupID)
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
