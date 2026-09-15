import Foundation
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
    let directory = try files.directory(user: user?.id)
    let nextStorage = try PersonalFileStorage(directory: directory)
    var nextPrefs = PrefsStore.load(from: nextStorage)
    var nextSymbols = SymbolPrefsStore(storage: nextStorage).load()
    let drawStore = DrawStore(url: directory.appendingPathComponent("draws.json"))
    var nextDrawings = try drawStore.read()
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
        for object in imported { try nextSync.capture(object, device: account.device.id, importing: claim.id) }
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
    nextStorage.setPrefsData(PrefsCodec.encode(nextPrefs), forKey: PrefsCodec.key)
    nextStorage.setSymbolPrefsData(try JSONEncoder().encode(nextSymbols), forKey: SymbolPrefsStore.defaultsKey)
    if nextStorage.error != nil { throw AccountError.storage }
    try drawStore.save(nextDrawings)
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
  func focus(_ symbol: String) {
    guard self.symbol != symbol else { return }; self.symbol = symbol; synchronize()
  }
  private func capture(_ objects: [SyncObject], collections: Set<String>) {
    guard !applying, owner != nil, let sync else { return }
    do {
      if let error = personal?.error { account.syncStatus = error; return }
      let keys = Set(objects.map(\.key))
      let deleted = sync.archive.local.values.filter { collections.contains($0.collection) && !keys.contains($0.key) && !$0.deleted }
      for object in objects { try sync.capture(object, device: account.device.id) }
      for var object in deleted { object.deleted = true; try sync.capture(object, device: account.device.id) }
      updateStatus(); debounce?.cancel()
      debounce = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(500)); guard !Task.isCancelled else { return }; self?.synchronize()
      }
    } catch { account.syncStatus = error.localizedDescription }
  }
  private func captureSettings() { do { capture([try PersonalSyncCodec.settings(prefs.prefs)], collections: ["settings"]) } catch { account.syncStatus = error.localizedDescription } }
  private func captureSymbols() { capture(PersonalSyncCodec.symbols(symbols.prefs), collections: ["favorites", "groups"]) }
  private func captureDrawings() { do { capture(try PersonalSyncCodec.drawings(drawings.storedArchive), collections: ["drawings", "drawingPreferences"]) } catch { account.syncStatus = error.localizedDescription } }
  private func setAutoSync(_ enabled: Bool) {
    do {
      try sync?.transaction { $0.autoSync = enabled }; updateStatus()
      if enabled { synchronize() } else { task?.cancel(); task = nil; taskID = UUID(); review.pauseAutomaticSync() }
    } catch { account.syncStatus = error.localizedDescription }
  }
  private func updateStatus() {
    account.autoSync = sync?.archive.autoSync ?? true; review.autoSync = account.autoSync
    account.pending = (sync?.archive.operations.count ?? 0) + review.pendingUploads
    account.lastSync = sync?.archive.lastSync.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    account.syncStatus = owner == nil ? "" : !account.autoSync ? "已暂停" : account.pending > 0 ? "待同步" : account.lastSync == nil ? "尚未同步" : "已同步"
  }
  func synchronize(manual: Bool = false) {
    guard task == nil, let sync, let api = account.client, owner != nil, manual || sync.archive.autoSync else { return }
    let requestEpoch = epoch; let requestedSymbol = symbol
    let runID = UUID(); taskID = runID
    account.syncStatus = "同步中"
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        if requestEpoch == epoch && taskID == runID {
          task = nil
          if requestedSymbol != symbol { synchronize() }
        }
      }
      do {
        while let op = sync.archive.operations.first {
          try Task.checkCancellation(); try sync.markSent(op.id)
          struct Push: Encodable { var operations: [SyncOperation] }
          let result: SyncPushResponse = try await api.request("v1/sync/operations", method: "POST", body: JSONEncoder().encode(Push(operations: [op])), key: op.id)
          try Task.checkCancellation(); guard requestEpoch == epoch && taskID == runID else { return }
          try sync.acknowledge(result)
        }
        let scopes = ["settings", "drawingPreferences", "favorites", "groups"] + (requestedSymbol.isEmpty ? [] : ["drawings"])
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
        try sync.transaction { $0.lastSync = Int64(Date().timeIntervalSince1970 * 1000) }
        try applyPending(); updateStatus(); review.synchronize(manual: manual)
      } catch is CancellationError { if requestEpoch == epoch && taskID == runID { updateStatus() } }
      catch { if requestEpoch == epoch && taskID == runID { account.pending = sync.archive.operations.count; account.syncStatus = error.localizedDescription } }
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
    let value = SymbolPrefs(favorites: names, recents: symbols.prefs.recents, groups: groups, groupForSymbol: membership, pinned: pinned, selectedGroupID: symbols.prefs.selectedGroupID)
    symbols.applySynced(value)
  }
}
