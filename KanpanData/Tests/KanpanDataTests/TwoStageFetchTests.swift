import Foundation
import Testing
@testable import KanpanData
import KanpanCore

/// 两段式首屏：小页和完整深度并行发出去，谁先回谁先画。
@Suite("两段式首屏")
struct TwoStageFetchTests {

  /// 小页立刻回，完整那发挂着等放行。
  private actor SplitHistory: HTTPTransport {
    private var deep: [CheckedContinuation<HTTPReply, Never>] = []
    private(set) var limits: [Int] = []

    var deepCount: Int { deep.count }

    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      guard url.path.contains("klines") else {
        return json(#"{"symbol":"BTCUSDT","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
      }
      let limit = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 0
      limits.append(limit)
      if limit <= MarketFeed.firstScreenLimit { return Self.bars(limit) }
      return await withCheckedContinuation { deep.append($0) }
    }

    func releaseDeep(_ count: Int) {
      for continuation in deep { continuation.resume(returning: Self.bars(count)) }
      deep.removeAll()
    }

    /// 末根对齐到同一个时间点，两段落在同一个绝对时间窗里，合并后不会出现重复根。
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

  private func makeFeed(_ transport: SplitHistory) -> MarketFeed {
    let deck = ReplayDeck([.hang])
    return MarketFeed(rest: BinanceREST(transport: transport),
                      ws: BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer())),
                      paths: Paths(root: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)),
                      reconcileMs: 0)
  }

  @Test("完整那发还没回来，小页先把图画上")
  func firstScreenPaintsBeforeFullDepth() async throws {
    let transport = SplitHistory()
    let feed = makeFeed(transport)
    await feed.setSnapshotEnabled(false)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)

    // 完整那发挂着，图却已经有东西了。
    #expect(await waitUntil(3) { await feed.currentSeries.count == MarketFeed.firstScreenLimit })
    #expect(await transport.deepCount == 1)
    #expect(await transport.limits.contains(MarketFeed.firstScreenLimit))
    #expect(await transport.limits.contains { $0 > MarketFeed.firstScreenLimit })

    // 完整深度回来之后接着铺开，补在左边。
    await transport.releaseDeep(1500)
    #expect(await waitUntil(3) { await feed.currentSeries.count == 1500 })
    let s = await feed.currentSeries
    for i in 1..<s.count { #expect(s.time(at: i) == s.time(at: i - 1) + 60_000) }
    await feed.stop()
  }

  @Test("完整那发先回来，小页落地时什么都不做")
  func lateFirstScreenDoesNotShrinkTheChart() async throws {
    let transport = SplitHistory()
    let feed = makeFeed(transport)
    await feed.setSnapshotEnabled(false)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(3) { await transport.deepCount == 1 })
    await transport.releaseDeep(1500)
    #expect(await waitUntil(3) { await feed.currentSeries.count == 1500 })

    // 小页这时才落地也不能把 1500 根盖成 300 根。
    try? await Task.sleep(for: .milliseconds(50))
    #expect(await feed.currentSeries.count == 1500)
    await feed.stop()
  }
}
