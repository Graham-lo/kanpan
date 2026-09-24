import Foundation
import KanpanAccount

/// Adapter for the existing stores: account integration does not replace their models or UI.
final class PersonalFileStorage: PrefsStorage, SymbolPrefsStorage, SearchHistoryStorage, @unchecked Sendable {
  private let directory: URL
  private let lock = NSLock()
  private var failed: String?
  var error: String? { lock.lock(); defer { lock.unlock() }; return failed }
  /// 这份档案是不是落在**测试专用的那棵子树**里（`accounts/tests/<uuid>/…`）。
  ///
  /// `AppAccountBridge.init` 只有在 `KANPAN_TEST_PROFILE=1` 且拿到一个合法 UUID 时
  /// 才会把根换到 `accounts/tests/<uuid>`，所以这条路径本身就是「隔离上下文成套成立」
  /// 的凭证。唯一的用处是给 UI 测试的自选种子当闸（`SymbolPrefsStore.testSeed`）：
  /// 挂在真账号目录上的这份档案永远答 `false`，种子顶不掉用户真实的自选。
  let isIsolatedForTests: Bool
  init(directory: URL) throws {
    self.directory = directory
    self.isIsolatedForTests = directory.path.contains("/kanpan/accounts/tests/")
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
      if let data {
        try Self.backupOnce(url)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      }
      else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    } catch { failed = AccountError.storage.localizedDescription }
  }
  /// 覆盖之前留一份一次性备份。
  ///
  /// 这套「读不动就拒绝覆盖 + 覆盖前留 `.backup`」原来只有画线有
  /// （`Kanpan/Kanpan/Drawing/DrawStore.save`）。账号目录里这几份都属于「没了拿不回来」
  /// 那一类，凭什么只有画线有？所以搬到这一层，`prefs.json` 与 `symbols.json`
  /// 一视同仁——上面那道 `guard failed == nil` 是「读失败拒绝覆盖」那一半，
  /// 这儿是「留一份原件」那一半。
  ///
  /// **一次性**：备份只在还没有备份时留，之后再怎么写都不动它，和 `DrawStore` 逐字同义。
  /// 它兜的是「这份档案第一次被程序改写之前长什么样」——真出事时那一份才是完整的，
  /// 每次写都刷新的话，坏掉的那一版第二次写就把好的那份盖了。
  private static func backupOnce(_ url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let backup = url.appendingPathExtension("backup")
    guard !FileManager.default.fileExists(atPath: backup.path) else { return }
    try FileManager.default.copyItem(at: url, to: backup)
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
