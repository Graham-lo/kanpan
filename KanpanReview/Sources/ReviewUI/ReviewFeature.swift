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
  /// 战绩按哪一版判定规则算的。服务端战绩响应里带着；没拉到之前就是本机草稿用的那一版。
  public private(set) var ruleVersion = "criteria-v2"
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

  /// 某个代号的价格小数位（`SymbolInfo.priceDecimals`），宿主从品种目录里接进来。
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
  /// 「记一笔」的那一刻，把当前这张图离屏画成一张 PNG（§4.3）。
  ///
  /// 画图的本事在 app 里（`ChartSnapshotRenderer`），这个包看不见它，所以由宿主注进来。
  /// 没接线就没有图：记录照记，详情里那一格整个不出现——不写「无截图」。
  @ObservationIgnored public var captureShot: (@MainActor () -> Data?)?
  /// 卡片上改起止时刻（P3.7）：落到哪根 K 线、目标失效要不要跟着区间重算、图要不要挪过去，
  /// 都得看这张图手里的那串 K 线——这个包看不见，所以宿主注进来，和图上拖手柄走同一段吸附。
  /// 没接线时只原样记下时刻。
  @ObservationIgnored public var onEditRange: (@MainActor (_ start: Int64, _ end: Int64) -> Void)?
  public func editRange(start: Int64, end: Int64) {
    if let onEditRange { onEditRange(start, end); return }
    guard end > start else { return }
    draft?.range.start = start; draft?.range.end = end; saveDraft()
  }
  /// 已经读进内存的那几张图。视图每帧都要问「这条有没有图」，不能每次都去读盘。
  /// 只留最近看过的几张：一张 PNG 几百 KB，攒多了就是白占内存。
  @ObservationIgnored private var shotCache: [UUID: Data] = [:]
  @ObservationIgnored private var shotOrder: [UUID] = []
  /// 问过服务端、确认那边也没有的。省得每打开一次详情就再去要一次。
  @ObservationIgnored private var shotMissing: Set<UUID> = []
  /// 这条记录有没有图，改一次这个数视图就重画一次（`shotCache` 本身不被观察）。
  public private(set) var shotVersion = 0
  public var onLogin: () -> Void = {}
  public var onSyncComplete: () -> Void = {}
  /// 刚做完一件还能反悔的事（P2.7）：一句话 + 撤销时要做的动作。
  /// 宿主把它接到全 app 那唯一一条提示上，这个包自己不画提示。
  @ObservationIgnored public var onUndoable: (@MainActor (String, @escaping @MainActor () -> Void) -> Void)?
  /// 撤销窗口有多长。和宿主那条提示带「撤销」时停留的时间一致；测试里调短。
  @ObservationIgnored public var undoWindow: Duration = .seconds(5)
  /// 一件事的结果要不要震一下（P2.9）。这个包不碰触觉，宿主接到全 app 那套 `Haptics` 上：
  /// `.done` 是判定落下了（完成复盘、同一次 / 独立判断），`.removed` 是作废了一条。
  @ObservationIgnored public var onFeedback: (@MainActor (ReviewFeedback) -> Void)?
  /// 刚作废、还在撤销窗口里的那一条。它的 void 操作已经排进队列，但窗口没过之前不发。
  @ObservationIgnored private var heldVoid: UUID?
  @ObservationIgnored private var voidRelease: Task<Void, Never>?
  public var pendingUploads: Int { store?.archive.queue.count ?? 0 }
  private var syncID = UUID()
  /// 同步正跑着时又来了一次请求（比如刚点了「完成复盘」）：记下来，这一轮收尾时再补跑一轮。
  /// 不记的话，那条新排进队列的操作赶上的正好是这一轮「队列已清空、在拉列表」那一段，
  /// 这一轮不会回头看队列，它就一直躺在本机，直到下一次别的事触发同步（P3.7 修订记录里
  /// 迟迟看不到刚写的复盘，就是这么来的）。值是那次请求的 `manual`。
  @ObservationIgnored private var syncAgain: Bool?
  public var autoSync = true
  public private(set) var nextPage: String?
  public private(set) var history: [ReviewRecord] = []
  public private(set) var historyLoading = false
  public private(set) var historyError: String?
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
  /// 已经在云端的旧记录仍然只由分页说了算，不然往下接页会接出重复行。
  /// 搜过词之后不补——那种视图的口径在服务端，本地补进去就是串行。
  public var bookRecords: [ReviewRecord] {
    guard isConnected && historyLoaded else { return records }
    let pending = Set(store?.archive.queue.map(\.recordId) ?? [])
    // 待上传的、以及被隔离成冲突的，本机那份才是人刚写下的内容——和 `record(_:)`
    // 一个口径，不然同一条记录在列表上和点进去之后是两个样子。
    let page = history.map { item -> ReviewRecord in
      guard let local = records.first(where: { $0.id == item.id }) else { return item }
      return pending.contains(item.id) || local.conflict != nil ? local : item
    }
    guard historyQuery.isEmpty else { return page }
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
  @ObservationIgnored private var attachmentCache: [UUID: Data] = [:]
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
    syncing = false; syncAgain = nil; searching = false; matches = []; statistics = []; searchID = nil; searchGeneration = UUID(); searchNext = nil; savedMatchIDs = []
    nextPage = nil; searchError = nil; statisticsError = nil; history = []; historyGeneration = UUID(); historyLoading = false; historyError = nil; historyLoaded = false
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
      draft = nil; saveDraft(); captureOpen = false; lastSaved = value.id
      attachShot(to: value.id)
      synchronize(); return true
    } catch { notice = error.localizedDescription; return false }
  }
  // MARK: - 那张图（§4.3）

  /// 记完一笔，顺手把当时那张图存下来，并排进上传队列。
  ///
  /// 画不出来（没接线、图还没渲染）就什么都不做：一条没有图的记录仍然是完整的记录，
  /// 不值得为此弹一句提示，更不该让保存失败。
  private func attachShot(to id: UUID) {
    guard let data = captureShot?(), !data.isEmpty, data.count <= Self.shotMaxBytes else { return }
    do { try store?.saveShot(data, for: id) } catch { return }
    remember(data, for: id)
    guard client != nil, let body = try? JSONEncoder().encode(["image": data.base64EncodedString()]) else { return }
    _ = change { archive in archive.queue.append(ReviewOperation(recordId: id, kind: "shot", body: body)) }
  }
  /// 服务端那边的上限也是这个数（`review.rs` 的 `SHOT_MAX_BYTES`）。本地先量一次，
  /// 省得存下来再被拒一次。
  static let shotMaxBytes = 2 * 1024 * 1024

  /// 这条记录的图。内存里有就给内存那份，否则读一次盘。
  public func shot(_ id: UUID) -> Data? {
    if let hit = shotCache[id] { return hit }
    guard let data = store?.shot(id) else { return nil }
    remember(data, for: id)
    return data
  }
  private func remember(_ data: Data, for id: UUID) {
    shotCache[id] = data
    shotOrder.removeAll { $0 == id }; shotOrder.append(id)
    while shotOrder.count > 4, let victim = shotOrder.first {
      shotOrder.removeFirst(); shotCache.removeValue(forKey: victim)
    }
    shotVersion &+= 1
  }
  /// 本机没有这张图（换了台设备、或者本地缓存被裁掉了），去服务端要一次。
  /// 没有就记下来，这一程不再问第二遍。
  public func loadShot(_ id: UUID) async {
    guard shot(id) == nil, !shotMissing.contains(id), let client, record(id)?.serverId != nil else { return }
    let requestEpoch = epoch
    do {
      guard let data = try await client.shot(id), !data.isEmpty else { shotMissing.insert(id); return }
      guard epoch == requestEpoch else { return }
      try? store?.saveShot(data, for: id)
      remember(data, for: id)
    } catch { shotMissing.insert(id) }
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
      // 存成了不说话（§P3-8）：他刚按的就是「保存」，回到列表那条记录已经带着
      // 他写的那句话——成没成看得见，再弹一条「复盘已保存」是替他自己的动作鼓掌。
      // 失败那一句留着（下面那行 `catch`），那才是他看不出来的事。
      }) { notice = nil; if publish { onFeedback?(.done) }; synchronize() }
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
      }) { holdVoid(id) }
    } catch { notice = error.localizedDescription }
  }

  /// 作废之后给五秒反悔（P2.7）。
  ///
  /// 服务端没有「取消作废」这一步，发出去就收不回来了。所以撤销只能是「还没发」：
  /// 操作照常排进队列（本地立刻显示已作废、app 被杀也不丢），只是撤销窗口没过之前
  /// `synchronize` 走到它就停下；窗口一过放行并同步。窗口里再作废一条，前一条的提示
  /// 已经被新的顶掉了，撤销按钮跟着没了，所以前一条随之放行。
  private func holdVoid(_ id: UUID) {
    heldVoid = id
    voidRelease?.cancel()
    let wait = undoWindow
    voidRelease = Task { [weak self] in
      try? await Task.sleep(for: wait)
      guard !Task.isCancelled, let self, self.heldVoid == id else { return }
      self.heldVoid = nil
      self.synchronize()
    }
    onFeedback?(.removed)
    onUndoable?("已作废") { [weak self] in self?.undoVoid(id) }
    synchronize()
  }

  /// 撤销作废：把还没发出去的那条 void 摘下来，记录回到作废之前。
  public func undoVoid(_ id: UUID) {
    guard heldVoid == id else { return }
    heldVoid = nil
    voidRelease?.cancel(); voidRelease = nil
    guard store?.archive.queue.contains(where: { $0.recordId == id && $0.kind == "void" && $0.attempted != true }) == true
    else { return }
    if change({ archive in
      archive.queue.removeAll { $0.recordId == id && $0.kind == "void" && $0.attempted != true }
      if let i = archive.records.firstIndex(where: { $0.id == id }) { archive.records[i].voided = false }
    }) { synchronize() }
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
      }) { onFeedback?(.done); synchronize() }
    } catch { notice = error.localizedDescription }
  }
  public func rememberReplay(_ id: UUID, position: ReviewReplayPosition) {
    replayPosition = position
    do { try store?.saveReplay(id, position: position) } catch { notice = error.localizedDescription }
  }
  public func savedReplay(_ id: UUID) -> ReviewReplayPosition? { store?.savedReplay(id) }
  /// 从头拉一次复盘本（换了筛选、换了搜索词、下拉刷新都走这儿）。
  ///
  /// 原来是「上一页 / 下一页」两颗按钮翻页（审计 §2.4）：复盘本是一本往回翻的本子，
  /// 人要的是一直往下滑，而不是在第 3 页和第 4 页之间来回点。现在第一页从这儿来，
  /// 后面的页由 `loadMoreHistory` 在滑到底时接上。
  public func loadHistory(query: String = "") async {
    guard let client else { history = records; return }
    let requestedTab = tab
    let requestEpoch = epoch; let generation = UUID(); historyGeneration = generation
    historyLoading = true; historyError = nil
    defer { if epoch == requestEpoch && historyGeneration == generation { historyLoading = false } }
    do {
      let response = try await client.list(query: query, todo: requestedTab == "todo", decided: requestedTab == "decided")
      try Task.checkCancellation()
      guard epoch == requestEpoch && historyGeneration == generation else { return }
      history = response.records; historyLoaded = true; nextPage = response.next; historyQuery = query; historyTab = requestedTab
    } catch is CancellationError {} catch { if epoch == requestEpoch && historyGeneration == generation { historyError = error.localizedDescription } }
  }
  /// 滑到底，接下一页。筛选或搜索词在这期间变过（`historyGeneration` 换了）就作废。
  public func loadMoreHistory() async {
    guard let client, let cursor = nextPage, historyLoaded, !historyLoading else { return }
    let requestedTab = historyTab; let query = historyQuery
    let requestEpoch = epoch; let generation = UUID(); historyGeneration = generation
    historyLoading = true; historyError = nil
    defer { if epoch == requestEpoch && historyGeneration == generation { historyLoading = false } }
    do {
      let response = try await client.list(after: cursor, query: query, todo: requestedTab == "todo", decided: requestedTab == "decided")
      try Task.checkCancellation()
      guard epoch == requestEpoch && historyGeneration == generation else { return }
      let known = Set(history.map(\.id))
      history += response.records.filter { !known.contains($0.id) }; nextPage = response.next
    } catch is CancellationError {} catch { if epoch == requestEpoch && historyGeneration == generation { historyError = error.localizedDescription } }
  }
  public func pauseAutomaticSync() { syncTask?.cancel(); syncID = UUID(); syncing = false; syncAgain = nil }
  public func synchronize(manual: Bool = false) {
    guard (autoSync || manual), let client else { return }
    if syncing { syncAgain = (syncAgain ?? false) || manual; return }
    let requestEpoch = epoch
    let runID = UUID(); syncID = runID
    syncing = true
    syncTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if epoch == requestEpoch && syncID == runID {
          syncing = false
          if let manual = syncAgain { syncAgain = nil; synchronize(manual: manual) }
        }
      }
      do {
        while var operation = store?.archive.queue.first {
          try Task.checkCancellation()
          guard epoch == requestEpoch && syncID == runID else { return }
          // 撤销窗口还没过的作废先不发（`holdVoid`）；窗口一过会再叫一次同步。
          if operation.kind == "void", operation.recordId == heldVoid, operation.attempted != true { return }
          if operation.attempted != true {
            // 图不是对记录内容的一次修改，没有版本可锁（服务端那条路也不读它）。
            if operation.kind != "create", operation.kind != "shot",
              let current = records.first(where: { $0.id == operation.recordId }),
              var body = try JSONSerialization.jsonObject(with: operation.body) as? [String: Any] {
              body["expectedRevision"] = current.revision
              operation.body = try JSONSerialization.data(withJSONObject: body)
            }
            operation.attempted = true
            let pending = operation
            guard change({ archive in if let index = archive.queue.firstIndex(where: { $0.id == pending.id }) { archive.queue[index] = pending } }) else { return }
          }
          // 图那条不换回一份记录：服务端只答「收下了」。
          let remote: ReviewRecord?
          do {
            switch operation.kind {
            case "create": remote = try await client.create(operation)
            case "shot": try await client.uploadShot(operation); remote = nil
            default: remote = try await client.update(operation)
            }
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
            if let remote, let i = archive.records.firstIndex(where: { $0.id == remote.id }) {
              var merged = Self.adopt(remote, over: archive.records[i])
              // 这一次成功的如果正是那条冲突的重发，冲突就算解了。
              if merged.conflict?.kind == operation.kind { merged.conflict = nil }
              if archive.queue.contains(where: { $0.recordId == remote.id && $0.kind == "reflection" }) { merged.reflection = archive.records[i].reflection }
              if archive.queue.contains(where: { $0.recordId == remote.id && $0.kind == "void" }) { merged.voided = true }
              archive.records[i] = merged
            }
          }) else { return }
          if let remote, let index = history.firstIndex(where: { $0.id == remote.id }) { history[index] = remote }
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
    do { try await client.saveMatch(match, search: id); guard epoch == currentEpoch else { return }; savedMatchIDs.insert(match.id) }  // 存成了不说话（§P3-8）：那颗按钮当场变成「已保存」。
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
    do {
      let response = try await client.stats(); guard requestEpoch == epoch else { return }
      statistics = response.resolvedGroups; statisticsError = nil
      if let version = response.ruleVersion, !version.isEmpty { ruleVersion = version }
    }
    catch { if requestEpoch == epoch { statisticsError = error.localizedDescription } }
  }

  // MARK: 已存案例 / 修订记录 / 补图（P3.7）
  //
  // 这三样都是「打开那一页才去问服务端」的只读或轻写操作，不进本机存档、不排上传队列：
  // 存档与队列管的是记录本身，而这几样离线时本来就看不了（补图要传几 MB，排队没有意义）。
  // 所以状态留在各自那一页上，这里只给出带登录检查的几条通路。

  /// 一页存下的案例。
  public func savedMatchesPage(after: String? = nil) async throws -> NativeSavedMatchesResponse {
    guard let client else { throw ScorebookError.invalidConnection }
    return try await client.savedMatches(after: after)
  }
  /// 删一条存下的案例；「找相似」那一页上的「已保存」标记跟着撤掉。
  public func removeSavedMatch(_ match: NativeSavedMatch) async throws {
    guard let client else { throw ScorebookError.invalidConnection }
    try await client.removeSavedMatch(match.id, expectedRevision: match.revision)
    savedMatchIDs.remove(match.id)
  }
  /// 从「已存案例」点开一条：和「找相似」结果点开是同一条路，只是没有发起它的那条记录。
  public func openSavedMatch(_ match: ReviewMatch) {
    searchRecord = nil; bookOpen = false; captureOpen = false
    onOpenMatch(match, ReviewClock.now)
  }
  /// 这条记录的全部修订。本机从没上过云的记录没有修订可看，给空。
  public func revisions(_ id: UUID) async throws -> [ReviewRevision] {
    guard let client else { throw ScorebookError.invalidConnection }
    guard record(id)?.serverId != nil else { return [] }
    return try await client.revisions(id)
  }
  /// 补图一条记录最多几张、单张最大多少——服务端 `review.rs` 的 `ATTACHMENTS_PER_RECORD` /
  /// `ATTACHMENT_MAX_BYTES` 同一个数。
  public static let attachmentLimit = 3
  public static let attachmentMaxBytes = 5 * 1024 * 1024
  public func attachments(_ id: UUID) async throws -> [ReviewAttachment] {
    guard let client else { throw ScorebookError.invalidConnection }
    guard record(id)?.serverId != nil else { return [] }
    return try await client.attachments(id)
  }
  /// 取一张补图。取过的放在内存里，横滑来回不重复下载。
  public func attachmentImage(_ id: UUID) async -> Data? {
    if let hit = attachmentCache[id] { return hit }
    guard let client, let data = try? await client.attachment(id) else { return nil }
    attachmentCache[id] = data
    return data
  }
  /// 补一张图。`data` 由调用方压成 JPEG、并保证不超过上限。
  public func addAttachment(_ data: Data, to record: UUID) async throws {
    guard let client else { throw ScorebookError.invalidConnection }
    let id = UUID()
    try await client.uploadAttachment(id: id, record: record, image: data)
    attachmentCache[id] = data
  }
  public func deleteAttachment(_ id: UUID) async throws {
    guard let client else { throw ScorebookError.invalidConnection }
    try await client.deleteAttachment(id)
    attachmentCache.removeValue(forKey: id)
  }
}

/// 复盘里一件事的结果，宿主按它出触觉（P2.9）。
public enum ReviewFeedback: Sendable, Equatable { case done, removed }
