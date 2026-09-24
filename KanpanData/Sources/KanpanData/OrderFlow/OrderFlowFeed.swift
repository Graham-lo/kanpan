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
/// - 落盘：大单本身（不含簿）按品种记一份小日志（`<目录>/<品种>.json`，结束的最多 500 条、挂着的不删、24 小时），
///   再打开这只时读回来接着画；不同步。
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

  /// 每隔多久按簿算一帧（出现、消失的确认要两次评估且相隔 ≥ 300 ms，所以不能比 300 ms 更密）。
  public static let evaluateEveryMs: Double = 500
  /// 内容没变时至少隔这么久也发一次（界面上的「12 分」要走）。
  public static let heartbeatMs: Int64 = 30_000
  /// 大单有变化时隔这么久落一次盘。
  public static let saveEveryMs: Int64 = 15_000

  public let symbol: String
  public let facts: OrderFlowFacts
  private let loadBooks: BookLoader
  private let makeAdapters: AdapterMaker
  private let loadClose: CloseLoader
  private let loadTurnover: TurnoverLoader
  private let file: URL?
  private let pacer: any Pacer
  private let clock: @Sendable () -> Int64
  private let log: FeedLog
  private let sink: Sink
  private let evaluateEveryMs: Double

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
  private var lastEmitted: OrderFlowSnapshot?
  private var lastEmitMs: Int64 = .min / 2
  private var lastSaveMs: Int64 = 0
  private var started = false
  private var stopped = false

  /// - Parameters:
  ///   - symbol: 品种键（`InstrumentID.canonical`），吐出去的快照带的就是它。
  ///   - override: 用户给这只 base 改过的门槛 / 步长。
  ///   - directory: 日志落盘目录；nil 表示不落盘。
  public init(symbol: String, facts: OrderFlowFacts, override: OrderFlowOverride?, directory: URL?,
              loadBooks: @escaping BookLoader, makeAdapters: @escaping AdapterMaker,
              loadClose: @escaping CloseLoader, loadTurnover: @escaping TurnoverLoader = { nil },
              pacer: any Pacer = SystemPacer(),
              clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
              evaluateEveryMs: Double = OrderFlowFeed.evaluateEveryMs,
              log: FeedLog = .silent, sink: @escaping Sink) {
    self.symbol = symbol
    self.facts = facts
    self.override = override?.normalized
    self.turnover = facts.turnover24h
    self.loadBooks = loadBooks
    self.makeAdapters = makeAdapters
    self.loadClose = loadClose
    self.loadTurnover = loadTurnover
    self.file = directory.map { Self.journalFile(in: $0, symbol: symbol) }
    self.pacer = pacer
    self.clock = clock
    self.evaluateEveryMs = max(evaluateEveryMs, 1)
    self.log = log
    self.sink = sink
    let now = clock()
    let restored = file.flatMap { try? Data(contentsOf: $0) }.flatMap(OrderFlowJournal.decode)
      .flatMap { $0.symbol == symbol && now - $0.savedAtMs < OrderFlowDefaults.retentionMs ? $0 : nil }
    self.model = OrderFlowModel(symbol: symbol,
                                thresholds: Self.effective(facts: facts, turnover: facts.turnover24h,
                                                           override: override?.normalized, derivedStep: nil),
                                restored: restored)
  }

  /// 按提供者建一条：品种表、连接、日线、成交额都从它来。这条线路给不出订单流就返回 nil。
  public init?(symbol: String, facts: OrderFlowFacts, override: OrderFlowOverride?,
               provider: any MarketProvider, directory: URL?, log: FeedLog = .silent, sink: @escaping Sink) {
    guard let catalog = (provider as? any OrderFlowSourcing)?.orderFlowCatalog else { return nil }
    self.init(symbol: symbol, facts: facts, override: override, directory: directory,
              loadBooks: { base in await catalog.books(base: base) },
              makeAdapters: { books in catalog.adapters(books) },
              loadClose: { day in try await Self.previousClose(provider: provider, symbol: symbol, referenceDayMs: day) },
              loadTurnover: { try? await provider.ticker24h(symbol: symbol, timeout: 8).quoteVolume },
              log: log, sink: sink)
  }

  /// 此刻生效的门槛与步长：默认表 → 叠用户改过的项 → 还没有步长就用按收盘推的那个。
  static func effective(facts: OrderFlowFacts, turnover: Double?, override: OrderFlowOverride?,
                        derivedStep: Double?) -> OrderFlowThresholds {
    var t = OrderFlowDefaults.thresholds(base: facts.overrideKey, asset: facts.asset, turnover24h: turnover)
      .applying(override)
    if t.step == nil { t.step = derivedStep }
    return t
  }

  /// 日志文件：`<dir>/<品种键里的字母数字>.json`。
  public static func journalFile(in directory: URL, symbol: String) -> URL {
    let safe = String(symbol.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
    return directory.appendingPathComponent(safe + ".json")
  }

  /// 清掉目录里 24 小时没动过的日志，以及旧版留下的门槛标定（按上游分的子目录、`.cal`）。
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
      if nowMs - modified >= OrderFlowDefaults.retentionMs { try? fm.removeItem(at: item) }
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

  public func start() {
    guard !started, !stopped else { return }
    started = true
    tasks.append(Task { [weak self] in await self?.setUp() })
    tasks.append(Task { [weak self] in await self?.evaluateLoop() })
    if turnover == nil, facts.asset == .crypto {
      tasks.append(Task { [weak self] in await self?.fetchTurnover() })
    }
    ensureDerivedStep()
  }

  /// 退订并清簿。大单有变化就顺手落盘。
  public func stop() async {
    stopped = true
    tasks.forEach { $0.cancel() }; tasks = []
    schemeTask?.cancel(); schemeTask = nil
    snapshotTasks.values.forEach { $0.cancel() }; snapshotTasks = [:]
    let dying = streams; streams = []; adapters = []
    for s in dying { await s.stop() }
    save()
  }

  /// 用户改了这只 base 的门槛 / 步长（面板里改，或别的设备同步过来）。
  public func setOverride(_ next: OrderFlowOverride?) {
    let normalized = next?.normalized
    guard normalized != override else { return }
    override = normalized
    refreshThresholds()
    ensureDerivedStep()
  }

  private func refreshThresholds() {
    let next = Self.effective(facts: facts, turnover: turnover, override: override, derivedStep: derivedStep)
    guard next != model.thresholds else { return }
    model.setThresholds(next)
    lastEmitted = nil  // 门槛一改立刻出一帧，不等心跳
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
    adapters = makeAdapters(books)
    log("主力订单流 \(symbol)：\(books.count) 本簿、\(adapters.count) 条连接\(result.fromCatalog ? "" : "（品种表没拿到，用保底）")")
    for (index, adapter) in adapters.enumerated() {
      let depth = DepthStream(adapter: adapter, pacer: pacer, log: log)
      streams.append(depth)
      tasks.append(Task { [weak self] in
        let events = await depth.start()
        for await event in events {
          guard let self, !Task.isCancelled else { return }
          await self.handle(event, stream: index)
        }
      })
    }
  }

  private func handle(_ event: DepthStreamEvent, stream index: Int) async {
    guard index < adapters.count, !stopped else { return }
    let books = adapters[index].books
    let now = clock()
    switch event {
    case .connected:
      for book in books {
        cancelSnapshot(book.id)
        await perform(model.connectionOpened(book.id), venue: book.id, stream: index)
      }
    case .messages(let messages):
      var actions: [String: OrderFlowModel.Action] = [:]
      for m in messages {
        let action = model.ingest(m.venueID, m.message, nowMs: now)
        if action != .none { actions[m.venueID] = action }
      }
      // 一条连接上只要有一本要重订，整条重拨一次就够了。
      if actions.values.contains(.resubscribe) {
        await streams[index].reconnect()
        return
      }
      for (venue, action) in actions.sorted(by: { $0.key < $1.key }) {
        await perform(action, venue: venue, stream: index)
      }
    case .disconnected(let reason):
      // 断线期间簿不再可信：回到「拉快照中」，重连后再重建。
      for book in books {
        model.disconnected(book.id)
        cancelSnapshot(book.id)
      }
      log("主力订单流 \(symbol) \(adapters[index].name) 断开：\(reason)")
    }
  }

  private func perform(_ action: OrderFlowModel.Action, venue: String, stream index: Int) async {
    switch action {
    case .none: break
    case .fetchSnapshot: fetchSnapshot(venue: venue, stream: index)
    case .resubscribe: await streams[index].reconnect()
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

  private func applied(_ snapshot: BookSnapshot, venue: String, stream index: Int) async {
    snapshotTasks[venue] = nil
    let action = model.applySnapshot(venue, snapshot, nowMs: clock())
    if action == .fetchSnapshot {
      // 快照比缓冲的增量还旧（或对不上）：等一小会儿让增量攒起来再拉，别连打。
      try? await pacer.sleep(ms: 500)
      guard !stopped else { return }
    }
    await perform(action, venue: venue, stream: index)
  }

  private func snapshotFailed(_ venue: String, _ message: String) {
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
    let frame = model.evaluate(nowMs: now)
    if model.journalDirty, now - lastSaveMs >= Self.saveEveryMs { save() }
    if let last = lastEmitted, last.sameContent(as: frame), now - lastEmitMs < Self.heartbeatMs { return }
    lastEmitted = frame
    lastEmitMs = now
    let sink = self.sink
    Task { await sink(frame) }
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
}
