import Foundation
import UIKit
import KanpanCore
import KanpanAccount
import ReviewDomain
import ReviewData
import ReviewUI

/// Connects existing stores to account storage. MarketModel and the chart engine are unchanged.
@MainActor final class AppAccountBridge {
  let files: AccountFiles
  private let account: AccountFeature
  private let prefs: PrefsStore
  private let symbols: SymbolPickerModel
  private let drawings: DrawingController
  private let alerts: AlertStore
  private let inbox: ShareInbox
  private let review: ReviewFeature
  private let search: SearchHistory
  private var personal: PersonalFileStorage?
  private var sync: SyncStore?
  private var owner: UUID?
  private var epoch = UUID()
  private var task: Task<Void, Never>?
  private var taskID = UUID()
  private var debounce: Task<Void, Never>?
  /// 「正在把云端那批装进本机」这段保护区，外加出了保护区才做的那些事（B6）。
  private let gate = ApplyGate()
  private var symbol = ""
  /// 上一次真的做过全量 bootstrap 的时刻。
  private var lastBootstrap = Date.distantPast
  /// 下一次同步必须做全量：登录 / 恢复会话 / 刚被服务端顶回来（版本冲突）之后置上。
  private var needsBootstrap = true
  /// 这个会话里已经按品种拉过画线的品种。切回老品种不再重复拉。
  private var bootstrappedDrawings: Set<String> = []
  /// 已经 prepare 过的属主。`.none` 是「一次都没 prepare 过」。
  private var preparedOwner: UUID??
  /// 两次全量 bootstrap 之间的最小间隔。
  private static let bootstrapInterval: TimeInterval = 300
  /// 服务端一次最多收 100 条操作（`Backend/kanpan-api/src/sync.rs:91`）。
  private static let pushBatchLimit = 100
  /// 一批**编码之后**最多多少字节。
  ///
  /// 条数从来不是唯一的上限：服务端整个请求体只收 512 KiB（`kanpan-api/src/lib.rs`
  /// 的 `DefaultBodyLimit`），而一条画线操作的大小完全由用户画了多少点决定——
  /// 一百条大操作轻轻松松越线。越线的下场是 413：**整批一条都不落库**，而这一批
  /// 又会原样重发，于是这个账号的队列从此再也前进不了。所以按真实字节往回削，
  /// 384 KiB 给 HTTP 头、令牌、以及 JSON 编码的余量留够空间。
  private static let pushBatchBytes = 384 * 1024
  var canApply: () -> Bool = { true }
  var onSwitch: () -> Void = {}
  /// 档案（prefs / symbols / 画线）**真的换进来之后**响一次。
  ///
  /// 和 `onSwitch` 的分工：`onSwitch` 在换属主**之前**响，用来把复盘、面板、浮层收干净；
  /// 这一个在 `useStorage` 全做完之后响，宿主可以在这儿按新档案重新兑现「该开哪张图、
  /// 该停在哪一格、该用哪个周期」。冷启动装访客档案、恢复登录态、换号、退登、
  /// 以及云端设置落地（`applyPending`）都会走到它。
  var onProfileReady: () -> Void = {}
  /// 推送 token 报给过谁（见 `PushTokenLedger`）。
  private var pushLedger = PushTokenLedger()
  /// 上一次 `applyPending()` 被 `canApply()` 挡回去了，等条件到齐要补跑。
  private var pendingApply = false

  init(account: AccountFeature, prefs: PrefsStore, symbols: SymbolPickerModel, drawings: DrawingController, alerts: AlertStore, review: ReviewFeature, search: SearchHistory, inbox: ShareInbox) throws {
    self.inbox = inbox
    self.account = account; self.prefs = prefs; self.symbols = symbols; self.drawings = drawings; self.alerts = alerts; self.review = review; self.search = search
    var root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("kanpan/accounts")
    // 测试档案另起一棵 `tests/<uuid>` 子树。**只在 DEBUG 构建里存在**（审查 C-02）：
    // 正式包里没有这条口子，Release 回归靠独立的测试安装沙盒隔离，不靠产品二进制
    // 自己认一个环境变量改档案目录。
    #if DEBUG
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1", let profile = ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"], UUID(uuidString: profile) != nil { root = root.appendingPathComponent("tests/" + profile) }
    #endif
    files = try AccountFiles(root: root)
    try migrateLegacy()
    dropSharedSearchHistory()
    dropLegacySymbols()
    account.onPrepareAccount = { [weak self] user in guard let self else { return {} }; return try self.prepare(user) }
    account.onSynchronize = { [weak self] in self?.synchronize(manual: true) }
    account.onAutoSync = { [weak self] enabled in self?.setAutoSync(enabled) }
    account.lastOwner = { [weak self] in self?.files.lastOwner }
    prefs.onChange = { [weak self] _ in self?.captureSettings() }
    symbols.onPrefsChange = { [weak self] _ in self?.captureSymbols() }
    // 自选页停在哪一类，真身在 `Prefs.favoritesGroup`（跟着账号走）。`KanpanSymbols`
    // 看不见设置包，所以在这儿——两边都认识的地方——把读法接过去。加自选 / 新建分类 /
    // 删分类时「落单的成员进哪一类」要问它。
    symbols.selectedGroupSource = { [weak prefs] in prefs?.prefs.favoritesGroup }
    drawings.onArchiveChange = { [weak self] _ in self?.captureDrawings() }
    alerts.onChange = { [weak self] _ in self?.captureAlerts() }
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
    let sequence: @MainActor (@escaping @Sendable () -> Void) -> Void = { [weak self] write in
      guard let self, let sync else { write(); return }
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
    symbols.persistence = { [weak self] value in
      guard let self, let sync, let personal, let data = try? JSONEncoder().encode(value) else { return false }
      sync.afterArchiveWritten { personal.setSymbolPrefsData(data, forKey: symbolsKey) }
      return true
    }
    // APNs 的 token 来了就报给服务端。现在这条**永远不会响**（没开发者会员，
    // 工程里没有推送 capability，注册必然失败），留着是为了开通那天不用改代码。
    PushRegistration.onToken = { [weak self] _ in self?.submitPushToken() }
    review.onLogin = { [weak account] in account?.open() }
    review.onSyncComplete = { [weak self] in
      guard let self else { return }
      do {
        if let owner, let batch = try files.pendingGuest(user: owner), sync?.archive.operations.isEmpty == true, review.pendingUploads == 0 {
          try files.completeGuestClaim(user: owner, batch: batch.id)
        }
        updateStatus()
      } catch { account.report(sync: error) }
    }
    // 存档写盘走后台串行队列；离开前台时把排队的写全部落地，免得被系统挂起/回收时
    // 最后一次 transaction 还停在内存里。
    //
    // **这一条必须是最后一个跑的**，所以登记成 `.sync` 档：它排空的是写盘队列，
    // 前面那些产数据的（根宽、复盘草稿）得先把操作生出来，才赶得上这趟车。
    // 以前这里是自己挂 `didEnterBackgroundNotification`，和 `MainScreen` 的
    // `scenePhase` 谁先谁后没人定义过——那正是用户那个 bug 的「杀法乙」。
    AppLifecycle.shared.register(id: "sync.archive", priority: .sync) { [weak self] in self?.sync?.flushNow() }
  }
  /// 把本机档案（没登录时是访客那份）装进各个 store。
  ///
  /// 以前这一步写在 `init` 里，于是它跑完之后宿主才有机会给 `onSwitch` / `onProfileReady`
  /// 赋值——冷启动这一次装档案调的是默认空闭包，宿主根本不知道档案已经换过了
  /// （R3-2：没登录过的人「上次看的那张图 / 落地页」整套失效）。现在拆成两步：
  /// 构造 → 宿主挂回调 → `activate()`，第一次装档案也走完整的通知。
  func activate() throws { try prepare(nil)() }
  /// 把 `UserDefaults.standard` 里那份旧的历史搜索一次性清掉，不归给任何身份。
  ///
  /// 这份历史是多个身份混在一起的——这台机器上所有登录过的人搜的词都记在同一个键里，
  /// 无法归属到具体的人，所以在搬到按身份存储（`PersonalFileStorage` 的 search.json）时
  /// 一次性清掉。归给「升级那一刻登录着的人」比不迁更糟：A 搜过的词会正式写进 B 的档案，
  /// B 之后怎么清自己的历史都清不掉那几条的来路。搜索历史是最不值钱的状态，
  /// 用几天自己就回来了，不值得为它担这个风险。
  ///
  /// 不挂 `legacy-imported.json` 那个标记：老用户早就越过那道标记了，挂上去等于不清。
  /// 清完之后写入已经改道到档案里，这个键不会再被写第二次，所以每次启动跑一遍是幂等的。
  private func dropSharedSearchHistory() {
    UserDefaults.standard.removeObject(forKey: SearchHistory.defaultsKey)
  }
  /// 搬完清原件：`UserDefaults` 里那份旧的自选档案（`kanpan.symbols.v1`）搬进
  /// 账号目录之后就抹掉。
  ///
  /// 和历史搜索不同，这份是**归当前这个人**的（自选、分组、置顶、最近看过的品种都在
  /// 这台机器上由他一个人攒出来的），所以先搬后清，不是直接丢。
  ///
  /// 为什么非清不可：`migrateLegacy()` 只复制、不清原件，于是同一份档案在机器上留了
  /// 两个真身——写在 `symbols.json`（`PersonalFileStorage`），读却可能读回
  /// `UserDefaults`。这正是 R3-1 那个「新装机每次冷启动都开 BTCUSDT、老用户永远停在
  /// 升级那一刻的品种上」的病根：那份 UserDefaults 副本在搬家那一刻冻住了，之后
  /// 一个字都不会再更新，谁不小心读到它谁就看到一份几个月前的自选表。清掉之后
  /// 这条错路在运行时就不存在了。
  ///
  /// 时机：一定跑在 `migrateLegacy()` **之后**——那一步要么已经把内容写进了访客目录，
  /// 要么因为目录里已经有 `symbols.json` 而跳过（文件那份更新，本来就该赢）；
  /// 它抛错的话 `init` 直接失败，这一行不会跑到，原件留着。
  ///
  /// 不挂 `legacy-imported.json` 那个标记（理由同 `dropSharedSearchHistory()`）：
  /// 早就越过标记的老用户机器上，那份冻住的副本还躺着，挂上标记等于不清。
  /// 写入早已改道到文件，这个键不会再被写第二次，所以每次启动跑一遍是幂等的。
  private func dropLegacySymbols() {
    UserDefaults.standard.removeObject(forKey: SymbolPrefsStore.defaultsKey)
    UserDefaults.standard.removeObject(forKey: SymbolPrefsStore.legacyDefaultsKey)
  }
  private func migrateLegacy() throws {
    let marker = files.root.appendingPathComponent("legacy-imported.json")
    guard !FileManager.default.fileExists(atPath: marker.path) else { return }
    let guest = try files.directory(user: nil)
    let values: [(String, Data)] = [("prefs.json", PrefsCodec.encode(prefs.prefs)), ("symbols.json", try JSONEncoder().encode(symbols.prefs)), ("draws.json", try JSONEncoder().encode(drawings.storedArchive))]
    for (name, data) in values {
      let target = guest.appendingPathComponent(name)
      if !FileManager.default.fileExists(atPath: target.path) { try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }
    // Only the unowned local review archive is eligible for automatic migration.
    //
    // 复盘落**三个**文件，不是一个：主档 `review-v1.json`、草稿 `draft-v1.json`、
    // 重温进度 `replay-positions.json`。这儿原来只搬主档，于是老用户升上来那一刻
    // 「写了一半还没提交的那条草稿」和「每条记录重温到哪一根」全留在老目录里再也读不到——
    // 那两份是纯粹的用户产出，不是可以重算的缓存。主档能不能搬得通仍然是前提
    // （`ReviewStore(directory:)` 解不动就抛，整次迁移不做）。
    let source = ReviewChartBridge.storageDirectory().appendingPathComponent("local", isDirectory: true)
    let old = source.appendingPathComponent("review-v1.json")
    if FileManager.default.fileExists(atPath: old.path),
       !FileManager.default.fileExists(atPath: guest.appendingPathComponent("review-v1.json").path) {
      _ = try ReviewStore(directory: source)
      for name in ["review-v1.json", "draft-v1.json", "replay-positions.json"] {
        let from = source.appendingPathComponent(name), to = guest.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: from.path),
              !FileManager.default.fileExists(atPath: to.path) else { continue }
        try FileManager.default.copyItem(at: from, to: to)
      }
    }
    try AccountFiles.write(true, to: marker)
  }
  private func prepare(_ user: AccountUser?) throws -> (@MainActor () -> Void) {
    // 同一个属主重复 prepare 是纯浪费：整套读盘 + 解码 + ReviewStore 初始化白做一遍，
    // 账号状态又原样换回去。冷启动的 `prepare(nil)` 和退登的 `prepare(nil)` 属主不同，
    // 不会被这里挡掉（一次都没 prepare 过时 `preparedOwner` 是 `.none`）。
    if let prepared = preparedOwner, prepared == user?.id, personal != nil { return {} }
    // 换档案是「必须现在就保证在盘上」的那种路口，所以这儿准阻塞（判据见
    // `ArchiveWriter.drain()`）。非排空不可的理由：正式文件的写现在排在写盘队列上
    // （见 `init` 里那三个 `persistence` 钩子），而下面这一整段是在主线程上**读**
    // 那几份文件、再按合并结果**写**回去。不排空的话，上一份档案里还没落完的那笔
    // 会落在这一段之后，把刚写回去的结果盖成旧的。
    sync?.flushNow()
    let directory = try files.directory(user: user?.id)
    let nextStorage = try PersonalFileStorage(directory: directory)
    let nextInbox = try ShareInbox.read(directory: directory)
    var nextPrefs = PrefsStore.load(from: nextStorage)
    // 自选要和画线同一个姿态：**读不动就把整段 `prepare` 中断**，绝不拿一份凭空造出来的
    // 空档往下走（下面 `:255` 那一步会把它回写进 `symbols.json`，用户的自选就永久没了）。
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
    let verdict = prefs.diagnose(nextStorage, owner: profileOwner)
    let archivedSettings = try nextSync.flatMap { sync in
      try sync.archive.local[PersonalSyncCodec.settings(nextPrefs).key].flatMap { try? PersonalSyncCodec.apply($0, to: nextPrefs) }
    }
    let recovery = SettingsRecovery.plan(verdict, onDisk: nextPrefs, baseline: archivedSettings)
    nextPrefs = recovery.prefs
    let claim = try user.flatMap { try files.claimGuest(user: $0.id) }
    if let claim {
      let guestStorage = try PersonalFileStorage(directory: claim.directory)
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
      if !FileManager.default.fileExists(atPath: directory.appendingPathComponent("draws.json").path) { nextDrawings.preferences = guestDrawings.preferences; adopted.insert("drawingPreferences") }
      let claimedAlerts = Set(nextAlerts.alerts.map(\.id))
      nextAlerts.alerts += guestAlerts.alerts.filter { !claimedAlerts.contains($0.id) }
      let groupIDs = Set(nextSymbols.groups.map(\.id))
      nextSymbols.groups += guestSymbols.groups.filter { !groupIDs.contains($0.id) }
      for key in guestSymbols.favorites where !nextSymbols.favorites.contains(key) {
        nextSymbols.favorites.append(key); nextSymbols.groupForSymbol[key] = guestSymbols.groupForSymbol[key]
        if guestSymbols.pinned.contains(key) { nextSymbols.pinned.append(key) }
      }
      let guestReview = try ReviewStore(directory: claim.directory)
      try nextReview.transaction { archive in
        for var record in guestReview.archive.records where record.serverId == nil && !archive.records.contains(where: { $0.id == record.id }) {
          record.draft = sanitize(record.draft); archive.records.append(record)
        }
        for var op in guestReview.archive.queue where !archive.queue.contains(where: { $0.id == op.id }) {
          guard archive.records.contains(where: { $0.id == op.recordId && $0.serverId == nil }) else { continue }
          if op.kind == "create", let value = try? JSONDecoder().decode(ReviewDraft.self, from: op.body) { op.body = try JSONEncoder().encode(sanitize(value)); op.attempted = nil }
          archive.queue.append(op)
        }
      }
      // 草稿与重温进度是两份**侧文件**，各自有自己的落盘位置，不能只改主档里那份镜像：
      // 草稿只写进 `archive.draft` 的话，下次 `ReviewStore.init` 会拿账号目录里那份
      // 写着「现在没有草稿」的 `draft-v1.json` 把它盖掉（游客写了一半的那条当场消失），
      // 进度则是压根没人并。规则与证据都在 `ReviewStore.adoptSideFiles(from:)`。
      try nextReview.adoptSideFiles(from: guestReview, sanitizingDraft: sanitize)
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
      for tombstone in nextSync.archive.objects.values where tombstone.collection == "drawings" && tombstone.deleted {
        let name = PersonalSyncCodec.instrument(tombstone); guard !name.isEmpty else { continue }
        let id = String(tombstone.id.split(separator: "/").last ?? "")
        if !nextSync.archive.operations.contains(where: { $0.objectId == tombstone.id && $0.action == "restore" }) {
          nextDrawings[name].removeAll { $0.id == id }
        }
      }
      // 画线的启动前向对账（B2）。
      //
      // 画线落两个文件：`DrawingController.write()` 先落同步存档（新的本地值和
      // 那条待发操作在同一份档里），再落 `draws.json`。两次写之间进程没了，盘上
      // 就是「新存档 + 旧 draws.json」。这里把差额向前补进 `draws.json`。
      //
      // **只向前**：只补那些存档里「本机说了算」（有待发操作或未了结的拒绝记录）
      // 的对象。云端下发的那些一个都不碰，否则这一步就成了拿存档去回滚用户
      // 已经落在盘上的画线。
      // 提醒也照样：删掉的不许在启动时复活，本机说了算的那几条向前补进 `alerts.json`。
      for tombstone in nextSync.archive.objects.values where tombstone.collection == "alerts" && tombstone.deleted {
        let id = String(tombstone.id.split(separator: "/").last ?? "")
        if !nextSync.archive.operations.contains(where: { $0.objectId == tombstone.id && $0.action == "restore" }) {
          nextAlerts.alerts.removeAll { $0.id == id }
        }
      }
      for object in nextSync.unpersistedLocalChanges(in: ["alerts"], onDisk: (try? PersonalSyncCodec.alerts(nextAlerts.alerts)) ?? []) {
        let id = String(object.id.split(separator: "/").last ?? "")
        if object.deleted { nextAlerts.alerts.removeAll { $0.id == id }; continue }
        guard let alert = try? PersonalSyncCodec.alert(object) else { continue }
        nextAlerts[id] = alert
      }
      let onDisk = (try? PersonalSyncCodec.drawings(nextDrawings)) ?? []
      for object in nextSync.unpersistedLocalChanges(in: ["drawings", "drawingPreferences"], onDisk: onDisk) {
        if object.collection == "drawingPreferences" {
          if let value = try? KanpanAccount.JSONValue.object(PersonalSyncCodec.expand(object.body)).decode(DrawingPreferences.self) {
            nextDrawings.preferences = value
          }
          continue
        }
        let name = PersonalSyncCodec.instrument(object); guard !name.isEmpty else { continue }
        let id = String(object.id.split(separator: "/").last ?? "")
        if object.deleted {
          nextDrawings[name].removeAll { $0.id == id }
          continue
        }
        // 解不开的那条就跳过：待发操作还在队列里，用户的意图不会丢，
        // 而云端那份也进不了 `local`，下一轮还有机会。
        guard let drawing = try? PersonalSyncCodec.drawing(object) else { continue }
        if let index = nextDrawings[name].firstIndex(where: { $0.id == id }) { nextDrawings[name][index] = drawing }
        else { nextDrawings[name].append(drawing) }
      }
      // 自选 / 分组的启动前向对账。判据和上面画线、提醒那两段逐字同义，只是
      // 这一档从前**根本没有**这一步——因为它的两次写本来就是反着的
      // （`symbols.json` 先落、存档后落），落在补得回来的那一侧的情况压根不会出现。
      // 2026-09-22 把顺序掉过来之后，「新存档 + 旧 symbols.json」成了崩溃后的常态，
      // 这一段就是把它补回来的人；没有它，用户重开会看见被自己删掉的那条自选还在，
      // 要等下一次云端应用才恢复。
      //
      // **只向前**：只补那些「本机说了算」（有待发操作或未了结的拒绝记录）的对象，
      // 云端下发的那些一个都不碰。位置按存档里记的 `order` 插回去，插不进就落到末尾——
      // 真身顺序仍以那条待发操作为准，下一次 `applyPending` 会把它摆正。
      for object in nextSync.unpersistedLocalChanges(in: ["favorites", "groups"], onDisk: PersonalSyncCodec.symbols(nextSymbols)) {
        var slot = Int.max
        if case .number(let order) = object.body["order"] { slot = Int(order) }
        if object.collection == "groups" {
          nextSymbols.groups.removeAll { $0.id == object.id }
          guard !object.deleted, case .string(let name) = object.body["name"] else { continue }
          nextSymbols.groups.insert(FavoriteGroup(id: object.id, name: name), at: min(max(slot, 0), nextSymbols.groups.count))
          continue
        }
        let symbol = PersonalSyncCodec.instrument(object); guard !symbol.isEmpty else { continue }
        nextSymbols.favorites.removeAll { $0 == symbol }
        nextSymbols.pinned.removeAll { $0 == symbol }
        nextSymbols.groupForSymbol[symbol] = nil
        guard !object.deleted else { continue }
        nextSymbols.favorites.insert(symbol, at: min(max(slot, 0), nextSymbols.favorites.count))
        if case .string(let group) = object.body["groupId"] { nextSymbols.groupForSymbol[symbol] = group }
        if object.body["pinned"] == .bool(true) { nextSymbols.pinned.append(symbol) }
      }
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
    nextSymbols.legacySelectedGroup = nil
    // Complete all fallible disk preparation before replacing any visible account state.
    // 这三份以前每次冷启动都原样重写一遍，只是为了「确保文件在」。读一次小 JSON 比
    // 一次原子写（临时文件 + rename + fsync）便宜得多，只在内容真的不一样时才落盘。
    let encodedPrefs = PrefsCodec.encode(nextPrefs)
    if encodedPrefs != nextStorage.prefsData(forKey: PrefsCodec.key) { nextStorage.setPrefsData(encodedPrefs, forKey: PrefsCodec.key) }
    let encodedSymbols = try JSONEncoder().encode(nextSymbols)
    if encodedSymbols != nextStorage.symbolPrefsData(forKey: SymbolPrefsStore.defaultsKey) { nextStorage.setSymbolPrefsData(encodedSymbols, forKey: SymbolPrefsStore.defaultsKey) }
    if nextStorage.error != nil { throw AccountError.storage }
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
      let baseline = nextSync.archive.local[settings.key].flatMap { try? PersonalSyncCodec.apply($0, to: nextPrefs) }
      // 盘上那份不可信时一条操作都不记（`SettingsRecovery.Plan.mayCapture`）。
      if recovery.mayCapture, dirty || ChartLayoutReconcile.decide(onDisk: nextPrefs, baseline: baseline) == .recapture {
        try nextSync.capture([settings], device: account.device.id, owning: PersonalSyncCodec.ownedKeys)
      }
      nextSync.flushNow()
    }
    let client: ScorebookClient?
    if user != nil, let api = account.client {
      client = ScorebookClient(connection: ReviewConnection(baseURL: api.baseURL)) { path, method, body, key in
        try await api.data(path, method: method, body: body, key: key)
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
      task?.cancel(); debounce?.cancel(); task = nil; taskID = UUID(); epoch = UUID(); gate.rotate(); gate.enter()
      onSwitch()
      owner = user?.id; personal = nextStorage; sync = nextSync
      preparedOwner = .some(user?.id)
      // 换属主之后本机拿到的是空档，下一次同步必须把服务端那份整份拉回来。
      needsBootstrap = true; lastBootstrap = .distantPast; bootstrappedDrawings = []
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
      gate.leave(); updateStatus()
      // 档案已经全部就位，宿主现在可以按它重新兑现首屏那几件事。
      onProfileReady()
      // 第一次装这个 app 的人手上是空的：没账号、没自选。给他几条默认自选，
      // 什么时候给、给过没有都在 `DefaultFavoritesSeeder` 里（方案第 3 节第四件）。
      // 代次拿来防「取榜那几秒里账号档案回来了」——那时这一趟当场作废。
      let seedEpoch = epoch
      DefaultFavoritesSeeder.consider(symbols: symbols, isGuest: user == nil,
                                      stillCurrent: { [weak self] in self?.epoch == seedEpoch },
                                      done: { [weak self] in self?.onProfileReady() })
      // 上一次运行拉回来了、但没装进本机就没了的那一批，在这儿补装（B4）。
      // 判据在存档里，所以断电重开照样看得出来，不用等下一轮全量。
      if nextSync?.needsApply == true { pendingApply = true; resumeApply() }
    }
  }
  private func sanitize(_ input: ReviewDraft) -> ReviewDraft {
    var value = input
    if let data = value.chartSettings, (try? PersonalSyncCodec.snapshotPrefs(data)) == nil {
      value.chartSettings = (try? JSONDecoder().decode(Prefs.self, from: data)).flatMap { try? PersonalSyncCodec.snapshot($0) }
    }
    return value
  }
  /// 图上换了品种。
  ///
  /// 以前这里直接 `synchronize()`：推完待发操作还要无条件走一遍四个 collection 的
  /// 全量 bootstrap 再加一次复盘同步，已登录用户每换一个品种就是五六次跨洋往返
  /// 加好几次整档重写。现在只做两件事——有待发就推，以及**这个会话里第一次**
  /// 看到这个品种时把它的画线拉一次（别的设备上画的线还是会出现，只是不再每次重拉）。
  func focus(_ symbol: String) {
    guard self.symbol != symbol else { return }
    self.symbol = symbol
    guard let sync, owner != nil else { return }
    let fresh = !symbol.isEmpty && !bootstrappedDrawings.contains(symbol)
    guard fresh || !sync.archive.operations.isEmpty else { return }
    run(fresh ? .drawings : .push, manual: false)
  }
  private func capture(_ objects: [SyncObject], collections: Set<String>) {
    guard !gate.isApplying, owner != nil, let sync else { return }
    do {
      if let error = personal?.error { account.syncStatus = error; return }
      let keys = Set(objects.map(\.key))
      let deleted = sync.archive.local.values.filter { collections.contains($0.collection) && !keys.contains($0.key) && !$0.deleted }
      // 一次事务记完：自选每条都带 `order`，往头部插一个品种会让后面每一条都变，
      // 逐条 capture 等于整档重写 N 次。
      try sync.capture(objects + deleted.map { var value = $0; value.deleted = true; return value },
                       device: account.device.id, owning: PersonalSyncCodec.ownedKeys)
      // **落盘立刻发起，但不在主线程上等它写完。**
      //
      // `sync.capture` 里那一句 `ArchiveWriter.schedule` 就是「现在开始写」：字节已经
      // 交给写盘队列，队列是 `.userInitiated`，手一抬到落盘通常几毫秒。手势结束那一刻
      // 要的「立刻落盘」到这里就兑现了。
      //
      // 这儿原来还跟着一句 `sync.flushNow()`（`queue.sync {}`），理由写的是「app 这一刻
      // 被杀，下次冷启动 `applyPending()` 会拿存档里那份旧的把偏好盖回去」，代价估成
      // 「几百字节的小 JSON」。两头都不成立，去掉了：
      //
      // - **代价不是几百字节。** 每条画线的完整几何在存档的 `objects` 和 `local` 里
      //   各存一份，`settings:chart` 一项就有 10.6 KB × 2；实测一份只有四条线的真实
      //   存档是 46 KB，画线多起来就是几百 KB。等的是这一整份的 JSON 编码 + 原子写，
      //   而这条路每次抬手、每次改设置都要走一遍。
      // - **它防的那个窗口已经被别人关死了。** 其一，「app 被杀」这件事在本仓里有
      //   唯一入口 `AppLifecycle`：`init` 里那个 `.sync` 档的钩子（`:107`）在离开前台 /
      //   进后台 / `willTerminate` 时调 `flushNow()`，而且**排在所有产数据的钩子后面**，
      //   用户划掉 app 走的正是这条路。其二，被举例的那个「偏好被盖回去」在设置这一档
      //   根本轮不到存档来兜：`PrefsStore.persist()` 是**同步**写 prefs.json + 脏标识，
      //   而且发生在 `onChange`（也就是这条 capture）**之前**；冷启动时 `prepare()`
      //   看见脏标识就会重新 `capture` 一条操作（`:340`），`applyPending()` 也按
      //   `Prefs.keeping(dirtyFields:)` 护着脏字段不被云端覆盖。存档丢掉那一版，
      //   用户的值一个字都不少。
      //
      // 剩下的窗口写在这儿，别再让下一个人去猜：**没有任何通知的猝死**（jetsam / 崩溃）
      // 恰好落在这几毫秒里时，画线与自选那两档会丢掉「这一改还没推上去」的记账——
      // 盘上的 draws.json / symbols.json 仍然是新的，用户看得见自己的东西，
      // 但下一次拉取会拿云端那份旧的把它盖回去。这是**几毫秒**换掉每次抬手的卡顿。
      // 至于网络推送，仍旧留给下面那 500ms 去抖：那是省流量，不是省命。
      updateStatus(); debounce?.cancel()
      debounce = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(500)); guard !Task.isCancelled else { return }; self?.run(.push, manual: false)
      }
    } catch { account.report(sync: error) }
  }
  private func captureSettings() {
    do {
      let object = try PersonalSyncCodec.settings(prefs.prefs)
      capture([object], collections: ["settings"])
      settleAgreedSettings(object)
    } catch { account.report(sync: error) }
  }
  /// 记完账再对一遍账：**脏着、却和存档一致、队列里也没它的**字段，清掉脏标识。
  ///
  /// `SyncStore.capture` 比出手上这份和存档 `local` 一样就不记操作，这本身没错——
  /// 没变化不该占队列。但 `PrefsStore` 的脏标识是在**改动那一刻**打的，它不知道
  /// 这一改在同步层看来是不是「没变化」（用户把周期从 4h 换到 1h 又换回 4h；
  /// 或者改动发生时正在应用云端那批，`gate` 把记账挡了，事后云端那份已经等于本地）。
  /// 于是脏标识永远等不到 `syncPushed` 来清它，这个字段就永远「本地更新、云端别碰」。
  ///
  /// 判「有东西可推」的三处：手上这份和存档 `local` 的差异、队列里对这个对象还没被
  /// 认下的操作、被服务端顶回来等着补推的那条。三处都不沾的脏字段才清。
  private func settleAgreedSettings(_ object: SyncObject) {
    guard !gate.isApplying, owner != nil, let sync, prefs.stamp.isDirty,
          let baseline = sync.archive.local[object.key], !baseline.deleted else { return }
    var blocked = Set<String>()
    for key in Set(object.body.keys).union(baseline.body.keys) where object.body[key] != baseline.body[key] {
      blocked.formUnion(SettingsWire.fields(for: key))
    }
    let queued = sync.archive.operations.filter { $0.collection == object.collection && $0.objectId == object.id }.map(\.fields)
      + sync.archive.rejected.filter { $0.intent.key == object.key }.map(\.operation.fields)
    for fields in queued { for key in fields.keys { blocked.formUnion(SettingsWire.fields(for: key)) } }
    let agreed = prefs.dirtyFields.subtracting(blocked)
    guard !agreed.isEmpty else { return }
    prefs.syncAgreed(agreed)
  }
  private func captureSymbols() { capture(PersonalSyncCodec.symbols(symbols.prefs), collections: ["favorites", "groups"]) }
  private func captureDrawings() { do { capture(try PersonalSyncCodec.drawings(drawings.storedArchive), collections: ["drawings", "drawingPreferences"]) } catch { account.report(sync: error) } }
  private func captureAlerts() { do { capture(try PersonalSyncCodec.alerts(alerts.all), collections: ["alerts"]) } catch { account.report(sync: error) } }
  /// 把这台设备的推送 token 交给服务端。
  ///
  /// 失败**不报给用户**：没有推送只是「提醒要等下一次打开 app 才看得见」，
  /// 不是故障（`kanpan-no-engineering-status-fields`）。没登录时连发都不发——
  /// 这个接口按人存 token。
  /// 这台设备的推送 token 还欠不欠某个账号一次上报（见 `PushTokenLedger`）。
  /// token 来的时候、以及每次同步都问一遍：没登录时来的 token，登录后补报；
  /// 报的那一下失败了，下一次同步再报。
  private func submitPushToken() {
    guard let api = account.client, let owner,
          let token = pushLedger.due(token: PushRegistration.token, owner: owner) else { return }
    let body: [String: String] = ["token": token, "kind": "alerts", "environment": PushRegistration.environment]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
    pushLedger.begin(token: token, owner: owner)
    Task { [weak self] in
      let ok = (try? await api.data("v1/devices/push-token", method: "POST", body: data)) != nil
      self?.pushLedger.finish(token: token, owner: owner, ok: ok)
    }
  }
  /// 「盯一个」那条实时活动的推送令牌：服务端拿它按行情推锁屏更新（有 APNs 密钥时）。
  func submitActivityToken(_ token: String, activityID: String, alertID: String) {
    guard let api = account.client, owner != nil else { return }
    let body: [String: String] = ["token": token, "kind": "liveActivity", "environment": PushRegistration.environment,
                                  "activityId": activityID, "alertId": alertID]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
    Task { _ = try? await api.data("v1/devices/push-token", method: "POST", body: data) }
  }
  /// 活动收起：服务端停止给它推更新、丢掉令牌。
  func endActivity(_ activityID: String) {
    guard let api = account.client, owner != nil else { return }
    guard let data = try? JSONSerialization.data(withJSONObject: ["activityId": activityID]) else { return }
    Task { _ = try? await api.data("v1/devices/live-activity/end", method: "POST", body: data) }
  }
  private func setAutoSync(_ enabled: Bool) {
    do {
      try sync?.transaction { $0.autoSync = enabled }; updateStatus()
      if enabled { run(.push, manual: false) } else { task?.cancel(); task = nil; taskID = UUID(); review.pauseAutomaticSync() }
    } catch { account.report(sync: error) }
  }
  private func updateStatus() {
    account.autoSync = sync?.archive.autoSync ?? true; review.autoSync = account.autoSync
    account.pending = (sync?.archive.operations.count ?? 0) + review.pendingUploads
    account.lastSync = sync?.archive.lastSync.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    // 被隔离的那几条要说出来：它们不在 `pending` 里（不会永远挂着归不了零），
    // 但用户的改动确实还没上云——这句就是那件事的唯一交代。
    //
    // 数是从**存档**里读的，不是内存里的一个数组：那些改动重启之后还在本机、
    // 还没推上去，这句话重启之后也就还得成立（B3）。
    let stuck = sync?.archive.rejected.count ?? 0
    account.syncStatus = owner == nil ? "" : !account.autoSync ? "已暂停" : account.pending > 0 ? "待同步"
      : stuck > 0 ? "\(stuck) 项暂未同步"
      : account.lastSync == nil ? "尚未同步" : "已同步"
  }
  /// 这一轮同步做到哪一步。
  private enum SyncPlan {
    /// 只把待发操作推上去。切品种、本地改动去抖之后走这条。
    case push
    /// 推完再拉一次当前品种的画线（每个品种每个会话一次）。
    case drawings
    /// 推完拉四档全量，再带一次复盘同步。只在登录 / 恢复会话 / 手动同步 /
    /// 距上次全量 ≥5 分钟的回前台 / 被服务端顶回来之后发生。
    case full
  }
  /// 外部（回前台、设置页、登录回调）唯一的入口。到点了才做全量。
  func synchronize(manual: Bool = false) {
    let due = needsBootstrap || Date().timeIntervalSince(lastBootstrap) >= Self.bootstrapInterval
    run(manual || due ? .full : .push, manual: manual)
    submitPushToken()
    // 分享不是个人同步：暂停自动同步也照样收信。只在登录 / 前台拉取入口挂一次。
    let current = epoch; let running = task
    Task { [weak self] in
      await running?.value
      guard let self, epoch == current else { return }
      inbox.pull()
    }
  }
  /// 上一轮还在跑时被挡下来的那次推送（值是它的 `manual`）。跑完补上。
  ///
  /// 以前 `run` 开头那句 `guard task == nil` 是**直接吞掉**的：用户手一松要求推一次，
  /// 正赶上前一轮同步没跑完，这一次就当没发生过。存档里那条操作只能等下一次触发，
  /// app 要是这会儿被杀，云端就永远停在旧值上。
  private var queuedPush: Bool?

  /// 被服务端按语义顶回来的那些操作现在记在**存档**里（`SyncArchive.rejected`），
  /// 不再是内存里的一个数组。见 `SyncStore.quarantine`。

  /// 这个错误是不是「再发一万次也不会成功」。
  ///
  /// 400 / 422 这类是服务端对内容本身的判决（字段不认、格式不对），重试没有意义；
  /// 401 要重新登录、429 是限流、5xx 与网络错误都是「这次不行」，那些该留在队列里
  /// 等下一轮。409 分两种，见 `isRollback`：`resync_required` 要重拉重整，
  /// `idempotency_mismatch` 是「同 id 的操作已经落过库、载荷却对不上」——那条
  /// 再发一万次也只会拿到同一个 409，只能隔离。
  private static func isPermanent(_ error: AccountError) -> Bool {
    guard case .http(let code, let reason) = error else { return false }
    if reason == "idempotency_mismatch" { return true }
    if code == 401 || code == 409 || code == 429 { return false }
    return code == 400 || code == 422 || reason == "invalid_operation"
  }
  /// 请求体太大被服务端挡在门外（413）。它和 409 一样证明这一批一条都没落库：
  /// `DefaultBodyLimit` 是在进 handler 之前拒的，根本没到数据库。
  private static func isTooLarge(_ error: AccountError) -> Bool {
    guard case .http(413, _) = error else { return false }
    return true
  }
  /// 这个错误能不能证明**这一批服务端一条都没落库**。
  ///
  /// `merge()` 在事务里抛 `resync_required`，`tx.commit()` 根本没跑到，所以整批
  /// 确定回滚，可以把 `sent` 清掉重整。别的理由不行：`idempotency_mismatch`
  /// 恰恰说明同 id 的操作确实已经落过库。
  private static func isRollback(_ error: AccountError) -> Bool {
    guard case .http(409, let reason) = error else { return false }
    return reason == "resync_required"
  }
  /// 一轮同步里最多做几次「回滚 → 重拉 → 重整 → 接着推」。
  ///
  /// 恢复本身要花两三次跨洋往返，正常最多用一次（服务端顶回来的那一下）。给三次
  /// 是为了容下「重拉的同时别的设备又改了一次」；再多就不是冲突而是打转了，
  /// 剩下的留给下一轮。
  private static let resyncBudget = 3
  /// 被 409 顶回来之后，把这一批碰过的对象重新拉一遍。
  ///
  /// **必须在这一轮里就拉。** `resync_required` 之后只置 `needsBootstrap` 是不够的：
  /// 下一轮 `.full` 照样**先跑推送循环**，照样撞同一个 409，永远到不了用来修复它的
  /// 拉取阶段——整个账号的队列就此再也前进不了（B1）。
  ///
  /// 按 collection 归并着拉，画线再按品种那一层的前缀收窄（画线 id 是
  /// `venue/market/symbol/<线 id>`）：既不会退化成一条一个请求，也不会为了一条线
  /// 把这个人所有品种的画线都拖回来。
  private func refetch(_ batch: [SyncOperation], api: AccountClient, into sync: SyncStore) async throws {
    var scopes: Set<[String]> = []
    for op in batch {
      guard op.collection == "drawings" else { scopes.insert([op.collection]); continue }
      let folder = op.objectId.split(separator: "/").dropLast().joined(separator: "/")
      scopes.insert(folder.isEmpty ? [op.collection] : [op.collection, folder + "/"])
    }
    for scope in scopes.sorted(by: { $0.joined(separator: "/") < $1.joined(separator: "/") }) {
      var after: String?
      repeat {
        var query = [URLQueryItem(name: "collection", value: scope[0])]
        if scope.count > 1 { query.append(URLQueryItem(name: "prefix", value: scope[1])) }
        if let after { query.append(URLQueryItem(name: "after", value: after)) }
        var components = URLComponents(); components.queryItems = query
        let page: SyncPage = try await api.request("v1/sync/bootstrap" + (components.string ?? ""))
        try Task.checkCancellation()
        try sync.receive(page); after = page.next
      } while after != nil
    }
  }
  private func run(_ plan: SyncPlan, manual: Bool) {
    guard task == nil else {
      // 全量 / 画线那两档自己有别的触发点（回前台、换品种），不必排队；
      // 会丢东西的只有「把待发操作推上去」这一档。
      if case .push = plan { queuedPush = (queuedPush ?? false) || manual }
      return
    }
    guard let sync, let api = account.client, owner != nil, manual || sync.archive.autoSync else { return }
    let requestEpoch = epoch; let requestedSymbol = symbol
    let runID = UUID(); taskID = runID
    account.syncStatus = "同步中"
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        if requestEpoch == epoch && taskID == runID {
          task = nil
          // 这一轮跑的时候用户又换了品种：补一次，但只补新品种要的那点。
          if requestedSymbol != symbol {
            let fresh = !symbol.isEmpty && !bootstrappedDrawings.contains(symbol)
            if fresh || !sync.archive.operations.isEmpty { run(fresh ? .drawings : .push, manual: false) }
          }
          // 这一轮跑的时候有人要过推送、被上面那道 guard 挡了：现在补上。
          if let queued = queuedPush, task == nil {
            queuedPush = nil
            if !sync.archive.operations.isEmpty { run(.push, manual: queued) }
          }
        }
      }
      do {
        // 一次一批，最多 100 条（服务端上限）。幂等落在每条操作的 id 上，
        // 整批重发时已生效的那几条按 digest 原样返回，不会重复应用。
        // 推上去那一刻的脏字段快照。推成功之后按「时刻没变」逐个清——
        // **推成功才清**，失败 / 断网 / 被杀都留着，下次启动本地照样赢。
        let marks = prefs.dirtyMarks
        // 这一轮开始时「云端改过本机记账」的计数。一轮下来它没动、又没拉任何 scope，
        // 就是纯推送：本机界面上已经是最新的，合并与两次阻塞落盘都省掉（见收尾处）。
        let arrivals = sync.remoteArrivals
        // 服务端**认掉**的那些操作里带的线上字段名。`markSent` 只是「发出去了」，
        // 不算成功；成功以 `SyncPushResponse` 里按 `operationId` 对上的为准，
        // 而且要扣掉它回报的 `droppedFields`（认了这条，但这几项没收下）。
        var acked: Set<String> = []
        // 这一轮**没落地**的那些线上字段名：被 `droppedFields` 顶回来的、整条没回执的、
        // 被隔离的。它得和 `acked` 一起交给 `SettingsStamp`——本地一个 `params` 字段
        // 在线上是 `params/MA`、`params/EMA`… 好几条路径（`PersonalSyncCodec.flatten`），
        // 只认下一条就把整个字段的脏标记清掉，等于把另外那条没推上去的改动当成推过了。
        // 哪些算「没落地」在这儿算，别让 `SettingsStamp` 去猜。
        var dropped: Set<String> = []
        // 撞过一次「这条永远不会成功」之后改成一条一条发，把坏的那条揪出来单独隔离，
        // 不让它替后面所有好操作挡路。
        var oneByOne = false
        // 还剩几次「回滚 → 重拉 → 重整 → 接着推」的机会。
        var resyncs = Self.resyncBudget
        // 这一轮的字节上限。撞过 413 就对半砍，砍到单条也过不去时把那条隔离掉。
        var byteBudget = Self.pushBatchBytes
        while !sync.archive.operations.isEmpty {
          try Task.checkCancellation()
          // 一批不是「队首一百条」，是「队首一百条里**能安全同批**的那几条」：
          // 删除后面紧跟的恢复、恢复后面带旧 generation 的那些，同批必定整批回滚
          // （`SyncStore.batch` 写了服务端 `merge()` 逐条推出来的那几条边）。
          // 两道闸：条数（服务端 `sync.rs` 的上限）和**编码之后的真实字节数**
          // （`DefaultBodyLimit`）。削法与理由都在 `SyncStore.nextBatch(limit:maxBytes:)`。
          let batch = sync.nextBatch(limit: oneByOne ? 1 : Self.pushBatchLimit, maxBytes: byteBudget)
          let payload = try JSONEncoder().encode(SyncPushRequest(batch))
          if payload.count > byteBudget {
            // 单独一条就超限：它再发一万次也只会换回 413。和语义错误那一档同一个
            // 处置——隔离掉，本地值与脏标记一个不动，别让它把后面所有人的操作堵死。
            if batch[0].collection == "settings" && batch[0].objectId == "chart" {
              dropped.formUnion(batch[0].fields.keys)
            }
            try sync.quarantine(batch[0].id, reason: "payload_too_large")
            updateStatus()
            continue
          }
          let before = sync.archive.operations.count
          try sync.markSent(batch.map(\.id))
          let result: SyncPushResponse
          do {
            result = try await api.request("v1/sync/operations", method: "POST", body: payload, key: batch[0].id)
          } catch let error as AccountError where Self.isTooLarge(error) {
            // 413：服务端连读都没读完，**这一批一条都没落库**（和 `resync_required`
            // 同一个性质），所以先把 `sent` 清掉，再把上限对半砍了重来。原样重发
            // 是死循环——这正是「一条大画线把整条队列堵死」的走法。
            try Task.checkCancellation(); guard requestEpoch == epoch && taskID == runID else { return }
            try sync.rollback(batch.map(\.id))
            // 砍到 16 KiB 就不再往下砍：再小也只能说明是那一条本身发不上去，
            // 下一圈开头那道字节闸会把它认出来并隔离掉，循环一定收敛。
            byteBudget = max(16 * 1024, min(byteBudget, payload.count) / 2)
            updateStatus()
            continue
          } catch let error as AccountError where Self.isRollback(error) && resyncs > 0 {
            // 服务端那一整个事务已经回滚，这批**一条都没落地**。所以：先把 `sent`
            // 清掉（不清就没法重整，那些操作会一直被当成「结果不明、不许碰」），
            // 然后**在同一轮里**把受影响的对象拉回来，按新版本重整本地意图，
            // 最后接着推。等下一轮就是回到同一个 409 里打转。
            try Task.checkCancellation(); guard requestEpoch == epoch && taskID == runID else { return }
            resyncs -= 1
            try sync.rollback(batch.map(\.id))
            try await refetch(batch, api: api, into: sync)
            guard requestEpoch == epoch && taskID == runID else { return }
            try sync.realign()
            // 重拉过之后本机这份已经是新的了，这一轮的全量不必再为它重来一次。
            updateStatus()
            continue
          } catch let error as AccountError where Self.isPermanent(error) {
            // 语义错误（400 / 422）：这条**再发一万次也不会成功**。重试只会把
            // 整条队列堵死——一次缩放就能让这个账号从此再也同步不上任何东西
            // （2026-09-19 实测：服务端 `valid_field` 不认 `barSpacing`，
            // 整条操作被 `invalid_operation` 顶回来）。
            try Task.checkCancellation(); guard requestEpoch == epoch && taskID == runID else { return }
            guard batch.count == 1 else { oneByOne = true; continue }   // 先揪出是哪一条
            let reason: String = { if case .http(_, let code) = error { return code }; return "request_failed" }()
            try sync.quarantine(batch[0].id, reason: reason)
            // **本地值和脏标记一个都不动**：下次启动本地照样赢。这条连同用户当时的
            // 意图一起写进了存档（`SyncArchive.rejected`），所以它既挡得住云端那份
            // 把本地值盖回去，也能在服务端修好之后由 `retryRejected` 用一条**新 id**
            // 的操作自己补上去，不用用户再改一次。被隔离的这条里那几条线上路径
            // 记进 `dropped`，免得同一个字段的兄弟路径在别的操作里被认下，
            // 反倒把这个字段的脏标记顺手清了。
            if batch[0].collection == "settings" && batch[0].objectId == "chart" {
              dropped.formUnion(batch[0].fields.keys)
            }
            updateStatus()
            continue
          }
          try Task.checkCancellation(); guard requestEpoch == epoch && taskID == runID else { return }
          let receipts = Dictionary(result.results.map { ($0.operationId, Set($0.droppedFields ?? [])) }, uniquingKeysWith: { a, _ in a })
          for op in batch where op.collection == "settings" && op.objectId == "chart" {
            guard let missed = receipts[op.id] else {                   // 没回执 = 没认掉
              dropped.formUnion(op.fields.keys); continue
            }
            acked.formUnion(op.fields.keys.filter { !missed.contains($0) })
            dropped.formUnion(missed)
          }
          try sync.acknowledge(result)
          // 服务端没认掉任何一条就别空转。
          guard sync.archive.operations.count < before else { break }
        }
        // 跳出循环时队列里还剩下的（服务端一条没认、被隔离的顶在前面挡着）：也算没落地。
        // 同一个字段的另一条路径还躺在队列里时，不能因为先发的那条被认下就把它清了。
        for op in sync.archive.operations where op.collection == "settings" && op.objectId == "chart" {
          dropped.formUnion(op.fields.keys)
        }
        // **只清服务端认下的那几个字段。** 被隔离的、被 `droppedFields` 丢掉的、
        // 还在队列里没发的，脏标记全都留着——下次启动本地照样赢。
        prefs.syncPushed(marks, acked: acked, dropped: dropped)
        var scopes: [String] = []
        switch plan {
        case .push: scopes = []
        case .drawings: scopes = requestedSymbol.isEmpty ? [] : ["drawings"]
        case .full: scopes = ["settings", "drawingPreferences", "favorites", "groups", "alerts"] + (requestedSymbol.isEmpty ? [] : ["drawings"])
        }
        for collection in scopes {
          var after: String?
          repeat {
            var query = [URLQueryItem(name: "collection", value: collection)]
            if collection == "drawings" { query.append(URLQueryItem(name: "prefix", value: InstrumentID.canonical(requestedSymbol) + "/")) }
            if let after { query.append(URLQueryItem(name: "after", value: after)) }
            var components = URLComponents(); components.queryItems = query
            let page: SyncPage = try await api.request("v1/sync/bootstrap" + (components.string ?? ""))
            try Task.checkCancellation(); guard requestEpoch == epoch && taskID == runID else { return }
            try sync.receive(page); after = page.next
          } while after != nil
        }
        if scopes.contains("drawings") { bootstrappedDrawings.insert(requestedSymbol) }
        if case .full = plan {
          needsBootstrap = false; lastBootstrap = Date()
          // 服务端修好之后，被它顶回来过的那几项自己补上去，不用用户再改一次。
          // **只在全量这一档。** 每次推送后都重试就是个忙循环：服务端要是真的
          // 永远不认这个字段，那就是每 500 毫秒一次跨洋往返换一次 400。
          // 这儿刚把云端那份拉回来，正好拿它和当前本地值现做差分。
          try sync.retryRejected(device: account.device.id, owning: PersonalSyncCodec.ownedKeys)
          if !sync.archive.operations.isEmpty { queuedPush = queuedPush ?? false }
        }
        // 纯推送（没拉任何 scope）而且回执没带回别的设备的改动：`local` 里没有界面上还没有的
        // 东西，`applyPending()` 那一整套（全量合并、两次主线程 `flushNow()`、`onProfileReady()`）
        // 跑了也是原样写回。这时把两个时刻一起记上就收工。上一次被 `canApply()` 挡下的
        // （`pendingApply`）、或者拉下来还没装进去的（`needsApply`），照旧走合并。
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if scopes.isEmpty, !pendingApply, try !sync.finishPushOnlyRound(since: arrivals, at: now) {
          updateStatus()
        } else {
          // 只记「拉到哪儿了」。「装进本机没有」由 `applyPending()` 落盘成功后自己记（B4）。
          try sync.markFetched(at: now)
          try applyPending(); updateStatus()
        }
        // 复盘同步只跟着全量走：登录 / 恢复会话 / 手动 / 到点的回前台。
        if case .full = plan { review.synchronize(manual: manual) }
      } catch is CancellationError { if requestEpoch == epoch && taskID == runID { updateStatus() } }
      catch {
        // 被服务端按版本顶回来了：本机这份不再可信，下一轮必须整份重拉。
        if case AccountError.http(let code, _) = error, (400..<500).contains(code), code != 401, code != 429 { needsBootstrap = true }
        if requestEpoch == epoch && taskID == runID { account.pending = sync.archive.operations.count; account.report(sync: error) }
      }
    }
  }
  /// 面板 / 画线 / 复盘关掉之后补跑一次被挡下的 `applyPending()`。
  ///
  /// 以前 `applyPending()` 撞上 `canApply() == false` 就直接 return、不留任何补跑的钩子，
  /// 云端刚改的设置最坏要等下一轮全量（`bootstrapInterval` = 300 秒）才落地——正是
  /// 「改完要等一下才生效」。现在挡下来时记一笔，条件一到齐就补。
  func resumeApply() {
    guard pendingApply, canApply(), sync != nil else { return }
    do { try applyPending(); updateStatus() } catch { account.report(sync: error) }
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
  /// （各文件 + 存档里的 `lastApplied`），落盘成功之后才清 `pendingApply`；
  /// 第三段才把同一代值推给内存里的 store 与界面。
  func applyPending() throws {
    guard let sync else { return }
    guard canApply() else { pendingApply = true; return }
    // 进门先记成「这一批还没装进去」，而不是从前那样先把它清掉。中途抛错时这一笔
    // 还在，面板一关 `resumeApply()` 就会重来；清掉的时机在第二段落盘成功之后。
    pendingApply = true
    let objects = sync.archive.local

    // —— 一、准备。只算不写，也不碰任何可见状态。这一段抛错等于这一批整个没发生。
    var nextPrefs: Prefs?
    if let settings = objects["settings:chart"] {
      // 按字段合并：本地脏的一律跳过，干净的跟着云端走。这里先算出合并结果，
      // 第三段 `prefs.applySynced` 会把同一套规则再走一遍（幂等）。
      nextPrefs = Prefs.keeping(prefs.dirtyFields, of: prefs.prefs, over: try PersonalSyncCodec.apply(settings, to: prefs.prefs))
    }
    var archive = drawings.storedArchive
    if let tools = objects["drawingPreferences:tools"] {
      archive.preferences = try KanpanAccount.JSONValue.object(PersonalSyncCodec.expand(tools.body)).decode(DrawingPreferences.self)
    }
    for object in objects.values where object.collection == "drawings" {
      let name = PersonalSyncCodec.instrument(object); guard !name.isEmpty else { continue }
      let id = String(object.id.split(separator: "/").last ?? "")
      if object.deleted { archive[name].removeAll { $0.id == id } }
      else {
        // 解不开的那条跳过，别整批抛（和下面提醒那一段同一条规矩）。
        // 新版本加一把画线工具，老版本的机器就会在这儿读到一个它不认识的 `kind`：
        // 整批抛出去的话 `pendingApply` 一直挂着，每次重试都在同一条上翻车，
        // 这台设备从此再也收不到任何设置、自选、画线——只因为别的设备画了一条新工具。
        guard let drawing = try? PersonalSyncCodec.drawing(object) else { continue }
        if let index = archive[name].firstIndex(where: { $0.id == id }) { archive[name][index] = drawing }
        else { archive[name].append(drawing) }
      }
    }
    // 提醒。服务端判出触发之后会自己写一条 `patch`（`status` / `firedAt` / `firedPrice`），
    // 就是从这儿落进本机的——所以这一段既管「别的设备加的提醒」，也管「它响了」。
    // 解不开的那条跳过而不是整批抛：一条坏数据不该让设置、自选、画线一起落不了地。
    var alertArchive = alerts.archive
    for object in objects.values where object.collection == "alerts" {
      let id = String(object.id.split(separator: "/").last ?? "")
      if object.deleted { alertArchive.alerts.removeAll { $0.id == id }; continue }
      guard let alert = try? PersonalSyncCodec.alert(object) else { continue }
      alertArchive[id] = alert
    }
    func order(_ a: SyncObject, _ b: SyncObject) -> Bool {
      let x: Double = { if case .number(let n) = a.body["order"] { return n }; return 0 }()
      let y: Double = { if case .number(let n) = b.body["order"] { return n }; return 0 }()
      return x == y ? a.id < b.id : x < y
    }
    let groups = objects.values.filter { $0.collection == "groups" && !$0.deleted }.sorted(by: order).compactMap { v -> FavoriteGroup? in
      guard case .string(let name) = v.body["name"] else { return nil }; return FavoriteGroup(id: v.id, name: name)
    }
    let favorites = objects.values.filter { $0.collection == "favorites" && !$0.deleted }.sorted(by: order)
    var names: [String] = [], membership: [String: String] = [:], pinned: [String] = []
    for value in favorites {
      let name = PersonalSyncCodec.instrument(value); guard !name.isEmpty else { continue }; names.append(name)
      if case .string(let group) = value.body["groupId"] { membership[name] = group }
      if value.body["pinned"] == .bool(true) { pinned.append(name) }
    }
    // 服务端只同步自选/分组这几张表，「最近」「常看」一直是本机的事——
    // 重建时要把它们原样带回去，否则每来一次同步就把常看清零。
    //
    // 这儿原来是手抄一行 `SymbolPrefs(favorites:recents:…:viewScores:scoredAt:)`，
    // 少抄一个本机字段就是「每同步一次，常看被清空一次」，而且不报任何错。现在改成
    // **云端重建出来的那份当底，再按 `SymbolFieldPlan` 的 localOnly 表把本机字段抄回去**：
    // 清单只有那一张表，加字段的人不必记得回这儿补参数（`SymbolFieldPlanTests` 替他记）。
    let rebuilt = SymbolPrefs(favorites: names, groups: groups, groupForSymbol: membership, pinned: pinned)
    let nextSymbols = SymbolPrefs.keeping(SymbolPrefs.localOnlyFieldNames, of: symbols.prefs, over: rebuilt)
    let encodedSymbols = try JSONEncoder().encode(nextSymbols)

    // —— 二、落盘。整套候选态一次性提交；成功之后才准清 `pendingApply`。
    //
    // 动手之前先把写盘队列排空。这一段是在主线程上直接写 `prefs.json` /
    // `symbols.json` / `draws.json` / `alerts.json`，而用户刚才那几笔编辑的正式文件
    // 写正排在队列上（`init` 里的 `persistence` 钩子）；不排空的话，那几笔会落在
    // 这一批之后，把刚装进来的云端那一代盖回旧的。这条路不是手指上的路
    // （它本来后面就跟着一次 `flushNow()`），准阻塞。
    sync.flushNow()
    if let nextPrefs, nextPrefs != prefs.prefs {
      personal?.setPrefsData(PrefsCodec.encode(nextPrefs), forKey: PrefsCodec.key)
    }
    if nextSymbols != symbols.prefs {
      personal?.setSymbolPrefsData(encodedSymbols, forKey: SymbolPrefsStore.defaultsKey)
    }
    if personal?.error != nil { throw AccountError.storage }
    try drawings.commitSynced(archive)
    try alerts.commitSynced(alertArchive)
    // 「拉到哪儿了」和「装进本机没有」是两个时刻。这一句必须排在所有文件落盘之后：
    // 它一旦落下去，下一次启动就不会再重做这一批了。
    try sync.markApplied(at: Int64(Date().timeIntervalSince1970 * 1000))
    sync.flushNow()
    pendingApply = false

    // —— 三、发布。到这儿盘上已经是新的一代，内存与界面跟上。
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
    drawings.publishSynced(archive)
    alerts.publishSynced(alertArchive)
    symbols.applySynced(nextSymbols)
    // 云端那份设置也是「档案换进来了」的一种：周期、落地页这些要跟着重新兑现一次。
    onProfileReady()
  }
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
  func recordLayout() { captureSettings() }
  /// 顺手推一次。推不上去无所谓（离线、没登录、正在跑别的），操作已经在盘上了，
  /// 下次同步会带走它；这里只是想让另一台设备早点看到。
  func pushLayout() { run(.push, manual: false) }
}
