import Foundation
import KanpanCore
import KanpanNetwork

/// 对比行情仅驻留内存；一条组合流，沿主序列时间范围补历史，不阻塞主行情。
public actor CompareFeed {
  public struct Snapshot: Sendable, Equatable {
    public var key: String
    public var series: BarSeries
    public init(key: String, series: BarSeries) { self.key = key; self.series = series }
    public func aligned(to main: BarSeries) -> (open: [Double?], close: [Double?]) {
      var opens = [Double?](repeating: nil, count: main.count)
      var closes = opens
      guard main.interval == series.interval else { return (opens, closes) }
      var j = 0
      for i in 0..<main.count {
        let time = main.time(at: i)
        while j < series.count && series.time(at: j) < time { j += 1 }
        if j < series.count, series.time(at: j) == time {
          let o = series.open[j], c = series.close[j]
          opens[i] = o.isFinite && o > 0 ? o : nil
          closes[i] = c.isFinite && c > 0 ? c : nil
        }
      }
      return (opens, closes)
    }
  }

  /// 交易所 → 这一家的提供者（认不出的交易所给 nil，那只就不取）。
  public typealias Providers = @Sendable (_ venue: String) -> (any MarketProvider)?

  private let provide: Providers
  private let ws: any MarketStream
  private let pacer: any Pacer
  /// 每家一个提供者，这一轮对比里复用（REST 的限流器按家共享）。
  private var providers: [String: any MarketProvider] = [:]
  private var keys: [String] = []
  private var interval: Interval = .h1
  /// 每只对比品种取数用的源周期（各家原生周期不一样：1y 在币安聚自 1M，在别家可能聚自 1d）。
  private var sources: [String: Interval] = [:]
  private var generation = UUID()
  private var data: [String: FeedComposer] = [:]
  private(set) var target: ClosedRange<Int64>?
  private var covered: [String: ClosedRange<Int64>] = [:]
  private var loads: [String: Task<Void, Never>] = [:]
  private var retries: [String: Task<Void, Never>] = [:]
  private var failures: [String: Int] = [:]
  private var blocked: Set<String> = []
  private var pendingTail: Set<String> = []
  private var pump: Task<Void, Never>?
  private var flush: Task<Void, Never>?
  private var sink: AsyncStream<[Snapshot]>.Continuation?
  private var connected = false
  /// 主图更新的收件箱（审查 P2-4）。调用方原来每次 `Task { await feed.updateMain(main) }`：
  /// 几个 Task 到达先后不定，旧的主图可能盖掉新的；更糟的是赶在 `start` 之前到的那次
  /// 因为对比品种还没定下来被直接丢掉，`start` 再拿创建那一刻的旧主图定取数范围。
  /// 现在走 `post(main:)`：同步投进这只只留最新一份的信箱，`start` 之后由一条任务按顺序取出来交给
  /// `updateMain`——顺序由投递顺序定，不看 Task 调度。
  private let mainInbox: AsyncStream<BarSeries>
  private nonisolated let mainPost: AsyncStream<BarSeries>.Continuation
  private var inboxPump: Task<Void, Never>?

  public init(provider: @escaping Providers, stream: any MarketStream, pacer: any Pacer = SystemPacer()) {
    provide = provider; ws = stream; self.pacer = pacer
    (mainInbox, mainPost) = AsyncStream<BarSeries>.makeStream(bufferingPolicy: .bufferingNewest(1))
  }

  deinit { mainPost.finish() }

  /// 主图变了（加载了更早的历史、末根走了）：同步投递，不用起 Task。只留最新一份，
  /// `start` 之前投的也不丢，`start` 一完就按它补齐范围。
  public nonisolated func post(main: BarSeries) { mainPost.yield(main) }

  /// 按用户选的线路取数：每只对比品种找它自己那一家，推送按家合流（一家一条连接）。
  public init(resolver: RouteResolver, log: FeedLog = .silent) {
    provide = { venue in VenueRegistry.descriptor(venue).map { resolver.provider(venue: $0.id) } }
    ws = MergedMarketStream { venue in
      VenueRegistry.descriptor(venue).map { resolver.provider(venue: $0.id).makeStream(silenceMs: nil, log: log) }
    }
    pacer = SystemPacer()
    (mainInbox, mainPost) = AsyncStream<BarSeries>.makeStream(bufferingPolicy: .bufferingNewest(1))
  }

  private func provider(for key: String) -> (any MarketProvider)? {
    let venue = InstrumentID(key).venue
    if let cached = providers[venue] { return cached }
    guard let made = provide(venue) else { return nil }
    providers[venue] = made
    return made
  }

  public func events() -> AsyncStream<[Snapshot]> {
    sink?.finish()
    let (stream, continuation) = AsyncStream<[Snapshot]>.makeStream(bufferingPolicy: .bufferingNewest(1))
    sink = continuation
    return stream
  }

  public func start(keys: [String], main: BarSeries) async {
    guard !Task.isCancelled else { return }
    retire()
    generation = UUID()
    let token = generation
    var unique: [String] = []
    var topics: [StreamTopic] = []
    var sources: [String: Interval] = [:]
    // 每只找它自己那一家要行情；认不出的交易所（新版本同步下来的）留在偏好里，
    // 但绝不能拿它的代号去别家冒领行情。
    for key in keys.map(InstrumentID.canonical) where key != InstrumentID.canonical(main.symbol) && !unique.contains(key) {
      guard let provider = provider(for: key) else { continue }
      let caps = provider.capabilities, source = caps.source(for: main.interval)
      unique.append(key); sources[key] = source
      // 有原生 K 线推送就订 K 线；没有的周期订逐笔在本地拼末根（和主图 `MarketFeed` 同一个办法）。
      topics.append(caps.liveKlineIntervals.contains(source) ? .kline(symbol: key, interval: source) : .trade(symbol: key))
      if unique.count == 3 { break }
    }
    self.keys = unique; self.sources = sources; interval = main.interval
    data = [:]; covered = [:]; failures = [:]; blocked = []; pendingTail = []; target = nil; connected = false
    publish()
    guard !unique.isEmpty, !main.isEmpty else { await ws.stop(); return }
    updateMain(main)
    if inboxPump == nil {
      let inbox = mainInbox
      inboxPump = Task { [weak self] in
        for await next in inbox {
          guard let self else { return }
          await self.updateMain(next)
        }
      }
    }
    let stream = await ws.start(topics: topics)
    guard generation == token, !Task.isCancelled else { return }
    pump = Task { [weak self] in
      for await event in stream {
        guard !Task.isCancelled, let self else { return }
        await self.receive(event, token: token)
      }
    }
  }

  public func updateMain(_ main: BarSeries) {
    guard main.interval == interval, !main.isEmpty, !keys.isEmpty else { return }
    let start = Aggregator.bucketStart(ms: main.firstTime, interval: interval)
    let end: Int64
    if interval == .y1 {
      let year = DateParts(ms: Double(main.lastTime), offsetMinutes: 0).year
      end = Aggregator.utcMs(year: year + 1, month: 1, day: 1) - 1
    } else { end = main.lastTime }
    target = start...end
    for key in keys { schedule(key) }
  }

  private func schedule(_ key: String, forceTail: Bool = false) {
    if forceTail { pendingTail.insert(key) }
    guard loads[key] == nil, retries[key] == nil, !blocked.contains(key), let target else { return }
    let refreshTail = pendingTail.remove(key) != nil
    let range: ClosedRange<Int64>
    if let old = covered[key] {
      if target.lowerBound < old.lowerBound {
        if refreshTail { pendingTail.insert(key) }
        range = target.lowerBound...(old.lowerBound - 1)
      }
      else if refreshTail || target.upperBound > old.upperBound {
        range = max(target.lowerBound, min(old.upperBound, data[key]?.series.lastTime ?? target.lowerBound))...target.upperBound
      } else { return }
    } else { range = target }
    guard let rest = provider(for: key), let source = sources[key] else { return }
    let token = generation, revision = data[key]?.wsRevision ?? 0
    loads[key] = Task { [weak self] in
      do {
        // 先拉右侧最近一页，够首屏即发布；再向左补到主序列起点。
        var end = range.upperBound
        while end >= range.lowerBound {
          try Task.checkCancellation()
          let bars = try await rest.klines(symbol: key, interval: source, limit: 300,
            startTime: nil, endTime: end)
          guard let self else { return }
          let accepted = await self.mergeHistory(bars.filter { $0.openTime >= range.lowerBound && $0.openTime <= range.upperBound },
            key: key, token: token, revision: revision)
          guard accepted else { return }
          guard let first = bars.first?.openTime, first > range.lowerBound, first <= end, bars.count == 300 else { break }
          end = first - 1
        }
        await self?.loaded(key, range: range, token: token, success: true)
      } catch {
        await self?.loaded(key, range: range, token: token, success: false, blocked: (error as? UpstreamError)?.stopsRetrying == true)
      }
    }
  }

  private func mergeHistory(_ bars: [Bar], key: String, token: UUID, revision: UInt64) -> Bool {
    guard token == generation, keys.contains(key), !Task.isCancelled else { return false }
    var composer = data[key] ?? composer(for: key)
    composer.merge(bars.filter(\.isValidMarketBar), preservingLiveTail: composer.wsRevision != revision)
    data[key] = composer
    publish()
    return true
  }

  private func loaded(_ key: String, range: ClosedRange<Int64>, token: UUID, success: Bool, blocked: Bool = false) {
    guard token == generation else { return }
    loads[key] = nil
    if blocked { self.blocked.insert(key); return }
    if success {
      failures[key] = 0
      if let old = covered[key] { covered[key] = min(old.lowerBound, range.lowerBound)...max(old.upperBound, range.upperBound) }
      else { covered[key] = range }
      schedule(key)
    } else {
      failures[key, default: 0] += 1
      let delay = min(30_000.0, 2_000 * pow(2, Double(min(failures[key, default: 1] - 1, 4))))
      retries[key] = Task { [weak self, pacer] in
        do { try await pacer.sleep(ms: delay) } catch { return }
        await self?.retry(key, token: token)
      }
    }
  }

  private func retry(_ key: String, token: UUID) {
    guard token == generation else { return }
    retries[key] = nil; schedule(key)
  }

  private func receive(_ event: WSEvent, token: UUID) {
    guard token == generation else { return }
    switch event {
    case .payload(.kline(let tick)):
      let key = InstrumentID.canonical(tick.symbol)
      guard keys.contains(key), tick.interval == sources[key]?.rawValue, tick.bar.isValidMarketBar else { return }
      var composer = data[key] ?? composer(for: key)
      guard composer.apply(tick) else { return }
      data[key] = composer
      scheduleFlush(token)
    case .payload(.trade(let trade)):
      // 逐笔只折进已经有历史的末根（`applyTick` 在空序列上不动），断线补缺照旧靠 REST。
      let key = InstrumentID.canonical(trade.symbol)
      guard keys.contains(key), var composer = data[key] else { return }
      guard composer.applyTick(price: trade.price, qty: trade.qty, timeMs: trade.timeMs, tradeID: trade.tradeID) != .ignored
      else { return }
      data[key] = composer
      scheduleFlush(token)
    case .connected:
      if connected { for key in keys { schedule(key, forceTail: true) } }
      connected = true
    default: break
    }
  }

  private func composer(for key: String) -> FeedComposer {
    FeedComposer(series: BarSeries(symbol: key, interval: sources[key] ?? interval, bars: []))
  }

  private func scheduleFlush(_ token: UUID) {
    guard flush == nil else { return }
    flush = Task { [weak self, pacer] in
      do { try await pacer.sleep(ms: 100) } catch { return }
      await self?.flushNow(token)
    }
  }

  private func flushNow(_ token: UUID) {
    guard token == generation else { return }
    flush = nil; publish()
  }

  public var current: [Snapshot] {
    keys.compactMap { key in
      guard let raw = data[key]?.series else { return nil }
      return Snapshot(key: key, series: interval == raw.interval ? raw : Aggregator.bucket(series: raw, into: interval))
    }
  }
  private func publish() { sink?.yield(current) }

  private func retire() {
    generation = UUID(); pump?.cancel(); pump = nil; flush?.cancel(); flush = nil
    for task in loads.values { task.cancel() }; loads = [:]
    for task in retries.values { task.cancel() }; retries = [:]
  }

  public func stop() async {
    inboxPump?.cancel(); inboxPump = nil
    retire(); keys = []; sources = [:]; data = [:]; covered = [:]; target = nil
    let previous = sink; sink = nil; previous?.finish()
    await ws.stop()
  }
}
