import Foundation
import KanpanCore

/// 对比行情仅驻留内存；一条组合流，沿主序列时间范围补历史，不阻塞主行情。
public actor CompareFeed {
  private static func symbol(_ key: String) -> String { InstrumentID(key).symbol }

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

  private let rest: BinanceREST
  private let ws: BinanceWS
  private let pacer: any Pacer
  private var keys: [String] = []
  private var interval: Interval = .h1
  private var generation = UUID()
  private var data: [String: FeedComposer] = [:]
  private var target: ClosedRange<Int64>?
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

  public init(rest: BinanceREST, ws: BinanceWS, pacer: any Pacer = SystemPacer()) {
    self.rest = rest; self.ws = ws; self.pacer = pacer
  }

  public init(hosts: BinanceHosts, policy: MarketRoutePolicy, log: FeedLog = .silent) {
    rest = .upstream(policy.source, hosts: hosts, log: log, policy: policy)
    var routed = hosts; routed.streamFallbacks = []
    ws = BinanceWS(hosts: routed, factory: SourceSocketFactory(source: policy.source,
      hosts: hosts, factory: URLSessionSocketFactory(), policy: policy, log: log), log: log)
    pacer = SystemPacer()
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
    // 当前上游只有币安 U 本位这一家；别的交易所的 key（新版本同步下来的）留在偏好里，
    // 但绝不能拿它的 symbol 去当前上游冒领行情。
    for key in keys where key.hasPrefix("binance/usd_m/") && key != InstrumentID.canonical(main.symbol) && !unique.contains(key) {
      unique.append(key)
      if unique.count == 3 { break }
    }
    self.keys = unique; interval = main.interval
    data = [:]; covered = [:]; failures = [:]; blocked = []; pendingTail = []; target = nil; connected = false
    publish()
    guard !unique.isEmpty, !main.isEmpty else { await ws.stop(); return }
    updateMain(main)
    let stream = await ws.start(streams: unique.map { BinanceHosts.klineStream(symbol: Self.symbol($0), interval: main.interval.source.rawValue) })
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
    let token = generation, iv = interval, revision = data[key]?.wsRevision ?? 0
    loads[key] = Task { [weak self, rest] in
      do {
        // 先拉右侧最近一页，够首屏即发布；再向左补到主序列起点。
        var end = range.upperBound
        while end >= range.lowerBound {
          try Task.checkCancellation()
          let bars = try await rest.klines(symbol: Self.symbol(key), interval: iv.source, limit: 300,
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
        await self?.loaded(key, range: range, token: token, success: false, blocked: (error as? BinanceError)?.stopsRetrying == true)
      }
    }
  }

  private func mergeHistory(_ bars: [Bar], key: String, token: UUID, revision: UInt64) -> Bool {
    guard token == generation, keys.contains(key), !Task.isCancelled else { return false }
    var composer = data[key] ?? FeedComposer(series: BarSeries(symbol: Self.symbol(key), interval: interval.source, bars: []))
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
      guard keys.contains(key), tick.interval == interval.source.rawValue, tick.bar.isValidMarketBar else { return }
      var composer = data[key] ?? FeedComposer(series: BarSeries(symbol: tick.symbol, interval: interval.source, bars: []))
      guard composer.apply(tick) else { return }
      data[key] = composer
      if flush == nil {
        flush = Task { [weak self, pacer] in
          do { try await pacer.sleep(ms: 100) } catch { return }
          await self?.flushNow(token)
        }
      }
    case .connected:
      if connected { for key in keys { schedule(key, forceTail: true) } }
      connected = true
    default: break
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
    retire(); keys = []; data = [:]; covered = [:]; target = nil
    let previous = sink; sink = nil; previous?.finish()
    await ws.stop()
  }
}
