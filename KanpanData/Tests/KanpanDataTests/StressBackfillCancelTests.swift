import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 压测（2026-09-26 行情与网络层）：补缺在途被取消。
///
/// 两个老毛病，都是「补缺那一发半路被掐」时才露面的：
/// - D1：被掐的那一发直接 return，合成器的 `isBackfilling` 永远挂着——之后所有 WS 推送
///   只进队列、不落到序列上，最后一根定格不动、队列无上限地涨；回前台「缺口不足一根」
///   不补，自愈 / `fill` 末尾见补缺在途都让路，谁也解不开。
/// - M1：补缺一出发就把缺口取走（取走即清），被掐之后缺口就没了。挂起那一下只按当时的
///   末根重记，快照末根到最新一屏之间那个洞就再也没人补，还会被快照带进下次冷启动。
///
/// 时序全靠闸门摆出来（补缺那一笔挂在 `Gate` 上、闸门不理会取消，和真回包一样），
/// 不靠 sleep 赌机器快慢；判据是结构性的：队列放没放、缺口清没清、序列连不连续、
/// 补缺打了几发。
@Suite("压测 · 补缺在途被取消")
struct StressBackfillCancelTests {

  private static let step: Int64 = 60_000
  private static let last: Int64 = 1_700_000_000_000

  private static func rows(from: Int64, through: Int64) -> HTTPReply {
    var out: [String] = []
    var t = from
    while t <= through {
      out.append("[\(t),\"1\",\"1\",\"1\",\"1\",\"1\",\(t + step - 1),\"1\",1,\"1\",\"1\",\"0\"]")
      t += step
    }
    return json("[" + out.joined(separator: ",") + "]")
  }

  /// 最新一屏回 `window` 根；补缺（带 startTime）前 `gapFailures` 发失败，
  /// 接下来那一发挂在 `gate` 上（`holdNext` 打开时），之后照常。
  private actor Upstream: HTTPTransport {
    let gapFailures: Int, window: Int
    let gate = Gate()
    private var holdNext: Bool
    private(set) var gapCalls = 0
    init(gapFailures: Int, window: Int, holdNext: Bool) {
      self.gapFailures = gapFailures; self.window = window; self.holdNext = holdNext
    }
    func arm() { holdNext = true }
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      guard url.path.contains("klines") else {
        return json(#"{"symbol":"BTCUSDT","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
      }
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      if let start = items.first(where: { $0.name == "startTime" })?.value.flatMap(Int64.init) {
        gapCalls += 1
        if gapCalls <= gapFailures { throw FeedError.badResponse("补缺挂了") }
        if holdNext { holdNext = false; await gate.wait() }
        let step = StressBackfillCancelTests.step, last = StressBackfillCancelTests.last
        return StressBackfillCancelTests.rows(from: last - (last - start) / step * step, through: last)
      }
      let limit = items.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? window
      let n = min(limit, window)
      return StressBackfillCancelTests.rows(from: StressBackfillCancelTests.last - Int64(n - 1) * StressBackfillCancelTests.step,
                                            through: StressBackfillCancelTests.last)
    }
  }

  /// 第一条连接照常连上（回放器挂着不发帧）；之后的连接一直连不上——挂在连接那一步，
  /// 取消才醒。这样回前台重连不会有 `.connected`，也就不会另派一发补缺把卡死的队列
  /// 「顺手」解开，被测的只剩被取消的那一发自己怎么收尾。
  private struct FirstOnlyFactory: WSSocketFactory {
    let deck = ReplayDeck([.hang])
    let made = Counter()
    func connect(to url: URL) async throws -> WSSocket {
      if made.bump() == 1 { return try await ReplayFactory(deck: deck, pacer: SystemPacer()).connect(to: url) }
      try await Task.sleep(nanoseconds: 600_000_000_000)
      throw CancellationError()
    }
  }

  private func tempPaths() -> Paths {
    let p = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent("kanpan-bfcancel-\(UUID().uuidString)"))
    try? p.ensureRoot()
    return p
  }

  private func contiguous(_ s: BarSeries) -> Bool {
    s.count > 0 && Int64(s.count) == (s.lastTime - s.firstTime) / Self.step + 1
  }

  @Test("M1 首屏收尾那一发补缺挂在路上时切出去又回来：洞必须补上，不能只从末根补",
        .timeLimit(.minutes(1)))
  func fillEndBackfillCancelledByForegroundKeepsTheHole() async throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    // 快照停在最新一根之前 100 根；最新一屏只回 5 根，中间 95 根只能靠补缺拿。
    let seedEnd = Self.last - 100 * Self.step
    let seed = makeSeries("BTCUSDT", .m1, count: 300, t0: seedEnd - 299 * Self.step)
    try paths.ensure(paths.series)
    _ = try SeriesStore.write(seed, in: paths.series)
    // 首屏附带的那发补缺失败 → 记缺口；`fill` 收尾时接着补，那一发挂在闸门上。
    let upstream = Upstream(gapFailures: 1, window: 5, holdNext: true)
    let pacer = FastPacer()
    let feed = MarketFeed(rest: BinanceREST(transport: upstream,
                                            limiter: RateLimiter(pacer: pacer, minGapMs: 0), pacer: pacer),
                          ws: BinanceWS(factory: ReplayFactory(deck: ReplayDeck([.hang]), pacer: SystemPacer())),
                          paths: paths, pacer: pacer, clock: clock(near: Self.last), reconcileMs: 0)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)

    // 那一发到了闸门前：此刻序列末根已是最新一根，中间有个洞，缺口记在快照末根。
    #expect(await waitUntil(10) { await upstream.gate.arrived == 1 })
    #expect(await feed.isBackfillingForTests)
    let before = await feed.currentSeries
    #expect(!contiguous(before), "前提不成立：序列里本该有个洞")
    #expect(await feed.pendingGapForTests == seedEnd)

    // 切出去看一眼马上回来：回前台那句 `loadTask?.cancel()` 把在途那一发掐了。
    // 原来它出发时已经把缺口取走，回前台只能看末根，于是只从最新一根补，洞留下了。
    await feed.enterBackground()
    await feed.enterForeground()
    // 被掐的那一发的回包这时才到（闸门不理会取消，真网络也一样）。
    await upstream.gate.open()

    let healed = await waitUntil(10) {
      let s = await feed.currentSeries
      return s.lastTime == Self.last && self.contiguous(s)
    }
    let s = await feed.currentSeries
    let owed = await feed.pendingGapForTests
    #expect(healed, "洞没补上：\(s.count) 根，\(s.firstTime)…\(s.lastTime)，缺口还欠 \(owed)")
    #expect(await waitForSteadyState(feed, timeout: 10), "补缺状态或缺口没收干净")
    await feed.stop()
  }

  @Test("D1 自愈 / 重连那一发补缺在途时进后台被掐：队列必须放行，缺口留着回前台补",
        .timeLimit(.minutes(1)))
  func backgroundCancelledBackfillReleasesTheQueue() async throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let upstream = Upstream(gapFailures: 0, window: 1500, holdNext: false)
    let factory = FirstOnlyFactory()
    let live = Counter()
    let feed = MarketFeed(rest: BinanceREST(transport: upstream),
                          ws: BinanceWS(factory: factory),
                          paths: paths, clock: clock(near: Self.last, aheadMs: 5_000), reconcileMs: 0)
    await feed.setSnapshotEnabled(false)
    let events = await feed.events()
    let collector = Task { [live] in
      for await update in events { if case .status(.live) = update.event { live.setTo(1) } }
    }
    defer { collector.cancel() }
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(10) { await feed.currentSeries.count == BinanceREST.maxKlines })
    #expect(await waitUntil(10) { live.value == 1 })
    #expect(await waitForSteadyState(feed, timeout: 10))

    // 挂起再回来：回前台那一发补缺挂在闸门上（放在 `loadTask` 里）。
    await feed.enterBackground()
    await feed.suspendForTests(lifecycle: await feed.lifecycleEpochForTests)
    await upstream.arm()
    await feed.enterForeground()
    #expect(await waitUntil(10) { await upstream.gate.arrived == 1 })
    // 又进后台、闹钟到点：挂起时不掐 `loadTask`，但这一发之后回前台还会被掐——
    // 这里直接走 `stop` 以外最狠的那条：再回前台一次（掐掉它）然后立刻进后台挂起。
    await feed.enterForeground()
    await feed.enterBackground()
    await feed.suspendForTests(lifecycle: await feed.lifecycleEpochForTests)
    await upstream.gate.open()

    // 后台时被掐：必须放行队列，缺口留着（不在后台重派）。
    #expect(await waitUntil(10) { !(await feed.isBackfillingForTests) },
            "被取消的补缺没有放行 WS 队列：之后的推送全都只进队列，末根定格")
    #expect(await feed.pendingGapForTests == Self.last, "缺口被带走了")
    let calls = await upstream.gapCalls
    #expect(await staysFalse(for: 0.3) { await upstream.gapCalls > calls }, "后台里不该再派补缺")
    // 回前台才补，补完缺口清零。
    await feed.enterForeground()
    #expect(await waitUntil(10) { await feed.pendingGapForTests == 0 }, "回前台后缺口没补")
    #expect(await waitForSteadyState(feed, timeout: 10))
    await feed.stop()
  }

  @Test("D1 回前台补缺在途、再切出去又回来（缺口不足一根）：被掐的那一发必须放行队列并补完",
        .timeLimit(.minutes(1)))
  func foregroundCancelledBackfillReleasesTheQueue() async throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let upstream = Upstream(gapFailures: 0, window: 1500, holdNext: false)
    let factory = FirstOnlyFactory()
    let live = Counter()
    // 墙上时钟停在末根那一分钟之内：`pendingBars()` 只看末根时是 1（「不足一根」）。
    let feed = MarketFeed(rest: BinanceREST(transport: upstream),
                          ws: BinanceWS(factory: factory),
                          paths: paths, clock: clock(near: Self.last, aheadMs: 5_000), reconcileMs: 0)
    await feed.setSnapshotEnabled(false)
    let events = await feed.events()
    let collector = Task { [live] in
      for await update in events { if case .status(.live) = update.event { live.setTo(1) } }
    }
    defer { collector.cancel() }
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(10) { await feed.currentSeries.count == BinanceREST.maxKlines })
    #expect(await waitUntil(10) { live.value == 1 })
    #expect(await waitForSteadyState(feed, timeout: 10))

    // 进后台被挂起：缺口记在末根。回前台那一发补缺挂在闸门上。
    await feed.enterBackground()
    await feed.suspendForTests(lifecycle: await feed.lifecycleEpochForTests)
    #expect(await feed.pendingGapForTests == Self.last)
    let callsBefore = await upstream.gapCalls
    await upstream.arm()
    await feed.enterForeground()
    #expect(await waitUntil(10) { await upstream.gate.arrived == 1 })

    // 又切出去一下马上回来：上一发被 `loadTask?.cancel()` 掐掉。
    await feed.enterBackground()
    await feed.enterForeground()
    await upstream.gate.open()

    #expect(await waitUntil(10) { !(await feed.isBackfillingForTests) },
            "被取消的补缺没有放行 WS 队列：之后的推送全都只进队列，末根定格")
    #expect(await waitUntil(10) { await feed.pendingGapForTests == 0 }, "缺口没补")
    // 被掐的那一发 + 它收尾时重派的那一发，至多两发；不许每次回前台再叠一发。
    let calls = await upstream.gapCalls - callsBefore
    #expect(calls >= 1 && calls <= 2, "补缺请求 \(calls) 发")
    #expect(await feed.currentSeries.lastTime == Self.last)
    await feed.stop()
  }
}
