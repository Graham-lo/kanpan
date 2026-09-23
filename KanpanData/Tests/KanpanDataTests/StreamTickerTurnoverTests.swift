import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

/// 推送帧不带成交额的线路（网关上的 OKX 替身）：推送一直新鲜，成交额也得按时从 REST 补。
///
/// 原来对表只在「5 秒没收到推送」时才问 REST 的 24h 行情，而替身的推送帧成交额是空的：
/// 推送一直在来，REST 就永远不问，顶栏「额」一直是「—」。
@Suite("推送帧不带成交额时定时补成交额")
struct StreamTickerTurnoverTests {
  private static let t0: Int64 = 1_700_000_040_000
  private static let step: Int64 = 60_000

  private final class Hits: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func add() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
  }

  private actor Seen {
    var tickers: [Ticker] = []
    func add(_ t: Ticker) { tickers.append(t) }
    var sawStreamFrame: Bool { tickers.contains { !$0.quoteVolume.isFinite } }
    var count: Int { tickers.count }
    /// 第 `mark` 帧之后又来过带成交额的那一帧。
    func turnover(after mark: Int) -> Bool { tickers.dropFirst(mark).contains { $0.quoteVolume == 4321 } }
  }

  private static func reply(_ url: URL, hits: Hits) -> HTTPReply {
    guard url.path.contains("klines") else {
      hits.add()
      return json(#"{"symbol":"BTCUSDT","lastPrice":"100","priceChangePercent":"0","highPrice":"200","lowPrice":"50","quoteVolume":"4321","openPrice":"100","closeTime":1000}"#)
    }
    let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let start = q.first { $0.name == "startTime" }?.value.flatMap(Int64.init)
    let rows = (0..<3).compactMap { i -> String? in
      let t = t0 - Int64(2 - i) * step
      if let start, t < start { return nil }
      return "[\(t),\"100.00\",\"200.00\",\"50.00\",\"100.00\",\"10.0\",\(t + step - 1),\"1000.0\",7,\"5.0\",\"500.0\",\"0\"]"
    }
    return json("[" + rows.joined(separator: ",") + "]")
  }

  /// 替身那种推送帧：没有 `p`，`q` 是空串。
  private static func streamFrame(at time: Int64) -> String {
    """
    {"stream":"btcusdt@ticker","data":{"e":"24hrTicker","E":\(time),"s":"BTCUSDT","o":"100",\
    "c":"101","P":"1.0","h":"200","l":"50","v":"12","q":"","C":\(time)}}
    """
  }

  @Test("推送新鲜但不带成交额：一分钟左右问一次 REST，把成交额交出去")
  func turnoverIsRefreshedWhileStreamIsFresh() async throws {
    let gate = Gate()
    // 推送每（虚拟）秒一帧，一直新鲜——「5 秒没推送才问 REST」那条永远不会触发。
    let pacer = ManualPacer()
    var steps: [ReplayStep] = [.hold(gate)]
    for i in 0..<120 { steps += [.frame(.text(Self.streamFrame(at: 5_000 + Int64(i) * 1000))), .silence(1000)] }
    let deck = ReplayDeck(steps + [.hang])
    let hits = Hits()
    let server = FakeServer { Self.reply($0, hits: hits) }
    let rest = BinanceREST(transport: FakeTransport(server))
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer))
    let feed = MarketFeed(rest: rest, ws: ws,
                          paths: Paths(root: FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)),
                          pacer: pacer, reconcileMs: 1000)
    await feed.setSnapshotEnabled(false)
    let seen = Seen()
    let stream = await feed.events()
    let pump = Task {
      for await e in stream { if case .ticker(let t) = e.event { await seen.add(t) } }
    }
    defer { pump.cancel() }
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(15) { await feed.currentSeries.lastTime == Self.t0 })
    #expect(await waitForSteadyState(feed))
    await gate.open()
    #expect(await waitUntil(15) { await seen.sawStreamFrame })
    // 先走十秒：首屏那一发校准不管怎么排，都已经落地了。
    for _ in 0..<10 { await pacer.advance(1000); try? await Task.sleep(nanoseconds: 5_000_000) }
    let mark = await seen.count
    let before = hits.value
    var found = false
    for _ in 0..<75 {
      await pacer.advance(1000)
      try? await Task.sleep(nanoseconds: 5_000_000)
      if await seen.turnover(after: mark) { found = true; break }
    }
    #expect(found, "推送帧不带成交额时，对表要专门补一次成交额")
    #expect(hits.value > before)
    await feed.stop()
    await pacer.drain()
  }
}
