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
/// - 服务端历史（2026-09-24）：kanpan-api 常驻跟踪大单生命周期、存 3 天（2026-09-25 从 30 天收到 3 天）。读完本地日志就取最近 6 小时并进模型
///   （2026-10-07 从 24 小时收到 6 小时：BTC 一页 470 KB / 一万条变 100 KB / 两千条，开图少等一截；更早的往左拖再补），
///   之后每分钟取一次增量（从上一页最晚的时刻往前退 5 分钟接着取）；图往左拖到已取区间之外，就 6 小时一段往前补，
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
  /// 取服务端记下的一段历史（`base` 已去掉缩放前缀）。`minLifeMs` 给了时，服务端不回活不到这么久就结束的单
  /// （挂着的照回）；nil 不带这个参数。取不到给 nil。
  public typealias HistoryLoader = @Sendable (_ base: String, _ fromMs: Int64, _ toMs: Int64,
                                              _ minLifeMs: Int64?) async -> OrderFlowHistoryPage?
  /// 取服务端每分钟大单买卖额（`base` 已去掉缩放前缀）。取不到给 nil。
  public typealias FlowLoader = @Sendable (_ base: String, _ fromMs: Int64, _ toMs: Int64) async -> BigTradeFlowPage?
  /// 大单成交账多久随帧换一份（分钟桶每笔大单都在长，图表与弹层一秒一换足够）。
  public static let tradesEveryMs: Int64 = 1_000

  /// 每隔多久按簿算一帧（出现、消失的确认要两次评估且相隔 ≥ 300 ms，所以不能比 300 ms 更密）。
  public static let evaluateEveryMs: Double = 500
  /// 内容没变时至少隔这么久也发一次（界面上的「12 分」要走）。
  public static let heartbeatMs: Int64 = 30_000
  /// 画出来一样、只是金额变了的帧最快隔这么久才发一次（图例「主力 买 12.3M」的合计要跟上，
  /// 但不能每拍都发）；十字线停在色块上（`precise` 为真）时不受这一条限制，读数要精确金额。
  /// 画面变了（有单出现 / 结束）那一帧照发，但其余画面没变的活单金额仍按上一次发出去的（`hold`），
  /// 到点再一起换——不然每有一单出现，满屏金额签都跟着跳一次（用户 2026-10-07：「数字变化的非常快，像出错的数据」）。
  public static let amountRefreshMs: Int64 = 5_000
  /// 大单有变化时隔这么久落一次盘。日志最多约 1 MB，更早的都在服务端，被杀掉丢的这一分钟下次打开由服务端补回。
  public static let saveEveryMs: Int64 = 60_000
  /// 服务端历史：每隔多久取一次增量；增量从上一页最晚时刻往前退多少接着取（服务端挂着的单 15 秒才刷一次库）；
  /// 一段取多长（首次与往左补都是 6 小时一段；与网页版 HISTORY_SPAN_MS 同口径）。
  public static let historyEveryMs: Int64 = 60_000
  public static let historyOverlapMs: Int64 = 5 * 60_000
  public static let historySpanMs: Int64 = 6 * 3_600_000
  /// 首次那一页没取到，隔多久再试；往左补的一段没取到，隔多久再试。
  static let historyRetryMs: Int64 = 10_000
  static let backfillRetryMs: Int64 = 30_000
  /// 往左补（6 小时之前）的那几页只要活过 5 分钟的单：那么早的碎单（BTC 一半活不过 1 分钟）拉远看是底噪，
  /// 还占着 2 万条的额度；首次与增量那两种页照旧全要（最近 6 小时的细节要紧）。
  public static let backfillMinLifeMs: Int64 = 300_000

  public let symbol: String
  public let facts: OrderFlowFacts
  private let loadBooks: BookLoader
  private let makeAdapters: AdapterMaker
  private let loadClose: CloseLoader
  private let loadTurnover: TurnoverLoader
  private let loadHistory: HistoryLoader
  private let loadFlow: FlowLoader
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
  /// 大单成交分钟账（本机逐笔 + 服务端 /flow 分钟行）。
  private var trades: BigTradeFlow
  private var tradesAttachedMs: Int64 = .min / 2
  private var flowFetch: Task<Void, Never>?
  private var flowDueMs: Int64 = .min / 2
  private var lastEmitMs: Int64 = .min / 2
  /// 上一次把活单的金额换成新的是什么时候（`amountRefreshMs`）。
  private var amountsAtMs: Int64 = .min / 2
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
  /// 取这些页时各产品用过的最高门槛（随游标落盘；读回时此刻门槛更低就不能接着用游标）。
  private var historyThresholds: OrderFlowThresholds?
  /// 上一次落盘时的游标：游标往前走了、大单没变时，进后台 / 停的时候也落一次盘。
  private var savedHistory: OrderFlowHistoryCursor?
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
  /// 日志里带着上一次标定的门槛：先按它出帧、读回日志、取历史，同时照常标定一遍，
  /// 标定完和它有出入再改（`calibrate`）。原来非币开图要空等最多 8 秒标定，已有的大单那几秒全看不见。
  private var recalibrating = false
  /// 上一次落盘时写进日志头的标定值：标定值变了、大单没变时也要落一次盘。
  private var savedCalibrated: Double?

  /// - Parameters:
  ///   - symbol: 品种键（`InstrumentID.canonical`），吐出去的快照带的就是它。
  ///   - override: 用户给这只 base 改过的门槛 / 步长。
  ///   - directory: 日志落盘目录；nil 表示不落盘。
  public init(symbol: String, facts: OrderFlowFacts, override: OrderFlowOverride?, directory: URL?,
              loadBooks: @escaping BookLoader, makeAdapters: @escaping AdapterMaker,
              loadClose: @escaping CloseLoader, loadTurnover: @escaping TurnoverLoader = { nil },
              loadHistory: @escaping HistoryLoader = { _, _, _, _ in nil },
              loadFlow: @escaping FlowLoader = { _, _, _ in nil },
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
    self.loadFlow = loadFlow
    self.trades = BigTradeFlow(symbol: symbol)
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
              loadHistory: { base, from, to, minLife in
                await catalog.history(base: base, fromMs: from, toMs: to, minLifeMs: minLife)
              },
              loadFlow: { base, from, to in await catalog.flow(base: base, fromMs: from, toMs: to) },
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
    flowFetch?.cancel(); flowFetch = nil
    schemeTask?.cancel(); schemeTask = nil
    snapshotTasks.values.forEach { $0.cancel() }; snapshotTasks = [:]
    let dying = streams; streams = []; adapters = []; connectionOf = [:]; connectedAtMs = [:]
    for s in dying { await s.stop() }
    save(force: true)
  }

  /// 马上落一次盘（app 进后台时调；`stop` 也会落）。大单没变、游标也没往前走就不写。
  /// 编码与写文件都在这个 actor 上做，不占主线程；写的是临时文件再改名，写到一半被杀也不会留下半份。
  public func saveNow() {
    save(force: true)
  }

  /// 读回这只的日志（24 小时内、品种对得上的）。门槛照此刻生效的那份（`start` 之前可能已经改过）。
  private func restoreJournal() {
    guard let file else { return }
    let now = clock()
    guard let journal = (try? Data(contentsOf: file)).flatMap(OrderFlowJournal.decode),
          journal.symbol == symbol, now - journal.savedAtMs < OrderFlowDefaults.journalRetentionMs else { return }
    if calibrating {
      // 上一次标定过：先按那个门槛读回、出帧，标定照跑，完了有出入再改。
      if let saved = journal.calibrated {
        calibrated = saved
        savedCalibrated = saved
        calibrating = false
        recalibrating = true
        let thresholds = Self.effective(facts: facts, turnover: turnover, override: override,
                                        derivedStep: derivedStep, calibrated: saved)
        model = OrderFlowModel(symbol: symbol, thresholds: thresholds, restored: journal)
        log("主力订单流 \(symbol)：先按上次标定的门槛 \(Int(saved)) 出帧，标定照跑")
        return
      }
      // 默认门槛还在等标定：先放着，标定完再读回（兜底 200 万会把标定门槛以上、200 万以下的单删掉）。
      deferredJournal = journal; return
    }
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
    if next.step != model.thresholds.step { resetHistory() } else { raiseHistoryThresholds(to: next) }
    model.setThresholds(next)
    emitNextTick()  // 门槛一改立刻出一帧，不等心跳
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
    if calibrating || recalibrating { calibrationDeadlineMs = clock() + OrderFlowDefaults.calibrationTimeoutMs }
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
      let cut = BigTradeFlow.threshold(model.thresholds).map(BigTradeFlow.cut(threshold:))
      for m in messages {
        if case .trade(let t) = m.message, let venue = model.venue(m.venueID) {
          trades.record(timeMs: t.timeMs > 0 ? t.timeMs : now, price: t.price,
                        usd: venue.notional.usd(price: t.price, quantity: t.quantity), buy: t.hitSide == .ask, cut: cut)
        }
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
    historyFromMs = nil; historyCursorMs = nil; historyTrackedSinceMs = nil; historyThresholds = nil
    historyPulledMs = .min / 2; historyRetryAtMs = .min / 2; backfillRetryAtMs = .min / 2
    historyBlockedStep = nil
  }

  enum HistoryKind: Sendable { case initial, increment, backfill }
  struct HistoryJob: Sendable, Equatable {
    var kind: HistoryKind
    var fromMs: Int64
    var toMs: Int64
  }

  /// 该取哪一页了：首次（最近 6 小时）→ 到点的增量 → 图往左拖出去了就往前补一段。都不该取是 nil。
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
    guard started, !stopped, !calibrating, historyFetch == nil else { return }
    adoptRestoredHistory()
    guard let job = nextHistoryJob(nowMs: clock()) else { return }
    let load = loadHistory, base = facts.overrideKey, generation = historyGeneration
    let minLife = job.kind == .backfill ? Self.backfillMinLifeMs : nil
    historyFetch = Task { [weak self] in
      let page = await load(base, job.fromMs, job.toMs, minLife)
      await self?.historyArrived(page, job: job, generation: generation)
    }
  }

  /// 读回的日志带着游标（模型接下了那份日志、步长与门槛都对得上）：接着用，下一次取的是游标之后的增量，
  /// 不再整页重取。原来每次起订都发首次页：ETH 24 小时一页 1.3 MB gzip、3 万行，首字节 0.9–4.5 秒。
  /// 游标停在一段（6 小时）以前（日志存得太久）不接着用：增量要取的比首次那页还长，不如整页重取。
  private func adoptRestoredHistory() {
    guard historyCursorMs == nil, let cursor = model.takeRestoredHistory(),
          clock() - cursor.cursorMs <= Self.historySpanMs else { return }
    historyFromMs = cursor.fromMs
    historyCursorMs = cursor.cursorMs
    historyTrackedSinceMs = cursor.trackedSinceMs
    historyThresholds = cursor.thresholds
    historyPulledMs = .min / 2  // 马上取一次增量
    savedHistory = cursor
  }

  /// 门槛改了（步长没变）：记下各产品用过的最高门槛。之后要是调低，低出来的那一截服务端没给过，
  /// 下次读回日志时不能接着用游标。
  private func raiseHistoryThresholds(to next: OrderFlowThresholds) {
    guard var used = historyThresholds else { return }
    for product in OrderFlowProduct.allCases {
      if let value = next[product] { used[product] = max(used[product] ?? value, value) }
    }
    historyThresholds = used
  }

  private var historyCursor: OrderFlowHistoryCursor? {
    guard let from = historyFromMs, let cursor = historyCursorMs else { return nil }
    return OrderFlowHistoryCursor(fromMs: from, cursorMs: cursor, trackedSinceMs: historyTrackedSinceMs,
                                  thresholds: historyThresholds)
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
        historyThresholds = model.thresholds
      case .increment:
        historyCursorMs = max(historyCursorMs ?? .min, page.latestMs ?? page.fromMs + Self.historyOverlapMs)
      case .backfill:
        historyFromMs = min(historyFromMs ?? page.fromMs, page.fromMs)
      }
      emitNextTick()  // 并进来的马上出一帧
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

  // MARK: - 大单成交分钟账

  /// 服务端每分钟大单买卖额：起订就取（从已有的最晚一分钟接着，没有就 3 天），之后每分钟一次；
  /// 取不到半分钟后再试，纯本地照常。
  private func pumpFlow(nowMs now: Int64) {
    guard started, !stopped, flowFetch == nil, now >= flowDueMs else { return }
    let load = loadFlow, base = facts.overrideKey, from = trades.serverFetchFrom(nowMs: now)
    flowFetch = Task { [weak self] in
      let page = await load(base, from, now)
      await self?.flowArrived(page)
    }
  }

  private func flowArrived(_ page: BigTradeFlowPage?) {
    guard !stopped else { return }
    flowFetch = nil
    let now = clock()
    guard let page else { flowDueMs = now + BigTradeFlow.retryMs; return }
    flowDueMs = now + BigTradeFlow.pollMs
    trades.merge(page, nowMs: now)
    tradesAttachedMs = .min / 2
    emitNextTick()
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
    if calibrating || recalibrating { calibrate(nowMs: now) }
    pumpHistory()
    trades.beat(nowMs: now, ok: !adapters.isEmpty && connectedAtMs.count == adapters.count)
    pumpFlow(nowMs: now)
    // 标定之前出「加载中」、不带门槛与默认：面板那时按品种事实查表（兜底 200 万），标定完换成标定值。
    var frame = calibrating ? OrderFlowSnapshot.loading(symbol, asOfMs: now) : model.evaluate(nowMs: now)
    if !calibrating {
      frame.defaults = Self.effective(facts: facts, turnover: turnover, override: nil, derivedStep: nil,
                                      calibrated: calibrated)
    }
    if now - tradesAttachedMs >= Self.tradesEveryMs || lastEmitted?.trades == nil {
      frame.trades = trades
    } else {
      frame.trades = lastEmitted?.trades
    }
    if model.journalDirty || calibrated != savedCalibrated, now - lastSaveMs >= Self.saveEveryMs { save() }
    guard let out = Self.pace(frame, after: lastEmitted, sinceLastMs: now - lastEmitMs,
                              sinceAmountsMs: now - amountsAtMs, precise: precise()) else { return }
    if out.amountsRefreshed { amountsAtMs = now }
    if out.frame.trades != lastEmitted?.trades { tradesAttachedMs = now }
    lastEmitted = out.frame
    lastEmitMs = now
    frameSink.yield(out.frame)
  }

  /// 非币默认门槛标定：所有簿都拿到首张快照就算；到点（订阅起来 8 秒）时有一本就按已有的算，一本都没有用兜底。
  /// 簿还没加进模型（品种表还在取）不算到点；一本簿都没有的品种直接用兜底。
  private func calibrate(nowMs now: Int64) {
    guard let deadline = calibrationDeadlineMs else { return }
    let depth = model.calibrationDepth()
    let complete = depth.total > 0 && depth.ready == depth.total
    guard complete || depth.total == 0 || now >= deadline else { return }
    let provisional = recalibrating
    calibrating = false
    recalibrating = false
    calibrationDeadlineMs = nil
    let fresh = depth.ready > 0 ? OrderFlowDefaults.calibratedThreshold(depth: depth.depth) : nil
    // 先按上次的值出着帧：这次一本簿都没标定出来就别拿兜底 200 万顶掉它。
    calibrated = provisional ? (fresh ?? calibrated) : fresh
    let shown = calibrated.map { "\(Int($0))" } ?? "标定不出，用兜底 \(Int(OrderFlowDefaults.tradfiPerpetual))"
    log("主力订单流 \(symbol)：默认门槛按簿深标定 \(shown)（±1% 簿深 \(Int(depth.depth))，\(depth.ready)/\(depth.total) 本簿）")
    let next = Self.effective(facts: facts, turnover: turnover, override: override, derivedStep: derivedStep,
                              calibrated: calibrated)
    if next != model.thresholds {
      // 先按上次的门槛取过历史了：门槛往下改，低出来那一截服务端没给过，历史从头取。
      if next.step != model.thresholds.step || (provisional && Self.lowers(next, from: model.thresholds)) {
        resetHistory()
      } else {
        raiseHistoryThresholds(to: next)
      }
      model.setThresholds(next)
    }
    if let journal = deferredJournal {
      deferredJournal = nil
      model.restore(journal)
    }
    emitNextTick()  // 标定完立刻出一帧
  }

  /// `next` 里有哪个产品的门槛比 `current` 低。
  static func lowers(_ next: OrderFlowThresholds, from current: OrderFlowThresholds) -> Bool {
    OrderFlowProduct.allCases.contains { product in
      guard let n = next[product], let c = current[product] else { return false }
      return n < c
    }
  }

  /// 下一拍不等心跳、一定发；但不丢上一帧——活单金额仍按 `hold` 的规矩按住。原来这里把 `lastEmitted` 清掉，
  /// 等于整帧金额重新来过：开图那几秒服务端历史一页一页并进来（15 分钟图要补三四页、每页一次），满屏金额
  /// 签每页都换一遍（10-07 网页端实测 2.5 / 3.4 / 4.3 / 5.2 秒各刷一次），正是用户说的「开启到稳定那段数字变得非常快」。
  private func emitNextTick() { lastEmitMs = .min / 2 }

  /// 心跳之内这一帧发不发：画出来有变化就发；只是金额变了，十字线停着就发、否则隔 `amountRefreshMs` 发一次。
  /// 这一拍该不该发、发哪一份：
  /// - 第一帧、十字线停着（`precise`）、距上次换金额已满 `amountRefreshMs`：照模型此刻的金额发；
  /// - 否则活着、画面没变的单金额按上一次发出去的（`hold`）；按完和上一帧逐字相同就不发（心跳到点除外）。
  /// 返回 nil 是不发；`amountsRefreshed` 为真表示这一帧换上了新金额（调用方记下时刻）。
  static func pace(_ frame: OrderFlowSnapshot, after last: OrderFlowSnapshot?, sinceLastMs: Int64,
                   sinceAmountsMs: Int64, precise: Bool) -> (frame: OrderFlowSnapshot, amountsRefreshed: Bool)? {
    guard let last else { return (frame, true) }
    let refresh = precise || sinceAmountsMs >= amountRefreshMs
    let out = refresh ? frame : hold(frame, from: last)
    if sinceLastMs < heartbeatMs, last.sameExactContent(as: out) { return nil }
    return (out, refresh)
  }

  /// 活着、除金额外没变（`BigOrder.sameShape`：不比高度与桶内均价，它们跟着金额 5 秒一换）的单，
  /// 金额与均价照 `last` 里发出去的那份；新单、成交格变了的、已结束的取 `frame` 的。
  static func hold(_ frame: OrderFlowSnapshot, from last: OrderFlowSnapshot) -> OrderFlowSnapshot {
    var held: [String: BigOrder] = [:]
    for o in last.orders where o.status == .live { held[o.id] = o }
    guard !held.isEmpty else { return frame }
    var out = frame
    for i in out.orders.indices where out.orders[i].status == .live {
      guard let h = held[out.orders[i].id], BigOrder.sameShape(h, out.orders[i]) else { continue }
      out.orders[i].notional = h.notional
      out.orders[i].filledNotional = h.filledNotional
      out.orders[i].price = h.price
    }
    return out
  }

  /// 落盘：大单有变化才写；`force`（停、进后台）时游标往前走了也写。都在这个 actor 上，不占主线程；
  /// `.atomic` 先写同目录的临时文件再改名，被杀在半路也只会留下旧的那一整份。
  private func save(force: Bool = false) {
    guard let file else { return }
    let cursor = historyCursor
    guard model.journalDirty || calibrated != savedCalibrated || (force && cursor != savedHistory) else { return }
    let now = clock()
    lastSaveMs = now
    guard var journal = model.journal(nowMs: now) else { return }
    journal.history = cursor
    journal.calibrated = calibrated
    do {
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try journal.encoded().write(to: file, options: .atomic)
      model.markJournalSaved()
      savedHistory = cursor
      savedCalibrated = calibrated
    } catch {
      log("主力订单流 \(symbol) 日志落盘失败：\(error)")
    }
  }

  // MARK: - 测试

  func modelForTests() -> OrderFlowModel { model }
  func calibratedForTests() -> (pending: Bool, value: Double?) { (calibrating, calibrated) }
  func recalibratingForTests() -> Bool { recalibrating }
  func historyRangeForTests() -> (from: Int64?, cursor: Int64?) { (historyFromMs, historyCursorMs) }
  func historyCursorForTests() -> OrderFlowHistoryCursor? { historyCursor }
}

// 测试用：看一眼最后收下的可视范围起点与用户改项（审查 P2-4 的乱序用例）。
extension OrderFlowFeed {
  var visibleWindowStartForTesting: Int64? { visibleFromMs }
  var overrideForTesting: OrderFlowOverride? { override }
}
