import Foundation
import KanpanCore
import KanpanNetwork

/// 一只品种在主力订单流里要用到的事实，由 app 按品种信息给。
public struct OrderFlowFacts: Sendable, Equatable {
  /// `SymbolInfo.base`，可能带币安的缩放前缀（`1000PEPE`）。
  public var base: String
  public var asset: SymbolClassification.Asset
  /// 合约表里的最小变动价（图上价格单位）。
  public var tick: Double?
  /// 24h 成交额（美元）。不知道给 nil，数据层自己去问一次。
  public var turnover24h: Double?

  public init(base: String, asset: SymbolClassification.Asset, tick: Double? = nil, turnover24h: Double? = nil) {
    self.base = base; self.asset = asset
    self.tick = tick.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
    self.turnover24h = turnover24h.flatMap { $0 >= 0 && $0.isFinite ? $0 : nil }
  }

  public init(info: SymbolInfo, turnover24h: Double? = nil) {
    self.init(base: info.base, asset: SymbolClassifier.classify(info).asset, tick: info.tickSize,
              turnover24h: turnover24h)
  }

  /// 去掉缩放前缀之后的币名：用户改过的门槛按它存（`[base: OrderFlowOverride]`），默认表也按它查。
  public var overrideKey: String { OrderFlowBase.normalize(base).base }

  /// 默认门槛与步长（还没叠用户改过的项）。
  public var defaults: OrderFlowThresholds {
    OrderFlowDefaults.thresholds(base: overrideKey, asset: asset, turnover24h: turnover24h)
  }
}

/// 主力订单流的数据层：一只品种的全部簿，从连上各家深度流到吐出「此刻的大单集合」全在这里。
///
/// - 订阅 / 退订：`start()` / `stop()`，只订当前看的这一只；切品种由 `RoutedMarketFeed` 整个换掉。
/// - 上游：按 base 查品种表（`OrderFlowCatalog`，网关给各家各产品的合约；拿不到就用保底那几本），
///   只留这只有门槛的产品（非币只有 U 本位永续），各家的簿按组合流 / 中继并成几条连接，
///   每条连接一个 `DepthStream`。某家没有、某条连不上，只是少几本簿。
/// - 门槛与步长：默认表（`OrderFlowDefaults`）叠用户改过的项（`setOverride`）；表里和用户都没给步长时，
///   按前一 UTC 日收盘 × 最小变动价推一个（`BucketScheme.derivedStep`），跨 UTC 日重算。
/// - 服务端历史（2026-09-24）：kanpan-api 常驻跟踪大单生命周期、存 3 天（2026-09-25 从 30 天收到 3 天）。读完本地日志就取最近 24 小时并进模型，
///   之后每分钟取一次增量（从上一页最晚的时刻往前退 5 分钟接着取）；图往左拖到已取区间之外，就 24 小时一段往前补，
///   最多到 3 天（`OrderFlowDefaults.retentionMs`，或服务端开始跟这只的时刻）。取不到就当没有，纯本地照常，不报错、不提示。
///   合并规则见 `OrderFlowModel.mergeHistory`。
/// - 非币默认门槛标定（2026-09-25）：非币、且不在固定表里的品种，默认门槛按簿深标定
///   （`OrderFlowDefaults.calibratedThreshold`）。所有簿都拿到首张快照就立刻算；订阅起来 8 秒还没齐，
///   有一本就按已有的算，一本都没有用兜底 200 万。算一次，这条订阅里不再变。标定出来之前不评估、
///   不读回日志、不取服务端历史（只出「加载中」），免得兜底门槛把 200 万以下的单删掉或挡在外面。
/// - 落盘：大单本身（不含簿）按品种记一份小日志（`<目录>/<品种>.json`，只存 24 小时、最多 5000 条，约 1 MB），
///   再打开这只时读回来接着画；更早的每次从服务端取，不落盘；不同步。
public actor OrderFlowFeed {
  public typealias Sink = @Sendable (OrderFlowSnapshot) async -> Void
  /// 前一 UTC 日收盘。`referenceDayMs` 是那一天 0 点（UTC）。
  public typealias CloseLoader = @Sendable (_ referenceDayMs: Int64) async throws -> Double?
  /// 按 base 查这只币的全部簿。
  public typealias BookLoader = @Sendable (_ base: String) async -> OrderFlowCatalog.Books
  /// 把一组簿并成几条连接。
  public typealias AdapterMaker = @Sendable (_ books: [DepthBook]) -> [any DepthFeedAdapter]
  /// 24h 成交额（美元）。
  public typealias TurnoverLoader = @Sendable () async -> Double?
  /// 取服务端记下的一段历史（`base` 已去掉缩放前缀）。取不到给 nil。
  public typealias HistoryLoader = @Sendable (_ base: String, _ fromMs: Int64, _ toMs: Int64) async -> OrderFlowHistoryPage?

  /// 每隔多久按簿算一帧（出现、消失的确认要两次评估且相隔 ≥ 300 ms，所以不能比 300 ms 更密）。
  public static let evaluateEveryMs: Double = 500
  /// 内容没变时至少隔这么久也发一次（界面上的「12 分」要走）。
  public static let heartbeatMs: Int64 = 30_000
  /// 画出来一样、只是金额变了的帧最快隔这么久才发一次（图例「主力 买 12.3M」的合计要跟上，
  /// 但不能每拍都发）；十字线停在色块上（`precise` 为真）时不受这一条限制，读数要精确金额。
  public static let amountRefreshMs: Int64 = 5_000
  /// 大单有变化时隔这么久落一次盘。日志最多约 1 MB，更早的都在服务端，被杀掉丢的这一分钟下次打开由服务端补回。
  public static let saveEveryMs: Int64 = 60_000
  /// 服务端历史：每隔多久取一次增量；增量从上一页最晚时刻往前退多少接着取（服务端挂着的单 15 秒才刷一次库）；
  /// 一段取多长（首次与往左补都是 24 小时一段）。
  public static let historyEveryMs: Int64 = 60_000
  public static let historyOverlapMs: Int64 = 5 * 60_000
  public static let historySpanMs: Int64 = 86_400_000
  /// 首次那一页没取到，隔多久再试；往左补的一段没取到，隔多久再试。
  static let historyRetryMs: Int64 = 10_000
  static let backfillRetryMs: Int64 = 30_000

  public let symbol: String
  public let facts: OrderFlowFacts
  private let loadBooks: BookLoader
  private let makeAdapters: AdapterMaker
  private let loadClose: CloseLoader
  private let loadTurnover: TurnoverLoader
  private let loadHistory: HistoryLoader
  private let historyEveryMs: Int64
  /// 图上一个价格单位是几个币（`1000PEPE` 为 1000）：服务端的价是每个币的价，并进来时要乘它。
  private let chartScale: Double
  private let file: URL?
  private let pacer: any Pacer
  private let clock: @Sendable () -> Int64
  private let log: FeedLog
  private let sink: Sink
  /// 帧按产生的先后排队送给 `sink`（审查第 40 项：原来一帧一个无结构 Task，先后不保证）。
  /// 帧是整份快照，只留最新几帧，调用方卡住时旧的被挤掉也无妨，顺序不乱。
  private let frames: AsyncStream<OrderFlowSnapshot>
  private let frameSink: AsyncStream<OrderFlowSnapshot>.Continuation
  private let evaluateEveryMs: Double
  /// 十字线此刻停在主图上（读数要精确金额）。在评估那一拍读，所以是个线程安全的读函数，不是状态。
  private let precise: @Sendable () -> Bool

  private var model: OrderFlowModel
  private var override: OrderFlowOverride?
  private var turnover: Double?
  /// 按前一日收盘推出来的步长（表里和用户都没给时才用）。
  private var derivedStep: Double?
  private var adapters: [any DepthFeedAdapter] = []
  private var streams: [DepthStream] = []
  private var tasks: [Task<Void, Never>] = []
  private var schemeTask: Task<Void, Never>?
  private var snapshotTasks: [String: Task<Void, Never>] = [:]
  /// 正在单本重订、还没等到新快照的簿：簿 → (哪条连接, 什么时候发的)。等太久（订阅被吞了）就整条重拨兜底。
  private var resubscribing: [String: (stream: Int, sinceMs: Int64)] = [:]
  /// 每条深度流上本地已经处理到的连接号（最近一次 `.connected(n)`）。要求重订 / 重拨时带上它：
  /// 事件流有缓冲，处理旧连接积压的消息时流那边可能已经换了新连接，过期的判断不许掐新连接。
  private var connectionOf: [Int: Int] = [:]
  /// 单本重订等快照最多等多久，过了就整条重拨。
  static let resubscribeTimeoutMs: Int64 = 10_000
  /// 每条深度流当前这条连接建好的时刻；断了、或已经决定整条重拨时清掉。
  private var connectedAtMs: [Int: Int64] = [:]
  /// 这条连接上已经催过首帧快照的簿（一条连接只催一次）。
  private var nudgedOnConnection: Set<String> = []
  /// 每本簿这一轮一共催过几次：品种在交易所那头已经没了、订阅永远不回快照时，不能无限催下去。
  private var firstSnapshotNudges: [String: Int] = [:]
  /// 快照在流里给的那几家：连上这么久一本簿还没收到首帧快照，就单本重订一次。
  static let firstSnapshotTimeoutMs: Int64 = 15_000
  static let maxFirstSnapshotNudges = 3
  private var lastEmitted: OrderFlowSnapshot?
  private var lastEmitMs: Int64 = .min / 2
  private var lastSaveMs: Int64 = 0
  private var started = false
  private var stopped = false

  // 服务端历史的进度。步长一变模型清空，这几项跟着清、`historyGeneration` 加一，路上那一页回来也不认了。
  /// 已经并进来的最早时刻（往左补从这里接着往前）；nil 是首次那一页还没取到。
  private var historyFromMs: Int64?
  /// 增量从哪儿接着取（上一页最晚的出现 / 结束时刻）。
  private var historyCursorMs: Int64?
  /// 服务端从什么时候开始跟这只（封顶 3 天前）：往左补到这里为止。
  private var historyTrackedSinceMs: Int64?
  /// 上一次取首次页 / 增量的时刻（不论成败）。
  private var historyPulledMs: Int64 = .min / 2
  private var historyRetryAtMs: Int64 = .min / 2
  private var backfillRetryAtMs: Int64 = .min / 2
  /// 服务端的步长和本机对不上（用户改过步长）：本机步长还是这个就不再取。
  private var historyBlockedStep: Double?
  private var historyGeneration = 0
  private var historyFetch: Task<Void, Never>?
  /// 图上此刻看的时间范围（最左 K 线的时刻往前补、淘汰时优先留它）。
  private var visibleFromMs: Int64?
  /// 可视范围 / 用户改项各自最后收下的那次调用的序号（审查 P2-4）：调用方每次各起一个 Task，
  /// 到达先后不定，带序号的调用按序号丢掉后到的旧值（不带序号的照旧直接收）。
  private var viewSequence: UInt64 = 0
  private var overrideSequence: UInt64 = 0

  // 非币默认门槛标定（见文件头）。
  /// 还在等标定：不评估、不读回日志、不取服务端历史。币与固定表里的品种一开始就是 false。
  private var calibrating: Bool
  /// 标定出来的门槛；标定不出（一本簿都没到）或不用标定是 nil。
  private var calibrated: Double?
  /// 订阅起来（簿都加进模型）之后到这个时刻还没齐，就按已有的算。
  private var calibrationDeadlineMs: Int64?
  /// 等标定期间读到的日志，标定完再交给模型。
  private var deferredJournal: OrderFlowJournal?

  /// - Parameters:
  ///   - symbol: 品种键（`InstrumentID.canonical`），吐出去的快照带的就是它。
  ///   - override: 用户给这只 base 改过的门槛 / 步长。
  ///   - directory: 日志落盘目录；nil 表示不落盘。
  public init(symbol: String, facts: OrderFlowFacts, override: OrderFlowOverride?, directory: URL?,
              loadBooks: @escaping BookLoader, makeAdapters: @escaping AdapterMaker,
              loadClose: @escaping CloseLoader, loadTurnover: @escaping TurnoverLoader = { nil },
              loadHistory: @escaping HistoryLoader = { _, _, _ in nil },
              historyEveryMs: Int64 = OrderFlowFeed.historyEveryMs,
              pacer: any Pacer = SystemPacer(),
              clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
              evaluateEveryMs: Double = OrderFlowFeed.evaluateEveryMs,
              precise: @escaping @Sendable () -> Bool = { false },
              log: FeedLog = .silent, sink: @escaping Sink) {
    self.symbol = symbol
    self.facts = facts
    self.override = override?.normalized
    self.turnover = facts.turnover24h
    self.loadBooks = loadBooks
    self.makeAdapters = makeAdapters
    self.loadClose = loadClose
    self.loadTurnover = loadTurnover
    self.loadHistory = loadHistory
    self.historyEveryMs = max(historyEveryMs, 1)
    self.chartScale = OrderFlowBase.normalize(facts.base).scale
    self.file = directory.map { Self.journalFile(in: $0, symbol: symbol) }
    self.pacer = pacer
    self.clock = clock
    self.evaluateEveryMs = max(evaluateEveryMs, 1)
    self.precise = precise
    self.log = log
    self.sink = sink
    self.calibrating = OrderFlowDefaults.needsCalibration(base: facts.overrideKey, asset: facts.asset)
    (frames, frameSink) = AsyncStream.makeStream(of: OrderFlowSnapshot.self, bufferingPolicy: .bufferingNewest(8))
    // 日志不在这里读：同一只切走再切回时，旧的那条可能还在停、还没落盘（审查第 40 项），读挪到 `start`。
    self.model = OrderFlowModel(symbol: symbol,
                                thresholds: Self.effective(facts: facts, turnover: facts.turnover24h,
                                                           override: override?.normalized, derivedStep: nil))
  }

  /// 按提供者建一条：品种表、连接、日线、成交额都从它来。这条线路给不出订单流就返回 nil。
  public init?(symbol: String, facts: OrderFlowFacts, override: OrderFlowOverride?,
               provider: any MarketProvider, directory: URL?, precise: @escaping @Sendable () -> Bool = { false },
               log: FeedLog = .silent, sink: @escaping Sink) {
    guard let catalog = (provider as? any OrderFlowSourcing)?.orderFlowCatalog else { return nil }
    self.init(symbol: symbol, facts: facts, override: override, directory: directory,
              loadBooks: { base in await catalog.books(base: base) },
              makeAdapters: { books in catalog.adapters(books) },
              loadClose: { day in try await Self.previousClose(provider: provider, symbol: symbol, referenceDayMs: day) },
              loadTurnover: { try? await provider.ticker24h(symbol: symbol, timeout: 8).quoteVolume },
              loadHistory: { base, from, to in await catalog.history(base: base, fromMs: from, toMs: to) },
              precise: precise, log: log, sink: sink)
  }

  /// 此刻生效的门槛与步长：默认表（非币用标定出的门槛）→ 叠用户改过的项 → 还没有步长就用按收盘推的那个。
  static func effective(facts: OrderFlowFacts, turnover: Double?, override: OrderFlowOverride?,
                        derivedStep: Double?, calibrated: Double? = nil) -> OrderFlowThresholds {
    var t = OrderFlowDefaults.thresholds(base: facts.overrideKey, asset: facts.asset, turnover24h: turnover,
                                         calibrated: calibrated)
      .applying(override)
    if t.step == nil { t.step = derivedStep }
    return t
  }

  /// 日志文件：`<dir>/<品种键里的字母数字>.json`。
  public static func journalFile(in directory: URL, symbol: String) -> URL {
    let safe = String(symbol.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
    return directory.appendingPathComponent(safe + ".json")
  }

  /// 清掉目录里 24 小时（`journalRetentionMs`）没动过的日志，以及旧版留下的门槛标定（按上游分的子目录、`.cal`）。
  public static func sweep(directory: URL, nowMs: Int64) {
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
    guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
    for item in items {
      let values = try? item.resourceValues(forKeys: Set(keys))
      if values?.isDirectory == true || item.pathExtension != "json" {
        try? fm.removeItem(at: item)
        continue
      }
      let modified = values?.contentModificationDate.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
      if nowMs - modified >= OrderFlowDefaults.journalRetentionMs { try? fm.removeItem(at: item) }
    }
  }

  /// 前一 UTC 日那根日线的收盘。
  static func previousClose(provider: any MarketProvider, symbol: String, referenceDayMs: Int64) async throws -> Double? {
    let bars = try await provider.klines(symbol: symbol, interval: .d1, limit: 3)
    if let exact = bars.last(where: { $0.openTime == referenceDayMs }) { return exact.close }
    // 日线的开盘时刻不在 UTC 0 点的交易所：取「今天 0 点之前开的最后一根」。
    return bars.last(where: { $0.openTime < referenceDayMs + 86_400_000 })?.close
  }

  // MARK: - 生命周期

  /// 起订。`prior` 是上一条正在停的订阅（`OrderFlowSlot` 记着）：先等它停完、日志落了盘，
  /// 再读这只的日志，免得读到旧版本、之后两边互相覆盖（审查第 40 项）。
  public func start(after prior: Task<Void, Never>? = nil) async {
    guard !started, !stopped else { return }
    started = true
    await prior?.value
    guard !stopped else { return }
    restoreJournal()
    let frames = self.frames, sink = self.sink
    tasks.append(Task { for await frame in frames { await sink(frame) } })
    tasks.append(Task { [weak self] in await self?.setUp() })
    tasks.append(Task { [weak self] in await self?.evaluateLoop() })
    if turnover == nil, facts.asset == .crypto {
      tasks.append(Task { [weak self] in await self?.fetchTurnover() })
    }
    ensureDerivedStep()
    pumpHistory()
  }

  /// 退订并清簿。大单有变化就顺手落盘。
  public func stop() async {
    stopped = true
    frameSink.finish()
    tasks.forEach { $0.cancel() }; tasks = []
    historyFetch?.cancel(); historyFetch = nil; historyGeneration += 1
    schemeTask?.cancel(); schemeTask = nil
    snapshotTasks.values.forEach { $0.cancel() }; snapshotTasks = [:]
    let dying = streams; streams = []; adapters = []; connectionOf = [:]; connectedAtMs = [:]
    for s in dying { await s.stop() }
    save()
  }

  /// 读回这只的日志（24 小时内、品种对得上的）。门槛照此刻生效的那份（`start` 之前可能已经改过）。
  private func restoreJournal() {
    guard let file else { return }
    let now = clock()
    guard let journal = (try? Data(contentsOf: file)).flatMap(OrderFlowJournal.decode),
          journal.symbol == symbol, now - journal.savedAtMs < OrderFlowDefaults.journalRetentionMs else { return }
    // 默认门槛还在等标定：先放着，标定完再读回（兜底 200 万会把标定门槛以上、200 万以下的单删掉）。
    if calibrating { deferredJournal = journal; return }
    model = OrderFlowModel(symbol: symbol, thresholds: model.thresholds, restored: journal)
  }

  /// 用户改了这只 base 的门槛 / 步长（面板里改，或别的设备同步过来）。
  public func setOverride(_ next: OrderFlowOverride?, sequence: UInt64? = nil) {
    if let sequence {
      guard sequence > overrideSequence else { return }
      overrideSequence = sequence
    }
    let normalized = next?.normalized
    guard normalized != override else { return }
    override = normalized
    refreshThresholds()
    ensureDerivedStep()
  }

  private func refreshThresholds() {
    let next = Self.effective(facts: facts, turnover: turnover, override: override, derivedStep: derivedStep,
                              calibrated: calibrated)
    guard next != model.thresholds else { return }
    // 步长一变模型整个清空重来：服务端历史也从头取（首次那一页），路上那一页作废。
    if next.step != model.thresholds.step { resetHistory() }
    model.setThresholds(next)
    lastEmitted = nil  // 门槛一改立刻出一帧，不等心跳
    pumpHistory()
  }

  private func fetchTurnover() async {
    guard let value = await loadTurnover(), value.isFinite, value >= 0, !Task.isCancelled, !stopped else { return }
    turnover = value
    refreshThresholds()
  }

  // MARK: - 簿与连接

  private func setUp() async {
    let result = await loadBooks(facts.base)
    guard !Task.isCancelled, !stopped else { return }
    let thresholds = model.thresholds
    let books = result.books.filter { thresholds[$0.venue.product] != nil }
    for book in books { model.addVenue(book.venue) }
    if calibrating { calibrationDeadlineMs = clock() + OrderFlowDefaults.calibrationTimeoutMs }
    adapters = makeAdapters(books)
    log("主力订单流 \(symbol)：\(books.count) 本簿、\(adapters.count) 条连接\(result.fromCatalog ? "" : "（品种表没拿到，用保底）")")
    for (index, adapter) in adapters.enumerated() {
      let depth = DepthStream(adapter: adapter, pacer: pacer, log: log)
      streams.append(depth)
      tasks.append(Task { [weak self] in
        // `stop()` 可能赶在这个 Task 起跑之前（它已经把 streams 清空、对这条流调过 stop）：
        // 重查一遍这条流还归不归这一轮，不归就别拨号（DepthStream 自己也会把 stop 之后的 start 挡掉）。
        guard let live = await self?.owns(depth), live, !Task.isCancelled else { return }
        let events = await depth.start()
        for await event in events {
          guard let self, !Task.isCancelled else { return }
          await self.handle(event, stream: index)
        }
      })
    }
  }

  /// 这条深度流还是不是当前这一轮的（没 stop、也没被换掉）。
  private func owns(_ depth: DepthStream) -> Bool { !stopped && streams.contains { $0 === depth } }

  private func handle(_ event: DepthStreamEvent, stream index: Int) async {
    guard index < adapters.count, !stopped else { return }
    let books = adapters[index].books
    let now = clock()
    switch event {
    case .connected(let id):
      connectionOf[index] = id
      connectedAtMs[index] = now
      for book in books {
        resubscribing[book.id] = nil
        nudgedOnConnection.remove(book.id)
        cancelSnapshot(book.id)
        await perform(model.connectionOpened(book.id), venue: book.id, stream: index)
      }
    case .messages(let messages):
      var actions: [String: OrderFlowModel.Action] = [:]
      for m in messages {
        let action = model.ingest(m.venueID, m.message, nowMs: now)
        if action != .none { actions[m.venueID] = action }
      }
      for venue in resubscribing.keys where model.isReady(venue) { resubscribing[venue] = nil }
      // 要重订的几本一起交给这条连接：能单本重订（OKX）就只动它们，同连接的别的簿照常；不能就整条重拨一次。
      let again = actions.filter { $0.value == .resubscribe }.keys.sorted()
      if !again.isEmpty { await resubscribe(again, stream: index, nowMs: now) }
      for (venue, action) in actions.sorted(by: { $0.key < $1.key }) where action != .resubscribe {
        await perform(action, venue: venue, stream: index)
      }
    case .disconnected(let reason):
      connectedAtMs[index] = nil
      // 断线期间簿不再可信：回到「拉快照中」，重连后再重建。
      for book in books {
        model.disconnected(book.id)
        resubscribing[book.id] = nil
        cancelSnapshot(book.id)
      }
      log("主力订单流 \(symbol) \(adapters[index].name) 断开：\(reason)")
    }
  }

  private func perform(_ action: OrderFlowModel.Action, venue: String, stream index: Int) async {
    switch action {
    case .none: break
    case .fetchSnapshot: fetchSnapshot(venue: venue, stream: index)
    case .resubscribe: await resubscribe([venue], stream: index, nowMs: clock())
    }
  }

  private func resubscribe(_ venues: [String], stream index: Int, nowMs: Int64) async {
    guard let connection = connectionOf[index] else { return }
    if await streams[index].resubscribe(venues, connection: connection) {
      for venue in venues { resubscribing[venue] = (index, nowMs) }
    }
  }

  /// 单本重订发出去太久还没等到新快照（订阅被中继或交易所吞了）：那条连接整条重拨。
  private func escalateStaleResubscribes(nowMs: Int64) {
    let stale = Set(resubscribing.values.filter { nowMs - $0.sinceMs >= Self.resubscribeTimeoutMs }.map(\.stream))
    guard !stale.isEmpty else { return }
    resubscribing = resubscribing.filter { !stale.contains($0.value.stream) }
    for index in stale.sorted() where index < streams.count {
      let stream = streams[index]
      guard let connection = connectionOf[index] else { continue }
      connectedAtMs[index] = nil
      log("主力订单流 \(symbol) \(adapters[index].name) 单本重订 \(Self.resubscribeTimeoutMs / 1000) 秒没等到快照，整条重连")
      Task { await stream.reconnect(connection: connection) }
    }
  }

  /// 快照在流里的那几家：首次订阅没回快照（订阅被中继或交易所吞了）的簿原来永远不会就绪——
  /// 流内快照的簿没就绪时增量一律不收、也不会触发任何动作，只有断档和重连才会重订。
  /// 连上 `firstSnapshotTimeoutMs` 还没就绪、也没在重订的，单本重订一次（不能单本重订的那家就整条重拨），
  /// 之后仍没等到就走「单本重订超时 → 整条重拨」那条路。每本一轮最多催 `maxFirstSnapshotNudges` 次，
  /// 免得交易所那头已经没了的品种把同连接的别的簿一遍遍拖下水。
  private func nudgeSilentBooks(nowMs: Int64) {
    for (index, since) in connectedAtMs.sorted(by: { $0.key < $1.key })
    where nowMs - since >= Self.firstSnapshotTimeoutMs && index < adapters.count {
      let tracked = Set(model.venues.map(\.id))
      let silent = adapters[index].books.map(\.venue).filter { venue in
        venue.snapshotInBand && tracked.contains(venue.id) && !model.isReady(venue.id)
          && resubscribing[venue.id] == nil && !nudgedOnConnection.contains(venue.id)
          && firstSnapshotNudges[venue.id, default: 0] < Self.maxFirstSnapshotNudges
      }.map(\.id)
      guard !silent.isEmpty else { continue }
      for venue in silent {
        nudgedOnConnection.insert(venue)
        firstSnapshotNudges[venue, default: 0] += 1
      }
      log("主力订单流 \(symbol) \(adapters[index].name) 连上 \(Self.firstSnapshotTimeoutMs / 1000) 秒没收到快照，重订 \(silent.joined(separator: " "))")
      Task { await self.resubscribe(silent, stream: index, nowMs: nowMs) }
    }
  }

  private func cancelSnapshot(_ venue: String) {
    snapshotTasks.removeValue(forKey: venue)?.cancel()
  }

  /// 拉一本簿的 REST 快照（快照不在流里的那一路）。同一本同一时刻只拉一份；失败按服务端给的等待或退避重试。
  private func fetchSnapshot(venue: String, stream index: Int) {
    guard snapshotTasks[venue] == nil, !stopped, index < adapters.count else { return }
    let adapter = adapters[index], pacer = self.pacer
    snapshotTasks[venue] = Task { [weak self] in
      var backoff = Backoff(baseMs: 1000, capMs: 15_000)
      while !Task.isCancelled {
        do {
          let snapshot = try await adapter.fetchSnapshot(venueID: venue)
          guard !Task.isCancelled else { return }
          await self?.applied(snapshot, venue: venue, stream: index)
          return
        } catch is CancellationError {
          return
        } catch let error as DepthSnapshotError where error.isClientError {
          await self?.snapshotFailed(venue, "快照被拒（HTTP \(error.status)），不再重试")
          return
        } catch {
          let wait = (error as? DepthSnapshotError)?.retryAfterMs ?? backoff.next()
          do { try await pacer.sleep(ms: wait) } catch { return }
        }
      }
    }
  }

  /// 在拉快照的那个任务里跑（actor 方法跟着调用方的任务走），所以 `Task.isCancelled` 就是「这一份被作废了没有」。
  ///
  /// 作废了（断线、换连接、停了）一律不理：拉快照那头「没被取消」的检查和这里之间隔着一次 actor 跳转，
  /// 断线 + 新连接起的新任务可能就排在中间——原来这里照样清掉 `snapshotTasks[venue]`（清掉的是新任务那一格，
  /// 同一本簿于是能同时拉两份），还把旧连接那一份快照塞给新连接的簿。
  private func applied(_ snapshot: BookSnapshot, venue: String, stream index: Int) async {
    guard !Task.isCancelled else { return }
    let action = model.applySnapshot(venue, snapshot, nowMs: clock())
    if action == .fetchSnapshot {
      // 快照比缓冲的增量还旧（或对不上）：等一小会儿让增量攒起来再拉，别连打。等的这段时间这一格仍记着
      // 本任务：期间断线照样能把它作废，增量那头要求的重拉也不会另起一份。
      do { try await pacer.sleep(ms: 500) } catch { return }
      guard !stopped, !Task.isCancelled else { return }
    }
    snapshotTasks[venue] = nil
    await perform(action, venue: venue, stream: index)
  }

  private func snapshotFailed(_ venue: String, _ message: String) {
    guard !Task.isCancelled else { return }
    snapshotTasks[venue] = nil
    log("主力订单流 \(symbol) \(venue) \(message)")
  }

  // MARK: - 步长

  /// 表里和用户都没给步长时，按前一日收盘推一个；已经在推就不重复起。
  private func ensureDerivedStep() {
    let needs = Self.effective(facts: facts, turnover: turnover, override: override, derivedStep: nil).step == nil
    guard needs, schemeTask == nil, started, !stopped else { return }
    schemeTask = Task { [weak self] in await self?.schemeLoop() }
  }

  private func schemeLoop() async {
    var backoff = Backoff(baseMs: 2000, capMs: 60_000)
    var loadedDay: Int64?
    while !Task.isCancelled {
      let day = BucketScheme.referenceDay(nowMs: clock())
      if loadedDay != day {
        let close = try? await loadClose(day)
        guard !Task.isCancelled else { return }
        if let close, let step = BucketScheme.derivedStep(referenceClose: close, tick: facts.tick) {
          derivedStep = step
          loadedDay = day
          backoff.reset()
          refreshThresholds()
        } else {
          do { try await pacer.sleep(ms: backoff.next()) } catch { return }
          continue
        }
      }
      // 睡到下一个 UTC 日 0 点过一分钟再重算。
      let next = day + 2 * 86_400_000 + 60_000
      do { try await pacer.sleep(ms: Double(max(1000, next - clock()))) } catch { return }
    }
  }

  // MARK: - 服务端历史

  /// 图上此刻看的时间范围（`ChartView.onViewChanged`，毫秒）。最左边早于已取到的，就往前补。
  public func setVisibleWindow(fromMs: Int64, toMs: Int64, sequence: UInt64? = nil) {
    guard fromMs <= toMs else { return }
    if let sequence {
      guard sequence > viewSequence else { return }
      viewSequence = sequence
    }
    visibleFromMs = fromMs
    model.setVisibleWindow(fromMs...toMs)
    pumpHistory()
  }

  private func resetHistory() {
    historyFetch?.cancel(); historyFetch = nil
    historyGeneration += 1
    historyFromMs = nil; historyCursorMs = nil; historyTrackedSinceMs = nil
    historyPulledMs = .min / 2; historyRetryAtMs = .min / 2; backfillRetryAtMs = .min / 2
    historyBlockedStep = nil
  }

  enum HistoryKind: Sendable { case initial, increment, backfill }
  struct HistoryJob: Sendable, Equatable {
    var kind: HistoryKind
    var fromMs: Int64
    var toMs: Int64
  }

  /// 该取哪一页了：首次（最近 24 小时）→ 到点的增量 → 图往左拖出去了就往前补一段。都不该取是 nil。
  func nextHistoryJob(nowMs now: Int64) -> HistoryJob? {
    // 还没有步长（按收盘推的那个还在路上）：并不进来，先不取。
    guard let step = model.thresholds.step else { return nil }
    if let blocked = historyBlockedStep, blocked == step { return nil }
    let oldest = now - OrderFlowDefaults.retentionMs
    guard let cursor = historyCursorMs, let loadedFrom = historyFromMs else {
      guard now >= historyRetryAtMs else { return nil }
      return HistoryJob(kind: .initial, fromMs: now - Self.historySpanMs, toMs: now)
    }
    if now - historyPulledMs >= historyEveryMs {
      return HistoryJob(kind: .increment, fromMs: max(oldest, min(cursor, now) - Self.historyOverlapMs), toMs: now)
    }
    if let visibleFrom = visibleFromMs, visibleFrom < loadedFrom, now >= backfillRetryAtMs {
      let floor = max(historyTrackedSinceMs ?? oldest, oldest)
      guard loadedFrom > floor else { return nil }
      return HistoryJob(kind: .backfill, fromMs: max(floor, loadedFrom - Self.historySpanMs), toMs: loadedFrom)
    }
    return nil
  }

  /// 有该取的就取（同一时刻只有一页在路上）。每一拍评估、改门槛、图挪了都来问一次，开销只是几个比较。
  /// 默认门槛还在等标定时不取：按兜底 200 万并进来的页会把 200 万以下的单挡在外面。
  private func pumpHistory() {
    guard started, !stopped, !calibrating, historyFetch == nil, let job = nextHistoryJob(nowMs: clock()) else { return }
    let load = loadHistory, base = facts.overrideKey, generation = historyGeneration
    historyFetch = Task { [weak self] in
      let page = await load(base, job.fromMs, job.toMs)
      await self?.historyArrived(page, job: job, generation: generation)
    }
  }

  private func historyArrived(_ page: OrderFlowHistoryPage?, job: HistoryJob, generation: Int) {
    guard generation == historyGeneration, !stopped else { return }
    historyFetch = nil
    let now = clock()
    if job.kind == .increment { historyPulledMs = now }
    guard let page else {
      // 服务端不通：纯本地照常。首次那页隔一会儿再试，增量等下一分钟，往前补的一段隔半分钟再试。
      switch job.kind {
      case .initial: historyRetryAtMs = now + Self.historyRetryMs
      case .increment: break
      case .backfill: backfillRetryAtMs = now + Self.backfillRetryMs
      }
      return
    }
    historyTrackedSinceMs = page.trackedSinceMs
    switch model.mergeHistory(page, chartScale: chartScale, nowMs: now) {
    case .merged:
      switch job.kind {
      case .initial:
        historyFromMs = page.fromMs
        historyCursorMs = page.latestMs ?? page.toMs
        historyPulledMs = now
      case .increment:
        historyCursorMs = max(historyCursorMs ?? .min, page.latestMs ?? page.fromMs + Self.historyOverlapMs)
      case .backfill:
        historyFromMs = min(historyFromMs ?? page.fromMs, page.fromMs)
      }
      lastEmitted = nil  // 并进来的马上出一帧
    case .pending:
      // 本机步长还没定（取的时候有，回来时没了，只可能是刚被清）：下一拍重来。
      break
    case .incompatible:
      if page.thresholds.step == nil {
        // 服务端这只刚开始跟、步长还没算出来：过一会儿再问。
        historyRetryAtMs = now + Self.historyRetryMs
        backfillRetryAtMs = now + Self.backfillRetryMs
      } else {
        // 用户改过步长：服务端按默认步长分的桶对不上，这个步长下只用本地的。
        historyBlockedStep = model.thresholds.step
        log("主力订单流 \(symbol)：步长和服务端不同，不并服务端历史")
      }
    }
    pumpHistory()
  }

  // MARK: - 出帧

  private func evaluateLoop() async {
    while !Task.isCancelled {
      step()
      do { try await pacer.sleep(ms: evaluateEveryMs) } catch { return }
    }
  }

  private func step() {
    guard !stopped else { return }
    let now = clock()
    escalateStaleResubscribes(nowMs: now)
    nudgeSilentBooks(nowMs: now)
    if calibrating { calibrate(nowMs: now) }
    pumpHistory()
    // 标定之前出「加载中」、不带门槛与默认：面板那时按品种事实查表（兜底 200 万），标定完换成标定值。
    var frame = calibrating ? OrderFlowSnapshot.loading(symbol, asOfMs: now) : model.evaluate(nowMs: now)
    if !calibrating {
      frame.defaults = Self.effective(facts: facts, turnover: turnover, override: nil, derivedStep: nil,
                                      calibrated: calibrated)
    }
    if model.journalDirty, now - lastSaveMs >= Self.saveEveryMs { save() }
    if let last = lastEmitted, now - lastEmitMs < Self.heartbeatMs, Self.skip(frame, after: last,
                                                                             sinceLastMs: now - lastEmitMs,
                                                                             precise: precise()) { return }
    lastEmitted = frame
    lastEmitMs = now
    frameSink.yield(frame)
  }

  /// 非币默认门槛标定：所有簿都拿到首张快照就算；到点（订阅起来 8 秒）时有一本就按已有的算，一本都没有用兜底。
  /// 簿还没加进模型（品种表还在取）不算到点；一本簿都没有的品种直接用兜底。
  private func calibrate(nowMs now: Int64) {
    guard let deadline = calibrationDeadlineMs else { return }
    let depth = model.calibrationDepth()
    let complete = depth.total > 0 && depth.ready == depth.total
    guard complete || depth.total == 0 || now >= deadline else { return }
    calibrating = false
    calibrationDeadlineMs = nil
    calibrated = depth.ready > 0 ? OrderFlowDefaults.calibratedThreshold(depth: depth.depth) : nil
    let shown = calibrated.map { "\(Int($0))" } ?? "标定不出，用兜底 \(Int(OrderFlowDefaults.tradfiPerpetual))"
    log("主力订单流 \(symbol)：默认门槛按簿深标定 \(shown)（±1% 簿深 \(Int(depth.depth))，\(depth.ready)/\(depth.total) 本簿）")
    let next = Self.effective(facts: facts, turnover: turnover, override: override, derivedStep: derivedStep,
                              calibrated: calibrated)
    if next != model.thresholds {
      if next.step != model.thresholds.step { resetHistory() }
      model.setThresholds(next)
    }
    if let journal = deferredJournal {
      deferredJournal = nil
      model.restore(journal)
    }
    lastEmitted = nil  // 标定完立刻出一帧
  }

  /// 心跳之内这一帧发不发：画出来有变化就发；只是金额变了，十字线停着就发、否则隔 `amountRefreshMs` 发一次。
  static func skip(_ frame: OrderFlowSnapshot, after last: OrderFlowSnapshot, sinceLastMs: Int64,
                   precise: Bool) -> Bool {
    guard last.sameContent(as: frame) else { return false }
    if last.sameExactContent(as: frame) { return true }
    return !precise && sinceLastMs < amountRefreshMs
  }

  private func save() {
    guard let file, model.journalDirty else { return }
    let now = clock()
    lastSaveMs = now
    guard let journal = model.journal(nowMs: now) else { return }
    do {
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try journal.encoded().write(to: file, options: .atomic)
      model.markJournalSaved()
    } catch {
      log("主力订单流 \(symbol) 日志落盘失败：\(error)")
    }
  }

  // MARK: - 测试

  func modelForTests() -> OrderFlowModel { model }
  func calibratedForTests() -> (pending: Bool, value: Double?) { (calibrating, calibrated) }
  func historyRangeForTests() -> (from: Int64?, cursor: Int64?) { (historyFromMs, historyCursorMs) }
}

// 测试用：看一眼最后收下的可视范围起点与用户改项（审查 P2-4 的乱序用例）。
extension OrderFlowFeed {
  var visibleWindowStartForTesting: Int64? { visibleFromMs }
  var overrideForTesting: OrderFlowOverride? { override }
}
