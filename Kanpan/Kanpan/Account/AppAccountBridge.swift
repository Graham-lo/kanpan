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

  init(account: AccountFeature, prefs: PrefsStore, symbols: SymbolPickerModel, drawings: DrawingController, review: ReviewFeature) throws {
    self.account = account; self.prefs = prefs; self.symbols = symbols; self.drawings = drawings; self.review = review
    var root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("kanpan/accounts")
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1", let profile = ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"], UUID(uuidString: profile) != nil { root = root.appendingPathComponent("tests/" + profile) }
    files = try AccountFiles(root: root)
    try migrateLegacy()
    try prepare(nil)()
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
    // 存档写盘走后台串行队列；退到后台时把排队的写全部落地，免得被系统挂起/回收时
    // 最后一次 transaction 还停在内存里。
    NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.sync?.flushNow() }
    }
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
    var nextPrefs = PrefsDecodeCache.load(from: nextStorage)
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
      let initial = try [PersonalSyncCodec.settings(nextPrefs)] + PersonalSyncCodec.drawings(nextDrawings) + PersonalSyncCodec.symbols(nextSymbols)
      try nextSync.transaction { archive in for object in initial where archive.local[object.key] == nil { archive.local[object.key] = object } }
    }
    let client: ScorebookClient?
    if let user, let api = account.client {
      client = ScorebookClient(connection: ReviewConnection(baseURL: api.baseURL, account: user.id.uuidString)) { path, method, body, key in
        try await api.data(path, method: method, body: body, key: key)
      }
    } else { client = nil }
    return { [self] in
      task?.cancel(); debounce?.cancel(); task = nil; taskID = UUID(); epoch = UUID(); applying = true
      onSwitch()
      owner = user?.id; personal = nextStorage; sync = nextSync
      preparedOwner = .some(user?.id)
      // 换属主之后本机拿到的是空档，下一次同步必须把服务端那份整份拉回来。
      needsBootstrap = true; lastBootstrap = .distantPast; bootstrappedDrawings = []
      prefs.useStorage(nextStorage, prefs: nextPrefs)
      symbols.useStorage(SymbolPrefsStore(storage: nextStorage), prefs: nextSymbols)
      drawings.useStorage(drawStore, archive: nextDrawings)
      review.activate(store: nextReview, client: client)
      applying = false; updateStatus()
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
    account.syncStatus = owner == nil ? "" : !account.autoSync ? "已暂停" : account.pending > 0 ? "待同步" : account.lastSync == nil ? "尚未同步" : "已同步"
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
  private func run(_ plan: SyncPlan, manual: Bool) {
    guard task == nil, let sync, let api = account.client, owner != nil, manual || sync.archive.autoSync else { return }
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
        }
      }
      do {
        // 一次一批，最多 100 条（服务端上限）。幂等落在每条操作的 id 上，
        // 整批重发时已生效的那几条按 digest 原样返回，不会重复应用。
        while !sync.archive.operations.isEmpty {
          try Task.checkCancellation()
          let batch = Array(sync.archive.operations.prefix(Self.pushBatchLimit))
          let before = sync.archive.operations.count
          try sync.markSent(batch.map(\.id))
          struct Push: Encodable { var operations: [SyncOperation] }
          let result: SyncPushResponse = try await api.request("v1/sync/operations", method: "POST", body: JSONEncoder().encode(Push(operations: batch)), key: batch[0].id)
          try Task.checkCancellation(); guard requestEpoch == epoch && taskID == runID else { return }
          try sync.acknowledge(result)
          // 服务端没认掉任何一条就别空转。
          guard sync.archive.operations.count < before else { break }
        }
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
  func applyPending() throws {
    guard canApply(), let sync else { return }
    applying = true; defer { applying = false }
    let objects = sync.archive.local
    if let settings = objects["settings:chart"] { prefs.applySynced(try PersonalSyncCodec.apply(settings, to: prefs.prefs)) }
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
  }
}
