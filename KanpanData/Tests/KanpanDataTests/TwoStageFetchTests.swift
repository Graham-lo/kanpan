import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
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
      // 带 startTime 的是补缺（`.connected` 排在首屏之后被处理时派的那一发），
      // 不是两段式取数的一部分：直接答「游标之后没有新的」，别挂到 `deep` 上去，
      // 不然「完整那发只挂着一笔」这条断言会随机多数出一笔。
      if (url.query ?? "").contains("startTime") { return json("[]") }
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
    // 两发都要过限流器（默认两笔之间隔 120ms）：小页先过的话，完整那发这会儿还在
    // 限流器里排着，没走到 transport。原来这里当场断言 `deepCount == 1`，没等到就红，
    // 后面的 `releaseDeep` 放了个空，晚到的完整那发再也没人放行，整条用例挂满超时。
    // 所以先等它真的挂上来，再确认此刻图上仍然只有小页那 300 根。
    #expect(await waitUntil(3) { await transport.deepCount == 1 })
    #expect(await feed.currentSeries.count == MarketFeed.firstScreenLimit)
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

    // 小页这时才落地也不能把 1500 根盖成 300 根。原来这里睡 50ms 再看一眼：小页要是
    // 在限流器里排在完整那发后面（两笔隔 120ms），50ms 时它还没落地，这一眼什么也
    // 没验到。现在先等首屏这一轮收尾——`filling` 落下之前 feed 会等小页结束：要么
    // 已经出站、答复回来了，要么还没出站就被取消、根本不发——再确认之后一段时间里
    // 序列始终是 1500 根。
    #expect(await waitUntil(3) { await feed.isFillingForTests == false })
    #expect(await staysFalse(for: 0.5) { await feed.currentSeries.count != 1500 })
    await feed.stop()
  }
}
