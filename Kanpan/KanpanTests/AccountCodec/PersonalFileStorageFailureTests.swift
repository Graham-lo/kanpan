import Foundation
import Testing
import KanpanAccount
@testable import Kanpan

/// 审查 D-07：账号目录那几份文件读写失败时，只挡出事的那一份、而且一时的失败不粘住。
/// 原来一次读失败（首解锁前、文件被占用）之后整份档案所有写都静默跳过、同步每批都抛，
/// 一直到 app 重启。
@MainActor
@Suite("账号档案 · 读写失败只挡它自己", .serialized)
struct PersonalFileStorageFailureTests {
  private let fm = FileManager.default

  private func directory() throws -> URL {
    let url = fm.temporaryDirectory.appendingPathComponent("personal-storage-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  private func chmod(_ url: URL, _ mode: Int) throws {
    try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
  }
  private func text(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }

  @Test("搜索历史读不动：偏好、自选照写，整份档案不报错")
  func unreadableSearchDoesNotBlockTheRest() throws {
    let dir = try directory(); defer { try? fm.removeItem(at: dir) }
    // search.json 是个目录：读它必然失败。
    try fm.createDirectory(at: dir.appendingPathComponent("search.json"), withIntermediateDirectories: true)
    let storage = try PersonalFileStorage(directory: dir, guest: false)
    #expect(storage.searchHistory(forKey: "k") == nil)
    storage.setPrefsData(Data(#"{"v":1}"#.utf8), forKey: PrefsCodec.key)
    storage.setSymbolPrefsData(Data(#"{"favorites":[]}"#.utf8), forKey: SymbolPrefsStore.defaultsKey)
    #expect(text(dir.appendingPathComponent("prefs.json")) == #"{"v":1}"#)
    #expect(text(dir.appendingPathComponent("symbols.json")) == #"{"favorites":[]}"#)
    #expect(storage.error == nil)
  }

  @Test("写失败一次不粘：下一次写成了就恢复，不再一错到底")
  func writeFailureIsTransient() throws {
    let dir = try directory(); defer { try? chmod(dir, 0o700); try? fm.removeItem(at: dir) }
    let storage = try PersonalFileStorage(directory: dir, guest: false)
    try chmod(dir, 0o500)
    storage.setPrefsData(Data(#"{"v":1}"#.utf8), forKey: PrefsCodec.key)
    #expect(storage.error != nil)
    try chmod(dir, 0o700)
    storage.setPrefsData(Data(#"{"v":2}"#.utf8), forKey: PrefsCodec.key)
    #expect(storage.error == nil)
    #expect(text(dir.appendingPathComponent("prefs.json")) == #"{"v":2}"#)
    // 别的文件从头到尾都没受影响。
    storage.setSymbolPrefsData(Data(#"{"favorites":[]}"#.utf8), forKey: SymbolPrefsStore.defaultsKey)
    #expect(text(dir.appendingPathComponent("symbols.json")) == #"{"favorites":[]}"#)
  }

  @Test("没读成的那份不拿空值盖；读成之后照常写")
  func unreadFileIsNotOverwrittenUntilRead() throws {
    let dir = try directory(); defer { try? fm.removeItem(at: dir) }
    let prefs = dir.appendingPathComponent("prefs.json")
    try Data(#"{"v":9,"skin":"moss"}"#.utf8).write(to: prefs)
    let storage = try PersonalFileStorage(directory: dir, guest: false)
    try chmod(prefs, 0o000)
    #expect(storage.prefsData(forKey: PrefsCodec.key) == nil)
    #expect(storage.error != nil)
    try chmod(prefs, 0o600)
    storage.setPrefsData(Data(#"{"v":1}"#.utf8), forKey: PrefsCodec.key)
    #expect(text(prefs) == #"{"v":9,"skin":"moss"}"#, "没读成的偏好被按空起步的值盖掉了")
    // 别的文件不受牵连。
    storage.setSymbolPrefsData(Data(#"{"favorites":[]}"#.utf8), forKey: SymbolPrefsStore.defaultsKey)
    #expect(text(dir.appendingPathComponent("symbols.json")) == #"{"favorites":[]}"#)
    // 再读一次读成了：恢复正常。
    #expect(storage.prefsData(forKey: PrefsCodec.key) != nil)
    #expect(storage.error == nil)
    storage.setPrefsData(Data(#"{"v":1}"#.utf8), forKey: PrefsCodec.key)
    #expect(text(prefs) == #"{"v":1}"#)
  }

  @Test("搜索历史进档案时没读成：之后记的新词接在盘上旧词前面，不顶掉整份")
  func searchHistoryMergesAfterLateRead() throws {
    let dir = try directory(); defer { try? fm.removeItem(at: dir) }
    let search = dir.appendingPathComponent("search.json")
    try JSONEncoder().encode(["btc", "sol"]).write(to: search)
    let storage = try PersonalFileStorage(directory: dir, guest: false)
    try chmod(search, 0o000)
    #expect(storage.searchHistory(forKey: "k") == nil)
    try chmod(search, 0o600)
    storage.setSearchHistory(["eth", "sol"], forKey: "k")
    #expect(storage.searchHistory(forKey: "k") == ["eth", "sol", "btc"])
  }

  @Test("prefs.json 解不开：档案照样装得上，走「损坏」那条恢复路")
  func damagedPrefsDoesNotBlockTheArchive() throws {
    let dir = try directory(); defer { try? fm.removeItem(at: dir) }
    try Data("not json".utf8).write(to: dir.appendingPathComponent("prefs.json"))
    let storage = try PersonalFileStorage(directory: dir, guest: false)
    #expect(!PrefsStore.isReadable(storage.prefsData(forKey: PrefsCodec.key)))
    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache())
    #expect(store.diagnose(storage, owner: "acct:A") == .damaged)
  }

  @Test("symbols.json 解不开仍然整段挡住（B-01：绝不拿空档盖掉自选）")
  func damagedSymbolsStillThrows() throws {
    let dir = try directory(); defer { try? fm.removeItem(at: dir) }
    try Data("not json".utf8).write(to: dir.appendingPathComponent("symbols.json"))
    #expect(throws: (any Error).self) { try PersonalFileStorage(directory: dir, guest: false) }
  }
}
