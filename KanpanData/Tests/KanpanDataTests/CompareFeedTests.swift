import Foundation
import Testing
import KanpanCore
import KanpanNetworkTestSupport
@testable import KanpanData
import KanpanNetwork

@Suite("对比行情", .serialized) struct CompareFeedTests {
  let t0: Int64 = 1_700_000_040_000
  private actor History: HTTPTransport {
    var rows: [Bar]
    var calls = 0
    let gate: Gate?
    init(_ rows: [Bar], gate: Gate? = nil) { self.rows = rows; self.gate = gate }
    func replace(_ rows: [Bar]) { self.rows = rows }
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      calls += 1
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
      let end = query.first { $0.name == "endTime" }?.value.flatMap(Int64.init) ?? .max
      let limit = query.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 300
      let body = rows.filter { $0.openTime <= end }.suffix(limit).map { b in
        "[\(b.openTime),\"\(b.open)\",\"\(b.high)\",\"\(b.low)\",\"\(b.close)\",\"\(b.volume)\",\(b.openTime + 59999),\"0\",0,\"0\",\"0\",\"0\"]"
      }
      if let gate { await gate.wait() }
      return json("[" + body.joined(separator: ",") + "]")
    }
  }
  private func bars(_ count: Int) -> [Bar] {
    (0..<count).map { i in Bar(openTime: t0 + Int64(i) * 60_000, open: 10, high: 12, low: 9, close: 11, volume: 1) }
  }
  private func main(_ bars: [Bar], interval: Interval = .m1) -> BarSeries { BarSeries(symbol: "BTCUSDT", interval: interval, bars: bars) }
  private func feed(_ history: History, deck: ReplayDeck = ReplayDeck([.hang])) -> (CompareFeed, BinanceWS) {
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer()))
    return (CompareFeed(rest: BinanceREST(transport: history), ws: ws), ws)
  }

  @Test func alignsOnlyExactOpenTimesAndPreservesGaps() {
    let all = bars(4)
    let snapshot = CompareFeed.Snapshot(key: "binance/usd_m/ETHUSDT", series: BarSeries(symbol: "ETHUSDT", interval: .m1, bars: [all[0], all[2]]))
    let aligned = snapshot.aligned(to: main(all))
    #expect(aligned.open == [10, nil, 10, nil])
    #expect(aligned.close == [11, nil, 11, nil])
    #expect(snapshot.aligned(to: main(all, interval: .h1)).close.allSatisfy { $0 == nil })
  }

  @Test(.timeLimit(.minutes(1))) func historyPagesFollowMainRangeAndCapThreeKeys() async throws {
    let all = bars(650), history = History(bars(650))
    let (feed, ws) = feed(history)
    await feed.start(keys: ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT", "binance/usd_m/DOGEUSDT", "binance/usd_m/XRPUSDT"], main: main(Array(all.suffix(200))))
    #expect(await waitUntil(10) { let rows = await feed.current; return rows.count == 3 && rows.allSatisfy { $0.series.count == 200 } })
    #expect(await ws.currentStreams.count == 3)
    await feed.updateMain(main(all))
    #expect(await waitUntil(10) { await feed.current.allSatisfy { $0.series.count == 650 } })
    let previous = await history.calls
    await feed.updateMain(main(all))
    #expect(await history.calls == previous)
    #expect(await feed.current.first?.series.firstTime == t0)
    await feed.stop()
    #expect(await feed.current.isEmpty)
  }

  @Test(.timeLimit(.minutes(1))) func yearlyUsesMonthlyAggregation() async throws {
    let january = Aggregator.utcMs(year: 2026, month: 1, day: 1)
    let monthly = (1...9).map { month in Bar(openTime: Aggregator.utcMs(year: 2026, month: month, day: 1), open: Double(month), high: Double(month + 2), low: Double(month), close: Double(month + 1), volume: 1) }
    let (feed, _) = feed(History(monthly))
    let main = BarSeries(symbol: "BTCUSDT", interval: .y1, bars: [Bar(openTime: january, open: 1, high: 11, low: 1, close: 10, volume: 9)])
    await feed.start(keys: ["binance/usd_m/ETHUSDT"], main: main)
    #expect(await waitUntil(10) { await feed.current.first?.series.count == 1 })
    let year = try #require(await feed.current.first?.series)
    #expect(year.interval == .y1 && year.open == [1] && year.close == [10] && year.volume == [9])
    await feed.stop()
  }

  @Test(.timeLimit(.minutes(1))) func cancelledHistoryCannotReappearAfterStop() async {
    let gate = Gate()
    // 同一闸门模拟取消后仍然回包的真实 HTTP。
    let held = History(bars(5), gate: gate)
    let (feed, _) = feed(held)
    await feed.start(keys: ["binance/usd_m/ETHUSDT"], main: main(bars(5)))
    #expect(await waitUntil(5) { await gate.waiting > 0 })
    await feed.stop()
    await gate.open()
    // 重新开始的是另一品种；迟到的旧结果不能污染它。
    await feed.start(keys: ["binance/usd_m/SOLUSDT"], main: main(bars(5)))
    #expect(await waitUntil(5) { await feed.current.first?.key == "binance/usd_m/SOLUSDT" })
    #expect(await feed.current.count == 1)
    await feed.stop()
  }

  @Test(.timeLimit(.minutes(1))) func websocketTailWinsAgainstSlowRestAndClosedBarStaysSealed() async throws {
    let restGate = Gate(), streamGate = Gate(), afterClosed = Gate()
    let history = History(bars(5), gate: restGate), time = t0 + 240_000
    func frame(_ close: Double, sequence: Int, closed: Bool = false) -> ReplayStep {
      .frame(.text("""
      {"stream":"ethusdt@kline_1m","data":{"e":"kline","E":\(time + Int64(sequence)),"s":"ETHUSDT",      "k":{"t":\(time),"T":\(time + 59999),"s":"ETHUSDT","i":"1m","f":1,"L":\(sequence),      "o":"10","h":"100","l":"9","c":"\(close)","v":"20","n":7,"x":\(closed),"q":"200","V":"1","Q":"10","B":"0"}}}
      """))
    }
    let deck = ReplayDeck([.hold(streamGate), frame(20, sequence: 1), frame(21, sequence: 2, closed: true), .hold(afterClosed), frame(22, sequence: 3), .hang])
    let (feed, _) = feed(history, deck: deck)
    await feed.start(keys: ["binance/usd_m/ETHUSDT"], main: main(bars(5)))
    #expect(await waitUntil(5) { await restGate.waiting > 0 })
    await streamGate.open()
    #expect(await waitUntil(5) { await feed.current.first?.series.close.last == 21 })
    await restGate.open(); await afterClosed.open()
    #expect(await waitUntil(5) { await feed.current.first?.series.count == 5 })
    let values = try #require(await feed.current.first?.series)
    #expect(values.close.last == 21)
    #expect(values.open.first == 10)
    await feed.stop()
  }

  @Test(.timeLimit(.minutes(1))) func reconnectRefreshesTheSameMainTailWithoutWaitingForANewBar() async {
    let reconnect = Gate(), history = History(bars(5))
    let deck = ReplayDeck([.hold(reconnect), .drop("fixture reconnect"), .hang])
    let (feed, _) = feed(history, deck: deck)
    await feed.start(keys: ["binance/usd_m/ETHUSDT"], main: main(bars(5)))
    #expect(await waitUntil(10) { await feed.current.first?.series.count == 5 })
    var newer = bars(5); newer[4].close = 12
    await history.replace(newer)
    await reconnect.open()
    #expect(await waitUntil(15) { await feed.current.first?.series.close.last == 12 })
    #expect(await history.calls >= 2)
    #expect(await feed.current.first?.series.count == 5)
    await feed.stop()
  }

  @Test func anUnknownVenueNeverBorrowsCurrentSourceData() async {
    let history = History(bars(5))
    let (feed, ws) = feed(history)
    await feed.start(keys: ["future/spot/ETHUSDT"], main: main(bars(5)))
    #expect(await history.calls == 0)
    #expect(await ws.currentStreams.isEmpty)
    #expect(await feed.current.isEmpty)
    await feed.stop()
  }
}

extension CompareFeedTests {
  /// 审查 P2-4：主图更新走同步投递的信箱，不再各起一个 Task。
  @Test("start 之前投递的主图不丢：start 一完就按它补齐范围", .timeLimit(.minutes(1)))
  func mainPostedBeforeStartIsNotLost() async {
    let all = bars(650)
    let (feed, _) = feed(History(all))
    feed.post(main: main(all))
    await feed.start(keys: ["binance/usd_m/ETHUSDT"], main: main(Array(all.suffix(200))))
    #expect(await waitUntil(10) { await feed.target?.lowerBound == t0 })
    #expect(await waitUntil(10) { await feed.current.first?.series.count == 650 })
    await feed.stop()
  }

  @Test("连着投递几份主图：最后一份说了算", .timeLimit(.minutes(1)))
  func lastPostedMainWins() async {
    let all = bars(650)
    let (feed, _) = feed(History(all))
    await feed.start(keys: ["binance/usd_m/ETHUSDT"], main: main(Array(all.suffix(200))))
    let last = main(Array(all.suffix(300)))
    for n in stride(from: 650, to: 300, by: -50) { feed.post(main: main(Array(all.suffix(n)))) }
    feed.post(main: last)
    #expect(await waitUntil(10) { await feed.target == last.firstTime...last.lastTime })
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(await feed.target == last.firstTime...last.lastTime, "之前投的旧主图不许后到盖回去")
    await feed.stop()
  }
}
