import Foundation
import KanpanAccount

/// Adapter for the existing stores: account integration does not replace their models or UI.
final class PersonalFileStorage: PrefsStorage, SymbolPrefsStorage, SearchHistoryStorage, @unchecked Sendable {
  private let directory: URL
  private let lock = NSLock()
  private var failed: String?
  var error: String? { lock.lock(); defer { lock.unlock() }; return failed }
  init(directory: URL) throws {
    self.directory = directory
    for name in ["prefs.json", "symbols.json"] {
      let url = directory.appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: url.path) {
        let data = try Data(contentsOf: url)
        // 只确认它是一份读得动的 JSON 对象。**版本号不在这儿判**：以前这里撞上
        // 对不上的版本就 `throw`，于是 `AppAccountBridge.init` 整个失败——用户一升级
        // （或者从新版本降回来）就连账号档案都挂不上，自选、画线、偏好全看不见。
        // 版本差异交给 `Prefs.init(from:)` 逐字段容错 + `PrefsCodec.migrate` 处理。
        guard (try JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil else { throw AccountError.storage }
      }
    }
  }
  private func read(_ name: String) -> Data? {
    lock.lock(); defer { lock.unlock() }
    let url = directory.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do { return try Data(contentsOf: url) } catch { failed = AccountError.storage.localizedDescription; return nil }
  }
  private func write(_ data: Data?, name: String) {
    lock.lock(); defer { lock.unlock() }
    // A read failure is not a valid empty value and must not overwrite the original file.
    guard failed == nil else { return }
    do {
      let url = directory.appendingPathComponent(name)
      if let data { try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
      else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    } catch { failed = AccountError.storage.localizedDescription }
  }
  func prefsData(forKey key: String) -> Data? { read("prefs.json") }
  func setPrefsData(_ data: Data?, forKey key: String) { write(data, name: "prefs.json") }
  func symbolPrefsData(forKey key: String) -> Data? { read("symbols.json") }
  func setSymbolPrefsData(_ data: Data?, forKey key: String) { write(data, name: "symbols.json") }
  /// 最近搜过的词。按身份存——同一台机器上 A 退出、B 登录，B 不该看见 A 搜过什么。
  func searchHistory(forKey key: String) -> [String]? {
    guard let data = read("search.json") else { return nil }
    return try? JSONDecoder().decode([String].self, from: data)
  }
  func setSearchHistory(_ value: [String]?, forKey key: String) {
    write(value.flatMap { try? JSONEncoder().encode($0) }, name: "search.json")
  }
}
