import Foundation
import KanpanCore
import KanpanNetwork

/// 主力订单流的数据层：一只品种的一条订阅，从连上深度流到吐出「此刻的大单集合」全在这里。
///
/// - 订阅 / 退订：`start()` / `stop()`，只订当前看的这一只；切品种由 `RoutedMarketFeed` 整个换掉。
/// - 上游：由提供者按线路给的 `DepthFeedAdapter` 决定（哪家、哪条线路、快照在不在流里），
///   这里不认识任何一家。
/// - 清簿：`stop()` 连同本地簿整个扔掉；大单状态永远不同步、不落盘。
/// - 采样落盘：只有门槛标定（`FloorCalibration`）按「上游 × 品种」落在本机缓存目录。
/// - 桶宽：前一 UTC 日收盘（日线）× 合约表 tick，跨 UTC 日重算；日线拉不到时先用簿中价顶着。
public actor OrderFlowFeed {
  public typealias Sink = @Sendable (OrderFlowSnapshot) async -> Void
  /// 前一 UTC 日收盘。`referenceDayMs` 是那一天 0 点（UTC）。
  public typealias CloseLoader = @Sendable (_ referenceDayMs: Int64) async throws -> Double?

  /// 每隔多久按簿算一帧。
  public static let evaluateEveryMs: Double = 500
  /// 内容没变时至少隔这么久也发一次（界面上的「12 分」要走）。
  public static let heartbeatMs: Int64 = 30_000
  /// 标定有新样本时隔这么久落一次盘。
  public static let saveEveryMs: Int64 = 60_000

  public let symbol: String
  private let adapter: any DepthFeedAdapter
  private let loadClose: CloseLoader
  private let tick: Double?
  private let file: URL?
  private let pacer: any Pacer
  private let clock: @Sendable () -> Int64
  private let log: FeedLog
  private let sink: Sink
  private let evaluateEveryMs: Double

  private var model: OrderFlowModel
  private var stream: DepthStream?
  private var tasks: [Task<Void, Never>] = []
  private var snapshotTask: Task<Void, Never>?
  /// 桶宽是日线定的（true）还是簿中价临时顶的（false）。
  private var schemeFromDaily = false
  private var lastEmitted: OrderFlowSnapshot?
  private var lastEmitMs: Int64 = .min / 2
  private var lastSaveMs: Int64 = 0
  private var stopped = false

  /// - Parameters:
  ///   - symbol: 品种键（`InstrumentID.canonical`），吐出去的快照带的就是它。
  ///   - tick: 合约表里的最小变动价；没有时按价格量级估一个。
  ///   - directory: 标定落盘目录；nil 表示不落盘。
  public init(symbol: String, adapter: any DepthFeedAdapter, tick: Double?, directory: URL?,
              loadClose: @escaping CloseLoader, pacer: any Pacer = SystemPacer(),
              clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
              evaluateEveryMs: Double = OrderFlowFeed.evaluateEveryMs,
              log: FeedLog = .silent, sink: @escaping Sink) {
    self.symbol = symbol
    self.adapter = adapter
    self.loadClose = loadClose
    self.tick = tick.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
    self.file = directory.map { Self.calibrationFile(in: $0, upstream: adapter.upstream, symbol: symbol) }
    self.pacer = pacer
    self.clock = clock
    self.evaluateEveryMs = evaluateEveryMs
    self.log = log
    self.sink = sink
    let saved = file.flatMap { try? Data(contentsOf: $0) }.flatMap { FloorCalibration(encoded: $0) }
    self.model = OrderFlowModel(symbol: symbol, sequenceModel: adapter.sequenceModel,
                                snapshotInBand: adapter.snapshotInBand, scheme: nil,
                                calibration: saved ?? FloorCalibration())
  }

  /// 按提供者建一条：适配器与日线都从它来。这一家这条线路没有深度流就返回 nil。
  public init?(symbol: String, provider: any MarketProvider, tick: Double?, directory: URL?,
               log: FeedLog = .silent, sink: @escaping Sink) {
    guard let adapter = provider.orderFlowAdapter(symbol: symbol) else { return nil }
    self.init(symbol: symbol, adapter: adapter, tick: tick, directory: directory,
              loadClose: { day in try await Self.previousClose(provider: provider, symbol: symbol, referenceDayMs: day) },
              log: log, sink: sink)
  }

  /// 标定文件：`<dir>/<上游>/<品种键里的字母数字>.cal`。
  public static func calibrationFile(in directory: URL, upstream: String, symbol: String) -> URL {
    func safe(_ s: String) -> String {
      String(s.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
    }
    return directory.appendingPathComponent(safe(upstream), isDirectory: true)
      .appendingPathComponent(safe(symbol) + ".cal")
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
    guard tasks.isEmpty, !stopped else { return }
    let depth = DepthStream(adapter: adapter, pacer: pacer, log: log)
    stream = depth
    tasks.append(Task { [weak self] in
      let events = await depth.start()
      for await event in events {
        guard let self, !Task.isCancelled else { return }
        await self.handle(event)
      }
    })
    tasks.append(Task { [weak self] in await self?.schemeLoop() })
    tasks.append(Task { [weak self] in await self?.evaluateLoop() })
  }

  /// 退订并清簿。标定有新样本就顺手落盘。
  public func stop() async {
    stopped = true
    tasks.forEach { $0.cancel() }; tasks = []
    snapshotTask?.cancel(); snapshotTask = nil
    let s = stream; stream = nil
    await s?.stop()
    save()
  }

  // MARK: - 深度流

  private func handle(_ event: DepthStreamEvent) async {
    let now = clock()
    switch event {
    case .connected:
      await perform(model.connectionOpened())
    case .messages(let messages):
      var pending = OrderFlowModel.Action.none
      for message in messages {
        let action = model.ingest(message, nowMs: now)
        if action != .none { pending = action }
      }
      await perform(pending)
    case .disconnected(let reason):
      // 断线期间簿不再可信：换个连接号让它回到「拉快照中」，重连后再重建。
      _ = model.connectionOpened()
      snapshotTask?.cancel(); snapshotTask = nil
      log("主力订单流 \(symbol) 断开：\(reason)")
    }
  }

  private func perform(_ action: OrderFlowModel.Action) async {
    switch action {
    case .none: break
    case .fetchSnapshot: fetchSnapshot()
    case .resubscribe: await stream?.reconnect()
    }
  }

  /// 拉一份快照（快照不在流里的那一路）。同一时刻只拉一份；失败按服务端给的等待或退避重试。
  private func fetchSnapshot() {
    guard snapshotTask == nil, !stopped else { return }
    let adapter = self.adapter, pacer = self.pacer
    snapshotTask = Task { [weak self] in
      var backoff = Backoff(baseMs: 1000, capMs: 15_000)
      while !Task.isCancelled {
        do {
          let snapshot = try await adapter.fetchSnapshot()
          guard !Task.isCancelled else { return }
          await self?.applied(snapshot)
          return
        } catch is CancellationError {
          return
        } catch let error as DepthSnapshotError where error.isClientError {
          await self?.snapshotFailed("快照被拒（HTTP \(error.status)），不再重试")
          return
        } catch {
          let wait = (error as? DepthSnapshotError)?.retryAfterMs ?? backoff.next()
          do { try await pacer.sleep(ms: wait) } catch { return }
        }
      }
    }
  }

  private func applied(_ snapshot: BookSnapshot) async {
    snapshotTask = nil
    let action = model.applySnapshot(snapshot, nowMs: clock())
    if action == .fetchSnapshot {
      // 快照比缓冲的增量还旧（或对不上）：等一小会儿让增量攒起来再拉，别连打。
      try? await pacer.sleep(ms: 500)
      guard !stopped else { return }
    }
    await perform(action)
  }

  private func snapshotFailed(_ message: String) {
    snapshotTask = nil
    log("主力订单流 \(symbol) \(message)")
  }

  // MARK: - 桶宽

  private func schemeLoop() async {
    var backoff = Backoff(baseMs: 2000, capMs: 60_000)
    while !Task.isCancelled {
      let now = clock()
      let day = BucketScheme.referenceDay(nowMs: now)
      if model.scheme?.referenceDayMs != day || !schemeFromDaily {
        let close = try? await loadClose(day)
        guard !Task.isCancelled else { return }
        if let close, let scheme = BucketScheme(referenceClose: close, tick: tick ?? Self.guessTick(close),
                                                referenceDayMs: day) {
          model.setScheme(scheme)
          schemeFromDaily = true
          backoff.reset()
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

  /// 合约表里没有 tick 时的兜底：按价格量级取十万分之一再落到 10 的整数次幂。
  static func guessTick(_ price: Double) -> Double {
    guard price > 0, price.isFinite else { return 1e-8 }
    return pow(10, (log10(price * 1e-5)).rounded(.down))
  }

  // MARK: - 出帧

  private func evaluateLoop() async {
    while !Task.isCancelled {
      step()
      do { try await pacer.sleep(ms: evaluateEveryMs) } catch { return }
    }
  }

  private func step() {
    let now = clock()
    if model.scheme == nil, !schemeFromDaily, model.isReady, let mid = bookMid() {
      // 日线还没到：先按簿中价把桶宽定下来，日线到了再换（宽度一样就不清跟踪表）。
      model.setScheme(BucketScheme(referenceClose: mid, tick: tick ?? Self.guessTick(mid),
                                   referenceDayMs: BucketScheme.referenceDay(nowMs: now)))
    }
    let frame = model.evaluate(nowMs: now)
    if model.calibrationDirty, now - lastSaveMs >= Self.saveEveryMs { save() }
    if let last = lastEmitted, last.sameContent(as: frame), now - lastEmitMs < Self.heartbeatMs { return }
    lastEmitted = frame
    lastEmitMs = now
    let sink = self.sink
    Task { await sink(frame) }
  }

  private func bookMid() -> Double? {
    let top = model.book.view(levels: 1)
    guard let bid = top.bids.first?.price, let ask = top.asks.first?.price else { return nil }
    return (bid + ask) / 2
  }

  private func save() {
    guard let file, model.calibrationDirty else { return }
    lastSaveMs = clock()
    let data = model.calibration.encoded()
    do {
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: file, options: .atomic)
      model.markCalibrationSaved()
    } catch {
      log("主力订单流 \(symbol) 标定落盘失败：\(error)")
    }
  }

  // MARK: - 测试

  func modelForTests() -> OrderFlowModel { model }
}
