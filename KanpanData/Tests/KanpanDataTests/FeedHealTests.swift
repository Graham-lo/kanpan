import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 首屏 / 补缺失败之后自己补回来（`MarketFeed.scheduleHeal`）。
///
/// 2026-09-25 真机：切完「涨跌幅起点」回到图表，ONDO 只剩最新一根、BTC 5m 中间缺一截
/// 像跳空，「跑一会又恢复正常」。那「一会」是线路巡检：币安那档报错后 60 秒内不探、
/// 之后 20 秒一轮，探通了才整张图重拉。这两条用例盯的是 feed 自己那一层：
/// 失败的那一小段几秒内自己再发，不等巡检、不要用户点横幅。
@Suite("失败后自愈")
struct FeedHealTests {

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

  /// 前 `windowFailures` 发「最新一屏」、前 `gapFailures` 发补缺（带 startTime）失败，之后正常。
  /// 最新一屏只回 `window` 根，好让快照末根到它之间真的留一个洞。
  private actor Upstream: HTTPTransport {
    let windowFailures: Int, gapFailures: Int, window: Int
    private(set) var windowCalls = 0, gapCalls = 0
    init(windowFailures: Int, gapFailures: Int, window: Int) {
      self.windowFailures = windowFailures; self.gapFailures = gapFailures; self.window = window
    }
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      guard url.path.contains("klines") else {
        return json(#"{"symbol":"BTCUSDT","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
      }
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      if let start = items.first(where: { $0.name == "startTime" })?.value.flatMap(Int64.init) {
        gapCalls += 1
        if gapCalls <= gapFailures { throw FeedError.badResponse("补缺挂了") }
        let step = FeedHealTests.step
        let last = FeedHealTests.last  // 网格对齐到最新一根（它不在整分钟上）
        return FeedHealTests.rows(from: last - (last - start) / step * step, through: last)
      }
      windowCalls += 1
      if windowCalls <= windowFailures { throw FeedError.badResponse("首屏挂了") }
      let limit = items.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? window
      let n = min(limit, window)
      return FeedHealTests.rows(from: FeedHealTests.last - Int64(n - 1) * FeedHealTests.step,
                                through: FeedHealTests.last)
    }
  }

  private func makeFeed(_ transport: Upstream, paths: Paths) -> MarketFeed {
    let pacer = FastPacer()
    return MarketFeed(rest: BinanceREST(transport: transport,
                                        limiter: RateLimiter(pacer: pacer, minGapMs: 0),
                                        pacer: pacer),
                      ws: BinanceWS(factory: ReplayFactory(deck: ReplayDeck([.hang]), pacer: SystemPacer())),
                      paths: paths, pacer: pacer, reconcileMs: 0)
  }

  private func tempPaths() -> Paths {
    let p = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent("kanpan-heal-\(UUID().uuidString)"))
    try? p.ensureRoot()
    return p
  }

  @Test("首屏连着两轮都失败：不用点横幅，自己补发到拿下")
  func firstFillHealsWithoutTap() async throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    // 一轮首屏 = 小页 + 完整那发的 3 次退避，挂 8 发足够把头两轮都打掉。
    let upstream = Upstream(windowFailures: 8, gapFailures: 0, window: 1500)
    let feed = makeFeed(upstream, paths: paths)
    await feed.setSnapshotEnabled(false)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)

    let healed = await waitUntil(10) { await feed.currentSeries.count >= MarketFeed.firstScreenLimit }
    let calls = await upstream.windowCalls
    #expect(healed, "首屏失败后没有自己补回来（最新一屏请求 \(calls) 次）")
    #expect(calls > 8)
  }

  @Test("快照到最新一屏之间的缺口补失败：几秒内自己再补，图上不留洞")
  func gapHealsWithoutTap() async throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    // 快照停在最新一根之前 100 根；最新一屏只回 5 根，中间 95 根只能靠补缺拿。
    let seedEnd = Self.last - 100 * Self.step
    let seed = makeSeries("BTCUSDT", .m1, count: 300, t0: seedEnd - 299 * Self.step)
    try paths.ensure(paths.series)
    _ = try SeriesStore.write(seed, in: paths.series)
    let upstream = Upstream(windowFailures: 0, gapFailures: 3, window: 5)
    let feed = makeFeed(upstream, paths: paths)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)

    let healed = await waitUntil(10) {
      let s = await feed.currentSeries
      return s.count > 0 && s.lastTime == Self.last && Int64(s.count) == (Self.last - s.firstTime) / Self.step + 1
    }
    let s = await feed.currentSeries
    let calls = await upstream.gapCalls
    #expect(healed, "缺口没有自己补上：\(s.count) 根，\(s.firstTime)…\(s.lastTime)，补缺请求 \(calls) 次")
    #expect(calls > 3)
    #expect(await waitUntil(5) { await feed.pendingGapForTests == 0 })
  }
}
