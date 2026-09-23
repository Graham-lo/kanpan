import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
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
    // 补缺（`contiguousTail`）问的是「`startTime` 这根之后还有什么」：必须按它筛，
    // 否则返回的第一根比游标还早，`contiguousTail` 判成「行情翻页没有推进」直接抛错，
    // feed 把这段记成欠着的缺口，再没人来补——稳态就永远等不到了。
    let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let start = q.first { $0.name == "startTime" }?.value.flatMap(Int64.init)
    let rows = (0..<3).compactMap { i -> String? in
      let t = t0 - Int64(2 - i) * step
      if let start, t < start { return nil }
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

  /// 起一套 feed，并且**在启动期那几件异步的事都落地之后**才放报文进来。
  ///
  /// 原来是在报文前面垫一段 300ms 静默赌机器够快：REST 那 3 根要是回得晚，报文就比
  /// 历史还早到，被合成器当过期帧丢掉，整条用例随机翻红。`.hold` 等的是事件而不是
  /// 时间，饿不死。
  ///
  /// 光等打底那 3 根还不够：`.connected` 排在首屏之后被处理时，feed 会为「快照到连上」
  /// 那一段派一发补缺，而补缺期间的 WS 帧只排队、落地时统一走 `.series`，一条
  /// `.lastBar` 都不发——机器忙的时候这条用例就会读到 0 次末根事件。所以先等一次
  /// `.status(.live)`（说明 `.connected` 已经处理过了），再等 `waitForSteadyState`。
  private func run(_ steps: [ReplayStep]) async -> (MarketFeed, Ticks, ManualPacer, Task<Void, Never>) {
    let gate = Gate()
    let deck = ReplayDeck([.hold(gate)] + steps)
    let server = FakeServer { Self.seedReply($0) }
    let rest = BinanceREST(transport: FakeTransport(server))
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer()))
    // 闸门那一拍挂在注进去的这把钟上：不拨针它就永远不到点。于是「攒着」和
    // 「放行」是两个确定的状态，不再靠墙上时钟去量 80 毫秒——机器被占满时那点
    // 余量根本量不准（量到 70ms 也不代表闸门错了）。
    let pacer = ManualPacer()
    let feed = MarketFeed(rest: rest, ws: ws,
                          paths: Paths(root: FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)),
                          pacer: pacer,
                          reconcileMs: 0)
    await feed.setSnapshotEnabled(false)
    let ticks = Ticks()
    let live = Counter()
    let stream = await feed.events()
    let pump = Task { [live] in
      for await e in stream {
        if case .lastBar(let b) = e.event { await ticks.add(b.openTime) }
        if case .status(let st) = e.event, st == .live { live.setTo(1) }
      }
    }
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    // 打底的 3 根到了合成器手上、连接已经报 live、补缺也不在途了，才开闸放报文。
    #expect(await waitUntil(15) { await feed.currentSeries.lastTime == Self.t0 })
    #expect(await waitUntil(15) { live.value == 1 })
    #expect(await waitForSteadyState(feed))
    await gate.open()
    return (feed, ticks, pacer, pump)
  }

  @Test("同一根上连着来 10 帧，只合成 ≤2 次末根事件")
  func tenFramesOnOneCandleCoalesce() async throws {
    // REST 那 3 根先落地（`run` 里的闸门管这件事），再放这 10 帧进来。
    var steps: [ReplayStep] = (1...10).map { i in
      .frame(.text(Self.frame(open: Self.t0, close: 100 + Double(i), at: 1_700_000_090_000 + Int64(i))))
    }
    steps.append(.hang)

    let (feed, ticks, pacer, pump) = await run(steps)
    defer { pump.cancel() }

    // 10 帧全部落进序列（末根收盘价 = 110）。
    #expect(await waitUntil(15) { await feed.currentSeries.close.last == 110 })
    // 第一帧不等拍子就出去（上一次抛出在很久以前），剩下 9 帧攒在闸门里。
    #expect(await waitUntil(15) { await ticks.count(of: Self.t0) == 1 },
            "闸门不能把实时推送整个掐掉，第一帧必须立刻到消费端")
    // 那一拍确实排在钟上了（在途最多一发）。
    #expect(await waitUntil(15) { await pacer.sleeping == 1 })
    // 拨过拍子末尾：攒着的 9 帧收口成一次事件。
    await pacer.advance(200)
    #expect(await waitUntil(15) { await ticks.count(of: Self.t0) == 2 })
    // 钟上没人再等了，也就不会有第三发——「≤2 次」是数出来的，不是睡出来的。
    #expect(await pacer.sleeping == 0)

    let n = await ticks.count(of: Self.t0)
    #expect(n <= 2, "同一根上的 10 帧最多合成 2 次事件（首帧放行 + 拍子末尾收口），实际 \(n)")
    await feed.stop()
    await pacer.drain()
  }

  @Test("开新根的那一帧不等拍子，立刻发")
  func newCandleEmitsImmediately() async throws {
    let t1 = Self.t0 + Self.step
    // 同一根上先来 10 帧，把闸门关上（刚发过一次，拍子还没走完）。
    var steps: [ReplayStep] = (1...10).map { i in
      .frame(.text(Self.frame(open: Self.t0, close: 100 + Double(i), at: 1_700_000_090_000 + Int64(i))))
    }
    // 紧接着就是新的一根：它必须立刻出去，而不是等到拍子末尾。
    steps.append(.frame(.text(Self.frame(open: t1, close: 123, at: 1_700_000_100_000))))
    steps.append(.hang)

    let (feed, ticks, pacer, pump) = await run(steps)
    defer { pump.cancel() }

    #expect(await waitUntil(15) { await feed.currentSeries.lastTime == t1 })
    // 关键：这条用例**一次都不拨针**。闸门那一拍只能靠拨针到点，所以新根的末根
    // 事件能到消费端，就证明它没进闸门——不必再去量墙上时钟差了多少毫秒。
    #expect(await waitUntil(15) { await ticks.first(of: t1) != nil }, "开新根必须推一次末根事件")
    #expect(await ticks.firstAny != nil)
    // 同一根上那 9 帧确实被收着（拍子排过），不然这条用例证明不了什么。
    #expect(await pacer.sleepLog().isEmpty == false, "同一根上的帧就该进闸门")
    await feed.stop()
    await pacer.drain()
  }
}
