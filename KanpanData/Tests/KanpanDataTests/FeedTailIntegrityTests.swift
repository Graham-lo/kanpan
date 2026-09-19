import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

/// 末根的两条正确性：每一根的定盘值都要到得了消费端；在路上的 REST 回包不许
/// 盖掉它出发之后才到的实时末根。
///
/// 这两件事都只在「合成器内部对、消费端拿到的不对」这个夹缝里出问题，所以用例
/// 一律镜像消费端的语义（`MarketModel.apply` 的 `.lastBar` 走 `upsert`），而不是
/// 去问 feed 自己手上那条序列——后者一直是对的。
@Suite("末根的定盘与基线")
struct FeedTailIntegrityTests {

  private static let t0: Int64 = 1_700_000_040_000      // 对齐到分钟
  private static let step: Int64 = 60_000

  /// 消费端的镜子：`.series` 整段换，`.lastBar` upsert，和 `MarketModel.apply` 一样。
  private actor Consumer {
    private var series: BarSeries?
    func take(_ e: FeedEvent) {
      switch e {
      case .series(let s): series = s
      case .lastBar(let b): _ = series?.upsert(b)
      default: break
      }
    }
    func close(at t: Int64) -> Double? {
      guard let s = series else { return nil }
      guard let i = (0..<s.count).first(where: { s.time(at: $0) == t }) else { return nil }
      return s.close[i]
    }
  }

  private static func frame(open t: Int64, close c: Double, at eventTime: Int64, closed: Bool = false) -> String {
    let px = String(format: "%.2f", c)
    // 高低要罩得住收盘价，否则 `isValidMarketBar` 直接把这一帧判废。
    let hi = String(format: "%.2f", max(200, c))
    let lo = String(format: "%.2f", min(50, c))
    return """
    {"stream":"btcusdt@kline_1m","data":{"e":"kline","E":\(eventTime),"s":"BTCUSDT",\
    "k":{"t":\(t),"T":\(t + step - 1),"s":"BTCUSDT","i":"1m","f":1,"L":\(eventTime),\
    "o":"100.00","c":"\(px)","h":"\(hi)","l":"\(lo)","v":"10.0","n":7,"x":\(closed),\
    "q":"1000.0","V":"5.0","Q":"500.0","B":"0"}}}
    """
  }

  /// REST：3 根打底，末根正好是 `t0`，第一条报文就是「更新末根」。
  private static func seedReply(_ url: URL) -> HTTPReply {
    guard url.path.contains("klines") else {
      return json(#"{"symbol":"BTCUSDT","lastPrice":"100","priceChangePercent":"0","highPrice":"200","lowPrice":"50","quoteVolume":"1","closeTime":3000}"#)
    }
    let rows = (0..<3).map { i -> String in
      let t = t0 - Int64(2 - i) * step
      return "[\(t),\"100.00\",\"200.00\",\"50.00\",\"100.00\",\"10.0\",\(t + step - 1),\"1000.0\",7,\"5.0\",\"500.0\",\"0\"]"
    }
    return json("[" + rows.joined(separator: ",") + "]")
  }

  private func run(_ steps: [ReplayStep]) async -> (MarketFeed, Consumer, Task<Void, Never>) {
    let deck = ReplayDeck(steps)
    let rest = BinanceREST(transport: FakeTransport(FakeServer { Self.seedReply($0) }))
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer()))
    let feed = MarketFeed(rest: rest, ws: ws,
                          paths: Paths(root: FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)),
                          reconcileMs: 0, initialLimit: 3)
    await feed.setSnapshotEnabled(false)
    let consumer = Consumer()
    let stream = await feed.events()
    let pump = Task { for await e in stream { await consumer.take(e.event) } }
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    return (feed, consumer, pump)
  }

  // ------------------------------------------------------------------ A-02

  @Test("换桶那一刻，上一根压在合帧闸门里的最终值必须补发给消费端")
  func lastValueOfTheSealedBarReachesTheConsumer() async throws {
    let t1 = Self.t0 + Self.step
    var steps: [ReplayStep] = [.silence(300)]
    // 同一根上连着 9 帧：第一帧放行，剩下的被 80ms 闸门攒着。
    steps += (1...9).map { i in
      .frame(.text(Self.frame(open: Self.t0, close: 100 + Double(i), at: 1_700_000_090_000 + Int64(i))))
    }
    // 紧接着换桶。老实现在这里把那发 flush 取消掉，只抛新根，于是消费端手上的
    // 上一根就永远停在 101。
    steps.append(.frame(.text(Self.frame(open: t1, close: 123, at: 1_700_000_100_000))))
    steps.append(.hang)

    let (feed, consumer, pump) = await run(steps)
    defer { pump.cancel() }
    #expect(await waitUntil(5) { await feed.currentSeries.lastTime == t1 })
    #expect(await waitUntil(5) { await consumer.close(at: t1) == 123 })
    let sealed = await consumer.close(at: Self.t0)
    #expect(sealed == 109, "上一根在消费端停在 \(sealed.map { "\($0)" } ?? "空")，合成器里是 109")
    await feed.stop()
  }

  @Test("交易所宣布收线的那一帧被闸门攒着，紧接着开新根就永远丢了")
  func sealingFrameIsNotSwallowedByTheCoalescer() async throws {
    let t1 = Self.t0 + Self.step
    var steps: [ReplayStep] = [.silence(300)]
    steps += (1...9).map { i in
      .frame(.text(Self.frame(open: Self.t0, close: 100 + Double(i), at: 1_700_000_090_000 + Int64(i))))
    }
    // x=true：这一根只会来这么一条，被闸门攒掉就再也没有第二条把它带上去。
    steps.append(.frame(.text(Self.frame(open: Self.t0, close: 110, at: 1_700_000_099_000, closed: true))))
    // 紧跟着开新的一根：老实现在这里把攒着的那发 flush 取消掉，定盘值就此蒸发。
    steps.append(.frame(.text(Self.frame(open: t1, close: 123, at: 1_700_000_100_000))))
    steps.append(.hang)

    let (feed, consumer, pump) = await run(steps)
    defer { pump.cancel() }
    #expect(await waitUntil(5) { await feed.currentSeries.lastTime == t1 })
    #expect(await waitUntil(5) { await consumer.close(at: t1) == 123 })
    let sealed = await consumer.close(at: Self.t0)
    #expect(sealed == 110, "定盘帧在消费端是 \(sealed.map { "\($0)" } ?? "空")，交易所报的是 110")
    await feed.stop()
  }

  // ------------------------------------------------------------------ A-03

  @Test("补洞请求在路上时到的实时末根，不能被它的陈旧回包盖回去")
  func staleGapReplyCannotOverwriteTheLiveTail() async throws {
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let live = now / Self.step * Self.step                 // 还在走的那根
    let bars = [live - 2 * Self.step, live - Self.step, live]
    let transport = HeldKlines(bars: bars, stale: 100)
    let rest = BinanceREST(transport: transport)
    // 报文得晚于两发 REST 出发：静默一段再推 999。
    let deck = ReplayDeck([.silence(600),
                           .frame(.text(Self.frame(open: live, close: 999, at: now + 1))),
                           .hang])
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer()))
    let feed = MarketFeed(rest: rest, ws: ws,
                          paths: Paths(root: FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)),
                          reconcileMs: 0, includeTicker: false, initialLimit: 3)
    await feed.setSnapshotEnabled(false)
    let stream = await feed.events()
    let seen = SeriesCount()
    let pump = Task {
      for await e in stream { if case .series = e.event { await seen.bump() } }
    }
    defer { pump.cancel() }

    // ① 先跑一轮把内存缓存填上，下一轮才会带着 `since > 0` 去补洞。
    await feed.start(symbol: "BTCUSDT", interval: .m1, selection: UUID())
    #expect(await waitUntil(5) { await feed.currentSeries.count == 3 })

    // ② 再进一次：缓存打底 → 主历史与补洞两发同时在飞，两发都扣住。
    await transport.hold()
    await seen.reset()
    await feed.switchTo(symbol: "BTCUSDT", interval: .m1, selection: UUID())
    #expect(await waitUntil(5) { await transport.held == 2 }, "主历史和补洞应当同时在路上")

    // ③ 两发都在飞的时候，WS 把末根推到 999。
    #expect(await waitUntil(5) { await feed.currentSeries.close.last == 999 })

    // ④ 先放主历史，再放补洞，两发回的都是出发前那一刻的陈旧快照（close=100）。
    await transport.release(gap: false)
    await transport.release(gap: true)
    // 缓存打底发一次 `.series`，主历史合完一次，补洞合完一次。
    #expect(await waitUntil(5) { await seen.value >= 3 })
    #expect(await feed.currentSeries.close.last == 999, "陈旧的补洞回包把活着的末根盖回去了")
    await feed.stop()
  }
}

private actor SeriesCount {
  private(set) var value = 0
  func bump() { value += 1 }
  func reset() { value = 0 }
}

/// 两条 klines 请求分开扣住：不带 `startTime` 的是主历史，带的是补洞。
/// 放行时回的是「请求出发那一刻」的陈旧快照——真实世界里一次往返几百毫秒，
/// 回来时 WS 早把末根推完了。
private actor HeldKlines: HTTPTransport {
  private let bars: [Int64]
  private let stale: Double
  private var holding = false
  private var parked: [(gap: Bool, cont: CheckedContinuation<HTTPReply, Never>)] = []
  var held: Int { parked.count }

  init(bars: [Int64], stale: Double) { self.bars = bars; self.stale = stale }

  func hold() { holding = true }

  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    guard url.path.contains("klines") else { return json("[]") }
    let gap = url.query?.contains("startTime") == true
    guard holding else { return reply(gap: gap) }
    return await withCheckedContinuation { parked.append((gap, $0)) }
  }

  func release(gap: Bool) {
    guard let i = parked.firstIndex(where: { $0.gap == gap }) else { return }
    let one = parked.remove(at: i)
    one.cont.resume(returning: reply(gap: gap))
  }

  private func reply(gap: Bool) -> HTTPReply {
    // 补洞那一发从末根拉起（`contiguousTail` 要求回包不早于 `from`）。
    let rows = (gap ? [bars[bars.count - 1]] : bars).map { t -> String in
      let px = String(format: "%.2f", stale)
      return "[\(t),\"\(px)\",\"\(px)\",\"\(px)\",\"\(px)\",\"10.0\",\(t + 59_999),\"1000.0\",7,\"5.0\",\"500.0\",\"0\"]"
    }
    return json("[" + rows.joined(separator: ",") + "]")
  }
}
