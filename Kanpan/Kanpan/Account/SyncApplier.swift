import Foundation
import os
import KanpanCore
import KanpanAccount

/// 应用远端：把同步存档里云端那批（`local`）装进本机正式文件与内存里的 store。
///
/// 从 `AppAccountBridge` 原样搬出来（2026-10-10 拆分）。「这一批欠着没装」的标记
/// （`pendingApply`）归这里；什么时候准装（`canApply`，面板 / 画线 / 复盘都不开着）、
/// 装完要不要回推（`captureSettings` / `captureSymbols`）、画线基线怎么挪、
/// 档案到货通知宿主（`onProfileReady`）都是注入进来的，不反向持有别的块。
@MainActor final class SyncApplier {
  /// 设置编不出字节（`PrefsCodec.encoded` 返回 nil）时留一句：那一次写盘整段跳过，绝不写空档。
  private static let log = Logger(subsystem: "com.kanpan.app", category: "account")
  private let profile: ActiveProfile
  private let prefs: PrefsStore
  private let symbols: SymbolPickerModel
  private let drawings: DrawingController
  private let alerts: AlertStore

  /// 这一刻准不准把云端那批落进本机（宿主的 `syncGate`）。
  var canApply: () -> Bool = { true }
  /// 云端设置 / 自选落地之后通知宿主重新兑现首屏（`AppAccountBridge.onProfileReady`）。
  var onProfileReady: () -> Void = {}
  /// 合并完本地设置还脏：离开保护区后反推一次（`SyncRecorder.captureSettings`）。
  var captureSettings: () -> Void = {}
  /// 同名分组并掉之后：离开保护区后把删除与改挂推上去（`SyncRecorder.captureSymbols`）。
  var captureSymbols: () -> Void = {}
  /// 画线增量基线跟着挪（`SyncRecorder.rebaseDrawingBaseline`）。
  var rebaseDrawings: (_ old: DrawArchive, _ new: DrawArchive) -> Void = { _, _ in }
  /// `resumeApply` 装完之后刷新账号页状态（`SyncLifecycle.updateStatus`）。
  var updateStatus: () -> Void = {}
  /// `resumeApply` 装失败时报给账号页。
  var report: (any Error) -> Void = { _ in }

  /// 上一次 `applyPending()` 被 `canApply()` 挡回去了，等条件到齐要补跑。
  private(set) var pendingApply = false

  init(profile: ActiveProfile, prefs: PrefsStore, symbols: SymbolPickerModel, drawings: DrawingController, alerts: AlertStore) {
    self.profile = profile; self.prefs = prefs; self.symbols = symbols; self.drawings = drawings; self.alerts = alerts
  }

  /// 一轮同步推 / 拉都成了之后：上一次被挡下、或者存档里记着欠装（`needsApply`）就装。
  /// `sync` 是那一轮起跑时的存档，判据照搬家之前逐字。
  func applyIfDue(_ sync: SyncStore) throws {
    if pendingApply || sync.needsApply { try applyPending() }
  }
  /// 换档案那一刻：上一次运行拉回来了、但没装进本机就没了的那一批，在这儿补装（B4）。
  /// 判据在存档里，所以断电重开照样看得出来，不用等下一轮全量。
  func resumeAfterSwitch() { pendingApply = true; resumeApply() }

  /// 面板 / 画线 / 复盘关掉之后补跑一次被挡下的 `applyPending()`。
  ///
  /// 以前 `applyPending()` 撞上 `canApply() == false` 就直接 return、不留任何补跑的钩子，
  /// 云端刚改的设置最坏要等下一轮全量（`bootstrapInterval` = 300 秒）才落地——正是
  /// 「改完要等一下才生效」。现在挡下来时记一笔，条件一到齐就补。
  func resumeApply() {
    guard pendingApply, canApply(), profile.sync != nil else { return }
    do { try applyPending(); updateStatus() } catch { report(error) }
  }
  /// 把云端那批装进本机：**准备 → 落盘 → 发布**三段。
  ///
  /// 从前是一段：进门先把 `pendingApply` 清掉，先把设置装进去，再去做会抛错的
  /// 画线解码与保存。中途抛一次，留下的是「设置换了、画线没换、`pendingApply`
  /// 也没了」；而 `lastSync` 在调它之前就已经写上了，下一轮认定这批已经消化过，
  /// 于是这批的画线永远不会落到本机（B4）。
  ///
  /// 现在：会抛错的活儿全在第一段做完，第一段抛错时**一个字节都没写、一个 store
  /// 都没碰**，`pendingApply` 原样留着等下一轮重来；第二段把整套候选态一次性落盘
  /// （各文件 + 存档里的 `lastApplied` / `unapplied`），落盘成功之后才清 `pendingApply`；
  /// 第三段才把同一代值推给内存里的 store 与界面。
  func applyPending() throws {
    guard let sync = profile.sync else { return }
    guard canApply() else { pendingApply = true; return }
    // 进门先记成「这一批还没装进去」，而不是从前那样先把它清掉。中途抛错时这一笔
    // 还在，面板一关 `resumeApply()` 就会重来；清掉的时机在第二段落盘成功之后。
    pendingApply = true
    // 这一次装哪几张表：云端改过、还没装的那几张（`nil` = 全部）。空的就是没有要装的——
    // 只把「装到哪儿了」记上，不合并、不落盘、不打扰界面。
    let scope = sync.archive.unapplied
    guard scope != [] else {
      try sync.markApplied(at: Int64(Date().timeIntervalSince1970 * 1000), covering: [])
      pendingApply = false; return
    }
    func wants(_ collections: String...) -> Bool { scope.map { !$0.isDisjoint(with: collections) } ?? true }
    let objects = sync.archive.local.values

    // —— 一、准备。只算不写，也不碰任何可见状态。这一段抛错等于这一批整个没发生。
    // 每一种对象怎么落到本地模型上，和启动前向对账是同一份（`SyncOverlay`）。
    // 设置按字段合并：本地脏的一律跳过，干净的跟着云端走；第三段 `prefs.applySynced`
    // 会把同一套规则再走一遍（幂等）。不在这次范围里的表，候选态就是现状，后面两段自然不动它。
    let nextPrefs = wants("settings")
      ? try SyncOverlay.settings(sync.archive.local["settings:chart"], onto: prefs.prefs, keeping: prefs.dirtyFields) : nil
    var archive = drawings.storedArchive
    if wants("drawings", "drawingPreferences") {
      SyncOverlay.drawings(objects.filter { $0.collection == "drawings" || $0.collection == "drawingPreferences" }, onto: &archive)
      // 进门的上限（压测收尾第 10 项）：别的设备、老版本推上来的几百条不原样落进来。
      SyncOverlay.capDrawings(&archive, ages: SyncOverlay.drawingAges(objects), from: "sync")
    }
    var alertArchive = alerts.archive
    if wants("alerts") { SyncOverlay.alerts(objects.filter { $0.collection == "alerts" }, onto: &alertArchive) }
    // 服务端只同步自选/分组这几张表，「最近」「常看」一直是本机的事，重建时原样带回去。
    // 整张重建要的是这两张表的**全部**对象，所以只要其中一张改过，就拿 `local` 里整份来建。
    let symbolsChanged = wants("favorites", "groups")
    let nextSymbols = symbolsChanged
      ? SyncOverlay.symbols(rebuiltFrom: objects.filter { $0.collection == "favorites" || $0.collection == "groups" }, keeping: symbols.prefs)
      : symbols.prefs
    let encodedSymbols = try JSONEncoder().encode(nextSymbols)
    // 设置要写盘的字节也在这一段编好：编不出来（`PrefsCodec.encoded` 返回 nil）就整批不装、
    // 等下一轮重来——第二段绝不写一份空档进去，第三段也不会把没落盘的那一代推给界面。
    var encodedPrefs: Data?
    if let nextPrefs, nextPrefs != prefs.prefs {
      guard let data = PrefsCodec.encoded(nextPrefs) else {
        Self.log.error("applyPending: prefs unencodable, batch left pending")
        throw AccountError.storage
      }
      encodedPrefs = data
    }
    // 云端手上还躺着同名的分组对象（两台设备、或访客档案与账号各建了一个「加密」）：
    // 重建那一步已经按名字并成一格了，这里记下「被并掉的 id → 留下的 id」，发布之后
    // 再记一次账——把多余的分组对象推删除、挂在上面的自选改挂过去，云端跟着收敛成一份。
    // 留哪一个只看 id（`SymbolPrefs.mergeSameNamed`），每台设备挑的都是同一个。
    let mergedGroups = SyncOverlay.mergedGroups(in: objects.filter { $0.collection == "groups" })

    // —— 二、落盘。整套候选态一次性提交；成功之后才准清 `pendingApply`。
    //
    // 动手之前先把写盘队列排空。这一段是在主线程上直接写 `prefs.json` /
    // `symbols.json` / `draws.json` / `alerts.json`，而用户刚才那几笔编辑的正式文件
    // 写正排在队列上（`AppAccountBridge.init` 里的 `persistence` 钩子）；不排空的话，那几笔会落在
    // 这一批之后，把刚装进来的云端那一代盖回旧的。这条路不是手指上的路
    // （它本来后面就跟着一次 `flushNow()`），准阻塞。
    sync.flushNow()
    if let encodedPrefs {
      profile.personal?.setPrefsData(encodedPrefs, forKey: PrefsCodec.key)
    }
    if nextSymbols != symbols.prefs {
      profile.personal?.setSymbolPrefsData(encodedSymbols, forKey: SymbolPrefsStore.defaultsKey)
    }
    if profile.personal?.error != nil { throw AccountError.storage }
    try drawings.commitSynced(archive)
    try alerts.commitSynced(alertArchive)
    // 「拉到哪儿了」和「装进本机没有」是两个时刻。这一句必须排在所有文件落盘之后：
    // 它一旦落下去，下一次启动就不会再重做这一批了。
    try sync.markApplied(at: Int64(Date().timeIntervalSince1970 * 1000), covering: scope)
    sync.flushNow()
    pendingApply = false

    // —— 三、发布。到这儿盘上已经是新的一代，内存与界面跟上。
    let gate = profile.gate
    gate.enter(); defer { gate.leave() }
    if let nextPrefs {
      prefs.applySynced(nextPrefs)
      // 合并完本地还脏，说明云端那份在这几个字段上是旧的——反过来把本地这份推上去，
      // 别等下一次用户改动才捎带。
      //
      // **必须等离开保护区之后再做**：记账那一步的第一道门就是 `!gate.isApplying`，
      // 写在保护区里面等于一条操作都产生不了（B6）。代次交给 `ApplyGate` 校验：
      // 中途换了账号、或者又起了一轮应用，这个快照就作废。
      gate.afterApplying { [weak self] in
        guard let self, prefs.stamp.isDirty else { return }
        captureSettings()
      }
    }
    rebaseDrawings(drawings.storedArchive, archive)
    drawings.publishSynced(archive)
    alerts.publishSynced(alertArchive)
    // 别的设备（旧版本）推下来的暂停态画线提醒，离开保护区后复活并推回去（理由同上面的设置）。
    gate.afterApplying { [weak self] in self?.alerts.reviveLegacyPaused() }
    symbols.applySynced(nextSymbols)
    if !mergedGroups.isEmpty {
      // 记账那一步的第一道门是 `!gate.isApplying`，写在保护区里一条操作都产生不了，
      // 所以同样等离开保护区再做（理由同上面的设置）。「停在哪一类」要是指着被并掉的那个，
      // 一并改指留下的那个，不然自选页会跳回第一类。
      gate.afterApplying { [weak self] in
        guard let self else { return }
        if let kept = mergedGroups[prefs.prefs.favoritesGroup] { prefs.update { $0.favoritesGroup = kept } }
        captureSymbols()
      }
    }
    // 云端那份自选不带「这只该归哪一类」：别的设备（网页版、老版本）加进来的、或者分类
    // 刚被删掉的，装进来时挂在「没有分类」或者一个不存在的分类上，分类页上看不见。
    // 离开保护区再补分类——补完照常回写，云端那份也跟着归好类（审查 D-01）。
    if symbolsChanged {
      gate.afterApplying { [weak self] in self?.symbols.classifyArrivals() }
    }
    // 云端那份设置也是「档案换进来了」的一种：周期、落地页这些要跟着重新兑现一次。
    // 它读的只有设置与自选；这两样都没动时不去惊动宿主。
    if wants("settings") || symbolsChanged { onProfileReady() }
  }
}
