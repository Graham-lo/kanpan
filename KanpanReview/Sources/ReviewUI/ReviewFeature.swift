import Foundation
import Observation
import ReviewDomain
import ReviewData

@MainActor @Observable public final class ReviewFeature {
  public var bookOpen = false
  public var captureOpen = false
  public var searchOpen = false
  /// 这一轮「找相似」是从哪条记录上发起的。宿主拿它记住重温的来路：看完某个相似
  /// 行情退出来，人该站回那条记录和它的搜索层上，而不是被扔在一张行情图上。
  public var searchRecord: UUID?
  public var selectedRecord: UUID?
  public var draft: ReviewDraft?
  public private(set) var records: [ReviewRecord] = []
  public private(set) var matches: [ReviewMatch] = []
  public private(set) var statistics: [ReviewStatsGroup] = []
  public private(set) var syncing = false
  public private(set) var searching = false
  public private(set) var searchCutoff: Int64 = 0
  public private(set) var searchProgress = "正在查找"
  public private(set) var searchNext: String?
  public private(set) var partialSearch = false
  public private(set) var savedMatchIDs: Set<String> = []
  private var searchID: UUID?
  private var searchGeneration = UUID()
  public var notice: String?
  public var searchError: String?
  public var statisticsError: String?
  public var tab = "todo"
  public var replayPosition: ReviewReplayPosition?
  /// 「找相似」在哪个范围里找：`history`（市场历史）/ `private`（我的记录）。
  ///
  /// 以前这是 `ReviewSearchView` 自己的一个 `@State`，每呈现一次就回到「市场历史」；
  /// `ReviewRecordView` 里还另有一个同名 `@State`，没有任何 UI 写它，却被「找相似」
  /// 那颗按钮拿去发起第一次搜索。两处合成这一处：范围是人的习惯，不是某条记录的属性。
  ///
  /// 这个包看不见 app 的 `Prefs`，所以落盘交给宿主：`MainScreen` 把它和
  /// `Prefs.reviewSearchScope`（随账号同步）两头对接——进来时灌初值，
  /// 改了就写回去，云端换了一份也照样灌回来。
  public var searchScope = "history"
  public var onOpenChart: (ReviewRecord) -> Void = { _ in }
  public var onOpenMatch: (ReviewMatch, Int64) -> Void = { _, _ in }
  public var onCapture: () -> Void = {}
  public var onLogin: () -> Void = {}
  public var onSyncComplete: () -> Void = {}
  public var pendingUploads: Int { store?.archive.queue.count ?? 0 }
  private var syncID = UUID()
  public var autoSync = true
  public private(set) var nextPage: String?
  public private(set) var history: [ReviewRecord] = []
  public private(set) var historyLoading = false
  public private(set) var historyError: String?
  public private(set) var historyPage = 0
  private var historyCursors: [String?] = [nil]
  private var historyGeneration = UUID()
  private var historyQuery = ""
  private var historyTab = ""
  private var historyLoaded = false
  public var bookRecords: [ReviewRecord] {
    guard isConnected && historyLoaded else { return records }
    let pending = Set(store?.archive.queue.map(\.recordId) ?? [])
    return history.map { item in pending.contains(item.id) ? records.first(where: { $0.id == item.id }) ?? item : item }
  }
  public func record(_ id: UUID) -> ReviewRecord? {
    if store?.archive.queue.contains(where: { $0.recordId == id }) == true { return records.first(where: { $0.id == id }) }
    return history.first(where: { $0.id == id }) ?? records.first(where: { $0.id == id })
  }
  private var epoch = UUID()
  @ObservationIgnored private var store: ReviewStore?
  @ObservationIgnored private var client: ScorebookClient?
  @ObservationIgnored private let directory: URL
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var syncTask: Task<Void, Never>?
  public var pendingCount: Int { records.filter(\.needsAction).count }
  public var isConnected: Bool { client != nil }

  public init(directory: URL) {
    self.directory = directory
    do {
      store = try ReviewStore(directory: directory.appendingPathComponent("local"))
      reload()
    } catch { notice = error.localizedDescription }
  }
  public func activate(store: ReviewStore, client: ScorebookClient?) {
    syncTask?.cancel(); cancelSearch(); epoch = UUID(); syncID = UUID()
    self.store = store; self.client = client; store.cloudCache = client != nil
    syncing = false; searching = false; matches = []; statistics = []; searchID = nil; searchGeneration = UUID(); searchNext = nil; savedMatchIDs = []
    nextPage = nil; searchError = nil; statisticsError = nil; history = []; historyCursors = [nil]; historyPage = 0; historyGeneration = UUID(); historyLoading = false; historyError = nil; historyLoaded = false
    bookOpen = false; captureOpen = false; searchOpen = false; selectedRecord = nil; searchRecord = nil
    reload()
  }
  /// 复盘本每次打开都落在「待办」（§2G2）。
  ///
  /// 原来这儿读的是 `archive.lastTab`：上次翻到「战绩」，下次进来还停在战绩，可打开
  /// 复盘本九成是奔着「有什么该我处理的」去的，落在别的标签上等于每次都要先自己拨回来。
  /// `lastTab` 字段留在存档里没动（老档照旧能读），只是不再拿它定开场。
  private func reload() {
    guard let store else { return }
    records = store.archive.records; draft = store.archive.draft; tab = "todo"
  }
  @discardableResult private func change(_ edit: (inout ReviewArchive) throws -> Void) -> Bool {
    guard let store else { notice = "复盘存档暂时不可用，原文件已保留"; return false }
    do { try store.transaction(edit); records = store.archive.records; return true }
    catch { notice = error.localizedDescription; return false }
  }
  public func saveDraft() { do { try store?.saveDraft(draft) } catch { notice = error.localizedDescription } }
  public func begin(_ value: ReviewDraft) {
    draft = value; saveDraft(); captureOpen = true
  }
  /// 刚记下的那一条（§2F2）。图上的标记照它闪一次，toast 上的「查看」也开它。
  public var lastSaved: UUID?

  public func saveRecord() -> Bool {
    guard var value = draft else { return false }
    let now = ReviewClock.now
    if let error = value.validation(at: now) { notice = error; return false }
    value.created = now
    do {
      let record = ReviewRecord(draft: value)
      let op = ReviewOperation(recordId: value.id, kind: "create", body: try JSONEncoder().encode(value))
      guard change({ archive in
        guard !archive.records.contains(where: { $0.id == value.id }) else { return }
        archive.records.insert(record, at: 0); archive.queue.append(op); archive.draft = nil
      }) else { return false }
      // toast 那句话交给 `MainScreen` 说（要带一颗「查看」，见 §2F2），这儿只负责
      // 把「刚记下的是哪条」留下来。`notice` 是纯提示通道，挂不了动作。
      draft = nil; saveDraft(); captureOpen = false; lastSaved = value.id; synchronize(); return true
    } catch { notice = error.localizedDescription; return false }
  }
  public func saveReflection(_ id: UUID, note: String, nextTime: String, publish: Bool) {
    guard var record = record(id) else { return }
    if publish && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notice = "先写一句复盘"; return }
    if publish { record.reflectionHistory.append(record.reflection) }
    record.reflection.note = note; record.reflection.nextTime = nextTime
    record.reflection.publishedAt = publish ? ReviewClock.now : nil
    let expected = record.revision
    do {
      struct Edit: Encodable { var expectedRevision: Int; var reflection: ReviewReflection; var publish: Bool }
      let operation = ReviewOperation(recordId: id, kind: "reflection", body: try JSONEncoder().encode(Edit(expectedRevision: expected, reflection: record.reflection, publish: publish)))
      if change({ archive in
        if let i = archive.records.firstIndex(where: { $0.id == id }) { archive.records[i] = record } else { archive.records.insert(record, at: 0) }
        // Unsent drafts may be coalesced; a request whose outcome is uncertain retains its key.
        archive.queue.append(operation)
      }) { notice = publish ? "复盘已保存" : nil; synchronize() }
    } catch { notice = error.localizedDescription }
  }
  public func voidRecord(_ id: UUID) {
    guard let record = record(id) else { return }
    do {
      struct VoidInput: Encodable { var expectedRevision: Int }
      let operation = ReviewOperation(recordId: id, kind: "void", body: try JSONEncoder().encode(VoidInput(expectedRevision: record.revision)))
      if change({ archive in
        if let i = archive.records.firstIndex(where: { $0.id == id }) { archive.records[i].voided = true } else { var value = record; value.voided = true; archive.records.insert(value, at: 0) }
        archive.queue.append(operation)
      }) { synchronize() }
    } catch { notice = error.localizedDescription }
  }
  public func resolveGroup(_ id: UUID, sameEpisode: Bool) {
    guard var value = record(id) else { return }
    do {
      struct Input: Encodable { var expectedRevision: Int; var sameEpisode: Bool }
      let operation = ReviewOperation(recordId: id, kind: "group", body: try JSONEncoder().encode(Input(expectedRevision: value.revision, sameEpisode: sameEpisode)))
      value.groupPending = false
      if change({ archive in
        if let index = archive.records.firstIndex(where: { $0.id == id }) { archive.records[index] = value }
        else { archive.records.insert(value, at: 0) }
        archive.queue.append(operation)
      }) { synchronize() }
    } catch { notice = error.localizedDescription }
  }
  public func rememberReplay(_ id: UUID, position: ReviewReplayPosition) {
    replayPosition = position
    do { try store?.saveReplay(id, position: position) } catch { notice = error.localizedDescription }
  }
  public func savedReplay(_ id: UUID) -> ReviewReplayPosition? { store?.savedReplay(id) }
  public func loadHistory(query: String = "", page target: Int = 0) async {
    guard let client else { history = records; return }
    let requestedTab = tab
    let reset = query != historyQuery || requestedTab != historyTab || target == 0
    let next = reset ? 0 : target
    guard next >= 0, reset || next <= historyCursors.count else { return }
    let cursor: String? = reset ? nil : next < historyCursors.count ? historyCursors[next] : nextPage
    if next > 0 && cursor == nil { return }
    let requestEpoch = epoch; let generation = UUID(); historyGeneration = generation
    historyLoading = true; historyError = nil
    defer { if epoch == requestEpoch && historyGeneration == generation { historyLoading = false } }
    do {
      let response = try await client.list(after: cursor, query: query, todo: requestedTab == "todo")
      try Task.checkCancellation()
      guard epoch == requestEpoch && historyGeneration == generation else { return }
      if reset { historyCursors = [nil] } else if next == historyCursors.count { historyCursors.append(cursor) }
      history = response.records; historyLoaded = true; nextPage = response.next; historyPage = next; historyQuery = query; historyTab = requestedTab
      // First screen cache stays bounded; older pages live only while this view is open.
    } catch is CancellationError {} catch { if epoch == requestEpoch && historyGeneration == generation { historyError = error.localizedDescription } }
  }
  public func pauseAutomaticSync() { syncTask?.cancel(); syncID = UUID(); syncing = false }
  public func synchronize(manual: Bool = false) {
    guard (autoSync || manual), !syncing, let client else { return }
    let requestEpoch = epoch
    let runID = UUID(); syncID = runID
    syncing = true
    syncTask = Task { [weak self] in
      guard let self else { return }
      defer { if epoch == requestEpoch && syncID == runID { syncing = false } }
      do {
        while var operation = store?.archive.queue.first {
          try Task.checkCancellation()
          guard epoch == requestEpoch && syncID == runID else { return }
          if operation.attempted != true {
            if operation.kind != "create", let current = records.first(where: { $0.id == operation.recordId }),
              var body = try JSONSerialization.jsonObject(with: operation.body) as? [String: Any] {
              body["expectedRevision"] = current.revision
              operation.body = try JSONSerialization.data(withJSONObject: body)
            }
            operation.attempted = true
            let pending = operation
            guard change({ archive in if let index = archive.queue.firstIndex(where: { $0.id == pending.id }) { archive.queue[index] = pending } }) else { return }
          }
          let remote: ReviewRecord
          if operation.kind == "create" { remote = try await client.create(operation) }
          else { remote = try await client.update(operation) }
          try Task.checkCancellation()
          guard epoch == requestEpoch && syncID == runID else { return }
          guard change({ archive in
            archive.queue.removeAll { $0.id == operation.id }
            if let i = archive.records.firstIndex(where: { $0.id == remote.id }) {
              var merged = remote
              if archive.queue.contains(where: { $0.recordId == remote.id && $0.kind == "reflection" }) { merged.reflection = archive.records[i].reflection }
              if archive.queue.contains(where: { $0.recordId == remote.id && $0.kind == "void" }) { merged.voided = true }
              archive.records[i] = merged
            }
          }) else { return }
          if let index = history.firstIndex(where: { $0.id == remote.id }) { history[index] = remote }
        }
        do {
          let page = try await client.list()
          try Task.checkCancellation()
          guard epoch == requestEpoch && syncID == runID else { return }
          guard change({ archive in
            for remote in page.records {
              guard !archive.queue.contains(where: { $0.recordId == remote.id }) else { continue }
              if let i = archive.records.firstIndex(where: { $0.id == remote.id }) { archive.records[i] = remote }
              else { archive.records.append(remote) }
            }
            archive.records.sort { $0.draft.created > $1.draft.created }
            let protected = Set(archive.queue.map(\.recordId))
            let recent = Set(archive.records.prefix(200).map(\.id))
            archive.records.removeAll { $0.serverId != nil && !protected.contains($0.id) && !recent.contains($0.id) }

          }) else { return }
          onSyncComplete()
        }
      } catch is CancellationError {} catch {
        guard epoch == requestEpoch && syncID == runID else { return }
        notice = error.localizedDescription
        if let id = store?.archive.queue.first?.recordId {
          _ = change { archive in if let i = archive.records.firstIndex(where: { $0.id == id }) { archive.records[i].syncError = error.localizedDescription } }
        }
      }
    }
  }
  public func search(_ range: ReviewRange, cutoff: Int64, scope: String) {
    // Cancel remotely even when the replacement selection is too short or login expired.
    let cancellation = cancelActiveSearch()
    searchOpen = true; matches = []; searchError = nil; searchNext = nil; partialSearch = false
    searchCutoff = cutoff; searchProgress = "正在查找"
    guard range.bars >= 16 else { searchError = "找相似至少框选 16 根 K 线"; searching = false; return }
    let requestEpoch = epoch; let generation = UUID(); searchGeneration = generation
    guard let client else { searchError = "登录后查找相似行情"; searching = false; return }
    let id = UUID(); searchID = id; searching = true
    searchTask = Task { [weak self] in
      guard let self else { return }
      do {
        await cancellation?.value
        try Task.checkCancellation()
        var job = try await client.startSearch(range: range, cutoff: cutoff, scope: scope, id: id)
        while job.status == "queued" || job.status == "running" {
          try Task.checkCancellation(); guard epoch == requestEpoch && searchGeneration == generation else { return }
          if let total = job.total, total > 0 { searchProgress = "正在比对 \(job.checked ?? 0)/\(total)" }
          try await Task.sleep(for: .seconds(2))
          job = try await client.searchStatus(id)
        }
        guard job.status == "completed" else { throw ScorebookError.http(503, job.status == "cancelled" ? "已取消" : "行情暂不完整，请稍后重试") }
        let result = try await client.searchResults(id)
        try Task.checkCancellation(); guard epoch == requestEpoch && searchGeneration == generation else { return }
        matches = result.items; searchNext = result.next; partialSearch = result.partial == true; searching = false
      } catch is CancellationError {} catch {
        if epoch == requestEpoch && searchGeneration == generation { searchError = error.localizedDescription; searching = false }
      }
    }
  }
  public func loadMoreMatches() async {
    guard let id = searchID, let cursor = searchNext, let client, !searching else { return }
    let currentEpoch = epoch; let generation = searchGeneration; searching = true
    defer { if epoch == currentEpoch && generation == searchGeneration { searching = false } }
    do {
      let page = try await client.searchResults(id, after: cursor)
      guard epoch == currentEpoch && generation == searchGeneration else { return }
      let known = Set(matches.map(\.id)); matches += page.items.filter { !known.contains($0.id) }; searchNext = page.next
    } catch { if epoch == currentEpoch && generation == searchGeneration { searchError = error.localizedDescription } }
  }
  public func saveMatch(_ match: ReviewMatch) async {
    guard let id = searchID, let client else { return }; let currentEpoch = epoch
    do { try await client.saveMatch(match, search: id); guard epoch == currentEpoch else { return }; savedMatchIDs.insert(match.id); notice = "已保存" }
    catch { if epoch == currentEpoch { notice = error.localizedDescription } }
  }
  public func cancelSearch() {
    _ = cancelActiveSearch()
  }
  private func cancelActiveSearch() -> Task<Void, Never>? {
    searchTask?.cancel(); searchGeneration = UUID(); searching = false
    let id = searchID
    searchID = nil
    guard let id, let client else { return nil }
    return Task { try? await client.cancelSearch(id) }
  }
  public func loadStatistics() async {
    guard let client else { statisticsError = "登录后查看战绩"; return }
    let requestEpoch = epoch
    do { let groups = try await client.stats().groups; guard requestEpoch == epoch else { return }; statistics = groups; statisticsError = nil }
    catch { if requestEpoch == epoch { statisticsError = error.localizedDescription } }
  }
}
