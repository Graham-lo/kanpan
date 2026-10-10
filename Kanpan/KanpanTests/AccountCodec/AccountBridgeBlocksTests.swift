import Foundation
import Testing
import KanpanCore
import KanpanAccount
import ReviewUI
@testable import Kanpan

/// 账号桥 2026-10-10 拆成几块之后，每一块离开 `AppAccountBridge` 也能单独建起来、单独干活。
///
/// 不是行为全集（同步语义各有各的用例），只钉住「这一块不靠别的块、依赖都从外面递进来」：
/// 记账（`SyncRecorder`）、应用远端（`SyncApplier`）、起停调度（`SyncLifecycle`）、
/// 换人（`AccountProfileSwitcher`）。
@MainActor
@Suite("账号桥拆分 · 各块独立构造", .serialized)
struct AccountBridgeBlocksTests {
  private static func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-blocks-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  private static func account() -> AccountFeature {
    AccountFeature(client: nil, defaults: UserDefaults(suiteName: "bridge-blocks-" + UUID().uuidString)!)
  }
  private static func prefs() -> PrefsStore {
    PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache(), sentinel: InMemoryPrefsStorage())
  }
  private static func symbols() -> SymbolPickerModel {
    SymbolPickerModel(store: SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "bridge-blocks"))
  }
  /// 登录态的一份档案：有主人、有柜子、有同步存档。
  private static func signedIn(_ url: URL) throws -> ActiveProfile {
    let profile = ActiveProfile()
    profile.owner = UUID()
    profile.personal = try PersonalFileStorage(directory: url, guest: false)
    profile.sync = try SyncStore(directory: url)
    return profile
  }

  @Test("记账：保护区里一条都不记；出了保护区改设置记成一条待发操作，并响一次 onRecorded")
  func recorderStandsAlone() throws {
    let url = try Self.directory(); defer { try? FileManager.default.removeItem(at: url) }
    let profile = try Self.signedIn(url)
    let recorder = SyncRecorder(profile: profile, account: Self.account(), prefs: Self.prefs(), symbols: Self.symbols(),
                                drawings: DrawingController(store: DrawStore(url: url.appendingPathComponent("draws.json"))),
                                alerts: AlertStore(store: AlertFileStore(url: url.appendingPathComponent("alerts.json"))))
    var recorded = 0
    recorder.onRecorded = { recorded += 1 }

    profile.gate.enter()
    recorder.captureSettings()
    #expect(recorded == 0)
    #expect(profile.sync?.archive.operations.isEmpty == true)

    profile.gate.leave()
    recorder.captureSettings()
    #expect(recorded == 1)
    #expect(profile.sync?.archive.operations.contains { $0.collection == "settings" } == true)
    profile.sync?.flushNow()
  }

  @Test("应用远端：canApply 挡住时记下欠装，放行后 resumeApply 补上（没有要装的表就只记一笔）")
  func applierStandsAlone() throws {
    let url = try Self.directory(); defer { try? FileManager.default.removeItem(at: url) }
    let profile = try Self.signedIn(url)
    let applier = SyncApplier(profile: profile, prefs: Self.prefs(), symbols: Self.symbols(),
                              drawings: DrawingController(store: DrawStore(url: url.appendingPathComponent("draws.json"))),
                              alerts: AlertStore(store: AlertFileStore(url: url.appendingPathComponent("alerts.json"))))
    var allowed = false, statusUpdates = 0, ready = 0
    applier.canApply = { allowed }
    applier.updateStatus = { statusUpdates += 1 }
    applier.onProfileReady = { ready += 1 }

    try applier.applyPending()
    #expect(applier.pendingApply)
    applier.resumeApply()
    #expect(applier.pendingApply, "还挡着，补跑也不动")
    #expect(statusUpdates == 0)

    allowed = true
    applier.resumeApply()
    #expect(!applier.pendingApply)
    #expect(statusUpdates == 1)
    // 新存档里没有云端改过的表：不合并、不发布，宿主不被惊动。
    #expect(ready == 0)
    profile.sync?.flushNow()
  }

  @Test("起停调度：账号页状态数只读档案；没登录不起一轮，登录了但没客户端也不起")
  func lifecycleStandsAlone() throws {
    let url = try Self.directory(); defer { try? FileManager.default.removeItem(at: url) }
    let account = Self.account()
    let guest = ActiveProfile()
    let idle = SyncLifecycle(profile: guest, account: account, prefs: Self.prefs(), review: ReviewFeature())
    idle.updateStatus()
    #expect(account.syncStatus == "")
    idle.focus("BTCUSDT")
    idle.synchronize(manual: true)
    #expect(account.syncStatus == "", "没登录：一轮都不起")

    let profile = try Self.signedIn(url)
    let lifecycle = SyncLifecycle(profile: profile, account: account, prefs: Self.prefs(), review: ReviewFeature())
    var applied = 0
    lifecycle.applyIfDue = { _ in applied += 1 }
    lifecycle.updateStatus()
    #expect(account.syncStatus == "尚未同步")
    #expect(account.pending == 0)
    lifecycle.synchronize(manual: true)
    #expect(account.syncStatus == "尚未同步", "没有客户端：guard 在起跑前就挡住")
    #expect(applied == 0)
    lifecycle.endRound(); lifecycle.forgetBootstrap()
    #expect(SyncLifecycle.pendingCount(operations: 2, reviewUploads: 1) == 3)
  }

  @Test("换人：访客档案 prepare → 提交，钩子按原顺序各响一次，档案就位；同一个属主再 prepare 不重装")
  func switcherStandsAlone() throws {
    let root = try Self.directory(); defer { try? FileManager.default.removeItem(at: root) }
    let files = try AccountFiles(root: root)
    let profile = ActiveProfile()
    let switcher = AccountProfileSwitcher(profile: profile, files: files, account: Self.account(), prefs: Self.prefs(),
                                          symbols: Self.symbols(),
                                          drawings: DrawingController(store: DrawStore(url: root.appendingPathComponent("legacy-draws.json"))),
                                          alerts: AlertStore(store: AlertFileStore(url: root.appendingPathComponent("legacy-alerts.json"))),
                                          inbox: ShareInbox(), review: ReviewFeature(), search: SearchHistory(storage: MemorySearchHistoryStorage()))
    var calls: [String] = []
    var gateDuringSwitch: Bool?
    switcher.hooks = AccountProfileSwitcher.Hooks(
      endRound: { calls.append("endRound") },
      willSwitch: { calls.append("willSwitch"); gateDuringSwitch = profile.gate.isApplying },
      forgetBootstrap: { calls.append("forgetBootstrap") },
      forgetDrawingBaseline: { calls.append("forgetDrawingBaseline") },
      updateStatus: { calls.append("updateStatus") },
      profileReady: { calls.append("profileReady") },
      seedFavorites: { user in calls.append("seedFavorites:\(user == nil ? "guest" : "user")") },
      resumePendingApply: { calls.append("resumePendingApply") })
    let epoch = profile.epoch

    try switcher.prepare(nil as AccountUser?)()
    #expect(calls == ["endRound", "willSwitch", "forgetBootstrap", "forgetDrawingBaseline",
                      "updateStatus", "profileReady", "seedFavorites:guest"])
    #expect(gateDuringSwitch == true, "onSwitch 响的时候已经进了保护区")
    #expect(!profile.gate.isApplying)
    #expect(profile.epoch != epoch)
    #expect(profile.owner == nil && profile.sync == nil && profile.personal != nil)

    calls = []
    try switcher.prepare(nil as AccountUser?)()
    #expect(calls.isEmpty, "同一个属主重复 prepare 当场返回")
  }
}
