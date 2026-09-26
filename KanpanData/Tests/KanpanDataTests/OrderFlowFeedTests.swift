import Foundation
import Testing
@testable import KanpanData
import KanpanCore
import KanpanNetwork
import KanpanNetworkTestSupport

// MARK: - 假件

/// 深度适配器假件：一条连接上若干本簿，连接是 `GateSocket`，测试往里推「脚本名」，
/// 解码按脚本表翻成带簿号的消息。
private final class ScriptAdapter: DepthFeedAdapter, @unchecked Sendable {
  let name: String
  let books: [DepthBook]
  var streamURLs: [URL] { [URL(string: "wss://depth.test/\(name)")!] }
  let script: [String: [VenueMessage]]
  let snapshots: Snapshots
  /// 像 OKX 那样能单本重订：给出「退订 / 订阅」两句（内容只要认得出是哪本）。
  let resubscribable: Bool

  actor Snapshots {
    var replies: [Result<BookSnapshot, DepthSnapshotError>]
    private(set) var calls: [String] = []
    private(set) var sockets: [GateSocket] = []
    init(_ replies: [Result<BookSnapshot, DepthSnapshotError>]) { self.replies = replies }
    func next(_ venue: String) throws -> BookSnapshot {
      calls.append(venue)
      let reply = replies.count > 1 ? replies.removeFirst() : replies[0]
      return try reply.get()
    }
    func add(_ s: GateSocket) { sockets.append(s) }
    func socket(_ i: Int) -> GateSocket? { i < sockets.count ? sockets[i] : nil }
    var connects: Int { sockets.count }
  }

  init(name: String, books: [DepthBook], script: [String: [VenueMessage]],
       snapshots: [Result<BookSnapshot, DepthSnapshotError>] = [], resubscribable: Bool = false) {
    self.name = name; self.books = books; self.script = script; self.resubscribable = resubscribable
    self.snapshots = Snapshots(snapshots.isEmpty ? [.failure(DepthSnapshotError(status: 404))] : snapshots)
  }

  func connect(candidate: Int) async throws -> any WSSocket {
    let n = await snapshots.connects
    let s = GateSocket(id: n + 1, url: streamURLs[0])
    await snapshots.add(s)
    return s
  }
  func decode(_ text: String) -> [VenueMessage] { script[text] ?? [] }
  func resubscribeMessages(venueID: String) -> [String]? {
    resubscribable ? ["unsubscribe \(venueID)", "subscribe \(venueID)"] : nil
  }
  func fetchSnapshot(venueID: String) async throws -> BookSnapshot { try await snapshots.next(venueID) }
}

private actor Frames {
  private(set) var all: [OrderFlowSnapshot] = []
  func add(_ f: OrderFlowSnapshot) { all.append(f) }
  var last: OrderFlowSnapshot? { all.last }
  var sawLoading: Bool { all.contains { $0.phase == .loading } }
}

/// 交给 `makeAdapters` 的簿记下来（验「没门槛的产品不订」）。
private actor Handed {
  private(set) var books: [DepthBook] = []
  func set(_ b: [DepthBook]) { books = b }
}

/// 测试拨的钟：`clock` 参数是同步闭包，用锁护着一个数。
private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var ms: Int64
  init(_ ms: Int64 = 1_700_000_000_000) { self.ms = ms }
  var now: Int64 { lock.withLock { ms } }
  func advance(_ delta: Int64) { lock.withLock { ms += delta } }
}

private func level(_ price: Double, _ quantity: Double) -> BookLevel { BookLevel(price: price, quantity: quantity) }

/// 买侧 1600 往下每 1 美元一档；1590 那档挂一堵 12 000 个币（约 1908 万美元）的墙。卖侧对称没墙。
private func deepSnapshot(last: Int64) -> BookSnapshot {
  var bids = (1...40).map { level(1_600 - Double($0), 150) }
  bids[9] = level(1_590, 12_000)
  let asks = (1...40).map { level(1_600 + Double($0), 150) }
  return BookSnapshot(lastUpdateID: last, requestedLevels: 1_000, bids: bids, asks: asks)
}

private func tempDir() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent("of-" + UUID().uuidString, isDirectory: true)
}

private let symbolKey = "binance/usd_m/ETHUSDT"

private let binancePerp = DepthBook(venue: OrderFlowVenue(
  exchange: "binance", label: "币安", product: .usdtPerp, instrument: "ETHUSDT", notional: .linear(multiplier: 1),
  sequenceModel: .previousFinalOverlap, snapshotInBand: false))
private let okxSpot = DepthBook(venue: OrderFlowVenue(
  exchange: "okx", label: "OKX", product: .spot, instrument: "ETH-USDT", notional: .linear(multiplier: 1),
  sequenceModel: .previousFinalExact, snapshotInBand: true))
private let okxCoin = DepthBook(venue: OrderFlowVenue(
  exchange: "okx", label: "OKX", product: .coinPerp, instrument: "ETH-USD-SWAP", notional: .inverse(contractUsd: 10),
  sequenceModel: .previousFinalExact, snapshotInBand: true))

private let eth = OrderFlowFacts(base: "ETH", asset: .crypto, tick: 0.01, turnover24h: 1e10)

/// 流内快照即就绪的 U 本位永续（OKX 那种）：非币标定用。
private let okxPerp = DepthBook(venue: OrderFlowVenue(
  exchange: "okx", label: "OKX", product: .usdtPerp, instrument: "SNDK-USDT-SWAP", notional: .linear(multiplier: 1),
  sequenceModel: .previousFinalExact, snapshotInBand: true))
/// 美股：步长照表 1。
private let sndk = OrderFlowFacts(base: "SNDK", asset: .equity, tick: 0.01)
/// `deepSnapshot` 中间价 ±1% 两侧的美元名义：买侧 1599…1584（1590 那档是墙），卖侧 1601…1616。
/// 0.03 × 26 521 500 ≈ 79.6 万 → round125 → 100 万。
private let deepSnapshotDepth: Double = {
  var d = 0.0
  for k in 1...16 {
    let bid = 1_600 - Double(k)
    d += bid * (bid == 1_590 ? 12_000 : 150) + (1_600 + Double(k)) * 150
  }
  return d
}()

/// 服务端历史假件：记下每一次问的区间，按脚本回一页（nil = 服务端不通）。
private actor HistoryServer {
  struct Call: Equatable { var base: String; var from: Int64; var to: Int64 }
  private(set) var calls: [Call] = []
  let reply: @Sendable (Call) -> OrderFlowHistoryPage?
  init(reply: @escaping @Sendable (Call) -> OrderFlowHistoryPage?) { self.reply = reply }
  func load(_ base: String, _ from: Int64, _ to: Int64) -> OrderFlowHistoryPage? {
    let call = Call(base: base, from: from, to: to)
    calls.append(call)
    return reply(call)
  }
  var count: Int { calls.count }
}

/// 服务端那一页：ETH 的默认门槛与步长（每个币的价，步长 1），从 3 天前开始跟（服务端只存 3 天）。
private func historyPage(_ call: HistoryServer.Call, orders: [BigOrder], step: Double = 1) -> OrderFlowHistoryPage {
  OrderFlowHistoryPage(base: call.base,
                       thresholds: OrderFlowThresholds(spot: 1e6, usdtPerp: 5e6, coinPerp: 5e6, delivery: 5e6, step: step),
                       trackedSinceMs: call.to - 3 * 86_400_000, fromMs: call.from, toMs: call.to, orders: orders)
}

// MARK: - OrderFlowFeed

@Suite("主力订单流 · 数据层")
struct OrderFlowFeedTests {
  private func makeFeed(_ adapters: [ScriptAdapter], facts: OrderFlowFacts = eth, override: OrderFlowOverride? = nil,
                        dir: URL?, frames: Frames, handed: Handed = Handed(),
                        close: Double? = 1_250, clock: TestClock? = nil,
                        history: OrderFlowFeed.HistoryLoader? = nil) -> OrderFlowFeed {
    let books = adapters.flatMap(\.books)
    return OrderFlowFeed(
      symbol: symbolKey, facts: facts, override: override, directory: dir,
      loadBooks: { base in
        OrderFlowCatalog.Books(base: base, chartScale: 1, books: books, fromCatalog: true)
      },
      makeAdapters: { wanted in
        Task { await handed.set(wanted) }
        let ids = Set(wanted.map(\.id))
        return adapters.filter { a in a.books.contains { ids.contains($0.id) } }
      },
      loadClose: { _ in close },
      loadHistory: history ?? { _, _, _ in nil },
      clock: { @Sendable in clock?.now ?? Int64(Date().timeIntervalSince1970 * 1000) },
      evaluateEveryMs: 10,
      sink: { await frames.add($0) })
  }

  @Test("出帧去重（审查 31）：画面没变不发；只是金额变了隔 5 秒发一次，十字线停着就逐拍发")
  func emitOnlyWhenPixelsChange() {
    let order = BigOrder(venueID: "binance:usdtPerp:ETHUSDT", exchange: "币安", product: .usdtPerp, side: .ask,
                         bucket: 3, price: 2_000, firstSeenMs: 1, initialNotional: 3_000_000, notional: 3_000_000,
                         threshold: 1_000_000)
    let last = OrderFlowSnapshot(symbol: symbolKey, phase: .ready, orders: [order], asOfMs: 1)
    var same = last; same.asOfMs = 501
    var jitter = same; jitter.orders[0].notional += 20_000
    var grew = same; grew.orders[0].notional += 500_000
    #expect(OrderFlowFeed.skip(same, after: last, sinceLastMs: 500, precise: true))
    #expect(OrderFlowFeed.skip(jitter, after: last, sinceLastMs: 500, precise: false))
    #expect(!OrderFlowFeed.skip(jitter, after: last, sinceLastMs: OrderFlowFeed.amountRefreshMs, precise: false))
    #expect(!OrderFlowFeed.skip(jitter, after: last, sinceLastMs: 500, precise: true))
    #expect(!OrderFlowFeed.skip(grew, after: last, sinceLastMs: 500, precise: false))
  }

  @Test("两家两条连接：REST 快照那本与流内快照那本各自就绪，墙各出一条；停时日志落盘，再开读回来",
        .timeLimit(.minutes(1)))
  func twoVenues() async throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let binance = ScriptAdapter(
      name: "binance", books: [binancePerp],
      script: ["d1": [VenueMessage(binancePerp.id, .delta(BookDelta(firstUpdateID: 95, finalUpdateID: 101,
                                                                    previousFinalUpdateID: 94)))]],
      snapshots: [.success(deepSnapshot(last: 100))])
    let okx = ScriptAdapter(name: "okx", books: [okxSpot],
                            script: ["snap": [VenueMessage(okxSpot.id, .snapshot(deepSnapshot(last: 100)))]])
    let frames = Frames()
    let feed = makeFeed([binance, okx], dir: dir, frames: frames)
    await feed.start()
    #expect(await waitUntil(5) { await binance.snapshots.connects == 1 })
    #expect(await waitUntil(5) { await okx.snapshots.connects == 1 })
    #expect(await waitUntil(5) { await binance.snapshots.calls == [binancePerp.id] })
    await binance.snapshots.socket(0)?.push(.text("d1"))
    await okx.snapshots.socket(0)?.push(.text("snap"))
    #expect(await waitUntil(5) { await frames.last?.orders.count == 2 })
    let last = try #require(await frames.last)
    #expect(last.symbol == symbolKey)
    #expect(Set(last.orders.map(\.venueID)) == [binancePerp.id, okxSpot.id])
    #expect(last.orders.allSatisfy { $0.side == .bid && $0.price == 1_590 && $0.isLive })
    #expect(last.orders.first { $0.product == .spot }?.threshold == 1_000_000)
    #expect(last.orders.first { $0.product == .usdtPerp }?.threshold == 5_000_000)
    // OKX 流内快照：不拉 REST。
    #expect(await okx.snapshots.calls.isEmpty)
    // 帧按产生的先后送到（审查第 40 项：原来一帧一个 Task，先后不保证）。
    let stamps = await frames.all.map(\.asOfMs)
    #expect(stamps == stamps.sorted())

    // 切走马上切回：旧的这条还在停（日志还没落盘），新的一条已经建好。
    // 新的在 init 里不读日志，`start(after:)` 等旧的停完才读，读到的是旧的最后落的那份（审查第 40 项）。
    let stopping = Task { await feed.stop() }
    let again = makeFeed([], dir: dir, frames: Frames())
    #expect(await again.modelForTests().orders.isEmpty)
    await again.start(after: stopping)
    let file = OrderFlowFeed.journalFile(in: dir, symbol: symbolKey)
    let saved = try #require(OrderFlowJournal.decode(try Data(contentsOf: file)))
    #expect(saved.orders.count == 2)
    #expect(saved.step == 1)
    #expect(await again.modelForTests().orders.map(\.id).sorted() == saved.orders.map(\.id).sorted())
    await again.stop()
  }

  @Test("流内快照断档、这家不会单本重订（Coinbase 那种整条连接一个序号）：整条连接重拨，新快照到了照常；挂着的单不因为重连被判结束", .timeLimit(.minutes(1)))
  func resubscribe() async throws {
    let okx = ScriptAdapter(
      name: "okx", books: [okxSpot],
      script: ["snap": [VenueMessage(okxSpot.id, .snapshot(deepSnapshot(last: 100)))],
               "gap": [VenueMessage(okxSpot.id, .reset)]])
    let frames = Frames()
    let feed = makeFeed([okx], dir: nil, frames: frames)
    await feed.start()
    #expect(await waitUntil(5) { await okx.snapshots.connects == 1 })
    await okx.snapshots.socket(0)?.push(.text("snap"))
    #expect(await waitUntil(5) { await frames.last?.orders.count == 1 })
    await okx.snapshots.socket(0)?.push(.text("gap"))
    #expect(await waitUntil(5) { await okx.snapshots.connects == 2 })
    await okx.snapshots.socket(1)?.push(.text("snap"))
    try await Task.sleep(for: .milliseconds(100))
    let last = try #require(await frames.last)
    #expect(last.orders.count == 1)
    #expect(last.orders.first?.isLive == true)
    await feed.stop()
  }

  @Test("流内快照断档、这家能单本重订（OKX）：只退订再订断的那本，不重拨；同连接的另一本照常", .timeLimit(.minutes(1)))
  func resubscribeOneBookInPlace() async throws {
    let okx = ScriptAdapter(
      name: "okx", books: [okxSpot, okxCoin],
      script: ["snap": [VenueMessage(okxSpot.id, .snapshot(deepSnapshot(last: 100)))],
               "coin": [VenueMessage(okxCoin.id, .snapshot(deepSnapshot(last: 100)))],
               "gap": [VenueMessage(okxSpot.id, .reset)]],
      resubscribable: true)
    let frames = Frames()
    let feed = makeFeed([okx], dir: nil, frames: frames)
    await feed.start()
    #expect(await waitUntil(5) { await okx.snapshots.connects == 1 })
    let socket = try #require(await okx.snapshots.socket(0))
    await socket.push(.text("snap"))
    await socket.push(.text("coin"))
    #expect(await waitUntil(5) { await frames.last?.venues.filter(\.ready).count == 2 })
    await socket.push(.text("gap"))
    #expect(await waitUntil(5) { await socket.sent.suffix(2) == ["unsubscribe \(okxSpot.id)", "subscribe \(okxSpot.id)"] })
    // 断的那本在等新快照，另一本一直就绪；连接没动。
    #expect(await waitUntil(5) { await frames.last?.venues.first { $0.instrument == "ETH-USDT" }?.ready == false })
    #expect(await frames.last?.venues.first { $0.instrument == "ETH-USD-SWAP" }?.ready == true)
    #expect(await okx.snapshots.connects == 1)
    #expect(await socket.cancelCalls == 0)
    await socket.push(.text("snap"))
    #expect(await waitUntil(5) { await frames.last?.venues.filter(\.ready).count == 2 })
    #expect(await okx.snapshots.connects == 1)
    await feed.stop()
  }

  @Test("单本重订发出去 10 秒还没等到新快照（订阅被吞了）：那条连接整条重拨兜底", .timeLimit(.minutes(1)))
  func staleResubscribeEscalates() async throws {
    let okx = ScriptAdapter(
      name: "okx", books: [okxSpot],
      script: ["snap": [VenueMessage(okxSpot.id, .snapshot(deepSnapshot(last: 100)))],
               "gap": [VenueMessage(okxSpot.id, .reset)]],
      resubscribable: true)
    let clock = TestClock()
    let feed = makeFeed([okx], dir: nil, frames: Frames(), clock: clock)
    await feed.start()
    #expect(await waitUntil(5) { await okx.snapshots.connects == 1 })
    let socket = try #require(await okx.snapshots.socket(0))
    await socket.push(.text("snap"))
    await socket.push(.text("gap"))
    #expect(await waitUntil(5) { await socket.sent.last == "subscribe \(okxSpot.id)" })
    clock.advance(OrderFlowFeed.resubscribeTimeoutMs - 1_000)
    try await Task.sleep(for: .milliseconds(100))
    #expect(await okx.snapshots.connects == 1)
    clock.advance(2_000)
    #expect(await waitUntil(5) { await okx.snapshots.connects == 2 })
    await feed.stop()
  }

  @Test("压测 · 流内快照那家首次订阅没回快照（被吞了）：连上 15 秒单本重订一次，快照到了照常就绪；不到 15 秒不动", .timeLimit(.minutes(1)))
  func silentFirstSubscribeIsNudgedOnce() async throws {
    let okx = ScriptAdapter(
      name: "okx", books: [okxSpot, okxCoin],
      script: ["snap": [VenueMessage(okxSpot.id, .snapshot(deepSnapshot(last: 100)))],
               "coin": [VenueMessage(okxCoin.id, .snapshot(deepSnapshot(last: 100)))]],
      resubscribable: true)
    let clock = TestClock()
    let frames = Frames()
    let feed = makeFeed([okx], dir: nil, frames: frames, clock: clock)
    await feed.start()
    #expect(await waitUntil(5) { await okx.snapshots.connects == 1 })
    let socket = try #require(await okx.snapshots.socket(0))
    await socket.push(.text("coin"))
    #expect(await waitUntil(5) { await frames.last?.venues.filter(\.ready).count == 1 })
    clock.advance(OrderFlowFeed.firstSnapshotTimeoutMs - 1_000)
    #expect(await staysFalse(for: 0.2) { await socket.sent.isEmpty == false })
    clock.advance(2_000)
    #expect(await waitUntil(5) { await socket.sent == ["unsubscribe \(okxSpot.id)", "subscribe \(okxSpot.id)"] },
            "只重订没回快照的那本，就绪的那本不动")
    #expect(await staysFalse(for: 0.2) { await socket.sent.count > 2 }, "一条连接只催一次")
    await socket.push(.text("snap"))
    #expect(await waitUntil(5) { await frames.last?.venues.filter(\.ready).count == 2 })
    #expect(await okx.snapshots.connects == 1)
    #expect(await socket.cancelCalls == 0)
    await feed.stop()
  }

  @Test("压测 · 交易所那头已经没了的品种（订阅永远不回快照）：催 3 次（每次单本重订 → 10 秒后整条重拨）就停，不再无限重拨", .timeLimit(.minutes(1)))
  func deadInstrumentStopsAfterThreeNudges() async throws {
    let okx = ScriptAdapter(name: "okx", books: [okxSpot], script: [:], resubscribable: true)
    let clock = TestClock()
    let feed = makeFeed([okx], dir: nil, frames: Frames(), clock: clock)
    await feed.start()
    // 钟边等边拨（每次轮询拨 0.5 秒）：不依赖数据层什么时候处理到 `.connected`。
    for round in 1...OrderFlowFeed.maxFirstSnapshotNudges {
      #expect(await waitUntil(5) { await okx.snapshots.connects == round })
      let socket = try #require(await okx.snapshots.socket(round - 1))
      #expect(await waitUntil(5) { clock.advance(500); return await socket.sent.last == "subscribe \(okxSpot.id)" },
              "第 \(round) 次：连上 15 秒没快照，单本重订")
      #expect(await waitUntil(5) { clock.advance(500); return await okx.snapshots.connects == round + 1 },
              "第 \(round) 次：重订 10 秒还没快照，整条重拨")
    }
    let rounds = OrderFlowFeed.maxFirstSnapshotNudges
    let last = try #require(await okx.snapshots.socket(rounds))
    // 再拨 10 分钟虚拟时间。
    for _ in 0..<60 {
      clock.advance(10_000)
      try await Task.sleep(for: .milliseconds(20))
    }
    let connects = await okx.snapshots.connects
    let sent = await last.sent
    #expect(connects == rounds + 1, "催满 \(rounds) 次之后不再重拨，实际拨了 \(connects) 次")
    #expect(sent.isEmpty, "催满之后新连接上也不再重订")
    await feed.stop()
  }

  @Test("快照 503 按 Retry-After 再拉一次；4xx 就不再重试", .timeLimit(.minutes(1)))
  func snapshotRetry() async throws {
    let delta = BookDelta(firstUpdateID: 95, finalUpdateID: 101, previousFinalUpdateID: 94)
    let adapter = ScriptAdapter(
      name: "binance", books: [binancePerp], script: ["d1": [VenueMessage(binancePerp.id, .delta(delta))]],
      snapshots: [.failure(DepthSnapshotError(status: 503, retryAfterMs: 20)), .success(deepSnapshot(last: 100))])
    let frames = Frames()
    let feed = makeFeed([adapter], dir: nil, frames: frames)
    await feed.start()
    #expect(await waitUntil(5) { await adapter.snapshots.connects == 1 })
    await adapter.snapshots.socket(0)?.push(.text("d1"))
    #expect(await waitUntil(5) { await frames.last?.orders.count == 1 })
    #expect(await adapter.snapshots.calls.count == 2)
    await feed.stop()

    let refused = ScriptAdapter(name: "binance", books: [binancePerp], script: [:],
                                snapshots: [.failure(DepthSnapshotError(status: 400))])
    let quiet = makeFeed([refused], dir: nil, frames: Frames())
    await quiet.start()
    #expect(await waitUntil(5) { await refused.snapshots.calls.count == 1 })
    #expect(await staysFalse(for: 0.2) { await refused.snapshots.calls.count > 1 })
    await quiet.stop()
  }

  @Test("用户把门槛抬过墙：那条立刻不再是大单；放回默认又按正常确认出现", .timeLimit(.minutes(1)))
  func overrideTakesEffect() async throws {
    let okx = ScriptAdapter(name: "okx", books: [okxSpot],
                            script: ["snap": [VenueMessage(okxSpot.id, .snapshot(deepSnapshot(last: 100)))]])
    let frames = Frames()
    let feed = makeFeed([okx], dir: nil, frames: frames)
    await feed.start()
    #expect(await waitUntil(5) { await okx.snapshots.connects == 1 })
    await okx.snapshots.socket(0)?.push(.text("snap"))
    #expect(await waitUntil(5) { await frames.last?.orders.count == 1 })
    await feed.setOverride(OrderFlowOverride(spot: 50_000_000))
    #expect(await waitUntil(5) { await frames.last?.orders.isEmpty == true })
    #expect(await frames.last?.thresholds.spot == 50_000_000)
    await feed.setOverride(nil)
    #expect(await waitUntil(5) { await frames.last?.orders.count == 1 })
    #expect(await frames.last?.thresholds.spot == 1_000_000)
    await feed.stop()
  }

  @Test("非币只订 U 本位永续：别的产品的簿不交给连接", .timeLimit(.minutes(1)))
  func tradfiOnlyPerp() async throws {
    let handed = Handed()
    let perp = ScriptAdapter(name: "binance", books: [binancePerp], script: [:])
    let spot = ScriptAdapter(name: "okx", books: [okxSpot, okxCoin], script: [:])
    let feed = makeFeed([perp, spot], facts: OrderFlowFacts(base: "AAPL", asset: .equity, tick: 0.01),
                        dir: nil, frames: Frames(), handed: handed)
    await feed.start()
    #expect(await waitUntil(5) { await handed.books.map(\.id) == [binancePerp.id] })
    await feed.stop()
  }

  @Test("非币默认门槛按簿深标定：簿都到齐就算；标定之前不评估、不读回日志、不取服务端历史；日志里兜底 200 万以下、标定门槛以上的单不被删",
        .timeLimit(.minutes(1)))
  func calibratesNonCryptoDefault() async throws {
    #expect(OrderFlowDefaults.calibratedThreshold(depth: deepSnapshotDepth) == 1_000_000)
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    // 真钟：墙的出现确认要两拍相隔 ≥ 300 ms。
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    // 日志里一单 150 万（兜底 200 万下会被删，标定 100 万下留着），24 小时以内结束的。
    let saved = BigOrder(venueID: okxPerp.id, exchange: "OKX", product: .usdtPerp, side: .ask, bucket: 1_650,
                         price: 1_650, firstSeenMs: now - 3_600_000, endMs: now - 1_800_000,
                         status: .cancelled, initialNotional: 1_500_000, notional: 1_500_000, threshold: 2_000_000)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try OrderFlowJournal(symbol: symbolKey, step: 1, savedAtMs: now, orders: [saved]).encoded()
      .write(to: OrderFlowFeed.journalFile(in: dir, symbol: symbolKey))
    let server = HistoryServer { _ in nil }
    let okx = ScriptAdapter(name: "okx", books: [okxPerp],
                            script: ["snap": [VenueMessage(okxPerp.id, .snapshot(deepSnapshot(last: 100)))]])
    let frames = Frames()
    let feed = makeFeed([okx], facts: sndk, dir: dir, frames: frames, history: { await server.load($0, $1, $2) })
    await feed.start()
    #expect(await waitUntil(5) { await okx.snapshots.connects == 1 })
    try await Task.sleep(for: .milliseconds(100))
    #expect(await feed.calibratedForTests().pending)
    #expect(await server.count == 0, "标定之前不取服务端历史")
    #expect(await feed.modelForTests().orders.isEmpty, "标定之前不读回日志")
    #expect(await frames.last?.phase == .loading)
    await okx.snapshots.socket(0)?.push(.text("snap"))
    #expect(await waitUntil(5) { await frames.last?.thresholds.usdtPerp == 1_000_000 })
    #expect(await feed.calibratedForTests().value == 1_000_000)
    #expect(await frames.last?.defaults == OrderFlowThresholds(usdtPerp: 1_000_000, step: 1), "面板的默认门槛是标定值")
    #expect(await waitUntil(5) { await frames.last?.orders.contains { $0.id == saved.id } == true })
    #expect(await waitUntil(5) { await frames.last?.orders.contains { $0.isLive && $0.price == 1_590 } == true })
    #expect(await waitUntil(5) { await server.count >= 1 }, "标定完才取服务端历史")
    // 用户改过的优先；默认仍是标定值。
    await feed.setOverride(OrderFlowOverride(usdtPerp: 3_000_000))
    #expect(await waitUntil(5) { await frames.last?.thresholds.usdtPerp == 3_000_000 })
    #expect(await frames.last?.defaults.usdtPerp == 1_000_000)
    await feed.stop()
  }

  @Test("非币标定到点：8 秒时有一本到了就按已有的算；一本都没到用兜底 200 万", .timeLimit(.minutes(1)))
  func calibrationTimesOut() async throws {
    // 一本到了、一本永远拉不到快照（REST 404）。
    let clock = TestClock()
    let okx = ScriptAdapter(name: "okx", books: [okxPerp],
                            script: ["snap": [VenueMessage(okxPerp.id, .snapshot(deepSnapshot(last: 100)))]])
    let stuck = ScriptAdapter(name: "binance", books: [binancePerp], script: [:])
    let frames = Frames()
    let feed = makeFeed([okx, stuck], facts: sndk, dir: nil, frames: frames, clock: clock)
    await feed.start()
    #expect(await waitUntil(5) { await okx.snapshots.connects == 1 })
    await okx.snapshots.socket(0)?.push(.text("snap"))
    try await Task.sleep(for: .milliseconds(200))
    #expect(await feed.calibratedForTests().pending, "还有一本没到，没到点就接着等")
    clock.advance(OrderFlowDefaults.calibrationTimeoutMs)
    #expect(await waitUntil(5) { await feed.calibratedForTests().pending == false })
    #expect(await feed.calibratedForTests().value == 1_000_000)
    #expect(await waitUntil(5) { await frames.last?.thresholds.usdtPerp == 1_000_000 })
    await feed.stop()

    // 一本都没到：兜底。
    let clock2 = TestClock()
    let frames2 = Frames()
    let none = makeFeed([ScriptAdapter(name: "binance", books: [binancePerp], script: [:])], facts: sndk, dir: nil,
                        frames: frames2, clock: clock2)
    await none.start()
    try await Task.sleep(for: .milliseconds(200))
    #expect(await none.calibratedForTests().pending)
    clock2.advance(OrderFlowDefaults.calibrationTimeoutMs)
    #expect(await waitUntil(5) { await none.calibratedForTests().pending == false })
    #expect(await none.calibratedForTests().value == nil)
    #expect(await waitUntil(5) { await frames2.last?.thresholds.usdtPerp == 2_000_000 })
    #expect(await frames2.last?.defaults.usdtPerp == 2_000_000)
    await none.stop()
  }

  @Test("币与固定表里的品种不等标定")
  func cryptoDoesNotCalibrate() async throws {
    let feed = makeFeed([], dir: nil, frames: Frames())
    #expect(await feed.calibratedForTests().pending == false)
    let btcLike = makeFeed([], facts: OrderFlowFacts(base: "BTC", asset: .equity), dir: nil, frames: Frames())
    #expect(await btcLike.calibratedForTests().pending == false)
  }

  @Test("门槛与步长：默认表 → 用户改过的项 → 没步长按前一日收盘推")
  func effectiveThresholds() async throws {
    let btc = OrderFlowFacts(base: "BTC", asset: .crypto)
    #expect(OrderFlowFeed.effective(facts: btc, turnover: nil, override: nil, derivedStep: nil)
      == OrderFlowThresholds(spot: 1_000_000, usdtPerp: 5_000_000, coinPerp: 5_000_000, delivery: 5_000_000, step: 100))
    let mine = OrderFlowFeed.effective(facts: btc, turnover: nil,
                                       override: OrderFlowOverride(usdtPerp: 8_000_000, step: 50), derivedStep: 7)
    #expect(mine.usdtPerp == 8_000_000 && mine.step == 50 && mine.spot == 1_000_000)
    let doge = OrderFlowFacts(base: "DOGE", asset: .crypto, tick: 0.00001)
    let d = OrderFlowFeed.effective(facts: doge, turnover: 3e9, override: nil, derivedStep: 0.0002)
    #expect(d.usdtPerp == 2_500_000 && d.spot == 750_000 && d.step == 0.0002)
    // 带缩放前缀的按去掉前缀的币名存用户改过的项。
    #expect(OrderFlowFacts(base: "1000PEPE", asset: .crypto).overrideKey == "PEPE")

    // 表里没有步长的币：前一日收盘 1250 × 0.1% → 1（不小于 tick）。
    let frames = Frames()
    let okx = ScriptAdapter(name: "okx", books: [okxSpot], script: [:])
    let feed = makeFeed([okx], facts: OrderFlowFacts(base: "XYZ", asset: .crypto, tick: 0.01, turnover24h: 1e10),
                        dir: nil, frames: frames)
    await feed.start()
    #expect(await waitUntil(5) { await frames.last?.thresholds.step == 1 })
    // 审查 30：帧里带「叠用户改过的项之前」的默认——按成交额分过档（app 自己查表只落到第三档），
    // 按收盘推的步长不算默认；用户改了门槛，默认不跟着变。
    let top = OrderFlowDefaults.thresholds(base: "XYZ", asset: .crypto, turnover24h: 1e10)
    #expect(top != OrderFlowDefaults.thresholds(base: "XYZ", asset: .crypto, turnover24h: nil))
    #expect(await frames.last?.defaults == top)
    await feed.setOverride(OrderFlowOverride(spot: 900_000_000))
    #expect(await waitUntil(5) { await frames.last?.thresholds.spot == 900_000_000 })
    #expect(await frames.last?.defaults == top)
    await feed.stop()
  }

  @Test("服务端历史：读完日志就取最近 24 小时并进来；每分钟取增量（从上一页最晚时刻退 5 分钟）；图往左拖出去就 24 小时一段往前补，补到够为止",
        .timeLimit(.minutes(1)))
  func serverHistory() async throws {
    let clock = TestClock()
    let t0 = clock.now
    let hour: Int64 = 3_600_000, day: Int64 = 86_400_000
    let ended = BigOrder(venueID: binancePerp.id, exchange: "币安", product: .usdtPerp, side: .bid, bucket: 0,
                         price: 1_500, firstSeenMs: t0 - 3 * hour, endMs: t0 - 2 * hour, status: .cancelled,
                         initialNotional: 8e6, notional: 8e6, threshold: 5e6)
    let live = BigOrder(venueID: binancePerp.id, exchange: "币安", product: .usdtPerp, side: .ask, bucket: 0,
                        price: 1_700, firstSeenMs: t0 - hour, initialNotional: 6e6, notional: 6e6, threshold: 5e6)
    // 首次那一页（到 t0）有两单；之后的增量、往前补的各段都是空的。
    let server = HistoryServer { call in historyPage(call, orders: call.to == t0 && call.from == t0 - day ? [ended, live] : []) }
    let frames = Frames()
    let feed = makeFeed([], dir: nil, frames: frames, clock: clock, history: { await server.load($0, $1, $2) })
    await feed.start()
    #expect(await waitUntil(5) { await frames.last?.orders.count == 2 })
    #expect(await server.calls.first == HistoryServer.Call(base: "ETH", from: t0 - day, to: t0))
    let orders = try #require(await frames.last?.orders)
    #expect(orders.map(\.firstSeenMs) == [t0 - 3 * hour, t0 - hour])
    #expect(orders.map(\.status) == [.cancelled, .live])
    #expect(orders.allSatisfy { $0.threshold == 5e6 })
    #expect(await server.count == 1)

    // 一分钟后取增量：从上一页最晚的时刻（挂着那单的出现时刻）往前退 5 分钟。
    clock.advance(OrderFlowFeed.historyEveryMs)
    #expect(await waitUntil(5) { await server.count == 2 })
    #expect(await server.calls.last == HistoryServer.Call(base: "ETH", from: t0 - hour - OrderFlowFeed.historyOverlapMs,
                                                         to: t0 + OrderFlowFeed.historyEveryMs))
    // 服务端这一页没再提那单挂着的：本机没有这本簿、又没人续命，3 分钟后才按失联结束——这一拍它还在。
    #expect(await frames.last?.orders.count == 2)

    // 图往左拖到 60 小时前：往前补两段（24–48 小时前、48 小时前到 3 天前），补到 3 天（留存上限）就停。
    // 此刻已经是 t0 + 1 分钟，3 天的底是 t0 + 1 分钟 − 3 天。
    let now = t0 + OrderFlowFeed.historyEveryMs
    await feed.setVisibleWindow(fromMs: t0 - 60 * hour, toMs: t0 - 40 * hour)
    #expect(await waitUntil(5) { await server.count == 4 })
    let calls = await server.calls
    #expect(calls[2] == HistoryServer.Call(base: "ETH", from: t0 - 2 * day, to: t0 - day))
    #expect(calls[3] == HistoryServer.Call(base: "ETH", from: now - OrderFlowDefaults.retentionMs, to: t0 - 2 * day))
    // 再往左拖也不取 3 天以前的。
    await feed.setVisibleWindow(fromMs: t0 - 5 * day, toMs: t0 - 4 * day)
    try await Task.sleep(for: .milliseconds(200))
    #expect(await server.count == 4)
    #expect(await feed.historyRangeForTests().from == now - OrderFlowDefaults.retentionMs)
    await feed.stop()
  }

  @Test("服务端不通：纯本地照常出单、不报错；首次那一页隔 10 秒再试。步长和服务端对不上（用户改过步长）：不并、也不再取",
        .timeLimit(.minutes(1)))
  func serverHistoryOfflineAndIncompatible() async throws {
    let clock = TestClock()
    let offline = HistoryServer { _ in nil }
    let okx = ScriptAdapter(name: "okx", books: [okxSpot],
                            script: ["snap": [VenueMessage(okxSpot.id, .snapshot(deepSnapshot(last: 100)))]])
    let frames = Frames()
    let feed = makeFeed([okx], dir: nil, frames: frames, clock: clock, history: { await offline.load($0, $1, $2) })
    await feed.start()
    #expect(await waitUntil(5) { await offline.count == 1 })
    #expect(await waitUntil(5) { await okx.snapshots.connects == 1 })
    await okx.snapshots.socket(0)?.push(.text("snap"))
    // 出现要连着两次评估、相隔 ≥ 300 ms：这里的钟是手拨的，簿就绪后拨过去。
    #expect(await waitUntil(5) { await frames.last?.venues.first?.ready == true })
    try await Task.sleep(for: .milliseconds(50))
    clock.advance(400)
    #expect(await waitUntil(5) { await frames.last?.orders.count == 1 })
    #expect(await frames.last?.phase == .ready)
    try await Task.sleep(for: .milliseconds(100))
    #expect(await offline.count == 1)
    clock.advance(10_000)
    #expect(await waitUntil(5) { await offline.count == 2 })
    #expect(await frames.last?.orders.count == 1)
    await feed.stop()

    // 用户把步长改成 2：服务端按 1 分的桶对不上，那一页不并；之后到点也不再取。
    let t0 = clock.now
    let foreign = BigOrder(venueID: binancePerp.id, exchange: "币安", product: .usdtPerp, side: .bid, bucket: 0,
                           price: 1_500, firstSeenMs: t0 - 600_000, endMs: t0 - 300_000, status: .cancelled,
                           initialNotional: 8e6, notional: 8e6, threshold: 5e6)
    let server = HistoryServer { call in historyPage(call, orders: [foreign]) }
    let frames2 = Frames()
    let custom = makeFeed([], override: OrderFlowOverride(step: 2), dir: nil, frames: frames2, clock: clock,
                          history: { await server.load($0, $1, $2) })
    await custom.start()
    #expect(await waitUntil(5) { await server.count == 1 })
    #expect(await waitUntil(5) { await frames2.last?.thresholds.step == 2 })
    try await Task.sleep(for: .milliseconds(100))
    #expect(await custom.modelForTests().orders.isEmpty)
    clock.advance(2 * OrderFlowFeed.historyEveryMs)
    try await Task.sleep(for: .milliseconds(200))
    #expect(await server.count == 1)
    await custom.stop()
  }

  @Test("清目录：24 小时没动的日志和旧版标定子目录删掉，新的留下")
  func sweep() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let fm = FileManager.default
    try fm.createDirectory(at: dir.appendingPathComponent("binance-um"), withIntermediateDirectories: true)
    let fresh = dir.appendingPathComponent("a.json"), stale = dir.appendingPathComponent("b.json")
    try Data("{}".utf8).write(to: fresh)
    try Data("{}".utf8).write(to: stale)
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(now - 90_000_000) / 1000)],
                         ofItemAtPath: stale.path)
    OrderFlowFeed.sweep(directory: dir, nowMs: now)
    let left = try fm.contentsOfDirectory(atPath: dir.path)
    #expect(left == ["a.json"])
  }
}

// MARK: - 路由接线

/// 记下每一次拨号的地址；K 线那条先吐一帧真 K 线（线路择优要认），深度那条挂着。
private actor DialLog {
  private(set) var urls: [String] = []
  func add(_ u: URL) { urls.append(u.absoluteString) }
  /// 这只的深度流拨了几次（合约组合流、现货组合流都算）。
  func depthDials(_ symbol: String) -> Int { urls.filter { $0.contains("\(symbol)@depth@100ms") }.count }
  /// 现货那条（data-stream.binance.vision）拨了几次。
  func spotDials(_ symbol: String) -> Int {
    urls.filter { $0.contains("data-stream.binance.vision") && $0.contains("\(symbol)@depth@100ms") }.count
  }
}

private struct DialFactory: WSSocketFactory {
  let log: DialLog
  func connect(to url: URL) async throws -> WSSocket {
    await log.add(url)
    let s = GateSocket(id: 0, url: url)
    if !url.absoluteString.contains("@depth@100ms") {
      let first = (url.query ?? "").split(separator: "/").first.map(String.init)?
        .replacingOccurrences(of: "streams=", with: "") ?? "btcusdt@kline_1m"
      await s.push(.text(Self.kline(stream: first)))
    }
    return s
  }
  static let lastOpen: Int64 = 1_700_000_000_000
  static func kline(stream: String) -> String {
    let symbol = stream.split(separator: "@").first.map(String.init)?.uppercased() ?? "BTCUSDT"
    let t = lastOpen
    return """
    {"stream":"\(stream)","data":{"e":"kline","E":\(t + 1),"s":"\(symbol)",\
    "k":{"t":\(t),"T":\(t + 59_999),"s":"\(symbol)","i":"1m","f":1,"L":2,\
    "o":"1","c":"1","h":"1","l":"1","v":"1","n":1,"x":false,"q":"1","V":"1","Q":"1","B":"0"}}}
    """
  }
  static func klines(_ count: Int) -> HTTPReply {
    let rows = (0..<count).map { i -> String in
      let t = lastOpen - Int64(count - 1 - i) * 60_000
      return "[\(t),\"1\",\"1\",\"1\",\"1\",\"1\",\(t + 59_999),\"1\",1,\"1\",\"1\",\"0\"]"
    }
    return json("[" + rows.joined(separator: ",") + "]")
  }
}

/// K 线历史挂在闸门上，放行之前界面拿不到 ≥ 3 根。
private struct HeldTransport: HTTPTransport {
  let inner: FakeTransport
  let gate: Gate
  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    if url.path.contains("klines") { await gate.wait() }
    return try await inner.get(url, timeout: timeout)
  }
}

private actor RoutedSeen {
  private(set) var series = 0
  private(set) var flow: [OrderFlowSnapshot?] = []
  func noteSeries() { series += 1 }
  func add(_ f: OrderFlowSnapshot?) { flow.append(f) }
  var lastFlow: OrderFlowSnapshot?? { flow.last }
}

@Suite("主力订单流 · 路由接线")
struct OrderFlowRoutingTests {
  @Test("K 线交给界面之前不订簿；换品种先清再订新的；关开关就退订", .timeLimit(.minutes(1)))
  func subscribesAfterFirstFrame() async throws {
    let hold = Gate()
    let server = FakeServer { url in
      if url.path.contains("klines") {
        let limit = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 300
        return DialFactory.klines(min(limit, 300))
      }
      if url.path.contains("depth") { return json(#"{"lastUpdateId":1,"bids":[],"asks":[]}"#) }
      return json(#"{"symbol":"X","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
    }
    let dials = DialLog()
    let hosts = BinanceHosts(oiProxy: "gw.test")
    let transport = HeldTransport(inner: FakeTransport(server), gate: hold)
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let routed = RoutedMarketFeed(
      hosts: hosts, paths: Paths(root: root), log: .silent,
      primary: BinanceREST(hosts: hosts, transport: transport, limiter: RateLimiter()),
      backup: BinanceREST(hosts: hosts, transport: transport, limiter: RateLimiter()),
      sockets: DialFactory(log: dials), http: transport, policy: .direct)
    await routed.setSnapshotEnabled(false)
    // 网关品种表在假服务器上拿不到：走保底那几本（币安 U 本位永续、币安现货、Coinbase 现货）。
    let facts: @Sendable (String) -> OrderFlowFacts? = { key in
      OrderFlowFacts(base: QuoteAssets.base(of: InstrumentID(key).symbol), asset: .crypto, tick: 0.01, turnover24h: 1e10)
    }
    await routed.setOrderFlow(enabled: true, facts: facts)

    let seen = RoutedSeen()
    let events = await routed.events()
    let collector = Task {
      for await update in events {
        if case .series(let s) = update.event, s.count >= 3 { await seen.noteSeries() }
        if case .orderFlow(let f) = update.event { await seen.add(f) }
      }
    }
    defer { collector.cancel() }

    await routed.start(symbol: "ETHUSDT", interval: .m1)
    // K 线推送已经连上，历史还挂着：簿一概不订。
    #expect(await waitUntil(5) { await dials.urls.contains { $0.contains("ethusdt@kline_1m") } })
    // 历史请求已经挂在闸门上：在它放行之前，没有任何东西能让界面拿到 ≥ 3 根，所以不用拿睡眠去等「确实没订」。
    #expect(await waitUntil(5) { await hold.arrived > 0 })
    #expect(await dials.depthDials("ethusdt") == 0)
    #expect(await seen.flow.isEmpty)

    await hold.open()
    #expect(await waitUntil(5) { await seen.series > 0 })
    #expect(await waitUntil(5) { await dials.depthDials("ethusdt") == 2 })
    #expect(await dials.spotDials("ethusdt") == 1)
    #expect(await waitUntil(5) { await seen.flow.first??.phase == .loading })

    // 换品种：先发一帧 nil 清掉，新品种的 K 线到了再订它的簿。
    let before = await seen.flow.count
    await routed.switchTo(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(5) { await seen.flow.dropFirst(before).contains { $0 == nil } })
    #expect(await waitUntil(5) { await dials.depthDials("btcusdt") == 2 })
    #expect(await waitUntil(5) { await seen.lastFlow??.symbol == "binance/usd_m/BTCUSDT" })

    // 关开关：退订并清图。
    await routed.setOrderFlow(enabled: false, facts: facts)
    #expect(await waitUntil(5) { await seen.lastFlow == .some(nil) })

    // 开关带序号（审查第 40 项）：界面每次调用各起一个 Task，先发的那次可能后到——按序号丢掉。
    // 旧的那次（关，序号 4）要是被照办了，会多一帧 nil、之后开（序号 6）又重订一遍。
    await routed.setOrderFlow(enabled: true, facts: facts, sequence: 5)
    #expect(await waitUntil(5) { await dials.depthDials("btcusdt") == 4 })
    let mark = await seen.flow.count
    await routed.setOrderFlow(enabled: false, facts: facts, sequence: 4)
    await routed.setOrderFlow(enabled: true, facts: facts, sequence: 6)
    await routed.setOrderFlow(enabled: false, facts: facts, sequence: 7)
    #expect(await waitUntil(5) { await seen.lastFlow == .some(nil) })
    #expect(await seen.flow.dropFirst(mark).filter { $0 == nil }.count == 1)
    #expect(await dials.depthDials("btcusdt") == 4)
    await routed.stop()
  }
}

extension OrderFlowFeedTests {
  @Test("刚建好连接任务就 stop（F10）：停了之后不许留一条活连接", .timeLimit(.minutes(1)))
  func stopRightAfterSetUpLeavesNoLiveSocket() async throws {
    for _ in 0..<20 {
      let adapter = ScriptAdapter(name: "binance", books: [binancePerp], script: [:])
      let handed = Handed()
      let feed = makeFeed([adapter], dir: nil, frames: Frames(), handed: handed)
      await feed.start()
      // `setUp` 已经把连接任务排上了（适配器交出去了），这一刻就停。
      #expect(await waitUntil(5) { await !handed.books.isEmpty })
      await feed.stop()
      // 给可能晚起跑的连接任务一点时间：它要么根本不拨号，要么拨了也立刻被掐掉。
      try await Task.sleep(nanoseconds: 30_000_000)
      let n = await adapter.snapshots.connects
      for i in 0..<n {
        let socket = try #require(await adapter.snapshots.socket(i))
        #expect(await socket.closed, "stop 之后第 \(i + 1) 条连接还活着")
      }
    }
  }
}

extension OrderFlowFeedTests {
  @Test("可视范围 / 用户改项带序号（P2-4）：先发的那次后到，按序号丢掉")
  func staleViewAndOverrideAreDropped() async {
    let adapter = ScriptAdapter(name: "binance", books: [binancePerp], script: [:])
    let feed = makeFeed([adapter], dir: nil, frames: Frames())
    await feed.setVisibleWindow(fromMs: 2_000_000, toMs: 3_000_000, sequence: 2)
    await feed.setVisibleWindow(fromMs: 1_000_000, toMs: 3_000_000, sequence: 1)
    #expect(await feed.visibleWindowStartForTesting == 2_000_000, "序号 1 比已收下的 2 旧，不认")
    await feed.setVisibleWindow(fromMs: 2_500_000, toMs: 3_000_000, sequence: 3)
    #expect(await feed.visibleWindowStartForTesting == 2_500_000)

    let newer = OrderFlowOverride(usdtPerp: 9_000_000), older = OrderFlowOverride(usdtPerp: 7_000_000)
    await feed.setOverride(newer, sequence: 5)
    await feed.setOverride(older, sequence: 4)
    #expect(await feed.overrideForTesting == newer.normalized)
    await feed.stop()
  }

  @Test("路由那一格的可视范围也按序号丢旧的（P2-4）")
  func slotDropsStaleView() {
    var slot = OrderFlowSlot()
    slot.setView(symbol: "BTCUSDT", fromMs: 2_000, toMs: 5_000, current: "BTCUSDT", sequence: 2)
    slot.setView(symbol: "BTCUSDT", fromMs: 1_000, toMs: 5_000, current: "BTCUSDT", sequence: 1)
    #expect(slot.view?.from == 2_000)
    #expect(slot.viewSequence == 2)
    // 不带序号的老调用照旧直接收。
    slot.setView(symbol: "BTCUSDT", fromMs: 1_500, toMs: 5_000, current: "BTCUSDT")
    #expect(slot.view?.from == 1_500)
  }
}
