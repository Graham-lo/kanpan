import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

@Suite("Data identity, snapshots and duplicate delivery")
struct DataIntegrityTests {
  func event(_ close: Double, time: Int64, closed: Bool = false, interval: String = "1m") -> KlineEvent {
    KlineEvent(symbol: "BTCUSDT", interval: interval, openTime: 60_000, closed: closed,
      bar: Bar(openTime: 60_000, open: 100, high: 110, low: 90, close: close, volume: Double(time)), eventTime: time)
  }
  @Test func lateFramesAndWrongIntervalCannotRewriteTail() {
    var composer = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1, bars: []))
    let accepted13 = composer.apply(event(105, time: 1000))
    #expect(accepted13)
    let accepted14 = !composer.apply(event(95, time: 900))
    #expect(accepted14)
    let accepted15 = !composer.apply(event(105, time: 1000))
    #expect(accepted15)
    let accepted16 = !composer.apply(event(95, time: 1100, interval: "1h"))
    #expect(accepted16)
    #expect(composer.series.close.last == 105)
    #expect(composer.wsRevision == 1)
    let accepted19 = composer.apply(event(106, time: 1100, closed: true))
    #expect(accepted19)
    let accepted20 = !composer.apply(event(95, time: 1200))
    #expect(accepted20)
    #expect(composer.series.close.last == 106)
  }
  @Test func restCannotReplaceLiveTailReceivedDuringRequest() {
    var composer = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1, bars: []))
    let accepted25 = composer.apply(event(105, time: 1000))
    #expect(accepted25)
    let requestRevision = composer.wsRevision
    let accepted27 = composer.apply(event(108, time: 1200))
    #expect(accepted27)
    composer.merge([event(95, time: 1100).bar], preservingLiveTail: composer.wsRevision != requestRevision)
    #expect(composer.series.close.last == 108)
    #expect(composer.series.volume.last == 1200)
    // A quiet-stream reconciliation can still repair a tail when no WS raced it.
    composer.merge([event(109, time: 1300).bar])
    #expect(composer.series.close.last == 109)
  }
  @Test func tradeDuplicatesDoNotDoubleVolume() {
    var composer = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1, bars: [event(105, time: 1000).bar]))
    #expect(composer.applyTick(price: 106, qty: 2, timeMs: 61000) == .updated)
    let volume = composer.series.volume.last
    #expect(composer.applyTick(price: 106, qty: 2, timeMs: 61000) == .ignored)
    #expect(composer.applyTick(price: 90, qty: 9, timeMs: 60500) == .ignored)
    #expect(composer.series.volume.last == volume)
    #expect(composer.series.close.last == 106)
  }
  @Test func sameMillisecondDistinctTradesAreNotDropped() {
    var composer = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1, bars: [event(105, time: 1000).bar]))
    let first = composer.applyTick(price: 106, qty: 2, timeMs: 61000, tradeID: 10)
    let second = composer.applyTick(price: 107, qty: 3, timeMs: 61000, tradeID: 11)
    let duplicate = composer.applyTick(price: 107, qty: 3, timeMs: 61000, tradeID: 11)
    #expect(first == .updated && second == .updated && duplicate == .ignored)
    #expect(composer.series.volume.last == 1005)
  }
  @Test func concurrentCatalogReadersShareOneRequest() async {
    let transport = HeldCatalog()
    let catalog = SymbolCatalog(rest: BinanceREST(transport: transport),
      paths: Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    let readers = Task {
      await withTaskGroup(of: [SymbolInfo].self) { group in
        for _ in 0..<20 { group.addTask { await catalog.all() } }
        var counts: [Int] = []
        for await rows in group { counts.append(rows.count) }
        return counts
      }
    }
    #expect(await waitUntil(3) { await transport.calls > 0 })
    await transport.release()
    let counts = await readers.value
    #expect(counts.count == 20 && counts.allSatisfy { $0 == 1 })
    #expect(await transport.calls == 1)
  }

  @Test("ticker 校准失败不降级已加载的历史")
  func tickerFailureDoesNotInvalidateHistory() async throws {
    let t0: Int64 = 1_700_000_000_000
    let rows = (0..<3).map { i -> String in
      let t = t0 + Int64(i) * Interval.m1.stepMs
      return "[\(t),\"100\",\"101\",\"99\",\"100.5\",\"10\",\(t + Interval.m1.stepMs - 1)]"
    }.joined(separator: ",")
    let server = FakeServer { url in
      if url.path.contains("ticker") { return json("{}", status: 503) }
      if url.path.contains("klines") {
        // 带 startTime 的是补缺：`.connected` 一旦排在首屏之后被处理，feed 就会为
        // 「快照到连上」那段派一发（生产上那段确实缺）。这时候必须按游标往后答，
        // 把整屏又扔回去会让 `contiguousTail` 判成「行情翻页没有推进」抛错，于是
        // 冒出一条 `.historyError`——正是这条用例断言「不许有」的那个东西。
        if (url.query ?? "").contains("startTime") { return json("[]") }
        return json("[\(rows)]")
      }
      return json("[]")
    }
    let pacer = SystemPacer()
    let rest = BinanceREST(transport: FakeTransport(server), pacer: pacer)
    let deck = ReplayDeck([.hang])
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer,
                       silenceMs: 60_000_000)
    let paths = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let feed = MarketFeed(rest: rest, ws: ws, paths: paths, pacer: pacer,
                          reconcileMs: 0, includeTicker: true, initialLimit: 3)
    let stream = await feed.events()
    let recorded = Updates()
    let reader = Task { for await update in stream { await recorded.add(update) } }

    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(3) { await feed.currentSeries.count == 3 })
    // Give the independent ticker request a chance to fail after history was published.
    try? await Task.sleep(for: .milliseconds(20))
    let events = await recorded.values
    #expect(!events.contains {
      if case .historyError(let message) = $0.event { return message != nil }
      return false
    })
    #expect(!events.contains {
      if case .status(.offline) = $0.event { return true }
      return false
    })

    await feed.stop()
    reader.cancel()
  }

  @Test func returningToSameSelectionCannotReviveOldRequest() async throws {
    let transport = HeldHistory()
    let rest = BinanceREST(transport: transport)
    let deck = ReplayDeck([.hang])
    // `initialLimit` 压到首屏那一档，让每次选择只发一个历史请求——这条用例查的是
    // 「旧选择的请求不能复活」，按下标逐个放行，两段式会把下标搅乱。两段式本身
    // 另有用例（`TwoStageFetchTests`）。
    let feed = MarketFeed(rest: rest, ws: BinanceWS(factory: ReplayFactory(deck: deck, pacer: SystemPacer())),
                          paths: Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                          reconcileMs: 0, initialLimit: MarketFeed.firstScreenLimit)
    let stream = await feed.events()
    let recorded = Updates()
    let reader = Task { for await update in stream { await recorded.add(update) } }
    await feed.setSnapshotEnabled(false)
    let old = UUID(), other = UUID(), current = UUID()
    await feed.start(symbol: "BTCUSDT", interval: .m1, selection: old)
    #expect(await waitUntil(3) { await transport.count == 1 })
    await feed.switchTo(symbol: "ETHUSDT", interval: .h1, selection: other)
    #expect(await waitUntil(3) { await transport.count == 2 })
    await feed.switchTo(symbol: "BTCUSDT", interval: .m1, selection: current)
    #expect(await waitUntil(3) { await transport.count == 3 })
    await transport.release(2, price: 300)
    #expect(await waitUntil(3) { await feed.currentSeries.close.last == 300 })
    await transport.release(0, price: 100)
    await transport.release(1, price: 200)
    await feed.stop()
    await reader.value
    #expect(await feed.currentSeries.symbol == "BTCUSDT")
    #expect(await feed.currentSeries.interval == .m1)
    #expect(await feed.currentSeries.close.last == 300)
    let series = await recorded.values.compactMap { update -> (UUID, BarSeries)? in
      if case .series(let bars) = update.event { return (update.selection, bars) }; return nil
    }
    #expect(!series.isEmpty)
    #expect(series.allSatisfy { $0.0 == current && $0.1.close.last == 300 })
  }
}

private actor Updates {
  var values: [FeedUpdate] = []
  func add(_ value: FeedUpdate) { values.append(value) }
}
private actor HeldHistory: HTTPTransport {
  var pending: [CheckedContinuation<HTTPReply, Never>] = []
  var count: Int { pending.count }
  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    if url.path.contains("klines") {
      // Deliberately ignores cancellation, like a response already in a network callback.
      return await withCheckedContinuation { pending.append($0) }
    }
    return json(#"{"symbol":"BTCUSDT","lastPrice":"300","priceChangePercent":"0","highPrice":"310","lowPrice":"290","quoteVolume":"1","closeTime":3000}"#)
  }
  func release(_ index: Int, price: Double) {
    pending[index].resume(returning: json("[[60000,\"\(price)\",\"\(price)\",\"\(price)\",\"\(price)\",\"1\",119999,\"1\",1,\"1\",\"1\",\"0\"]]"))
  }
}

private actor HeldCatalog: HTTPTransport {
  var calls = 0
  var pending: [CheckedContinuation<HTTPReply, Never>] = []
  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    calls += 1
    return await withCheckedContinuation { pending.append($0) }
  }
  func release() {
    for continuation in pending {
      continuation.resume(returning: json(#"{"symbols":[{"symbol":"BTCUSDT","baseAsset":"BTC","quoteAsset":"USDT","contractType":"PERPETUAL","status":"TRADING","pricePrecision":2,"quantityPrecision":3,"filters":[]}]}"#))
    }
  }
}
