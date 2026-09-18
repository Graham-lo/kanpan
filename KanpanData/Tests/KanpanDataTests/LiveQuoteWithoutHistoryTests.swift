import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 历史还没到、WS 已经活着的那段时间里，界面不能装作什么都没有。
///
/// `RoutedMarketFeed.forward()` 有一道「交接门」：在 `publishedRoute` 追上这一代之前，
/// 所有事件都被挡住。原来这道门只认一条——历史至少 3 根。于是首屏历史一慢（撞上
/// 上游 429 罚停、或者网关一次 busy），`.status` 和 `.ticker` 连同实时价一起被吃掉：
/// 顶栏一直是「—」，状态停在「离线」，而持仓量走的是网关那条独立的路照样有数。
/// 一屏自相矛盾，而且「离线」是假的——WS 明明连着。
///
/// 现在 WS 报了 `.live` 也能开门。图还是空的，那件事由 `historyError` 的横幅去说
/// （巡检那句「暂时无法连接，点此重试」本来就不走这道门，见 `BlankChartTests`）。
@Suite("历史没到但 WS 活着")
struct LiveQuoteWithoutHistoryTests {

  /// K 线永远 429，24h 行情正常——就是矩阵里 iPhone 15 撞上的那个形状。
  private actor KlinesRateLimited: HTTPTransport {
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      guard url.path.contains("klines") else {
        return json(#"{"symbol":"BTCUSDT","lastPrice":"78298.9","priceChangePercent":"1.5","highPrice":"79000","lowPrice":"77000","quoteVolume":"10891416786","closeTime":3000}"#)
      }
      throw BinanceError(status: 429, url: "klines")
    }
  }

  /// 收集器。`waitUntil` 的闭包是并发执行的，标志位得放在 actor 里。
  private actor Seen {
    var live = false
    var price: Double?
    var source: MarketSource?
    func noteLive() { live = true }
    func note(price: Double) { self.price = price }
    func note(source: MarketSource) { self.source = source }
    /// 两个条件得在同一次跨隔离的跳转里读完：`waitUntil` 的闭包是自动闭包，
    /// 里面不能连着 `await` 两个 actor 属性。
    var ready: Bool { live && price != nil }
  }

  @Test("首屏历史全 429 时，WS 的实时价照样交给界面，状态也不谎报离线")
  func liveQuoteReachesTheUIWithoutHistory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let pacer = FastPacer()
    let rest = BinanceREST(transport: KlinesRateLimited(),
                           limiter: RateLimiter(pacer: pacer, minGapMs: 0),
                           pacer: pacer)
    // WS 正常连上并推一根 K 线，然后挂住——连接活着，只是历史拿不回来。
    let frame = ReplayStep.frame(.text("""
    {"stream":"btcusdt@kline_1m","data":{"e":"kline","E":1700000000001,"s":"BTCUSDT",\
    "k":{"t":1700000000000,"T":1700000059999,"s":"BTCUSDT","i":"1m","f":1,"L":2,\
    "o":"78236.8","c":"78298.9","h":"78299.8","l":"78216.3","v":"352.066","n":6824,\
    "x":false,"q":"27552910.7","V":"1","Q":"1","B":"0"}}}
    """))
    let routed = RoutedMarketFeed(hosts: BinanceHosts(),
                                  paths: Paths(root: root),
                                  primary: rest, backup: rest,
                                  sockets: ReplayFactory(deck: ReplayDeck([frame, .hang]), pacer: SystemPacer()),
                                  policy: .direct)
    let stream = await routed.events()
    await routed.setSnapshotEnabled(false)
    await routed.start(symbol: "BTCUSDT", interval: .m1)

    let seen = Seen()
    let collector = Task {
      for await update in stream {
        switch update.event {
        case .status(.live): await seen.noteLive()
        case .ticker(let ticker): await seen.note(price: ticker.last)
        case .source(let source): await seen.note(source: source)
        default: break
        }
      }
    }
    _ = await waitUntil(8) { await seen.ready }
    collector.cancel()

    #expect(await seen.source == .binance, "线路得交接出去，否则界面根本不知道自己连的是哪家")
    #expect(await seen.live, "WS 连着就不能报「离线」——那是假的，用户会去白折腾网络")
    #expect(await seen.price != nil, "历史没到不等于没有实时价，顶栏不该一直挂着「—」")
  }
}
