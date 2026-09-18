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
  private let review: ReviewFeature
  private let search: SearchHistory
  private var personal: PersonalFileStorage?
  private var sync: SyncStore?
  private var owner: UUID?
  private var epoch = UUID()
  private var task: Task<Void, Never>?
  private var taskID = UUID()
  private var debounce: Task<Void, Never>?
  private var applying = false
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
  var canApply: () -> Bool = { true }
  var onSwitch: () -> Void = {}
  /// 档案（prefs / symbols / 画线）**真的换进来之后**响一次。
  ///
  /// 和 `onSwitch` 的分工：`onSwitch` 在换属主**之前**响，用来把复盘、面板、浮层收干净；
  /// 这一个在 `useStorage` 全做完之后响，宿主可以在这儿按新档案重新兑现「该开哪张图、
  /// 该停在哪一格、该用哪个周期」。冷启动装访客档案、恢复登录态、换号、退登、
  /// 以及云端设置落地（`applyPending`）都会走到它。
  var onProfileReady: () -> Void = {}
  /// 上一次 `applyPending()` 被 `canApply()` 挡回去了，等条件到齐要补跑。
  private var pendingApply = false

  init(account: AccountFeature, prefs: PrefsStore, symbols: SymbolPickerModel, drawings: DrawingController, review: ReviewFeature, search: SearchHistory) throws {
    self.account = account; self.prefs = prefs; self.symbols = symbols; self.drawings = drawings; self.review = review; self.search = search
    var root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("kanpan/accounts")
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1", let profile = ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"], UUID(uuidString: profile) != nil { root = root.appendingPathComponent("tests/" + profile) }
    files = try AccountFiles(root: root)
    try migrateLegacy()
    dropSharedSearchHistory()
    dropLegacySymbols()
    account.onPrepareAccount = { [weak self] user in guard let self else { return {} }; return try self.prepare(user) }
    account.onSynchronize = { [weak self] in self?.synchronize(manual: true) }
    account.onAutoSync = { [weak self] enabled in self?.setAutoSync(enabled) }
    prefs.onChange = { [weak self] _ in self?.captureSettings() }
    symbols.onPrefsChange = { [weak self] _ in self?.captureSymbols() }
    drawings.onArchiveChange = { [weak self] _ in self?.captureDrawings() }
    review.onLogin = { [weak account] in account?.open() }
    review.onSyncComplete = { [weak self] in
      guard let self else { return }
      do {
        if let owner, let batch = try files.pendingGuest(user: owner), sync?.archive.operations.isEmpty == true, review.pendingUploads == 0 {
          try files.completeGuestClaim(user: owner, batch: batch.id)
        }
        updateStatus()
      } catch { account.syncStatus = error.localizedDescription }
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
    let old = ReviewChartBridge.storageDirectory().appendingPathComponent("local/review-v1.json")
    let next = guest.appendingPathComponent("review-v1.json")
    if FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: next.path) {
      _ = try ReviewStore(directory: old.deletingLastPathComponent())
      try FileManager.default.copyItem(at: old, to: next)
    }
    try AccountFiles.write(true, to: marker)
  }
  private func prepare(_ user: AccountUser?) throws -> (@MainActor () -> Void) {
    // 同一个属主重复 prepare 是纯浪费：整套读盘 + 解码 + ReviewStore 初始化白做一遍，
    // 账号状态又原样换回去。冷启动的 `prepare(nil)` 和退登的 `prepare(nil)` 属主不同，
    // 不会被这里挡掉（一次都没 prepare 过时 `preparedOwner` 是 `.none`）。
    if let prepared = preparedOwner, prepared == user?.id, personal != nil { return {} }
    let directory = try files.directory(user: user?.id)
    let nextStorage = try PersonalFileStorage(directory: directory)
    var nextPrefs = PrefsStore.load(from: nextStorage)
    var nextSymbols = SymbolPrefsStore(storage: nextStorage).load()
    let drawStore = DrawStore(url: directory.appendingPathComponent("draws.json"))
    var nextDrawings = try drawStore.read()
    let loadedDrawings = nextDrawings
    let nextReview = try ReviewStore(directory: directory)
    let nextSync = user == nil ? nil : try SyncStore(directory: directory)
    let claim = try user.flatMap { try files.claimGuest(user: $0.id) }
    if let claim {
      let guestStorage = try PersonalFileStorage(directory: claim.directory)
      let guestPrefs = PrefsStore.load(from: guestStorage)
      let guestSymbols = SymbolPrefsStore(storage: guestStorage).load()
      let guestDrawings = try DrawStore(url: claim.directory.appendingPathComponent("draws.json")).read()
      if !FileManager.default.fileExists(atPath: directory.appendingPathComponent("prefs.json").path) { nextPrefs = guestPrefs }
      for (key, values) in guestDrawings.bySymbol {
        let existing = Set(nextDrawings[key].map(\.id)); nextDrawings[key] += values.filter { !existing.contains($0.id) }
      }
      if !FileManager.default.fileExists(atPath: directory.appendingPathComponent("draws.json").path) { nextDrawings.preferences = guestDrawings.preferences }
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
        if archive.draft == nil { archive.draft = guestReview.archive.draft.map(sanitize) }
      }
      if let nextSync {
        let imported = try [PersonalSyncCodec.settings(guestPrefs)] + PersonalSyncCodec.drawings(guestDrawings) + PersonalSyncCodec.symbols(guestSymbols)
        // 一次事务记完：逐条来的话这一档要被整份重写几十上百遍。
        try nextSync.capture(imported, device: account.device.id, importing: claim.id)
      }
    }
    if let nextSync {
      for tombstone in nextSync.archive.objects.values where tombstone.collection == "drawings" && tombstone.deleted {
        guard case .string(let name) = tombstone.body["symbol"] else { continue }
        let id = String(tombstone.id.split(separator: "/").last ?? "")
        if !nextSync.archive.operations.contains(where: { $0.objectId == tombstone.id && $0.action == "restore" }) {
          nextDrawings[name].removeAll { $0.id == id }
        }
      }
    }
    PersonalSyncCodec.keepDeviceFields(prefs.prefs, in: &nextPrefs)
    // Complete all fallible disk preparation before replacing any visible account state.
    // 这三份以前每次冷启动都原样重写一遍，只是为了「确保文件在」。读一次小 JSON 比
    // 一次原子写（临时文件 + rename + fsync）便宜得多，只在内容真的不一样时才落盘。
    let encodedPrefs = PrefsCodec.encode(nextPrefs)
    if encodedPrefs != nextStorage.prefsData(forKey: PrefsCodec.key) { nextStorage.setPrefsData(encodedPrefs, forKey: PrefsCodec.key) }
    let encodedSymbols = try JSONEncoder().encode(nextSymbols)
    if encodedSymbols != nextStorage.symbolPrefsData(forKey: SymbolPrefsStore.defaultsKey) { nextStorage.setSymbolPrefsData(encodedSymbols, forKey: SymbolPrefsStore.defaultsKey) }
    if nextStorage.error != nil { throw AccountError.storage }
    if nextDrawings != loadedDrawings { try drawStore.save(nextDrawings) }
    if let nextSync {
      let settings = try PersonalSyncCodec.settings(nextPrefs)
      let initial = try [settings] + PersonalSyncCodec.drawings(nextDrawings) + PersonalSyncCodec.symbols(nextSymbols)
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
      if dirty || ChartLayoutReconcile.decide(onDisk: nextPrefs, baseline: baseline) == .recapture {
        try nextSync.capture([settings], device: account.device.id)
      }
      nextSync.flushNow()
    }
    let client: ScorebookClient?
    if let user, let api = account.client {
      client = ScorebookClient(connection: ReviewConnection(baseURL: api.baseURL, account: user.id.uuidString)) { path, method, body, key in
        try await api.data(path, method: method, body: body, key: key)
      }
    } else { client = nil }
    let previouslyPrepared = preparedOwner
    return { [self] in
      task?.cancel(); debounce?.cancel(); task = nil; taskID = UUID(); epoch = UUID(); applying = true
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
      prefs.useStorage(nextStorage, prefs: nextPrefs, arrival: arrival,
                       owner: user?.id.uuidString ?? ("guest:" + files.guestBatch.uuidString))
      symbols.useStorage(SymbolPrefsStore(storage: nextStorage), prefs: nextSymbols)
      drawings.useStorage(drawStore, archive: nextDrawings)
      search.useStorage(nextStorage)
      review.activate(store: nextReview, client: client)
      applying = false; updateStatus()
      // 档案已经全部就位，宿主现在可以按它重新兑现首屏那几件事。
      onProfileReady()
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
    guard !applying, owner != nil, let sync else { return }
    do {
      if let error = personal?.error { account.syncStatus = error; return }
      let keys = Set(objects.map(\.key))
      let deleted = sync.archive.local.values.filter { collections.contains($0.collection) && !keys.contains($0.key) && !$0.deleted }
      // 一次事务记完：自选每条都带 `order`，往头部插一个品种会让后面每一条都变，
      // 逐条 capture 等于整档重写 N 次。
      try sync.capture(objects + deleted.map { var value = $0; value.deleted = true; return value }, device: account.device.id)
      // **立刻把这笔操作写到盘上。**
      //
      // `sync.capture` 只是把 transaction 排进写盘队列，队列在后台串行跑；app 这一刻
      // 被杀（用户捏完一下顺手划掉），这条操作就跟着进程一起没了，而下次冷启动
      // `applyPending()` 会拿存档里那份旧的把偏好盖回去——用户看到的就是「改动没生效」。
      // 排空队列是 `queue.sync {}`，几百字节的小 JSON，不值得为它省。
      // 至于网络推送，仍旧留给下面那 500ms 去抖：那是省流量，不是省命。
      sync.flushNow()
      updateStatus(); debounce?.cancel()
      debounce = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(500)); guard !Task.isCancelled else { return }; self?.run(.push, manual: false)
      }
    } catch { account.syncStatus = error.localizedDescription }
  }
  private func captureSettings() { do { capture([try PersonalSyncCodec.settings(prefs.prefs)], collections: ["settings"]) } catch { account.syncStatus = error.localizedDescription } }
  private func captureSymbols() { capture(PersonalSyncCodec.symbols(symbols.prefs), collections: ["favorites", "groups"]) }
  private func captureDrawings() { do { capture(try PersonalSyncCodec.drawings(drawings.storedArchive), collections: ["drawings", "drawingPreferences"]) } catch { account.syncStatus = error.localizedDescription } }
  private func setAutoSync(_ enabled: Bool) {
    do {
      try sync?.transaction { $0.autoSync = enabled }; updateStatus()
      if enabled { run(.push, manual: false) } else { task?.cancel(); task = nil; taskID = UUID(); review.pauseAutomaticSync() }
    } catch { account.syncStatus = error.localizedDescription }
  }
  private func updateStatus() {
    account.autoSync = sync?.archive.autoSync ?? true; review.autoSync = account.autoSync
    account.pending = (sync?.archive.operations.count ?? 0) + review.pendingUploads
    account.lastSync = sync?.archive.lastSync.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    // 被隔离的那几条要说出来：它们不在 `pending` 里（不会永远挂着归不了零），
    // 但用户的改动确实还没上云——这句就是那件事的唯一交代。
    account.syncStatus = owner == nil ? "" : !account.autoSync ? "已暂停" : account.pending > 0 ? "待同步"
      : !stuck.isEmpty ? "有 \(stuck.count) 项这台服务器还不认，已留在本机"
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
  }
  /// 上一轮还在跑时被挡下来的那次推送（值是它的 `manual`）。跑完补上。
  ///
  /// 以前 `run` 开头那句 `guard task == nil` 是**直接吞掉**的：用户手一松要求推一次，
  /// 正赶上前一轮同步没跑完，这一次就当没发生过。存档里那条操作只能等下一次触发，
  /// app 要是这会儿被杀，云端就永远停在旧值上。
  private var queuedPush: Bool?

  /// 被服务端按语义顶回来、已经从待发队列里隔离出来的那些操作。
  ///
  /// 只活在这次会话里：用户的值和脏标记都还在本机，服务端修好之后下一次改动会
  /// 重新组一条新操作补上去，所以不需要把它们写进存档。留着是为了能在状态里
  /// 说清「有几项这台服务器还不认」，而不是让用户看见一个永远归不了零的 pending。
  private var stuck: [SyncOperation] = []

  /// 这个错误是不是「再发一万次也不会成功」。
  ///
  /// 400 / 422 这类是服务端对内容本身的判决（字段不认、格式不对），重试没有意义；
  /// 401 要重新登录、409 要重拉、429 是限流、5xx 与网络错误都是「这次不行」，
  /// 那些该留在队列里等下一轮。
  private static func isPermanent(_ error: AccountError) -> Bool {
    guard case .http(let code, let reason) = error else { return false }
    if code == 401 || code == 409 || code == 429 { return false }
    return code == 400 || code == 422 || reason == "invalid_operation"
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
        while !sync.archive.operations.isEmpty {
          try Task.checkCancellation()
          let batch = Array(sync.archive.operations.prefix(oneByOne ? 1 : Self.pushBatchLimit))
          let before = sync.archive.operations.count
          try sync.markSent(batch.map(\.id))
          struct Push: Encodable { var operations: [SyncOperation] }
          let result: SyncPushResponse
          do {
            result = try await api.request("v1/sync/operations", method: "POST", body: JSONEncoder().encode(Push(operations: batch)), key: batch[0].id)
          } catch let error as AccountError where Self.isPermanent(error) {
            // 语义错误（400 / 422）：这条**再发一万次也不会成功**。重试只会把
            // 整条队列堵死——一次缩放就能让这个账号从此再也同步不上任何东西
            // （2026-09-19 实测：服务端 `valid_field` 不认 `barSpacing`，
            // 整条操作被 `invalid_operation` 顶回来）。
            try Task.checkCancellation(); guard requestEpoch == epoch && taskID == runID else { return }
            guard batch.count == 1 else { oneByOne = true; continue }   // 先揪出是哪一条
            try sync.quarantine(batch[0].id)
            stuck.append(batch[0])
            // **本地值和脏标记一个都不动**：下次启动本地照样赢，服务端修好之后
            // 用户下一次改动会拿当前的值重新组一条新操作补上去。被隔离的这条里
            // 那几条线上路径记进 `dropped`，免得同一个字段的兄弟路径在别的操作里
            // 被认下，反倒把这个字段的脏标记顺手清了。
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
        case .full: scopes = ["settings", "drawingPreferences", "favorites", "groups"] + (requestedSymbol.isEmpty ? [] : ["drawings"])
        }
        for collection in scopes {
          var after: String?
          repeat {
            var query = [URLQueryItem(name: "collection", value: collection)]
            if collection == "drawings" { query.append(URLQueryItem(name: "prefix", value: "binance/usd_m/" + requestedSymbol + "/")) }
            if let after { query.append(URLQueryItem(name: "after", value: after)) }
            var components = URLComponents(); components.queryItems = query
            let page: SyncPage = try await api.request("v1/sync/bootstrap" + (components.string ?? ""))
            try Task.checkCancellation(); guard requestEpoch == epoch && taskID == runID else { return }
            try sync.receive(page); after = page.next
          } while after != nil
        }
        if scopes.contains("drawings") { bootstrappedDrawings.insert(requestedSymbol) }
        if case .full = plan { needsBootstrap = false; lastBootstrap = Date() }
        try sync.transaction { $0.lastSync = Int64(Date().timeIntervalSince1970 * 1000) }
        try applyPending(); updateStatus()
        // 复盘同步只跟着全量走：登录 / 恢复会话 / 手动 / 到点的回前台。
        if case .full = plan { review.synchronize(manual: manual) }
      } catch is CancellationError { if requestEpoch == epoch && taskID == runID { updateStatus() } }
      catch {
        // 被服务端按版本顶回来了：本机这份不再可信，下一轮必须整份重拉。
        if case AccountError.http(let code, _) = error, (400..<500).contains(code), code != 401, code != 429 { needsBootstrap = true }
        if requestEpoch == epoch && taskID == runID { account.pending = sync.archive.operations.count; account.syncStatus = error.localizedDescription }
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
    do { try applyPending(); updateStatus() } catch { account.syncStatus = error.localizedDescription }
  }
  func applyPending() throws {
    guard let sync else { return }
    guard canApply() else { pendingApply = true; return }
    pendingApply = false
    applying = true; defer { applying = false }
    let objects = sync.archive.local
    if let settings = objects["settings:chart"] {
      // `applySynced` 是**按字段合并**：本地脏的一律跳过，干净的跟着云端走。
      // 合并完本地还脏，就说明云端那份在这几个字段上是旧的——反过来把本地这份推上去，
      // 别等下一次用户改动才捎带。
      prefs.applySynced(try PersonalSyncCodec.apply(settings, to: prefs.prefs))
      if prefs.stamp.isDirty { captureSettings() }
    }
    var archive = drawings.storedArchive
    if let tools = objects["drawingPreferences:tools"] {
      archive.preferences = try KanpanAccount.JSONValue.object(PersonalSyncCodec.expand(tools.body)).decode(DrawingPreferences.self)
    }
    for object in objects.values where object.collection == "drawings" {
      guard case .string(let name) = object.body["symbol"] else { continue }
      let id = String(object.id.split(separator: "/").last ?? "")
      if object.deleted { archive[name].removeAll { $0.id == id } }
      else {
        let drawing = try PersonalSyncCodec.drawing(object)
        if let index = archive[name].firstIndex(where: { $0.id == id }) { archive[name][index] = drawing }
        else { archive[name].append(drawing) }
      }
    }
    try drawings.applySynced(archive)
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
      guard case .string(let name) = value.body["symbol"] else { continue }; names.append(name)
      if case .string(let group) = value.body["groupId"] { membership[name] = group }
      if value.body["pinned"] == .bool(true) { pinned.append(name) }
    }
    // 服务端只同步自选/分组这几张表，「最近」「常看」一直是本机的事——
    // 重建时要把它们原样带回去，否则每来一次同步就把常看清零。
    let value = SymbolPrefs(favorites: names, recents: symbols.prefs.recents, groups: groups,
                            groupForSymbol: membership, pinned: pinned,
                            selectedGroupID: symbols.prefs.selectedGroupID,
                            viewScores: symbols.prefs.viewScores, scoredAt: symbols.prefs.scoredAt)
    symbols.applySynced(value)
    // 云端那份设置也是「档案换进来了」的一种：周期、落地页这些要跟着重新兑现一次。
    onProfileReady()
  }
}

/// 视野模块的「云端那条腿」。
///
/// `ChartViewport` 只认这三个动作，不认识账号、存档、网络；没登录时它手上这个引用
/// 是 `nil`，模块照常工作。登录与否对外**没有第二种行为**——同一个保存时刻、
/// 同一套语义，差别只在这条腿在不在。
extension AppAccountBridge: ChartViewport.Sync {
  /// 把当前这份设置记成一条待发操作（内存 + 排进写盘队列）。
  func recordLayout() { captureSettings() }
  /// 把写盘队列排空。**这一句才是「杀了 app 也还在」的那一刀。**
  func flushLayoutArchive() { sync?.flushNow() }
  /// 顺手推一次。推不上去无所谓（离线、没登录、正在跑别的），操作已经在盘上了，
  /// 下次同步会带走它；这里只是想让另一台设备早点看到。
  func pushLayout() { run(.push, manual: false) }
}
