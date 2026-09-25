import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// WS 链路加固里落在 KanpanData 这一层的几条（审查 F1 / F4 / 回前台）。
@Suite("行情链路加固（数据层）")
struct FeedChainHardeningTests {

  private static let step: Int64 = 60_000
  private static let t0: Int64 = 1_700_000_040_000   // 对齐到分钟

  // ------------------------------------------------------------------ F4

  private func composer(count: Int = 3) -> FeedComposer {
    FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1,
                                   bars: makeBars(t0: Self.t0, step: Self.step, count: count)))
  }

  @Test("逐笔改了末根也要记一次推送版本号；没改动就不记")
  func tickBumpsRevision() {
    var c = composer()
    let last = c.series.lastTime
    let r0 = c.wsRevision
    #expect(c.applyTick(price: 123, qty: 1, timeMs: last + 1_000) == .updated)
    let r1 = c.wsRevision
    #expect(r1 == r0 &+ 1, "折进末根没有记版本号：慢一拍的 REST 会把它盖回去")
    #expect(c.applyTick(price: 124, qty: 1, timeMs: last + Self.step) == .appended)
    let r2 = c.wsRevision
    #expect(r2 == r1 &+ 1)
    // 时间倒退的逐笔被忽略：版本号不动。
    #expect(c.applyTick(price: 125, qty: 1, timeMs: last) == .ignored)
    #expect(c.wsRevision == r2)
  }

  @Test("补缺期间的逐笔排队不丢；补完按到达顺序重放，落在 REST 末根里的只折价不加量")
  func ticksQueuedDuringBackfill() {
    var c = composer()
    let last = c.series.lastTime
    c.beginBackfill()
    #expect(c.applyTick(price: 150, qty: 2, timeMs: last + Self.step + 1_000) == .ignored)
    #expect(c.applyTick(price: 160, qty: 3, timeMs: last + 2 * Self.step + 1_000) == .ignored)
    #expect(c.queuedTicks == 2)
    #expect(c.series.lastTime == last, "补缺期间不该改序列")
    // REST 回来：补到 last+step（含排队期间第一笔的量），第二笔落在它之后的新桶里。
    let rest = [Bar(openTime: last + Self.step, open: 140, high: 155, low: 139, close: 149, volume: 10)]
    let revision = c.wsRevision
    _ = c.endBackfill(with: rest)
    #expect(c.queuedTicks == 0)
    #expect(c.series.lastTime == last + 2 * Self.step)
    let n = c.series.count
    // REST 末根：价格跟逐笔、量留 REST 的（不重复计量）。
    #expect(c.series.close[n - 2] == 150)
    #expect(c.series.volume[n - 2] == 10)
    // 之后新开的那根：连量一起折。
    #expect(c.series.close[n - 1] == 160)
    #expect(c.series.volume[n - 1] == 3)
    #expect(c.wsRevision != revision)
  }

  // ------------------------------------------------------------------ F1：快照打底的上限

  @Test("快照离现在超过提供者的补缺上限：不拿来打底")
  func seedRespectsTailCap() {
    let s = makeSeries("BTCUSDT", .m1, count: 300)
    let now = Double(s.lastTime)
    #expect(MarketFeed.seedUsable(s, sourceStepMs: 60_000, nowMs: now + 1_000 * 60_000, maxTailBars: 1400))
    // 1400 根的上限（Coinbase）：欠 1399 根 + 2 根余量已经超了。
    #expect(!MarketFeed.seedUsable(s, sourceStepMs: 60_000, nowMs: now + 1_399 * 60_000, maxTailBars: 1400))
    #expect(!MarketFeed.seedUsable(s, sourceStepMs: 60_000, nowMs: now + 2_000 * 60_000, maxTailBars: 1400))
  }

  // ------------------------------------------------------------------ F1：整条 feed

  /// 可拨的墙上时钟。
  final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var ms: Int64
    init(_ ms: Int64) { self.ms = ms }
    var nowMs: Int64 { lock.withLock { ms } }
    func advance(_ d: Int64) { lock.withLock { ms += d } }
    var clock: @Sendable () -> Date {
      { [self] in Date(timeIntervalSince1970: Double(nowMs) / 1000) }
    }
  }

  /// 按拨出来的「现在」回 K 线：最新一屏以当前这根收尾；补缺按模式回。
  actor Upstream: HTTPTransport {
    enum GapMode: Sendable { case normal, fail, endless }
    let box: ClockBox
    var gap: GapMode = .normal
    private(set) var gapCalls = 0, windowCalls = 0
    init(_ box: ClockBox) { self.box = box }
    func setGap(_ g: GapMode) { gap = g }
    var calls: Int { gapCalls + windowCalls }

    private static func rows(from: Int64, count: Int) -> HTTPReply {
      let out = (0..<max(0, count)).map { i -> String in
        let t = from + Int64(i) * FeedChainHardeningTests.step
        return "[\(t),\"1\",\"1\",\"1\",\"1\",\"1\",\(t + 59_999),\"1\",1,\"1\",\"1\",\"0\"]"
      }
      return json("[" + out.joined(separator: ",") + "]")
    }

    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      guard url.path.contains("klines") else {
        return json(#"{"symbol":"BTCUSDT","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
      }
      let step = FeedChainHardeningTests.step
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let limit = items.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 1500
      let nowBucket = box.nowMs / step * step
      if let start = items.first(where: { $0.name == "startTime" })?.value.flatMap(Int64.init) {
        gapCalls += 1
        let first = (start + step - 1) / step * step
        switch gap {
        case .fail: throw FeedError.badResponse("补缺挂了")
        case .endless: return Self.rows(from: first, count: limit)
        case .normal: return Self.rows(from: first, count: min(limit, Int((nowBucket - first) / step) + 1))
        }
      }
      windowCalls += 1
      return Self.rows(from: nowBucket - Int64(limit - 1) * step, count: limit)
    }
  }

  private static func frame(open t: Int64) -> String {
    """
    {"stream":"btcusdt@kline_1m","data":{"e":"kline","E":\(t + 1_000),"s":"BTCUSDT",\
    "k":{"t":\(t),"T":\(t + step - 1),"s":"BTCUSDT","i":"1m","f":1,"L":2,\
    "o":"1.00","c":"1.00","h":"1.00","l":"1.00","v":"1.0","n":1,"x":false,\
    "q":"1.0","V":"0.5","Q":"0.5","B":"0"}}}
    """
  }

  private func tempPaths() -> Paths {
    let p = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent("kanpan-chain-\(UUID().uuidString)"))
    try? p.ensureRoot()
    return p
  }

  private func makeFeed(_ upstream: Upstream, box: ClockBox, paths: Paths,
                        deck: ReplayDeck = ReplayDeck([.hang])) -> MarketFeed {
    let pacer = FastPacer()
    return MarketFeed(rest: BinanceREST(transport: upstream,
                                        limiter: RateLimiter(pacer: pacer, minGapMs: 0), pacer: pacer),
                      ws: BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer())),
                      paths: paths, pacer: pacer, clock: box.clock, reconcileMs: 0, initialLimit: 50)
  }

  private static func contiguous(_ s: BarSeries) -> Bool {
    s.count > 0 && Int64(s.count) == (s.lastTime - s.firstTime) / step + 1
  }

  @Test("回前台时断档超过补缺上限：整段换成最新一屏，不留洞、不去撞注定失败的补缺")
  func foregroundAfterLongGapReplaces() async throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let box = ClockBox(Self.t0 + 30_000)
    let upstream = Upstream(box)
    let feed = makeFeed(upstream, box: box, paths: paths)
    await feed.setSnapshotEnabled(false)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(15) { await feed.currentSeries.lastTime == Self.t0 })
    #expect(await waitForSteadyState(feed))

    // 锁屏一周（10080 根 > 币安 6000 根的补缺上限）。
    box.advance(10_080 * Self.step)
    let now1 = box.nowMs / Self.step * Self.step
    let gapBefore = await upstream.gapCalls
    await feed.enterForeground()
    #expect(await waitUntil(15) { await feed.currentSeries.lastTime == now1 })
    #expect(await waitForSteadyState(feed))
    let s = await feed.currentSeries
    #expect(Self.contiguous(s), "序列中间留了洞：\(s.count) 根 \(s.firstTime)…\(s.lastTime)")
    #expect(s.firstTime > Self.t0, "旧序列没换掉，只是把新一屏接在后面")
    #expect(await upstream.gapCalls == gapBefore, "明知接不上还发了补缺")
    #expect(await feed.pendingGapForTests == 0)
    #expect(await feed.isBackfillingForTests == false)
    await feed.stop()
  }

  @Test("补缺被提供者判「接不上」（gapTooLong）：同样整段换掉，缺口不再挂着")
  func gapTooLongFromProviderReplaces() async throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let box = ClockBox(Self.t0 + 30_000)
    let upstream = Upstream(box)
    let feed = makeFeed(upstream, box: box, paths: paths)
    await feed.setSnapshotEnabled(false)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(15) { await feed.currentSeries.lastTime == Self.t0 })
    #expect(await waitForSteadyState(feed))

    // 按时钟只欠 200 根，但上游翻满 4 页还没到头（时钟和交易所对不上的情形）。
    box.advance(200 * Self.step)
    let now1 = box.nowMs / Self.step * Self.step
    await upstream.setGap(.endless)
    await feed.enterForeground()
    #expect(await waitUntil(15) { await feed.currentSeries.lastTime == now1 })
    #expect(await waitForSteadyState(feed))
    #expect(await upstream.gapCalls == 4)
    let s = await feed.currentSeries
    #expect(Self.contiguous(s), "序列中间留了洞：\(s.count) 根 \(s.firstTime)…\(s.lastTime)")
    #expect(await feed.pendingGapForTests == 0)
    #expect(await feed.isBackfillingForTests == false)
    await feed.stop()
  }

  @Test("回前台补缺失败、之后又推来新根：这时候不落快照，免得把洞带进下次冷启动")
  func noSnapshotWithUnfilledGap() async throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let box = ClockBox(Self.t0 + 30_000)
    let upstream = Upstream(box)
    let gate = Gate()
    let now1 = Self.t0 + 100 * Self.step
    let deck = ReplayDeck([.hold(gate), .frame(.text(Self.frame(open: now1))), .hang])
    let feed = makeFeed(upstream, box: box, paths: paths, deck: deck)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(15) { await feed.currentSeries.lastTime == Self.t0 })
    #expect(await waitForSteadyState(feed))

    box.advance(100 * Self.step)
    await upstream.setGap(.fail)
    await feed.enterForeground()
    // 补缺（连同几轮自愈）都失败了，缺口记着。
    #expect(await waitUntil(15) {
      let gap = await feed.pendingGapForTests
      let backfilling = await feed.isBackfillingForTests
      return gap > 0 && !backfilling
    })
    // 推送带来缺口之后的新根：序列中间现在有个洞。
    await gate.open()
    #expect(await waitUntil(15) { await feed.currentSeries.lastTime == now1 })
    #expect(!Self.contiguous(await feed.currentSeries))
    #expect(await feed.pendingGapForTests > 0)

    await feed.enterBackground()
    let dir = paths.series
    #expect(await staysFalse(for: 0.6) {
      SeriesStore.read(symbol: "BTCUSDT", interval: .m1, in: dir)?.lastTime == now1
    }, "带洞的序列被落成了快照")
    if let snap = SeriesStore.read(symbol: "BTCUSDT", interval: .m1, in: dir) {
      #expect(Self.contiguous(snap), "快照中间有洞：\(snap.count) 根 \(snap.firstTime)…\(snap.lastTime)")
    }
    await feed.stop()
  }

  @Test("stop 之后晚到的回前台通知：不重开连接、不发请求")
  func foregroundAfterStopIsInert() async throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let box = ClockBox(Self.t0 + 30_000)
    let upstream = Upstream(box)
    let feed = makeFeed(upstream, box: box, paths: paths)
    await feed.setSnapshotEnabled(false)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(15) { await feed.currentSeries.lastTime == Self.t0 })
    #expect(await waitForSteadyState(feed))
    await feed.enterBackground()
    await feed.stop()
    box.advance(100 * Self.step)
    let before = await upstream.calls
    await feed.enterForeground()
    #expect(await feed.isWSRunningForTests == false)
    #expect(await staysFalse(for: 0.3) { await upstream.calls != before })
  }
}
