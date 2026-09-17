import Foundation
import Observation

// ============================================================ 历史搜索
//
// 搜索页上方那一排「历史搜索」词条（原型 `header-search-2026-09-17.html` 的 `.hchips`）。
//
// **为什么不塞进 `SymbolPrefs`**：那一份是随账号同步的（`AppAccountBridge`），
// 换个账号会被整份覆盖；而且 `SymbolPrefsStore.load()` 是一个字段一个字段重建的，
// 多加一个字段等于要同时改同步那一侧。搜索词是「这台机器上我刚才在找什么」，
// 本来就不该跟着账号跑，所以单开一个只记在本机的小仓。

/// 存储口子。测试塞内存实现，app 用 `UserDefaults`。
protocol SearchHistoryStorage: AnyObject {
  func searchHistory(forKey key: String) -> [String]?
  func setSearchHistory(_ value: [String]?, forKey key: String)
}

extension UserDefaults: SearchHistoryStorage {
  func searchHistory(forKey key: String) -> [String]? { stringArray(forKey: key) }
  func setSearchHistory(_ value: [String]?, forKey key: String) { set(value, forKey: key) }
}

final class MemorySearchHistoryStorage: SearchHistoryStorage {
  private var box: [String: [String]] = [:]
  init() {}
  func searchHistory(forKey key: String) -> [String]? { box[key] }
  func setSearchHistory(_ value: [String]?, forKey key: String) { box[key] = value }
}

/// 最近搜过的词。新的在前、去重、按 `limit` 截断。
@MainActor
@Observable
final class SearchHistory {
  static let defaultsKey = "kanpan.searchHistory.v1"
  /// 一行放得下的量。原型那一排是两行封顶，10 个正好。
  static let limit = 10
  /// 一个词最长记多少个字符。搜索框可以粘一整段进去，别让它撑坏那一排。
  static let maxTermLength = 24

  private(set) var terms: [String] = []

  @ObservationIgnored private let storage: SearchHistoryStorage
  @ObservationIgnored private let key: String

  init(storage: SearchHistoryStorage? = nil, key: String = SearchHistory.defaultsKey) {
    self.storage = storage ?? (ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1"
      ? MemorySearchHistoryStorage() : UserDefaults.standard)
    self.key = key
    terms = Self.clean(self.storage.searchHistory(forKey: self.key) ?? [])
  }

  /// 记一个词。空白、太长、重复都在这儿收拾干净。
  func remember(_ raw: String) {
    let term = Self.normalize(raw)
    guard !term.isEmpty else { return }
    var next = terms.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
    next.insert(term, at: 0)
    terms = Array(next.prefix(Self.limit))
    save()
  }

  func remove(_ term: String) {
    let before = terms.count
    terms.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
    guard terms.count != before else { return }
    save()
  }

  func clear() {
    guard !terms.isEmpty else { return }
    terms = []
    save()
  }

  private func save() { storage.setSearchHistory(terms.isEmpty ? nil : terms, forKey: key) }

  /// 去空白、截长度。大小写原样留着——用户打的是 `btc` 就显示 `btc`。
  static func normalize(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(trimmed.prefix(maxTermLength))
  }

  /// 从盘上读出来的东西：修得好就用，修不好丢掉。
  static func clean(_ raw: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for item in raw {
      let term = normalize(item)
      guard !term.isEmpty, seen.insert(term.lowercased()).inserted else { continue }
      out.append(term)
      if out.count == limit { break }
    }
    return out
  }
}
