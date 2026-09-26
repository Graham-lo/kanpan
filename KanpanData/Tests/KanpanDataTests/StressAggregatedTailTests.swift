import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 压测（2026-09-26 行情与网络层）：聚出来的周期（币安 1y ← 1M；Coinbase 3m / 12h / 1w / 1M / 1y）
/// 在推送猛灌时的开销。
///
/// 原来每收一条源周期报文都把整条源序列重聚一遍，再往主线程抛一整条 `.series`
/// 外加 `.historyError(nil)`，完全绕开 80ms 合帧闸门：推送多密，整图重算就有多密。
/// 判据是结构性的——整条 `.series` 的次数不随报文条数增长；只重算末桶的结果必须和
/// 整段重聚逐根一致（跨月、跨年各走一次）。
@Suite("压测 · 聚合周期推送猛灌")
struct StressAggregatedTailTests {

  private static func month(_ y: Int, _ m: Int) -> Int64 { Aggregator.utcMs(year: y, month: m, day: 1) }
  private static func nextMonth(_ y: Int, _ m: Int) -> Int64 { m == 12 ? month(y + 1, 1) : month(y, m + 1) }

  /// 2021-01 … 2023-11 的月线，全是 1。
  private static func monthlyRows() -> HTTPReply {
    var rows: [String] = []
    for y in 2021...2023 {
      for m in 1...12 where !(y == 2023 && m > 11) {
        let t = month(y, m), end = nextMonth(y, m) - 1
        rows.append("[\(t),\"1\",\"1\",\"1\",\"1\",\"1\",\(end),\"1\",1,\"1\",\"1\",\"0\"]")
      }
    }
    return json("[" + rows.joined(separator: ",") + "]")
  }

  private static func frame(y: Int, m: Int, close: Double, high: Double, volume: Double, eventTime: Int64) -> ReplayStep {
    let t = month(y, m), end = nextMonth(y, m) - 1
    return .frame(.text("""
    {"stream":"btcusdt@kline_1M","data":{"e":"kline","E":\(eventTime),"s":"BTCUSDT",\
    "k":{"t":\(t),"T":\(end),"s":"BTCUSDT","i":"1M","f":1,"L":\(eventTime),\
    "o":"1","c":"\(close)","h":"\(high)","l":"1","v":"\(volume)","n":1,"x":false,"q":"1","V":"0.5","Q":"1","B":"0"}}}
    """))
  }

  @Test("1y：1M 推送连灌 1500 条再跨月、跨年——整条序列不再每条抛一次，末桶和整段重聚一致",
        .timeLimit(.minutes(1)))
  func yearlyTailFollowsMonthlyFlood() async throws {
    let flood = 1500
    let gate = Gate()
    var steps: [ReplayStep] = [.hold(gate)]
    var e: Int64 = 1_700_000_000_000
    var lastClose = 0.0
    for i in 0..<flood {
      e += 1
      lastClose = 100 + Double(i) * 0.01
      steps.append(Self.frame(y: 2023, m: 11, close: lastClose, high: lastClose, volume: Double(i + 1), eventTime: e))
    }
    e += 1; steps.append(Self.frame(y: 2023, m: 12, close: 90, high: 120, volume: 3, eventTime: e))
    e += 1; steps.append(Self.frame(y: 2024, m: 1, close: 95, high: 95, volume: 2, eventTime: e))
    steps.append(.hang)
    let deck = ReplayDeck(steps)

    let server = FakeServer { url in
      guard url.path.contains("klines") else {
        return json(#"{"symbol":"BTCUSDT","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
      }
      return Self.monthlyRows()
    }
    let feed = MarketFeed(rest: BinanceREST(transport: FakeTransport(server)),
                          ws: BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer())),
                          paths: Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                          reconcileMs: 0)
    await feed.setSnapshotEnabled(false)
    let wholeSeries = Counter(), lastBars = Counter(), counting = Counter()
    let live = Counter()
    let events = await feed.events()
    let collector = Task { [wholeSeries, lastBars, counting, live] in
      for await update in events {
        switch update.event {
        case .series: if counting.value == 1 { wholeSeries.bump() }
        case .lastBar: if counting.value == 1 { lastBars.bump() }
        case .status(.live): live.setTo(1)
        default: break
        }
      }
    }
    defer { collector.cancel() }
    await feed.start(symbol: "BTCUSDT", interval: .y1)
    #expect(await waitUntil(10) { await feed.currentSeries.count == 3 })
    #expect(await waitUntil(10) { live.value == 1 })
    #expect(await waitForSteadyState(feed, timeout: 10))

    counting.setTo(1)
    await gate.open()
    let done = await waitUntil(10) {
      let s = await feed.currentSeries
      return s.count == 4 && s.lastTime == Self.month(2024, 1) && s.close[s.count - 1] == 95
    }
    #expect(done, "年线没跟上推送")
    // 等收尾那一拍合帧也抛完，再数。
    #expect(await waitUntil(5) { (await feed.isBackfillingForTests) == false })

    // 结构性：整条序列的次数和报文条数无关（原来 = 1502 次）。
    #expect(wholeSeries.value <= 2, "推送期间整条 .series 抛了 \(wholeSeries.value) 次（报文 \(flood + 2) 条）")
    #expect(lastBars.value >= 2, "跨年开新桶必须立刻抛末根，只见 \(lastBars.value) 次")

    // 正确性：只重算末桶 == 整段重聚。
    let src = try #require(await feed.sourceSeriesForTests)
    let expected = Aggregator.bucket(series: src, into: .y1)
    let got = await feed.currentSeries
    #expect(got.count == expected.count)
    for i in 0..<min(got.count, expected.count) {
      #expect(got.bar(at: i) == expected.bar(at: i), "第 \(i) 桶：\(got.bar(at: i)) ≠ \(expected.bar(at: i))")
    }
    let y2023 = got.bar(at: 2)
    #expect(y2023.high == 120 && y2023.close == 90)
    await feed.stop()
  }
}
