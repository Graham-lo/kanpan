import Foundation
import Testing
@testable import KanpanData
import KanpanCore

/// 合帧闸门：同一根上的 kline 报文攒着发，开新根立刻发。
///
/// 背景：`applyKline` 原来一律 `emitTick(force: true)`，等于 WS 上最密的那条流
/// 完全绕开了 80ms 闸门，而逐笔（`foldTick`）早就是合帧的——两条路推的是同一根
/// K 线，没道理一条限速一条不限。改完之后同一根上的更新走闸门，**时间戳一变**
/// （开了新的一根）立刻放行，因为那是结构性变化，晚 80ms 收线肉眼就是「顿一下」。
@Suite("合帧闸门：kline 也限速，开新根不等")
struct TickCoalesceTests {

  private static let t0: Int64 = 1_700_000_040_000      // 对齐到分钟
  private static let step: Int64 = 60_000

  /// 一条 combined stream 的 kline 报文。
  private static func frame(open t: Int64, close c: Double, at eventTime: Int64) -> String {
    let px = String(format: "%.2f", c)
    return """
    {"stream":"btcusdt@kline_1m","data":{"e":"kline","E":\(eventTime),"s":"BTCUSDT",\
    "k":{"t":\(t),"T":\(t + step - 1),"s":"BTCUSDT","i":"1m","f":1,"L":\(eventTime),\
    "o":"100.00","c":"\(px)","h":"200.00","l":"50.00","v":"10.0","n":7,"x":false,\
    "q":"1000.0","V":"5.0","Q":"500.0","B":"0"}}}
    """
  }

  /// REST：给 3 根打底，末根正好是 `t0`，这样第一条报文是「更新末根」。
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

  /// 每一次 `.lastBar` 的（末根 openTime, 收到的时刻）。
  private actor Ticks {
    private(set) var items: [(t: Int64, at: Date)] = []
    func add(_ t: Int64) { items.append((t, Date())) }
    func count(of t: Int64) -> Int { items.filter { $0.t == t }.count }
    func first(of t: Int64) -> Date? { items.first { $0.t == t }?.at }
    var firstAny: Date? { items.first?.at }
    var total: Int { items.count }
  }

  private func run(_ steps: [ReplayStep]) async -> (MarketFeed, Ticks, Task<Void, Never>) {
    let deck = ReplayDeck(steps)
    let server = FakeServer { Self.seedReply($0) }
    let rest = BinanceREST(transport: FakeTransport(server))
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer()))
    let feed = MarketFeed(rest: rest, ws: ws,
                          paths: Paths(root: FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)),
                          reconcileMs: 0)
    await feed.setSnapshotEnabled(false)
    let ticks = Ticks()
    let stream = await feed.events()
    let pump = Task {
      for await e in stream {
        if case .lastBar(let b) = e.event { await ticks.add(b.openTime) }
      }
    }
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    return (feed, ticks, pump)
  }

  @Test("同一根上连着来 10 帧，只合成 ≤2 次末根事件")
  func tenFramesOnOneCandleCoalesce() async throws {
    // 先静默一下，让 REST 那 3 根先落地；不然报文比历史还早到，会被合成器丢掉。
    var steps: [ReplayStep] = [.silence(300)]
    steps += (1...10).map { i in
      .frame(.text(Self.frame(open: Self.t0, close: 100 + Double(i), at: 1_700_000_090_000 + Int64(i))))
    }
    steps.append(.hang)

    let (feed, ticks, pump) = await run(steps)
    defer { pump.cancel() }

    // 10 帧全部落进序列（末根收盘价 = 110）。
    #expect(await waitUntil(5) { await feed.currentSeries.close.last == 110 })
    // 再等满一个拍子，把攒着的那一次也收口。
    try? await Task.sleep(for: .milliseconds(300))

    let n = await ticks.count(of: Self.t0)
    #expect(n >= 1, "闸门不能把实时推送整个掐掉")
    #expect(n <= 2, "同一根上的 10 帧最多合成 2 次事件（首帧放行 + 拍子末尾收口），实际 \(n)")
    await feed.stop()
  }

  @Test("开新根的那一帧不等拍子，立刻发")
  func newCandleEmitsImmediately() async throws {
    let t1 = Self.t0 + Self.step
    var steps: [ReplayStep] = [.silence(300)]
    // 同一根上先来 10 帧，把闸门关上（刚发过一次，拍子还没走完）。
    steps += (1...10).map { i in
      .frame(.text(Self.frame(open: Self.t0, close: 100 + Double(i), at: 1_700_000_090_000 + Int64(i))))
    }
    // 紧接着就是新的一根：它必须立刻出去，而不是等到拍子末尾。
    steps.append(.frame(.text(Self.frame(open: t1, close: 123, at: 1_700_000_100_000))))
    steps.append(.hang)

    let (feed, ticks, pump) = await run(steps)
    defer { pump.cancel() }

    #expect(await waitUntil(5) { await feed.currentSeries.lastTime == t1 })
    let firstOfNew = await ticks.first(of: t1)
    let firstAny = await ticks.firstAny
    let start = try #require(firstAny)
    let arrived = try #require(firstOfNew, "开新根必须推一次末根事件")
    // 闸门是 80ms。这一帧要是被闸门收着，只能等到拍子末尾才出去。
    let gap = arrived.timeIntervalSince(start)
    #expect(gap < 0.06, "开新根等了 \(Int(gap * 1000))ms，说明被闸门收住了")
    await feed.stop()
  }
}
