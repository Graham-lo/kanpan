import Foundation
import KanpanAccount

/// Adapter for the existing stores: account integration does not replace their models or UI.
final class PersonalFileStorage: PrefsStorage, SymbolPrefsStorage, SearchHistoryStorage, @unchecked Sendable {
  private let directory: URL
  private let lock = NSLock()
  /// 在盘上、却还没读成过的文件。内存里那一份不是从它来的（读失败时调用方拿到的是
  /// `nil`、按空档起步），所以**不许拿来盖它**；下一次读成了就消。
  ///
  /// 原来这儿是一个整份的 `failed`（审查 D-07）：任何一个文件读失败一次——首解锁前、
  /// 文件被短暂占用——之后这份档案**所有**文件的写都静默跳过，`applyPending` 每一批都
  /// 因为 `error != nil` 抛出、同步就此卡死，这次会话里改的设置、自选全部没落盘，界面上
  /// 一个字的提示都没有，而且没有任何一条路能把它清掉。现在按文件记：哪个没读成只挡哪个。
  private var unread: Set<String> = []
  /// 最近一次写没写成的文件。写失败是一时的（盘满、被占用），下一次写成了就消，
  /// 不再一错到底。
  private var unwritten: Set<String> = []
  /// 这份档案的正式文件（偏好、脏标识、哨兵、自选）眼下是不是有没读成 / 没写成的。
  /// 调用方（`AppAccountBridge.prepare` / `applyPending`）写完一轮看它，有就整批作废、
  /// 下次重来。`search.json` 不算：最近搜过的词写不进去，不该把整套同步拦下来。
  var error: String? {
    lock.lock(); defer { lock.unlock() }
    let blocking = unread.union(unwritten).subtracting(Self.nonEssential)
    return blocking.isEmpty ? nil : AccountError.storage.localizedDescription
  }
  private static let nonEssential: Set<String> = ["search.json"]
  /// 这份档案收不收 UI 测试的自选种子：落在**测试专用的那棵子树**里（`accounts/tests/<uuid>/…`），
  /// 而且是**访客档案**。
  ///
  /// `AppAccountBridge.init` 只有在 `KANPAN_TEST_PROFILE=1` 且拿到一个合法 UUID 时
  /// 才会把根换到 `accounts/tests/<uuid>`，所以这条路径本身就是「隔离上下文成套成立」
  /// 的凭证。唯一的用处是给 UI 测试的自选种子当闸（`SymbolPrefsStore.testSeed`）：
  /// 挂在真账号目录上的这份档案永远答 `false`，种子顶不掉用户真实的自选。
  ///
  /// 测试子树里的**账号**档案也答 `false`：账号的自选要像真用户那样，登录时从访客档案认领、
  /// 之后读盘上那份（理由见 `SymbolPrefsStore.testSeed` 第 3 条）。
  let takesTestSeed: Bool
  /// `guest`：这是访客档案（没登录时那一份、或者登录时被认领的那一份）。
  init(directory: URL, guest: Bool) throws {
    self.directory = directory
    self.takesTestSeed = guest && directory.path.contains("/kanpan/accounts/tests/")
    // 只确认 symbols.json 是一份读得动的 JSON 对象（解不开的自选由 `SymbolPrefsStore.read()`
    // 再挡一道，整段 `prepare` 中断，见那里 B-01 的说明）。**版本号不在这儿判**：以前这里撞上
    // 对不上的版本就 `throw`，于是 `AppAccountBridge.init` 整个失败——用户一升级
    // （或者从新版本降回来）就连账号档案都挂不上，自选、画线、偏好全看不见。
    //
    // prefs.json **不在这儿判**：解不开的偏好有一整条恢复路（`SettingsCacheVerdict.damaged`
    // → `SettingsRecovery`：同步存档里那份优先、没有才回落云端），原件在第一次被改写前
    // 由 `backupOnce` 留一份。以前这儿见它解不开就 `throw`，那条恢复路根本走不到——
    // 这个人在这台机器上的档案从此一次都装不上。
    let url = directory.appendingPathComponent("symbols.json")
    if FileManager.default.fileExists(atPath: url.path) {
      let data = try Data(contentsOf: url)
      guard (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil else { throw AccountError.storage }
    }
  }
  private func read(_ name: String) -> Data? {
    lock.lock(); defer { lock.unlock() }
    let url = directory.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else { unread.remove(name); return nil }
    do {
      let data = try Data(contentsOf: url)
      unread.remove(name)
      return data
    } catch {
      unread.insert(name)
      return nil
    }
  }
  private func write(_ data: Data?, name: String) {
    lock.lock(); defer { lock.unlock() }
    // 没读成的那份不是「空」，不能拿内存里按空起步的值盖掉原件。只挡这一个文件。
    guard !unread.contains(name) else { return }
    do {
      let url = directory.appendingPathComponent(name)
      if let data {
        try Self.backupOnce(url)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      }
      else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
      unwritten.remove(name)
    } catch { unwritten.insert(name) }
  }
  /// 覆盖之前留一份一次性备份。
  ///
  /// 这套「读不动就拒绝覆盖 + 覆盖前留 `.backup`」原来只有画线有
  /// （`Kanpan/Kanpan/Drawing/DrawStore.save`）。账号目录里这几份都属于「没了拿不回来」
  /// 那一类，凭什么只有画线有？所以搬到这一层，`prefs.json` 与 `symbols.json`
  /// 一视同仁——上面那道 `guard !unread.contains(name)` 是「读失败拒绝覆盖」那一半，
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
    var next = value
    // 进档案那一下没读成（首解锁前被拉起之类），内存里那份是从空起步的：这会儿再读一次，
    // 读成了把盘上的旧词接在新词后面，不让刚记的一个词把整份历史顶掉（`SearchHistory`
    // 下次装档案时按上限裁）。清空（`nil`）是人亲手点的，照清。
    if let fresh = value, isUnread("search.json"), let data = read("search.json") {
      let old = (try? JSONDecoder().decode([String].self, from: data)) ?? []
      next = fresh + old.filter { !fresh.contains($0) }
    }
    write(next.flatMap { try? JSONEncoder().encode($0) }, name: "search.json")
  }
  private func isUnread(_ name: String) -> Bool { lock.lock(); defer { lock.unlock() }; return unread.contains(name) }
}
