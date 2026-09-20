import Foundation
import Observation
import KanpanCore
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

  /// 复盘里的时刻按哪一档时区写（审查 B-08，复核项 5）。
  ///
  /// 和图表、时间轴、十字线读数同一口径：宿主把 `ChartState.timezone`（也就是
  /// `Prefs.timeZone`）灌进来，改了再灌一次。原来这几页用 `Text(Date, style: .date)`，
  /// 那认的是**设备**时区：图表切到「交易所（UTC+8）」之后，同一根 K 线在轴上是 1/6，
  /// 在复盘本里还写着 1/5。
  public var timezone: TZChoice = .exchange

  /// 某个代号的价格小数位（`SymbolInfo.pricePrecision`），宿主从品种目录里接进来。
  ///
  /// 查不到给 `nil`，那就按这口价自己猜（`priceDecimalsFallback`）。这个包看不见
  /// 品种目录，所以只留一个口子；不留的话就只能像原来那样「最多 8 位、能省就省」，
  /// 同一张记录里目标价写 `76800`、失效价写 `76812.5`（审查 B-07）。
  public var priceDecimals: (String) -> Int? = { _ in nil }

  /// 当前这一档时区在「被格式化的那一刻」的偏移口径。
  public var tzOffset: TZOffset { timezone.offsetMinutes }

  /// 一口价：小数位问品种目录，非有限值按项目规矩写 `--`。
  public func price(_ value: Double, symbol: String) -> String {
    ReviewLabels.price(value, decimals: priceDecimals(symbol))
  }

  /// 列表里那种短时刻：`9/20 14:03`。
  public func dayTime(_ ms: Int64) -> String { ReviewLabels.dayTime(ms: ms, offsetMinutes: tzOffset) }

  /// 带年份的完整时刻（到期这类跨月跨年的）：`2026-09-20 14:03`。
  public func fullTime(_ ms: Int64) -> String { ReviewLabels.full(ms: ms, offsetMinutes: tzOffset) }

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
  /// 复盘本上摆出来的那一列：**服务端这一页 ∪ 只活在本机的那些**。
  ///
  /// 原来这儿只有 `history.map`：服务端页里有的那条，用本地待上传版本盖一下；
  /// 服务端页里**没有**的本地新记录，一条都不补（审查 B-03）。于是登录后成功拉过一次
  /// 列表、断网、再记一条——那条在 `archive` 里、在 `queue` 里，就是不在复盘本上。
  /// `isConnected` 只说明有客户端对象，不代表这一刻网络通；`loadHistory` 失败也不会
  /// 把 `historyLoaded` 放回去，所以这个洞会一直开着。
  ///
  /// 补进来的只有「服务端还不知道的」：待上传的、从没上云的、以及被隔离成冲突的。
  /// 已经在云端的旧记录仍然只由分页说了算，不然翻页会翻出重复行。
  /// 搜过词、翻到第二页之后不补——那两种视图的口径在服务端，本地补进去就是串行。
  public var bookRecords: [ReviewRecord] {
    guard isConnected && historyLoaded else { return records }
    let pending = Set(store?.archive.queue.map(\.recordId) ?? [])
    // 待上传的、以及被隔离成冲突的，本机那份才是人刚写下的内容——和 `record(_:)`
    // 一个口径，不然同一条记录在列表上和点进去之后是两个样子。
    let page = history.map { item -> ReviewRecord in
      guard let local = records.first(where: { $0.id == item.id }) else { return item }
      return pending.contains(item.id) || local.conflict != nil ? local : item
    }
    guard historyQuery.isEmpty, historyPage == 0 else { return page }
    let known = Set(page.map(\.id))
    let extras = records.filter { record in
      !known.contains(record.id) && (pending.contains(record.id) || record.serverId == nil || record.conflict != nil)
    }
    guard !extras.isEmpty else { return page }
    return (page + extras).sorted { $0.draft.created > $1.draft.created }
  }
  public func record(_ id: UUID) -> ReviewRecord? {
    let local = records.first(where: { $0.id == id })
    // 还在队列里、或者被隔离成冲突的，本机那份才是人刚写下的内容。
    if store?.archive.queue.contains(where: { $0.recordId == id }) == true || local?.conflict != nil { return local }
    return history.first(where: { $0.id == id }) ?? local
  }
  /// 云端那份 + 只活在本机的那几样。
  ///
  /// `conflict`（被隔离下来的上传）压根不在协议里，拉一次列表就会被抹掉；
  /// 两个裁定版本只在详情响应的外层出现，列表里没有，也不能被 `nil` 盖掉。
  private static func adopt(_ remote: ReviewRecord, over local: ReviewRecord) -> ReviewRecord {
    var value = remote
    value.conflict = local.conflict
    // 还挂着未裁决的冲突时，人写的那份要留在屏幕上。
    //
    // 被隔离的那条上传里装的正是他刚写下的复盘，云端那份还没有它；这时候把云端那份
    // 盖回来，他打开记录看到的是一段旧文字——「我明明写了」。内容在 `conflict.body`
    // 里并没有丢，但界面上丢了就等于丢了（审查 B-02）。裁决完（`resolveConflict`）
    // 冲突一清，这里自然就以云端为准。
    if local.conflict != nil {
      value.reflection = local.reflection
      value.reflectionHistory = local.reflectionHistory
      value.voided = local.voided || value.voided
    }
    if value.assessmentRevision == nil { value.assessmentRevision = local.assessmentRevision }
    if value.reflectionAssessmentRevision == nil { value.reflectionAssessmentRevision = local.reflectionAssessmentRevision }
    return value
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
    // **先改写 created，再校验**。上去的那份写着「此刻」，校验却拿圈选那一刻去量，
    // 两者一错位，本地放行、服务端必拒的记录就进了队列（审查 B-06 / B-02）：
    // 草稿搁了一天再按保存，`expires` 还停在昨天，本地量的是昨天的 created 所以通过，
    // 服务端量的是今天的 created，`expires <= created`，400。
    value.created = now
    if let error = value.validation(at: now) { notice = error; return false }
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
          do {
            if operation.kind == "create" { remote = try await client.create(operation) }
            else { remote = try await client.update(operation) }
          } catch {
            if error is CancellationError { return }
            guard epoch == requestEpoch && syncID == runID else { return }
            // 三种结局，别再混成一种（审查 B-02）。
            switch ReviewFailure.verdict(for: error) {
            case .transient:
              // 网络断了、凭证过期、服务端忙：这条**原样留在队首**，连幂等键一起留着，
              // 下次同步一模一样地重发——幂等重试的前提就是同一个键配同一份 body。
              notice = error.localizedDescription
              _ = change { archive in
                if let index = archive.records.firstIndex(where: { $0.id == operation.recordId }) {
                  archive.records[index].syncError = error.localizedDescription
                }
              }
              return
            case .conflict, .rejected:
              // 这条**再也发不出去**了。摘下来存成冲突（人写的内容一个字不丢），
              // 队列接着往下跑：后面那些无关记录凭什么陪它一起卡死。
              guard quarantine(operation, error: error) else { return }
              continue
            }
          }
          try Task.checkCancellation()
          guard epoch == requestEpoch && syncID == runID else { return }
          guard change({ archive in
            archive.queue.removeAll { $0.id == operation.id }
            if let i = archive.records.firstIndex(where: { $0.id == remote.id }) {
              var merged = Self.adopt(remote, over: archive.records[i])
              // 这一次成功的如果正是那条冲突的重发，冲突就算解了。
              if merged.conflict?.kind == operation.kind { merged.conflict = nil }
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
              // `adopt` 而不是直接赋值：列表里没有 `conflict`，也没有那两个裁定版本。
              // 直接盖回去，刚被隔离下来的那条冲突就在同一轮同步的末尾被自己抹掉了，
              // 人再也看不到「有一条没传上去，等你裁决」（审查 B-02）。
              if let i = archive.records.firstIndex(where: { $0.id == remote.id }) {
                archive.records[i] = Self.adopt(remote, over: archive.records[i])
              } else { archive.records.append(remote) }
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
  /// 把一条再也发不出去的操作从队列里摘下来，内容原样存进这条记录的 `conflict`。
  ///
  /// 摘掉的是「这一次投递」，不是「人写的东西」：正文、备注、作废意图都在 `body` 里
  /// 留着，等人裁决（`resolveConflict`）。
  private func quarantine(_ operation: ReviewOperation, error: any Error) -> Bool {
    let code = ReviewFailure.code(for: error)
    let status = (error as? any ReviewFailureStatus)?.reviewStatusCode
    let reason = ReviewFailure.message(code, status: status)
    // 新建被拒没法「重新基准」——它本来就没有 expectedRevision 可以换；
    // 4xx 的参数拒绝更是重发一万次都一样。这两种只给「留在本机」。
    let retryable = ReviewFailure.verdict(for: error) == .conflict && operation.kind != "create"
    let conflict = ReviewConflict(kind: operation.kind, code: code, reason: reason,
                                  at: ReviewClock.now, body: operation.body, retryable: retryable)
    notice = reason
    return change { archive in
      archive.queue.removeAll { $0.id == operation.id }
      if let index = archive.records.firstIndex(where: { $0.id == operation.recordId }) {
        archive.records[index].conflict = conflict
        archive.records[index].syncError = nil
      }
    }
  }

  /// 人对那条冲突的裁决（审查 B-02）。
  ///
  /// * `keepLocal = true`：拿服务端**最新版本**做基准，把本地那份内容重发一遍。
  ///   发的是一条**新操作、新幂等键**——同一个键下改 body 是幂等重试的大忌，
  ///   服务端记着那个键第一次的请求，改了就是 `idempotency_mismatch`。
  /// * `keepLocal = false`：认云端那份，本地这条丢掉，顺手把权威版本拉回来。
  ///
  /// 不可重试的那种（新建被拒、参数被拒）只走第二条路：冲突标记清掉，
  /// 本地内容照旧留在记录里，不再往上传。
  public func resolveConflict(_ id: UUID, keepLocal: Bool) async {
    guard let record = record(id), let conflict = record.conflict else { return }
    guard keepLocal, conflict.retryable, let client else {
      _ = change { archive in
        if let index = archive.records.firstIndex(where: { $0.id == id }) { archive.records[index].conflict = nil }
      }
      if !keepLocal { await refreshDetail(id) }
      return
    }
    let requestEpoch = epoch
    do {
      let latest = try await client.detail(id).merged
      guard epoch == requestEpoch else { return }
      var body = (try JSONSerialization.jsonObject(with: conflict.body) as? [String: Any]) ?? [:]
      body["expectedRevision"] = latest.revision
      let operation = ReviewOperation(recordId: id, kind: conflict.kind, body: try JSONSerialization.data(withJSONObject: body))
      guard change({ archive in
        if let index = archive.records.firstIndex(where: { $0.id == id }) {
          var merged = Self.adopt(latest, over: archive.records[index])
          merged.conflict = nil
          // 云端那份的备注不能盖掉人这边正要重发的那份。
          merged.reflection = archive.records[index].reflection
          merged.reflectionHistory = archive.records[index].reflectionHistory
          merged.voided = archive.records[index].voided || merged.voided
          archive.records[index] = merged
        }
        archive.queue.append(operation)
      }) else { return }
      synchronize()
    } catch {
      guard epoch == requestEpoch else { return }
      notice = error.localizedDescription
    }
  }

  /// 拉一次详情。
  ///
  /// 「服务端判到第几版」和「这份复盘是照着第几版写的」只在详情响应的**外层**，
  /// 列表里没有（审查 B.2）。打开一条记录时补这一次，人才看得见「结果在我写完之后
  /// 又变过」。拉不到就安静收场：列表那份照常显示，不拿一次网络抖动去打扰人。
  public func refreshDetail(_ id: UUID) async {
    guard let client, record(id)?.serverId != nil else { return }
    let requestEpoch = epoch
    do {
      let latest = try await client.detail(id).merged
      guard epoch == requestEpoch else { return }
      _ = change { archive in
        if let index = archive.records.firstIndex(where: { $0.id == latest.id }) {
          archive.records[index] = Self.adopt(latest, over: archive.records[index])
        } else { archive.records.append(latest) }
      }
      if let index = history.firstIndex(where: { $0.id == latest.id }) { history[index] = latest }
    } catch {}
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
        // 缺 `partial` 这个键时按「没找全」算。缺字段代表的是「这一版服务端没说」，
        // 把它当成「全量搜完了」，等于替服务端造了一个它没给过的保证（审查 B.2）。
        matches = result.items; searchNext = result.next; partialSearch = result.partial ?? true; searching = false
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
    // `resolvedGroups`：优先用服务端新给的**相对口径**分组（`comparableGroups`，
    // 老服务端没有就退回 `groups`），再把对应那份证据里的判定状态贴回每一组。
    // 屏幕上只摆这一份，不给用户两套口径去挑。服务端一直在算「够不够 20 笔」，
    // 客户端以前只接 `groups` 那两个裸数字，于是一笔一组被算成 0% 摆上去
    // （审查 B.2 / B-07）。
    do { let groups = try await client.stats().resolvedGroups; guard requestEpoch == epoch else { return }; statistics = groups; statisticsError = nil }
    catch { if requestEpoch == epoch { statisticsError = error.localizedDescription } }
  }
}
