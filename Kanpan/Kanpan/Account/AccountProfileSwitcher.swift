import Foundation
import os
import KanpanCore
import KanpanAccount
import ReviewDomain
import ReviewData
import ReviewUI

/// 换人 / 装档案：把某个属主（没登录是访客）的整份档案从盘上读出来、认领访客那份、
/// 启动前向对账、体检设置，再一次性提交给各个 store。
///
/// 从 `AppAccountBridge` 原样搬出来（2026-10-10 拆分）。`prepare(_:)` 是「先把所有会失败的活
/// 干完，再一次性提交」：返回的闭包才是提交，提交那一段换 `ActiveProfile` 的主人 / 柜子 / 存档 /
/// 代次。提交途中要碰别的块的地方（收掉在途同步、清画线基线、刷新状态、默认自选、补装欠着的那批）
/// 都是注入进来的闭包，顺序和搬家之前逐字一样。
@MainActor final class AccountProfileSwitcher {
  /// 设置编不出字节（`PrefsCodec.encoded` 返回 nil）时留一句：那一次写盘整段跳过，绝不写空档。
  private static let log = Logger(subsystem: "com.kanpan.app", category: "account")
  private let profile: ActiveProfile
  private let files: AccountFiles
  private let account: AccountFeature
  private let prefs: PrefsStore
  private let symbols: SymbolPickerModel
  private let drawings: DrawingController
  private let alerts: AlertStore
  private let inbox: ShareInbox
  private let review: ReviewFeature
  private let search: SearchHistory

  /// 提交那一段依次要碰的别处。全部由 `AppAccountBridge` 接线；默认什么都不做。
  struct Hooks {
    /// 收掉上一份档案在途的同步与去抖推送（`SyncLifecycle.endRound`）。排在换代次之前。
    var endRound: () -> Void = {}
    /// 换属主**之前**通知宿主（`AppAccountBridge.onSwitch`）：把复盘、面板、浮层收干净。
    var willSwitch: () -> Void = {}
    /// 换属主之后：下一次同步必须全量（`SyncLifecycle.forgetBootstrap`）。
    var forgetBootstrap: () -> Void = {}
    /// 换属主之后：画线增量基线清空（`SyncRecorder.forgetDrawingBaseline`）。
    var forgetDrawingBaseline: () -> Void = {}
    /// 离开保护区之后刷新账号页状态（`SyncLifecycle.updateStatus`）。
    var updateStatus: () -> Void = {}
    /// 档案全部就位，通知宿主（`AppAccountBridge.onProfileReady`）。
    var profileReady: () -> Void = {}
    /// 默认自选播种（`AccountChores.seedDefaultFavorites`）。代次在调它那一刻取。
    var seedFavorites: (_ user: UUID?) -> Void = { _ in }
    /// 存档里记着欠装的那一批，补装（`SyncApplier.resumeAfterSwitch`）。
    var resumePendingApply: () -> Void = {}
  }
  var hooks = Hooks()

  /// 已经 prepare 过的属主。`.none` 是「一次都没 prepare 过」。
  private var preparedOwner: UUID??

  init(profile: ActiveProfile, files: AccountFiles, account: AccountFeature, prefs: PrefsStore,
       symbols: SymbolPickerModel, drawings: DrawingController, alerts: AlertStore,
       inbox: ShareInbox, review: ReviewFeature, search: SearchHistory) {
    self.profile = profile; self.files = files; self.account = account; self.prefs = prefs
    self.symbols = symbols; self.drawings = drawings; self.alerts = alerts
    self.inbox = inbox; self.review = review; self.search = search
  }

  func prepare(_ user: AccountUser?) throws -> (@MainActor () -> Void) {
    // 同一个属主重复 prepare 是纯浪费：整套读盘 + 解码 + ReviewStore 初始化白做一遍，
    // 账号状态又原样换回去。冷启动的 `prepare(nil)` 和退登的 `prepare(nil)` 属主不同，
    // 不会被这里挡掉（一次都没 prepare 过时 `preparedOwner` 是 `.none`）。
    if let prepared = preparedOwner, prepared == user?.id, profile.personal != nil { return {} }
    // 换档案是「必须现在就保证在盘上」的那种路口，所以这儿准阻塞（判据见
    // `ArchiveWriter.drain()`）。非排空不可的理由：正式文件的写现在排在写盘队列上
    // （见 `AppAccountBridge.init` 里那三个 `persistence` 钩子），而下面这一整段是在主线程上**读**
    // 那几份文件、再按合并结果**写**回去。不排空的话，上一份档案里还没落完的那笔
    // 会落在这一段之后，把刚写回去的结果盖成旧的。
    profile.sync?.flushNow()
    let directory = try files.directory(user: user?.id)
    let nextStorage = try PersonalFileStorage(directory: directory, guest: user == nil)
    let nextInbox = try ShareInbox.read(directory: directory)
    var nextPrefs = PrefsStore.load(from: nextStorage)
    // 自选要和画线同一个姿态：**读不动就把整段 `prepare` 中断**，绝不拿一份凭空造出来的
    // 空档往下走（下面写回 `symbols.json` 那一步会把它落盘，用户的自选就永久没了）。
    // 以前这儿是 `load()`，解不动静默退成空档；画线那一行一直是 `try drawStore.read()`，
    // 两侧不对称正是 B-01。`prepare` 抛之后各调用方的行为见 `AccountFeature`：
    // 冷启动 `activate()` 由 `MainScreen` 接住（提示一句 + 照常兑现落地页，档案不换），
    // 登录 / 退登 / 恢复会话则是把错误摆在账号页上、那一次动作不生效——
    // 都不崩，也都不会写盘。
    var nextSymbols = try SymbolPrefsStore(storage: nextStorage).read()
    let drawStore = DrawStore(url: directory.appendingPathComponent("draws.json"))
    var nextDrawings = try drawStore.read()
    let loadedDrawings = nextDrawings
    // 提醒和画线同一个姿态：读不动就中断这次 prepare，绝不拿一份空档往下走
    // （下面那一步会把它回写进 `alerts.json`，用户设的提醒就永久没了）。
    let alertStore = AlertFileStore(url: directory.appendingPathComponent("alerts.json"))
    var nextAlerts = try alertStore.read()
    let loadedAlerts = nextAlerts
    let nextReview = try ReviewStore(directory: directory)
    let nextSync = user == nil ? nil : try SyncStore(directory: directory)
    // 体检 `prefs.json`（审查 17）。必须在下面任何一步写盘之前：这一段末尾会把整理好的
    // 设置写回 `prefs.json`，之后再体检永远是 `.intact`。坏了 / 没了时照 `SettingsRecovery`
    // 办：先找同步存档里本机上一次记下的那份，绝不拿出厂值当「本机刚改的」推上云端。
    let profileOwner = user?.id.uuidString ?? ("guest:" + files.guestBatch.uuidString)
    // 「本机上一次记下的那份」是本机装进去的那一版（`appliedLocal`，底稿还在时就是底稿），
    // 不是云端推过来、还没装的 `local`；本机那一版里压根没有设置对象时才退回 `local`。
    let archivedSettings = try nextSync.flatMap { sync in
      let key = try PersonalSyncCodec.settings(nextPrefs).key
      return (sync.archive.appliedLocal[key] ?? sync.archive.local[key]).flatMap { try? PersonalSyncCodec.apply($0, to: nextPrefs) }
    }
    // 存档里有这份就交给体检：`prefs.json` 没了而存档还在，是「被清了」不是「第一次」，
    // 不能只凭哨兵（哨兵在另一层，可能一起丢了、也可能记着上一个人）。
    let verdict = prefs.diagnose(nextStorage, owner: profileOwner, synced: archivedSettings != nil)
    let recovery = SettingsRecovery.plan(verdict, onDisk: nextPrefs, baseline: archivedSettings)
    nextPrefs = recovery.prefs
    let claim = try user.flatMap { try files.claimGuest(user: $0.id) }
    if let claim {
      let guestStorage = try PersonalFileStorage(directory: claim.directory, guest: true)
      let guestPrefs = PrefsStore.load(from: guestStorage)
      // 访客那份同理：解不动就中断这次登录，而不是把访客的自选当成「本来就没有」
      // 悄悄丢掉（下一行的画线一直是这个姿态）。
      let guestSymbols = try SymbolPrefsStore(storage: guestStorage).read()
      let guestDrawings = try DrawStore(url: claim.directory.appendingPathComponent("draws.json")).read()
      let guestAlerts = try AlertFileStore(url: claim.directory.appendingPathComponent("alerts.json")).read()
      // 并之前账号手上已经有的那几条：下面记导入批次时只记访客**新带来**的（见 `guestImport`）。
      let accountBefore = try PersonalSyncCodec.drawings(nextDrawings) + PersonalSyncCodec.symbols(nextSymbols) + PersonalSyncCodec.alerts(nextAlerts.alerts)
      var adopted = Set<String>()
      // 档案坏了 / 被清了不是「这个号第一次在这台机器上登录」：那时访客那份不许顶上来
      // （顶上来就会被当成导入推上云端，盖掉这个人自己的设置）。
      if recovery.mayAdoptGuest, !FileManager.default.fileExists(atPath: directory.appendingPathComponent("prefs.json").path) { nextPrefs = guestPrefs; adopted.insert("settings") }
      for (key, values) in guestDrawings.bySymbol {
        let existing = Set(nextDrawings[key].map(\.id)); nextDrawings[key] += values.filter { !existing.contains($0.id) }
      }
      // 两份各自不满 50、并起来超了：进门就裁（丢最老的），别让多出来的先被记成导入操作推上去、
      // 下一轮再推一遍删除（压测收尾第 10 项，规则见 `DrawArchive.capToLimit()`）。
      SyncOverlay.capDrawings(&nextDrawings, ages: SyncOverlay.drawingAges(nextSync.map { Array($0.archive.local.values) } ?? []), from: "guest")
      if !FileManager.default.fileExists(atPath: directory.appendingPathComponent("draws.json").path) { nextDrawings.preferences = guestDrawings.preferences; adopted.insert("drawingPreferences") }
      let claimedAlerts = Set(nextAlerts.alerts.map(\.id))
      nextAlerts.alerts += guestAlerts.alerts.filter { !claimedAlerts.contains($0.id) }
      nextSymbols.absorb(guest: guestSymbols)
      let guestReview = try ReviewStore(directory: claim.directory)
      try nextReview.transaction { archive in try Self.absorbGuestReview(guestReview.archive, into: &archive, sanitize: Self.sanitize) }
      // 草稿与重温进度是两份**侧文件**，各自有自己的落盘位置，不能只改主档里那份镜像：
      // 草稿只写进 `archive.draft` 的话，下次 `ReviewStore.init` 会拿账号目录里那份
      // 写着「现在没有草稿」的 `draft-v1.json` 把它盖掉（游客写了一半的那条当场消失），
      // 进度则是压根没人并。规则与证据都在 `ReviewStore.adoptSideFiles(from:)`。
      try nextReview.adoptSideFiles(from: guestReview, sanitizingDraft: Self.sanitize)
      if let nextSync {
        // 只记盘上真的变成访客那份的对象：已登录的人每次冷启动都会走到这里（冷启动先装
        // 访客档案，访客目录因此总有文件可「认领」），整份导入会把同步存档的 `local` 改成
        // 默认值，下面的脏标识 / 对账一步再以当下时间戳把这个人的设置重记一遍，
        // 最后冷启动的那台设备就把别的设备更晚的改动盖掉了。规则见 `guestImport`。
        let imported = try PersonalSyncCodec.guestImport(
          merged: [PersonalSyncCodec.settings(nextPrefs)] + PersonalSyncCodec.drawings(nextDrawings) + PersonalSyncCodec.symbols(nextSymbols) + PersonalSyncCodec.alerts(nextAlerts.alerts),
          guest: [PersonalSyncCodec.settings(guestPrefs)] + PersonalSyncCodec.drawings(guestDrawings) + PersonalSyncCodec.symbols(guestSymbols) + PersonalSyncCodec.alerts(guestAlerts.alerts),
          accountBefore: accountBefore, adopted: adopted)
        // 一次事务记完：逐条来的话这一档要被整份重写几十上百遍。
        try nextSync.capture(imported, device: account.device.id, importing: claim.id, owning: PersonalSyncCodec.ownedKeys)
      }
    }
    if let nextSync {
      // 启动前向对账（B2）。
      //
      // 画线、提醒、自选都落两个文件：先落同步存档（新的本地值和那条待发操作在同一份档里），
      // 再落正式文件。两次写之间进程没了，盘上就是「新存档 + 旧正式文件」。这里把差额
      // **只向前**补进正式文件：本机说了算（有待发操作或未了结的拒绝记录）的对象落 `local`
      // 那份，别的对象只认云端的墓碑（删掉的不许在启动时复活）；云端下发的活值一个都不碰，
      // 否则这一步就成了拿存档去回滚用户已经落在盘上的东西。挑哪几份是
      // `SyncStore.startupCorrections`，怎么落是 `SyncOverlay`——和 `applyPending` 同一份。
      SyncOverlay.alerts(nextSync.startupCorrections(in: ["alerts"], onDisk: (try? PersonalSyncCodec.alerts(nextAlerts.alerts)) ?? []),
                         onto: &nextAlerts)
      SyncOverlay.drawings(nextSync.startupCorrections(in: ["drawings", "drawingPreferences"], onDisk: (try? PersonalSyncCodec.drawings(nextDrawings)) ?? []),
                           onto: &nextDrawings)
      SyncOverlay.symbols(nextSync.startupCorrections(in: ["favorites", "groups"], onDisk: PersonalSyncCodec.symbols(nextSymbols)),
                          patching: &nextSymbols)
    }
    PersonalSyncCodec.keepDeviceFields(prefs.prefs, in: &nextPrefs)
    // 「自选页停在哪一类」从自选档案搬进偏好：老存档里它写在 `symbols.json` 的
    // `selectedGroupID` 上，新家是 `prefs.json` 的 `favoritesGroup`（随账号同步）。
    //
    // 搬完立刻把老键清空，两个理由：一是它不清空就会在每次 `prepare` 里再搬一次，
    // 把用户之后挑的那一类顶回升级那一刻的值；二是那份档案要整份推给服务端，
    // 留着一个谁也不读的死键只会让下一个人猜它还算不算数。
    // 两份都在这一步之后才写盘，所以搬家和清空是同一次落盘里的事，中途断电也不会
    // 出现「老的清了、新的没写上」。
    if nextPrefs.favoritesGroup.isEmpty, let legacy = nextSymbols.legacySelectedGroup {
      nextPrefs.favoritesGroup = legacy
    }
    // 盘上那份自选读进来时同名分类已经并好了（`SymbolPrefs.init`）；「停在哪一类」要是
    // 指着被并掉的那个，照同步存档里的分组对象改指留下的那个，免得启动那一下跳回第一类。
    if let nextSync, let kept = SyncOverlay.mergedGroups(in: nextSync.archive.local.values)[nextPrefs.favoritesGroup] {
      nextPrefs.favoritesGroup = kept
    }
    nextSymbols.legacySelectedGroup = nil
    // Complete all fallible disk preparation before replacing any visible account state.
    // 这三份以前每次冷启动都原样重写一遍，只是为了「确保文件在」。读一次小 JSON 比
    // 一次原子写（临时文件 + rename + fsync）便宜得多，只在内容真的不一样时才落盘。
    // 编不出字节就不写：盘上那份原样留着，绝不拿空 Data 盖掉它。
    if let encodedPrefs = PrefsCodec.encoded(nextPrefs) {
      if encodedPrefs != nextStorage.prefsData(forKey: PrefsCodec.key) { nextStorage.setPrefsData(encodedPrefs, forKey: PrefsCodec.key) }
    } else {
      Self.log.error("prepare: prefs unencodable, kept prefs.json on disk untouched")
    }
    let encodedSymbols = try JSONEncoder().encode(nextSymbols)
    if encodedSymbols != nextStorage.symbolPrefsData(forKey: SymbolPrefsStore.defaultsKey) { nextStorage.setSymbolPrefsData(encodedSymbols, forKey: SymbolPrefsStore.defaultsKey) }
    if nextStorage.error != nil { throw AccountError.storage }
    // 启动前向对账补回来的、以及老版本已经把几百条原样落在盘上的，这次装档案顺手裁到上限。
    // 「多老」按同步存档里的全量算（没登录就是本机落笔顺序），和 `applyPending` 同一把尺。
    SyncOverlay.capDrawings(&nextDrawings, ages: SyncOverlay.drawingAges(nextSync.map { Array($0.archive.local.values) } ?? []), from: "load")
    if nextDrawings != loadedDrawings { try drawStore.save(nextDrawings) }
    if nextAlerts != loadedAlerts { try alertStore.save(nextAlerts) }
    if let nextSync {
      let settings = try PersonalSyncCodec.settings(nextPrefs)
      let initial = try [settings] + PersonalSyncCodec.drawings(nextDrawings) + PersonalSyncCodec.symbols(nextSymbols) + PersonalSyncCodec.alerts(nextAlerts.alerts)
      // 没有的才填：存档里已经有的那份可能带着待发操作，别把它按盘上这份原样抹平。
      try nextSync.transaction { archive in for object in initial where archive.local[object.key] == nil { archive.local[object.key] = object } }
      // 但「已经有了就什么都不做」在设置这一档上是个洞：盘上那份是**上一次运行时
      // 用户改过的**，存档里那份可能停在更早的一次同步上。两份不一样却不生成操作，
      // `SyncStore.receive` 的护栏（有待发操作才护住本地）就护不住它，下一次拉取
      // 会拿云端那份旧的把用户刚做的改动盖掉。规则写在 `ChartLayoutReconcile` 里。
      //
      // 2026-09-19 补：脏标识是这件事的正解——盘上那份带着「还没推上去」的字段，
      // 就必须生成一条操作，不管和存档里那份比起来像不像。`ChartLayoutReconcile`
      // 留着兜老档（装了脏标识之前就存在的那些安装，它们一个标识都没有）。
      let dirty = PrefsStore.storedStamp(in: nextStorage)?.isDirty ?? false
      // 对着本机装进去的那一版比（`appliedLocal`）：底稿还在时 `local` 是云端推过来、还没装的，
      // 盘上这份等于底稿、不等于它，拿它比就会把云端的改动判成「盘上有没记上的改动」。
      // 判成 `.recapture` 之后记账那一步（`SyncStore.stage`）也是拿底稿差分的，两头一致。
      let baseline = nextSync.archive.appliedLocal[settings.key].flatMap { try? PersonalSyncCodec.apply($0, to: nextPrefs) }
      // 盘上那份不可信时一条操作都不记（`SettingsRecovery.Plan.mayCapture`）。
      if recovery.mayCapture, dirty || ChartLayoutReconcile.decide(onDisk: nextPrefs, baseline: baseline) == .recapture {
        try nextSync.capture([settings], device: account.device.id, owning: PersonalSyncCodec.ownedKeys)
      }
      nextSync.flushNow()
    }
    let client: ScorebookClient?
    if user != nil, let api = account.client {
      // 钉住这份档案的主人：复盘的上传 / 拉取属于这个人，换号之后还在途的那一趟
      // 当场取消，不带着下一个人的令牌出门（`AccountClient.data(owner:)`）。
      let pinnedOwner = user?.id
      client = ScorebookClient { path, method, body, key in
        try await api.data(path, method: method, body: body, key: key, owner: pinnedOwner)
      }
    } else { client = nil }
    let previouslyPrepared = preparedOwner
    return { [self] in
      // 身份跟着**提交**走，不跟着取目录走。上面那一长串读盘、解码、`ReviewStore`
      // 初始化里任何一步抛出来，人就还留在原来的档案里；身份要是在 `files.directory`
      // 那一步就已经挪过去了，这次半路失败之后 `Library/Caches` 下那几份按身份分目录的
      // 行情缓存会写进另一个人的目录（见 `AccountFiles.activate`）。
      files.activate(user: user?.id)
      // 钥匙串读不动时的后备：记下这回装的是谁（只有身份，没有令牌）。
      files.remember(owner: user)
      hooks.endRound(); profile.epoch = UUID(); profile.gate.rotate(); profile.gate.enter()
      hooks.willSwitch()
      profile.owner = user?.id; profile.personal = nextStorage; profile.sync = nextSync
      preparedOwner = .some(user?.id)
      // 换属主之后本机拿到的是空档，下一次同步必须把服务端那份整份拉回来。
      hooks.forgetBootstrap()
      // 新档案盘上的画线和存档之间可能差着没记上的一笔：第一次抬手整份对一遍。
      hooks.forgetDrawingBaseline()
      // 「同一个人的档案晚到」和「真的换了个人」对那一捏是相反的意思：前者要保住
      // 用户刚做的，后者必须作废。分界线在**上一个属主是不是一个真账号**：
      // - `.none`（一次都没 prepare 过）/ `.some(nil)`（上一个是访客）：这是冷启动
      //   那条链——先装访客档案顶着，`account.restore()` 回来再换成账号那份。
      //   人没换，只是**自己的档案晚到了 900ms**，这中间他捏的那一下得留着。
      // - `.some(uuid)`（上一个是某个真账号）：退登或换号，那是另一个人了，作废。
      let arrival: ChartLayoutArrival = (previouslyPrepared ?? nil) == nil ? .sameProfile : .ownerSwitched
      prefs.useStorage(nextStorage, prefs: nextPrefs, arrival: arrival, owner: profileOwner,
                       verdict: verdict, keepsDirtyMarks: recovery.keepsDirtyMarks)
      symbols.useStorage(SymbolPrefsStore(storage: nextStorage), prefs: nextSymbols)
      drawings.useStorage(drawStore, archive: nextDrawings)
      alerts.useStorage(alertStore, archive: nextAlerts)
      inbox.activate(directory: directory, owner: user?.id, cache: nextInbox, api: account.client)
      search.useStorage(nextStorage)
      review.activate(store: nextReview, client: client)
      profile.gate.leave(); hooks.updateStatus()
      // 旧版本「缺线暂停」留下的画线提醒复活（2026-10-06 起画线与提醒互相独立）。
      // 排在离开保护区之后：走 `write` → 记账同步，服务端那份才会重新开始判。
      alerts.reviveLegacyPaused()
      // 换进来的档案里可能有还没分类的自选（访客那几只并进来的、上一次同步装进来没归类的）。
      // 目录早就到了的话 `setCatalog` 不会再跑一趟，这里补上并回写（审查 D-01）。
      symbols.classifyArrivals()
      // 档案已经全部就位，宿主现在可以按它重新兑现首屏那几件事。
      hooks.profileReady()
      // 访客和账号都给同一份默认自选（只补缺的），规则在 `AccountChores.seedDefaultFavorites`。
      // 代次拿来防「取榜那几秒里账号档案回来了」——那时这一趟当场作废。
      hooks.seedFavorites(user?.id)
      // 上一次运行拉回来了、但没装进本机就没了的那一批，在这儿补装（B4）。
      // 判据在存档里，所以断电重开照样看得出来，不用等下一轮全量。
      if nextSync?.needsApply == true { hooks.resumePendingApply() }
    }
  }
  /// 访客的复盘并进账号：只收访客**本机独有**（没有 serverId）、账号里还没有的记录，
  /// 以及挂在这些本机独有记录上的待发操作；新建那一笔的 body 顺手洗一遍图表设置快照。
  ///
  /// 按 id 查表，不在循环里 `contains(where:)`：原来两层线性查找是「访客条数 × 账号条数」
  /// （队列那一段还要再乘一次记录条数），访客离线攒了几千条时整段压在登录那一下的主线程上。
  nonisolated static func absorbGuestReview(_ guest: ReviewArchive, into archive: inout ReviewArchive,
                                sanitize: (ReviewDraft) -> ReviewDraft) throws {
    var claimed = Set(archive.records.map(\.id))
    for var record in guest.records where record.serverId == nil && !claimed.contains(record.id) {
      record.draft = sanitize(record.draft); archive.records.append(record); claimed.insert(record.id)
    }
    let localOnly = Set(archive.records.lazy.filter { $0.serverId == nil }.map(\.id))
    var queued = Set(archive.queue.map(\.id))
    for var op in guest.queue where !queued.contains(op.id) {
      guard localOnly.contains(op.recordId) else { continue }
      if op.kind == "create", let value = try? JSONDecoder().decode(ReviewDraft.self, from: op.body) { op.body = try JSONEncoder().encode(sanitize(value)); op.attempted = nil }
      archive.queue.append(op); queued.insert(op.id)
    }
  }
  private static func sanitize(_ input: ReviewDraft) -> ReviewDraft {
    var value = input
    if let data = value.chartSettings, (try? PersonalSyncCodec.snapshotPrefs(data)) == nil {
      value.chartSettings = (try? JSONDecoder().decode(Prefs.self, from: data)).flatMap { try? PersonalSyncCodec.snapshot($0) }
    }
    return value
  }
}
