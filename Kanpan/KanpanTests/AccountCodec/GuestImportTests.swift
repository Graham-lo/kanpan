import Foundation
import Testing
import KanpanAccount
@testable import Kanpan

/// 访客档案并进账号时，同步队列里该记什么（`PersonalSyncCodec.guestImport`）。
///
/// 这里照着 `AppAccountBridge.prepare` 冷启动那一段的次序走一遍真的 `SyncStore`：
/// 已登录的人冷启动 → 先装访客档案（默认偏好写进访客目录）→ `claimGuest` 认领它 →
/// 记导入批次 → 脏标识那一步按盘上的设置再 `capture` 一次。
@MainActor @Suite("访客档案并进账号") struct GuestImportTests {
  private let device = UUID()

  private func store() throws -> SyncStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("guest-import-" + UUID().uuidString)
    return try SyncStore(directory: directory)
  }

  /// P4.5 复现的那条：B 在 T2 改了皮肤和深浅（队列里压着两条 T2 时刻的操作），
  /// 冷启动时不能因为「认领」了一份默认的访客档案，就把这两个字段以冷启动时刻重记一遍。
  @Test func coldStartOfASignedInDeviceStagesNothing() throws {
    let sync = try store()
    var mine = Prefs.defaults
    mine.skin = .classic; mine.theme = .light
    try sync.capture([PersonalSyncCodec.settings(Prefs.defaults)], device: device)
    try sync.capture([PersonalSyncCodec.settings(mine)], device: device)
    let before = sync.archive.operations.map(\.id)
    #expect(sync.archive.operations.last?.fields.keys.contains("skin") == true)

    let guestPrefs = Prefs.defaults, guestSymbols = SymbolPrefs()
    let accountSymbols = SymbolPrefs(favorites: ["binance/usd_m/DOGEUSDT", "binance/usd_m/SOLUSDT"])
    let accountBefore = PersonalSyncCodec.symbols(accountSymbols)
    let imported = try PersonalSyncCodec.guestImport(
      merged: [PersonalSyncCodec.settings(mine)] + accountBefore,
      guest: [PersonalSyncCodec.settings(guestPrefs)] + PersonalSyncCodec.symbols(guestSymbols),
      accountBefore: accountBefore, adopted: [])
    #expect(imported.isEmpty)
    try sync.capture(imported, device: device, importing: UUID())
    // 脏标识那一步：盘上是这个人自己的设置，和存档 `local` 一致，不该再生出操作。
    try sync.capture([PersonalSyncCodec.settings(mine)], device: device)
    #expect(sync.archive.operations.map(\.id) == before)
    #expect(sync.archive.local["settings:chart"]?.body["skin"] == .string("classic"))
  }

  /// 反面：整份原样导入访客那份（修之前的写法）就会多出两条——一条把 `local` 改成默认值，
  /// 一条以当下时间戳把这个人的设置重记。留着这条是为了说明上面那条断言确实咬得住。
  @Test func importingTheWholeGuestProfileRestampsTheOwnersSettings() throws {
    let sync = try store()
    var mine = Prefs.defaults
    mine.skin = .classic; mine.theme = .light
    try sync.capture([PersonalSyncCodec.settings(Prefs.defaults)], device: device)
    try sync.capture([PersonalSyncCodec.settings(mine)], device: device)
    let before = sync.archive.operations.count
    try sync.capture([PersonalSyncCodec.settings(Prefs.defaults)], device: device, importing: UUID())
    try sync.capture([PersonalSyncCodec.settings(mine)], device: device)
    #expect(sync.archive.operations.count == before + 2)
    #expect(sync.archive.operations.last?.fields.keys.contains("theme") == true)
  }

  /// 第一次在这台设备上登录：访客的设置整份被采用、访客新加的自选接在账号原有的后面，
  /// 这些照旧要记进导入批次；两边都有的那只不记。
  @Test func firstSignInImportsWhatTheGuestBroughtIn() throws {
    var guestPrefs = Prefs.defaults
    guestPrefs.skin = .terra
    let guestSymbols = SymbolPrefs(favorites: ["binance/usd_m/ETHUSDT", "binance/usd_m/BTCUSDT"])
    let accountSymbols = SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"])
    let merged = SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    let imported = try PersonalSyncCodec.guestImport(
      merged: [PersonalSyncCodec.settings(guestPrefs)] + PersonalSyncCodec.symbols(merged),
      guest: [PersonalSyncCodec.settings(guestPrefs)] + PersonalSyncCodec.symbols(guestSymbols),
      accountBefore: PersonalSyncCodec.symbols(accountSymbols), adopted: ["settings"])
    #expect(imported.map(\.key).sorted() == ["favorites:binance/usd_m/ETHUSDT", "settings:chart"])
    // 接在后面：`order` 取合并后的位置，不是它在访客列表里的位置。
    #expect(imported.first { $0.collection == "favorites" }?.body["order"] == .number(1))
    #expect(imported.first { $0.collection == "settings" }?.body["skin"] == .string("terra"))
  }
}
