import Foundation
import UIKit
import KanpanCore
import KanpanAccount
import ReviewUI

/// Connects existing stores to account storage. MarketModel and the chart engine are unchanged.
///
/// 2026-10-10 起这里只是**门面 + 组装者**：对外的属性与方法（`MainScreen` 用到的那些）不变，
/// 活儿按职责分在几块里，各块的依赖都在下面的 `init` 里显式接线，互不反向持有：
///
/// | 块 | 管什么 | 以前的名字 |
/// |---|---|---|
/// | `ActiveProfile` | 此刻装着的档案：主人、柜子、同步存档、代次、保护区 | 桥上的 `owner` / `personal` / `sync` / `epoch` / `gate` |
/// | `AccountProfileSwitcher` | 换人 / 装档案（prepare → 提交）、访客认领、启动前向对账 | `AppAccountBridge.prepare` / `absorbGuestReview` |
/// | `SyncRecorder` | 本机改动 → 待发操作、脏标记对账、画线增量基线 | `AppAccountBridge.capture*` / `settleAgreedSettings` / `unsettledSettingsFields` |
/// | `SyncApplier` | 云端那批 → 本机（三段式）、被挡下的补装 | `AppAccountBridge.applyPending` / `resumeApply` |
/// | `SyncLifecycle` | 同步引擎起停与调度、去抖推送、账号页状态数 | `AppAccountBridge.run` / `focus` / `updateStatus` / `pendingCount` |
/// | `AccountChores` | 推送 / 实时活动令牌、品种通知、收件箱、访客认领收尾、默认自选 | `AppAccountBridge.submitPushToken` 等 |
/// | `AccountLegacyMigration` | 建桥时的一次性搬家与清理 | `AppAccountBridge.migrateLegacy` / `drop*` |
///
/// 仓库里别处注释写的 `AppAccountBridge.prepare` / `.capture` / `.applyPending` / `.run`，
/// 按上表找对应的块。
@MainActor final class AppAccountBridge {
  let files: AccountFiles
  private let profile: ActiveProfile
  private let switcher: AccountProfileSwitcher
  private let recorder: SyncRecorder
  private let applier: SyncApplier
  private let lifecycle: SyncLifecycle
  private let chores: AccountChores
  var canApply: () -> Bool = { true }
  var onSwitch: () -> Void = {}
  /// 档案（prefs / symbols / 画线）**真的换进来之后**响一次。
  ///
  /// 和 `onSwitch` 的分工：`onSwitch` 在换属主**之前**响，用来把复盘、面板、浮层收干净；
  /// 这一个在 `useStorage` 全做完之后响，宿主可以在这儿按新档案重新兑现「该开哪张图、
  /// 该停在哪一格、该用哪个周期」。冷启动装访客档案、恢复登录态、换号、退登、
  /// 以及云端设置落地（`applyPending`）都会走到它。
  var onProfileReady: () -> Void = {}

  init(account: AccountFeature, prefs: PrefsStore, symbols: SymbolPickerModel, drawings: DrawingController, alerts: AlertStore, review: ReviewFeature, search: SearchHistory, inbox: ShareInbox) throws {
    // 根目录（含 DEBUG 测试档案那棵子树）只在 `AccountsRoot` 一处：后台替自动复盘传回合的
    // `ExchangeReviewUplink` 开的是同一棵树。
    files = try AccountFiles(root: AccountsRoot.url)
    try AccountLegacyMigration.run(files: files, prefs: prefs, symbols: symbols, drawings: drawings)
    let profile = ActiveProfile()
    self.profile = profile
    lifecycle = SyncLifecycle(profile: profile, account: account, prefs: prefs, review: review)
    recorder = SyncRecorder(profile: profile, account: account, prefs: prefs, symbols: symbols, drawings: drawings, alerts: alerts)
    applier = SyncApplier(profile: profile, prefs: prefs, symbols: symbols, drawings: drawings, alerts: alerts)
    chores = AccountChores(profile: profile, files: files, account: account, prefs: prefs, symbols: symbols, inbox: inbox, review: review)
    switcher = AccountProfileSwitcher(profile: profile, files: files, account: account, prefs: prefs, symbols: symbols,
                                      drawings: drawings, alerts: alerts, inbox: inbox, review: review, search: search)
    wireBlocks(account: account)

    account.onPrepareAccount = { [weak self] user in guard let self else { return {} }; return try self.switcher.prepare(user) }
    account.onSynchronize = { [weak self] in self?.synchronize(manual: true) }
    account.lastOwner = { [weak self] in self?.files.lastOwner }
    prefs.onChange = { [weak recorder] _ in recorder?.captureSettings() }
    symbols.onPrefsChange = { [weak recorder] _ in recorder?.captureSymbols() }
    // 自选页停在哪一类（`SymbolPickerModel.selectedGroupSource`）不在这儿接：桥建不起来时
    // 也得有，接线在 `MainScreen.wireAccount()` 开头。
    drawings.onArchiveChange = { [weak recorder] _ in recorder?.captureDrawings() }
    alerts.onChange = { [weak recorder] _ in recorder?.captureAlerts() }
    // 「存档先落、正式文件后落」这个不变量（B2）的兑现处。
    //
    // 三份正式文件（`draws.json` / `alerts.json` / `symbols.json`）都是在记账
    // （`capture`）的前后脚写的。记账那一侧从前跟着一次主线程 `flushNow()`，顺序
    // 就是那么来的；那次阻塞去掉之后，两次写变成一次排队、一次就地，顺序当场反了。
    // 这三个钩子把正式文件那次写**也排到同一条写盘队列上**：串行 FIFO 保证它跑在
    // 自己前面那次存档写之后，而队列上的合并写只会让存档更新，所以盘上任何一刻
    // 都满足「存档不比正式文件旧」——主线程一步都不等。
    //
    // 没登录（`sync == nil`）时就地写，和从前逐字一样：那时压根没有存档这回事。
    let sequence: @MainActor (@escaping @Sendable () -> Void) -> Void = { [weak profile] write in
      guard let profile, let sync = profile.sync else { write(); return }
      sync.afterArchiveWritten(write)
    }
    drawings.persistence = sequence
    alerts.persistence = sequence
    // 自选这一档换个形状：`SymbolPrefsStore` 是 `@MainActor` 的，不能在写盘队列上使唤。
    // 编码在这儿（主 actor）做完，排队的只剩「把这串字节写进 symbols.json」，
    // 而 `PersonalFileStorage` 本来就是带锁的 `@unchecked Sendable`，那正是
    // `applyPending` 落盘走的同一个口。拿不到档案柜（还没 prepare）就答 false，
    // 由模型自己就地写。
    // `defaultsKey` 是 `SymbolPrefsStore` 的 `@MainActor` 静态量，不能在写盘队列上读，
    // 所以在这儿（主 actor）先取出来，排队的闭包只带一个普通字符串过去。
    let symbolsKey = SymbolPrefsStore.defaultsKey
    symbols.persistence = { [weak profile] value in
      guard let profile, let sync = profile.sync, let personal = profile.personal, let data = try? JSONEncoder().encode(value) else { return false }
      sync.afterArchiveWritten { personal.setSymbolPrefsData(data, forKey: symbolsKey) }
      return true
    }
    // APNs 的 token 来了就报给服务端。现在这条**永远不会响**（没开发者会员，
    // 工程里没有推送 capability，注册必然失败），留着是为了开通那天不用改代码。
    PushRegistration.onToken = { [weak chores] _ in chores?.submitPushToken() }
    review.onLogin = { [weak account] in account?.open() }
    review.onSyncComplete = { [weak chores] in chores?.reviewSyncCompleted() }
    // 存档写盘走后台串行队列；离开前台时把排队的写全部落地，免得被系统挂起/回收时
    // 最后一次 transaction 还停在内存里。
    //
    // **这一条必须是最后一个跑的**，所以登记成 `.sync` 档：它排空的是写盘队列，
    // 前面那些产数据的（根宽、复盘草稿）得先把操作生出来，才赶得上这趟车。
    // 以前这里是自己挂 `didEnterBackgroundNotification`，和 `MainScreen` 的
    // `scenePhase` 谁先谁后没人定义过——那正是用户那个 bug 的「杀法乙」。
    AppLifecycle.shared.register(id: "sync.archive", priority: .sync) { [weak profile] in profile?.sync?.flushNow() }
  }
  /// 各块之间的接线。全部弱引用：块与块之间谁也不持有谁，只有门面持有它们。
  private func wireBlocks(account: AccountFeature) {
    let lifecycle = lifecycle, recorder = recorder, applier = applier, chores = chores
    lifecycle.applyIfDue = { [weak applier] sync in try applier?.applyIfDue(sync) }
    lifecycle.pullListingNotices = { [weak chores] in chores?.pullListingNotices() }
    recorder.onRecorded = { [weak lifecycle] in lifecycle?.updateStatus(); lifecycle?.schedulePush() }
    applier.canApply = { [weak self] in self?.canApply() ?? false }
    applier.onProfileReady = { [weak self] in self?.onProfileReady() }
    applier.captureSettings = { [weak recorder] in recorder?.captureSettings() }
    applier.captureSymbols = { [weak recorder] in recorder?.captureSymbols() }
    applier.rebaseDrawings = { [weak recorder] old, new in recorder?.rebaseDrawingBaseline(from: old, to: new) }
    applier.updateStatus = { [weak lifecycle] in lifecycle?.updateStatus() }
    applier.report = { [weak account] error in account?.report(sync: error) }
    chores.updateStatus = { [weak lifecycle] in lifecycle?.updateStatus() }
    chores.onProfileReady = { [weak self] in self?.onProfileReady() }
    switcher.hooks = AccountProfileSwitcher.Hooks(
      endRound: { [weak lifecycle] in lifecycle?.endRound() },
      willSwitch: { [weak self] in self?.onSwitch() },
      forgetBootstrap: { [weak lifecycle] in lifecycle?.forgetBootstrap() },
      forgetDrawingBaseline: { [weak recorder] in recorder?.forgetDrawingBaseline() },
      updateStatus: { [weak lifecycle] in lifecycle?.updateStatus() },
      profileReady: { [weak self] in self?.onProfileReady() },
      seedFavorites: { [weak chores] user in chores?.seedDefaultFavorites(for: user) },
      resumePendingApply: { [weak applier] in applier?.resumeAfterSwitch() })
  }
  /// 把本机档案（没登录时是访客那份）装进各个 store。
  ///
  /// 以前这一步写在 `init` 里，于是它跑完之后宿主才有机会给 `onSwitch` / `onProfileReady`
  /// 赋值——冷启动这一次装档案调的是默认空闭包，宿主根本不知道档案已经换过了
  /// （R3-2：没登录过的人「上次看的那张图 / 落地页」整套失效）。现在拆成两步：
  /// 构造 → 宿主挂回调 → `activate()`，第一次装档案也走完整的通知。
  ///
  /// **登录过的人直接装他自己那份**（`AccountFiles.lastOwner`，registry.json 里同步读得到的
  /// 身份，不带令牌）。从前一律先装访客那份顶着，等 `account.restore()` 异步读完钥匙串再换：
  /// 冷启动先按访客的设置 / 自选 / 画线铺一整屏，约 0.2s 后整屏换成账号那份——
  /// 周期、指标、涨跌色都要跳一次；而且 `prepare(nil)` 会把 `lastOwner` 抹掉，
  /// 钥匙串读不动时的「按上次那个人装」（审查 17）在冷启动这条路上从来没生效过。
  /// 现在 `restore()` 读到的是同一个人时，`prepare(saved)` 撞上 `preparedOwner` 当场返回，
  /// 一次都不重装；读到「没有登录」时由 `AccountFeature.restore()` 退回访客那份。
  /// 没登录过的人（`lastOwner == nil`）照旧装访客那份，R3-2 那条链不变。
  func activate() throws { try switcher.prepare(files.lastOwner)() }
  /// 图上换了品种（规则见 `SyncLifecycle.focus`）。
  func focus(_ symbol: String) { lifecycle.focus(symbol) }
  /// 外部（回前台、设置页、登录回调）唯一的入口。到点了才做全量。
  func synchronize(manual: Bool = false) {
    lifecycle.synchronize(manual: manual)
    chores.submitPushToken()
    // 分享不是个人同步：只在登录 / 前台拉取入口挂一次。
    lifecycle.afterCurrentRound { [weak chores] in
      chores?.pullInbox()
      chores?.pullListingNotices()
    }
  }
  /// 设置里开着「品种上新与停牌下架」就去拉一次服务端记下的品种状态通知（`ListingNotices`）。
  func pullListingNotices() { chores.pullListingNotices() }
  /// 面板 / 画线 / 复盘关掉之后补跑一次被挡下的 `applyPending()`（`SyncApplier.resumeApply`）。
  func resumeApply() { applier.resumeApply() }
  /// 把云端那批装进本机（`SyncApplier.applyPending`）。
  func applyPending() throws { try applier.applyPending() }
  /// 「盯一个」那条实时活动的推送令牌（`AccountChores.submitActivityToken`）。
  func submitActivityToken(_ token: String, activityID: String, alertID: String) {
    chores.submitActivityToken(token, activityID: activityID, alertID: alertID)
  }
  /// 活动收起：服务端停止给它推更新、丢掉令牌。
  func endActivity(_ activityID: String) { chores.endActivity(activityID) }
}

/// 视野模块的「云端那条腿」。
///
/// `ChartViewport` 只认这两个动作，不认识账号、存档、网络；没登录时它手上这个引用
/// 是 `nil`，模块照常工作。登录与否对外**没有第二种行为**——同一个保存时刻、
/// 同一套语义，差别只在这条腿在不在。
extension AppAccountBridge: ChartViewport.Sync {
  /// 把当前这份设置记成一条待发操作：内存改完，整份存档的落盘**当场发起**
  /// （`ArchiveWriter.schedule`，后台串行队列，`.userInitiated`），不在这儿等它写完。
  ///
  /// 「杀了 app 也还在」靠的是另外两件事，不是在手指上等这一下：根宽本身由
  /// `PrefsStore.persist()` 同步写进 prefs.json（发生在这句之前），而「app 要走了」
  /// 那一刀在 `AppLifecycle` 的 `.sync` 档钩子上（见 `init` 里的 `sync.archive`）。
  func recordLayout() { recorder.captureSettings() }
  /// 顺手推一次。推不上去无所谓（离线、没登录、正在跑别的），操作已经在盘上了，
  /// 下次同步会带走它；这里只是想让另一台设备早点看到。
  func pushLayout() { lifecycle.run(.push, manual: false) }
}
