import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 首屏历史拉不下来时，图不能就这么一直空着。
///
/// 2026-09-18 的 13 台矩阵在 iPhone 15 上红了一条 `testTradFiSearchAndMarketData`，
/// 诊断里的链路日志是一串 `直连 fapi.binance.com /fapi/v1/klines HTTP 429` +
/// `限流 429（上游），记录罚停`，最后 `chart.canvas` 的值停在「行情加载中」，整屏
/// 找不到任何错误提示，也没有能点的重试。顺着链路查下去有两处各自独立的毛病：
///
/// - `MarketFeed` 把只剩 WS 那一根的序列也当快照落了盘（日志里的 `快照 79B`）。
///   `RoutedMarketFeed` 要收够 3 根才肯把这条线路交给界面，所以这份快照下次冷启动
///   读回来照样画不出第一帧——它唯一的作用是把上一份能用的快照覆盖掉。
/// - `RoutedMarketFeed` 收到 `.historyError` 会先喊一声 `.routing(.switching)`，
///   而行情页收到 `.switching` 的第一件事就是 `historyError = nil`。内部每重试一次
///   就抹掉一次横幅，巡检那句「暂时无法连接，点此重试」刚亮起来就没了。
///
/// 两个用例分别盯住其中一头。
@Suite("首屏拉不到历史时的表现")
struct BlankChartTests {

  /// K 线永远 429，其余接口正常。
  private actor AlwaysRateLimited: HTTPTransport {
    private(set) var klineCalls = 0
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      guard url.path.contains("klines") else {
        return json(#"{"symbol":"BTCUSDT","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
      }
      klineCalls += 1
      throw BinanceError(status: 429, url: "klines")
    }
  }

  private static func klineFrame(open time: Int64) -> ReplayStep {
    .frame(.text("""
    {"stream":"btcusdt@kline_1m","data":{"e":"kline","E":\(time + 1),"s":"BTCUSDT",\
    "k":{"t":\(time),"T":\(time + 59_999),"s":"BTCUSDT","i":"1m","f":1,"L":2,\
    "o":"1","c":"1","h":"1","l":"1","v":"1","n":1,"x":false,"q":"1","V":"1","Q":"1","B":"0"}}}
    """))
  }

  @Test("历史全 429、只有 WS 推来一根时，不把这一根落成快照")
  func thinSeriesIsNotSnapshotted() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let paths = Paths(root: root)
    let pacer = FastPacer()
    let transport = AlwaysRateLimited()
    let deck = ReplayDeck([Self.klineFrame(open: 1_700_000_000_000), .hang])
    let feed = MarketFeed(rest: BinanceREST(transport: transport,
                                            limiter: RateLimiter(pacer: pacer, minGapMs: 0),
                                            pacer: pacer),
                          ws: BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer())),
                          paths: paths,
                          pacer: pacer,
                          reconcileMs: 0)
    await feed.setSnapshotEnabled(true)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)

    // 等到那一根 WS K 线真的进了序列，确认我们测的确实是「有一根、但不够画」。
    #expect(await waitUntil(5) { await feed.currentSeries.count == 1 })
    #expect(await transport.klineCalls > 0)

    // 落盘是 detached 任务，给它足够的时间真写下去——写了才算红。
    let wrote = await waitUntil(2) { Self.hasStoredSeries(paths) }
    #expect(!wrote, "只有 \(MarketFeed.snapshotFloor) 根以下的序列不该落成快照，它画不出第一帧，只会覆盖掉上一份好的")
  }

  private static func hasStoredSeries(_ paths: Paths) -> Bool {
    let fm = FileManager.default
    if fm.fileExists(atPath: paths.snapshot.path) { return true }
    let inSeries = (try? fm.contentsOfDirectory(atPath: paths.series.path)) ?? []
    return !inSeries.isEmpty
  }

  /// 事件收集器。`waitUntil` 的闭包是并发执行的，标志位得放在 actor 里。
  private actor Seen {
    var retryOffer = false
    var switching = false
    func noteRetryOffer() { retryOffer = true }
    func noteSwitching() { switching = true }
  }

  @Test("历史报错不冒充换线路，「点此重试」不会被自己抹掉")
  func historyErrorDoesNotAnnounceASwitch() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let pacer = FastPacer()
    let transport = AlwaysRateLimited()
    let rest = BinanceREST(transport: transport,
                           limiter: RateLimiter(pacer: pacer, minGapMs: 0),
                           pacer: pacer)
    let routed = RoutedMarketFeed(hosts: BinanceHosts(),
                                  paths: Paths(root: root),
                                  primary: rest, backup: rest,
                                  sockets: ReplayFactory(deck: ReplayDeck([.hang]), pacer: SystemPacer()),
                                  policy: .direct)
    let stream = await routed.events()
    await routed.setSnapshotEnabled(false)
    await routed.start(symbol: "BTCUSDT", interval: .m1)

    // 收一段事件：要看见「暂时无法连接，点此重试」，且这一路上一次
    // `.routing(.switching)` 都不该有——那一声会让行情页把横幅清掉。
    let seen = Seen()
    let collector = Task {
      for await update in stream {
        switch update.event {
        case .routing(.switching): await seen.noteSwitching()
        case .historyError(let message?) where message.contains("重试"): await seen.noteRetryOffer()
        default: break
        }
      }
    }
    _ = await waitUntil(8) { await seen.retryOffer }
    collector.cancel()

    #expect(await seen.retryOffer, "历史一直拉不下来，得让用户看见错误并且能点重试")
    #expect(await !seen.switching, "线路没换，就不该报 .routing(.switching)——行情页收到它会把「点此重试」清掉")
  }
}
