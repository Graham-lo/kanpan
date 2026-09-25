import Foundation
import Testing
import KanpanCore
import KanpanNetworkTestSupport
@testable import KanpanData
import KanpanNetwork

/// 列表行情的合并推送：按品种键里的交易所分组，每家一条连接。
@Suite("列表行情合并推送")
struct MergedMarketStreamTests {

  /// 记下被怎么用的一条假连接。事件由用例手动推。
  final class FakeStream: MarketStream, @unchecked Sendable {
    private let lock = NSLock()
    private var sink: AsyncStream<WSEvent>.Continuation?
    private(set) var started: [[StreamTopic]] = []
    private(set) var replaced: [[StreamTopic]] = []
    private(set) var stopped = 0

    func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
      let (stream, sink) = AsyncStream<WSEvent>.makeStream()
      lock.withLock { self.sink = sink; started.append(topics) }
      return stream
    }
    func replace(topics: [StreamTopic]) async { lock.withLock { replaced.append(topics) } }
    func stop() async { lock.withLock { stopped += 1; sink?.finish() } }
    var firstFrameSilenceMs: Double { get async { 60_000 } }
    var currentConnectionID: Int { get async { 1 } }
    func emit(_ event: WSEvent) { lock.withLock { _ = sink?.yield(event) } }
    var counts: (started: Int, replaced: Int, stopped: Int) {
      lock.withLock { (started.count, replaced.count, stopped) }
    }
  }

  final class Factory: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var made: [(String, FakeStream)] = []
    func make(_ venue: String) -> (any MarketStream)? {
      let s = FakeStream()
      lock.withLock { made.append((venue, s)) }
      return s
    }
    var streams: [(String, FakeStream)] { lock.withLock { made } }
  }

  actor Collected {
    var statuses: [FeedStatus] = []
    var tickers = 0
    func note(_ event: WSEvent) {
      switch event {
      case .status(let s): statuses.append(s)
      case .payload: tickers += 1
      default: break
      }
    }
  }

  @Test("同一家的品种共用一条连接；换订阅不重连，清空就收掉")
  func oneConnectionPerVenue() async throws {
    let factory = Factory()
    let merged = MergedMarketStream { factory.make($0) }
    let events = await merged.start(topics: [.ticker(symbol: "binance/usd_m/BTCUSDT"),
                                             .ticker(symbol: "ETHUSDT")])
    #expect(factory.streams.count == 1)
    #expect(factory.streams.first?.0 == "binance")
    #expect(factory.streams.first?.1.started.first?.count == 2)

    await merged.replace(topics: [.ticker(symbol: "binance/usd_m/SOLUSDT")])
    #expect(factory.streams.count == 1, "同一家换订阅不该再开一条")
    #expect(factory.streams.first?.1.counts.replaced == 1)

    let seen = Collected()
    let pump = Task { for await e in events { await seen.note(e) } }
    let fake = factory.streams[0].1
    fake.emit(.status(.live))
    fake.emit(.payload(.ticker(Ticker(symbol: "binance/usd_m/SOLUSDT", last: 1, changePercent: 0,
                                      high: 1, low: 1, quoteVolume: 1, timeMs: 1))))
    #expect(await waitUntil(2) { await seen.tickers == 1 })
    #expect(await seen.statuses == [.live])

    await merged.replace(topics: [])
    #expect(fake.counts.stopped == 1, "没有这家的品种了，连接就该收掉")
    await merged.stop()
    pump.cancel()
  }

  /// 换订阅 / 开连接都慢、而且「落定」记在完成那一刻的假连接：第一次 replace 慢、之后快，
  /// 专门造「先发的后到」。
  final class SlowStream: MarketStream, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private(set) var settled: [[StreamTopic]] = []
    private(set) var inFlight = 0
    func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
      try? await Task.sleep(nanoseconds: 80_000_000)
      lock.withLock { settled.append(topics) }
      return AsyncStream { _ in }
    }
    func replace(topics: [StreamTopic]) async {
      let n = lock.withLock { calls += 1; inFlight += 1; return calls }
      try? await Task.sleep(nanoseconds: n == 1 ? 150_000_000 : 5_000_000)
      lock.withLock { settled.append(topics); inFlight -= 1 }
    }
    func stop() async {}
    var firstFrameSilenceMs: Double { get async { 60_000 } }
    var currentConnectionID: Int { get async { 1 } }
    var last: [StreamTopic]? { lock.withLock { settled.last } }
    var busy: Bool { lock.withLock { inFlight > 0 } }
  }

  @Test("两次并发 replace：最终订阅等于最后一次（先发的慢请求后到也不能盖回去）")
  func concurrentReplaceEndsOnLast() async throws {
    let slow = SlowStream()
    let merged = MergedMarketStream { _ in slow }
    _ = await merged.start(topics: [.ticker(symbol: "BTCUSDT")])
    let a: [StreamTopic] = [.ticker(symbol: "ETHUSDT")]
    let b: [StreamTopic] = [.ticker(symbol: "SOLUSDT")]
    let first = Task { await merged.replace(topics: a) }
    #expect(await waitUntil(2) { slow.busy }, "第一次 replace 该已经在路上")
    let second = Task { await merged.replace(topics: b) }
    await first.value; await second.value
    #expect(slow.last == b)
    // 无序的 want 也一样：最后写下的那份说了算。
    merged.want(a); merged.want(b); merged.want(a)
    #expect(await waitUntil(2) { slow.last == a && !slow.busy })
    await merged.stop()
  }

  @Test("并发 replace 同时加一家新交易所：只开一条连接")
  func concurrentReplaceOpensOneConnectionPerVenue() async throws {
    let factory = Factory()
    let merged = MergedMarketStream { factory.make($0) }
    _ = await merged.start(topics: [.ticker(symbol: "BTCUSDT")])
    let both: [StreamTopic] = [.ticker(symbol: "BTCUSDT"), .ticker(symbol: "coinbase/spot/BTC-USD")]
    async let x: Void = merged.replace(topics: both)
    async let y: Void = merged.replace(topics: both)
    async let z: Void = merged.replace(topics: both)
    _ = await (x, y, z)
    #expect(factory.streams.filter { $0.0 == "coinbase" }.count == 1)
    #expect(factory.streams.filter { $0.0 == "binance" }.count == 1)
    await merged.stop()
  }
}
