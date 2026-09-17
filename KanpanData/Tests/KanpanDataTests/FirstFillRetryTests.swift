import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 首屏历史的重试。
///
/// 2026-09-18 模拟器上出现过一次「实时价、成交量、持仓量都有，就是一根 K 线都没有」
/// （诊断快照里 `bars: 1`，那一根是 WS 推来的）。根因是首屏那一发 `klines` 撞上
/// 上游一个随机的 429，然后整条链路谁都没有再试一次：
///
/// - `MarketRESTTransport.direct` 把 429 变成**抛出来**的 `BinanceError`，
///   于是 `BinanceREST.fetch` 里那段按 `reply.status` 重试的代码根本走不到；
/// - 抛出来的那一支只记罚停就接着往上抛，注释写「让调用方按自己的节奏重试」；
/// - 而调用方 `MarketFeed.fillOnce` 压根没有重试，只亮一条横幅就收工。
///
/// 两头都补上之后，这两个用例分别盯住其中一头。
@Suite("首屏历史重试")
struct FirstFillRetryTests {

  /// 前 `failures` 发 K 线请求失败，之后正常发货。
  private actor FlakyHistory: HTTPTransport {
    private let failures: Int
    private let error: any Error
    private(set) var klineCalls = 0

    init(failures: Int, error: any Error) {
      self.failures = failures
      self.error = error
    }

    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      guard url.path.contains("klines") else {
        return json(#"{"symbol":"BTCUSDT","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
      }
      klineCalls += 1
      if klineCalls <= failures { throw error }
      let limit = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 0
      return Self.bars(limit)
    }

    private static func bars(_ count: Int) -> HTTPReply {
      let step: Int64 = 60_000
      let last: Int64 = 1_700_000_000_000
      let rows = (0..<count).map { i -> String in
        let t = last - Int64(count - 1 - i) * step
        return "[\(t),\"1\",\"1\",\"1\",\"1\",\"1\",\(t + step - 1),\"1\",1,\"1\",\"1\",\"0\"]"
      }
      return json("[" + rows.joined(separator: ",") + "]")
    }
  }

  private func makeFeed(_ transport: FlakyHistory) -> MarketFeed {
    // 退避是真的在睡，只是时钟被放快 1000 倍：1 秒的罚停 1 毫秒就过去了。
    let pacer = FastPacer()
    let deck = ReplayDeck([.hang])
    return MarketFeed(rest: BinanceREST(transport: transport,
                                        limiter: RateLimiter(pacer: pacer, minGapMs: 0),
                                        pacer: pacer),
                      ws: BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer())),
                      paths: Paths(root: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)),
                      pacer: pacer,
                      reconcileMs: 0)
  }

  @Test("上游连回两个 429，首屏自己重试到拿下")
  func rateLimitedFirstFillRecovers() async throws {
    let transport = FlakyHistory(failures: 2, error: BinanceError(status: 429, url: "klines"))
    let feed = makeFeed(transport)
    await feed.setSnapshotEnabled(false)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)

    #expect(await waitUntil(5) { await feed.currentSeries.count >= MarketFeed.firstScreenLimit })
    #expect(await transport.klineCalls > 2)
  }

  @Test("首屏那一发彻底失败，也会自己再来一发")
  func hardFailureFirstFillRecovers() async throws {
    // 不是限流：`BinanceREST` 不会替它重试，只有 `MarketFeed` 自己那层退避能救。
    let transport = FlakyHistory(failures: 2, error: FeedError.badResponse("首屏挂了"))
    let feed = makeFeed(transport)
    await feed.setSnapshotEnabled(false)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)

    #expect(await waitUntil(5) { await feed.currentSeries.count >= MarketFeed.firstScreenLimit })
  }
}
