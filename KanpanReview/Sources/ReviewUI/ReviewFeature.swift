import Foundation
import Observation
import KanpanCore
import ReviewDomain
import ReviewData

@MainActor @Observable public final class ReviewFeature {
  public var bookOpen = false {
    // 复盘本关上时搜索框回到空：原来那串字是 `ReviewBook` 自己的 `@State`，每开一次就是新的。
    didSet { if oldValue && !bookOpen { clearBookSearch() } }
  }
  public var captureOpen = false
  public var searchOpen = false
  /// 这一轮「找相似」是从哪条记录上发起的。宿主拿它记住重温的来路：看完某个相似
  /// 行情退出来，人该站回那条记录和它的搜索层上，而不是被扔在一张行情图上。
  public var searchRecord: UUID?
  public var selectedRecord: UUID?
  public var draft: ReviewDraft?
  public private(set) var records: [ReviewRecord] = [] { didSet { recordsRevision &+= 1; retally() } }
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
  public private(set) var history: [ReviewRecord] = [] { didSet { historyRevision &+= 1 } }
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
    // 这几样每次都要真的读一遍：它们是被观察的，缓存命中时不读，SwiftUI 就登记不上，
    // 记录或服务端页变了列表也不会重画。读一个数组只是拿引用，不花 O(n)。
    let key = BookKey(records: recordsRevision, history: historyRevision,
                      pending: store?.archive.queue.map(\.recordId) ?? [],
                      loaded: historyLoaded, query: historyQuery, connected: isConnected)
    _ = records; _ = history
    if let cached = bookCache, cached.key == key { return cached.value }
    let value = buildBookRecords()
    bookCache = (key, value); bookBuilds &+= 1
    return value
  }
  /// 真正拼那一列。原来每次读 `bookRecords` 都跑一遍，而且每一条服务端记录都
  /// `records.first(where:)` 线性找本机那份——H 条 × R 条的比较，复盘本 body 一次读三遍，
  /// 搜索框每敲一字又同步读一遍（压测 2026-09-26：H=R=3000 时每字约 1350 万次 UUID 比较）。
  /// 现在按 id 建一次索引（`recordIndex`，记录不变就不重建），整列按输入缓存。
  private func buildBookRecords() -> [ReviewRecord] {
    guard isConnected && historyLoaded else { return records }
    let pending = Set(store?.archive.queue.map(\.recordId) ?? [])
    let index = recordIndex
    // 待上传的、以及被隔离成冲突的，本机那份才是人刚写下的内容——和 `record(_:)`
    // 一个口径，不然同一条记录在列表上和点进去之后是两个样子。
    let page = history.map { item -> ReviewRecord in
      guard let at = index[item.id] else { return item }
      let local = records[at]
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
  /// `bookRecords` 的缓存键：任何一样变了才重拼。
  private struct BookKey: Equatable {
    var records: Int, history: Int, pending: [UUID], loaded: Bool, query: String, connected: Bool
  }
  @ObservationIgnored private var recordsRevision = 0
  @ObservationIgnored private var historyRevision = 0
  @ObservationIgnored private var bookCache: (key: BookKey, value: [ReviewRecord])?
  @ObservationIgnored private var sectionsCache: (key: BookKey, query: String, value: ReviewBookSections)?
  @ObservationIgnored private var recordIndexCache: (revision: Int, map: [UUID: Int])?
  /// 测试用：`bookRecords` / `bookSections` / 按 id 的索引各真拼过几次。
  @ObservationIgnored private(set) var bookBuilds = 0
  @ObservationIgnored private(set) var sectionBuilds = 0
  @ObservationIgnored private(set) var indexBuilds = 0
  /// 本机记录按 id 的位置。同一个 id 出现两次时认前面那条，和原来的 `first(where:)` 一致。
  private var recordIndex: [UUID: Int] {
    if let cached = recordIndexCache, cached.revision == recordsRevision { return cached.map }
    var map = [UUID: Int](minimumCapacity: records.count)
    for (at, record) in records.enumerated() where map[record.id] == nil { map[record.id] = at }
    recordIndexCache = (recordsRevision, map); indexBuilds &+= 1
    return map
  }

  // MARK: - 复盘本的搜索框

  /// 搜索框里此刻的字（`ReviewBook` 的 `.searchable` 绑在这儿）。
  ///
  /// 列表不跟着每一个字重算：停手 `bookSearchDebounce` 之后才落到 `bookQuery`，
  /// 本地过滤和服务端搜索都认 `bookQuery`。清空是一下子的事，不等。
  public var bookSearchText = "" { didSet { if bookSearchText != oldValue { scheduleBookQuery() } } }
  /// 落定的搜索词。
  public private(set) var bookQuery = ""
  /// 停手多久才算落定。
  @ObservationIgnored public var bookSearchDebounce: Duration = .milliseconds(200)
  /// 等那一下的办法。测试换成手拨的，不靠墙钟睡。
  @ObservationIgnored var bookSearchSleep: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  @ObservationIgnored private var bookQueryTask: Task<Void, Never>?
  /// 测试用：搜索词真落定过几次。
  @ObservationIgnored private(set) var bookQueryCommits = 0
  private func scheduleBookQuery() {
    bookQueryTask?.cancel(); bookQueryTask = nil
    let text = bookSearchText
    guard !text.isEmpty else { commitBookQuery(text); return }
    let wait = bookSearchDebounce
    bookQueryTask = Task { [weak self] in
      do { try await self?.bookSearchSleep(wait) } catch { return }
      guard !Task.isCancelled, let self, self.bookSearchText == text else { return }
      self.commitBookQuery(text)
    }
  }
  private func commitBookQuery(_ text: String) {
    guard text != bookQuery else { return }
    bookQuery = text; bookQueryCommits &+= 1
    // 服务端那一页也按落定的词重拉。原来是 `ReviewBook` 上一个 `.task(id: filter)` 睡 350ms 再拉。
    if bookOpen && isConnected { Task { await loadHistory(query: text) } }
  }
  /// 测试用：等最后一次输入落定（或被取消）。
  func settleBookSearch() async { await bookQueryTask?.value }
  private func clearBookSearch() {
    bookQueryTask?.cancel(); bookQueryTask = nil
    bookSearchText = ""
    if !bookQuery.isEmpty { bookQuery = "" }
  }

  /// 复盘本这一屏要摆的几组：按落定的搜索词过滤一遍，再一趟分进「待处理 / 等答案 / 已判定」。
  /// 输入（`bookRecords` 的键、搜索词）不变就不重算——body 里读几次都是同一份。
  public var bookSections: ReviewBookSections {
    let rows = bookRecords
    let query = bookQuery
    // `bookRecords` 刚把 `bookCache` 填好，键就在那儿。
    guard let key = bookCache?.key else { return ReviewBookSections(rows, query: query) }
    if let cached = sectionsCache, cached.key == key, cached.query == query { return cached.value }
    let value = ReviewBookSections(rows, query: query)
    sectionsCache = (key, query, value); sectionBuilds &+= 1
    return value
  }
  public func record(_ id: UUID) -> ReviewRecord? {
    let local = recordIndex[id].map { records[$0] }
    // 还在队列里、或者被隔离成冲突的，本机那份才是人刚写下的内容。
    if store?.archive.queue.contains(where: { $0.recordId == id }) == true || local?.conflict != nil { return local }
    return history.first(where: { $0.id == id }) ?? local
  }
  private var epoch = UUID()
  @ObservationIgnored private var store: ReviewStore?
  /// 补图的内存缓存，最近用过的 `attachmentCacheLimit` 张。原来只进不出，横滑翻过的
  /// 每一张图（几百 KB 一张）都一直攒在内存里，换账号也不清。
  @ObservationIgnored private var attachmentCache: [UUID: Data] = [:]
  @ObservationIgnored private var attachmentOrder: [UUID] = []
  static let attachmentCacheLimit = 8
  @ObservationIgnored private var client: ScorebookClient?
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var syncTask: Task<Void, Never>?
  /// 欠着要人处理的几条（复盘按钮角标、复盘本「待判定 N」）。
  ///
  /// 原来是计算属性，每读一次把全部记录过滤一遍；顶栏角标、复盘本的筹码条、战绩卡各读各的，
  /// 复盘本一次 body 光这几个数就扫 5 遍记录。现在 `records` 一变就一趟数完（`retally()`），
  /// 数没变不赋值——读它的视图只在这个数真变了才重画。
  public private(set) var pendingCount = 0
  /// 战绩卡上本机现算的那几个数，和 `pendingCount` 同一趟数出来。
  public private(set) var tally = ReviewTally()
  /// 测试用：真数过几趟。
  @ObservationIgnored private(set) var tallyPasses = 0
  private func retally() {
    var next = ReviewTally(), pending = 0
    for record in records {
      if record.needsAction { pending += 1 }
      guard !record.voided else { continue }
      next.live += 1
      if record.outcome == .realized { next.realized += 1 } else if record.outcome == .unrealized { next.unrealized += 1 }
    }
    tallyPasses &+= 1
    if pendingCount != pending { pendingCount = pending }
    if tally != next { tally = next }
  }
  public var isConnected: Bool { client != nil }

  /// 不带档案也能构造：档案由宿主在装好账号那一刻 `activate(store:client:)` 注进来
  /// （冷启动先装访客那份，登录后换账号那份）。以前这儿自己在 `local/` 开一份档案，
  /// 那是账号化之前的老位置，只剩迁移还读它（`ReviewPaths.legacy`）——每次冷启动
  /// 白读一遍、白建一个目录。
  public init() {}
  public func activate(store: ReviewStore, client: ScorebookClient?) {
    syncTask?.cancel(); cancelSearch(); epoch = UUID(); syncID = UUID(); clearBookSearch()
    attachmentCache = [:]; attachmentOrder = []
    self.store = store; self.client = client; store.cloudCache = client != nil
    syncing = false; syncAgain = nil; searching = false; matches = []; statistics = []; searchID = nil; searchGeneration = UUID(); searchNext = nil; savedMatchIDs = []
    nextPage = nil; searchError = nil; statisticsError = nil; history = []; historyGeneration = UUID(); historyLoading = false; historyError = nil; historyLoaded = false
    bookOpen = false; captureOpen = false; searchOpen = false; selectedRecord = nil; searchRecord = nil
    reload()
    // 换进一份档案（冷启动、登录、退登）时扫一次没人认领的图；不挂定时器（审查 D4）。
    store.pruneShots()
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
    // 队列里只记「这条记录的图要传」，图本身已经在 `shots/<id>.png` 里了，引擎发的
    // 那一刻现读（第 25 项）。以前整张图 base64 进 body，主档每改一次都跟着重写一遍。
    guard client != nil else { return }
    _ = change { archive in archive.queue.append(ReviewOperation(recordId: id, kind: "shot", body: Data())) }
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
    guard let store else { syncing = false; return }
    // 一轮一个引擎：状态全在存档里，引擎自己不留跨轮次的东西（`ReviewSyncEngine`）。
    let engine = ReviewSyncEngine(store: store, transport: client)
    engine.stillCurrent = { [weak self] in self?.epoch == requestEpoch && self?.syncID == runID }
    // 撤销窗口还没过的作废先不发（`holdVoid`）；窗口一过会再叫一次同步。
    engine.isHeld = { [weak self] operation in
      operation.kind == "void" && operation.recordId == self?.heldVoid && operation.attempted != true
    }
    engine.onChange = { [weak self, store] in self?.records = store.archive.records }
    engine.onNotice = { [weak self] text in self?.notice = text }
    engine.onAdopted = { [weak self] remote in
      guard let self, let index = history.firstIndex(where: { $0.id == remote.id }) else { return }
      history[index] = remote
    }
    syncTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if epoch == requestEpoch && syncID == runID {
          syncing = false
          if let manual = syncAgain { syncAgain = nil; synchronize(manual: manual) }
        }
      }
      if await engine.run() { onSyncComplete() }
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
          var merged = ReviewSyncEngine.adopt(latest, over: archive.records[index])
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
          archive.records[index] = ReviewSyncEngine.adopt(latest, over: archive.records[index])
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
        // 退避 + 总时长封顶（审查 P2-2）：见 `ReviewPollSchedule`。
        let started = ContinuousClock.now
        var schedule = ReviewPollSchedule()
        while job.status == "queued" || job.status == "running" {
          try Task.checkCancellation(); guard epoch == requestEpoch && searchGeneration == generation else { return }
          if let total = job.total, total > 0 { searchProgress = "正在比对 \(job.checked ?? 0)/\(total)" }
          let elapsed = started.duration(to: .now) / .seconds(1)
          guard let wait = schedule.next(checked: job.checked, elapsed: elapsed) else {
            // 等太久了：撤掉服务端那个任务，停在可重试（查找页那颗「重试」）。
            try? await client.cancelSearch(id)
            throw ReviewPollSchedule.timedOut
          }
          try await Task.sleep(for: .seconds(wait))
          do { job = try await client.searchStatus(id) }
          catch where ReviewPollSchedule.keepsPolling(after: error) { continue }
        }
        guard job.status == "completed" else { throw ScorebookError.http(503, job.status == "cancelled" ? "search_cancelled" : "search_incomplete") }
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
    guard let client else { throw ScorebookError.signedOut }
    return try await client.savedMatches(after: after)
  }
  /// 删一条存下的案例；「找相似」那一页上的「已保存」标记跟着撤掉。
  public func removeSavedMatch(_ match: NativeSavedMatch) async throws {
    guard let client else { throw ScorebookError.signedOut }
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
    guard let client else { throw ScorebookError.signedOut }
    guard record(id)?.serverId != nil else { return [] }
    return try await client.revisions(id)
  }
  /// 补图一条记录最多几张、单张最大多少——服务端 `review.rs` 的 `ATTACHMENTS_PER_RECORD` /
  /// `ATTACHMENT_MAX_BYTES` 同一个数。
  public static let attachmentLimit = 3
  public static let attachmentMaxBytes = 5 * 1024 * 1024
  public func attachments(_ id: UUID) async throws -> [ReviewAttachment] {
    guard let client else { throw ScorebookError.signedOut }
    guard record(id)?.serverId != nil else { return [] }
    return try await client.attachments(id)
  }
  /// 取一张补图。取过的放在内存里，横滑来回不重复下载。
  public func attachmentImage(_ id: UUID) async -> Data? {
    if let hit = attachmentCache[id] { rememberAttachment(id, hit); return hit }
    guard let client, let data = try? await client.attachment(id) else { return nil }
    rememberAttachment(id, data)
    return data
  }
  private func rememberAttachment(_ id: UUID, _ data: Data) {
    attachmentCache[id] = data
    attachmentOrder.removeAll { $0 == id }; attachmentOrder.append(id)
    while attachmentOrder.count > Self.attachmentCacheLimit {
      attachmentCache.removeValue(forKey: attachmentOrder.removeFirst())
    }
  }
  /// 补一张图。`data` 由调用方压成 JPEG、并保证不超过上限。
  public func addAttachment(_ data: Data, to record: UUID) async throws {
    guard let client else { throw ScorebookError.signedOut }
    let id = UUID()
    try await client.uploadAttachment(id: id, record: record, image: data)
    rememberAttachment(id, data)
  }
  public func deleteAttachment(_ id: UUID) async throws {
    guard let client else { throw ScorebookError.signedOut }
    try await client.deleteAttachment(id)
    attachmentCache.removeValue(forKey: id); attachmentOrder.removeAll { $0 == id }
  }
}

/// 复盘里一件事的结果，宿主按它出触觉（P2.9）。
public enum ReviewFeedback: Sendable, Equatable { case done, removed }

/// 复盘本一屏的几组（`ReviewFeature.bookSections`）。一趟过滤、一趟分组。
public struct ReviewBookSections: Sendable {
  /// 过滤后的全部（「全部」那一档，空状态也看它）。
  public let all: [ReviewRecord]
  /// 待处理：`needsAction`。
  public let pending: [ReviewRecord]
  /// 等答案：还在等、又不欠人处理的。
  public let waiting: [ReviewRecord]
  /// 已判定。
  public let decided: [ReviewRecord]
  init(_ rows: [ReviewRecord], query: String) {
    var all: [ReviewRecord] = [], pending: [ReviewRecord] = [], waiting: [ReviewRecord] = [], decided: [ReviewRecord] = []
    all.reserveCapacity(rows.count)
    for record in rows {
      guard query.isEmpty || record.draft.range.symbol.localizedCaseInsensitiveContains(query)
              || record.draft.text.localizedCaseInsensitiveContains(query) else { continue }
      all.append(record)
      let acts = record.needsAction
      if acts { pending.append(record) } else if record.outcome == .waiting { waiting.append(record) }
      if record.isDecided { decided.append(record) }
    }
    self.all = all; self.pending = pending; self.waiting = waiting; self.decided = decided
  }
}

/// 本机记录的几个数（战绩卡）：没作废的几条、其中判对 / 判错各几条。
public struct ReviewTally: Equatable, Sendable {
  public var live = 0
  public var realized = 0
  public var unrealized = 0
  public init() {}
}
