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
  /// 一个键一个文件。
  ///
  /// 这儿原来**根本不看 `key`**：`prefsData`/`setPrefsData` 一律读写 `prefs.json`。
  /// 单独一个偏好档的时候看不出问题，2026-09-19 把脏标识（`SettingsStamp`）也塞进
  /// 同一个柜子之后当场炸了——`PrefsStore.persist` 先把新的 `Prefs` 写进 prefs.json，
  /// 紧接着 `writeStamp()` 又拿一份 `{"dirty":…}` 覆盖了同一个文件。冷启动读回来
  /// 解不出 `Prefs`，整份退出厂值：用户捏小了图，回来是出厂的 4pt——正是他报的那个
  /// 现象，而且**丢的是整份设置**（皮肤、周期、指标……），不只根宽。
  ///
  /// 账号目录里这几份都属于「没了拿不回来」那一类，各自一个文件，谁也别压谁。
  /// 认不出的键（比如更老的 `kanpan.prefs.v1`）仍然落回 prefs.json，读老档不受影响。
  static func fileName(forKey key: String) -> String {
    switch key {
    case SettingsStamp.storageKey: return "settings-stamp.json"
    case SettingsSentinel.storageKey: return "settings-sentinel.json"
    default: return "prefs.json"
    }
  }
  func prefsData(forKey key: String) -> Data? { read(Self.fileName(forKey: key)) }
  func setPrefsData(_ data: Data?, forKey key: String) { write(data, name: Self.fileName(forKey: key)) }
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
