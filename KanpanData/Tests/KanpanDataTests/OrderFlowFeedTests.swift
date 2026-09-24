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
       snapshots: [Result<BookSnapshot, DepthSnapshotError>] = []) {
    self.name = name; self.books = books; self.script = script
    self.snapshots = Snapshots(snapshots.isEmpty ? [.failure(DepthSnapshotError(status: 404))] : snapshots)
  }

  func connect(candidate: Int) async throws -> any WSSocket {
    let n = await snapshots.connects
    let s = GateSocket(id: n + 1, url: streamURLs[0])
    await snapshots.add(s)
    return s
  }
  func decode(_ text: String) -> [VenueMessage] { script[text] ?? [] }
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

// MARK: - OrderFlowFeed

@Suite("主力订单流 · 数据层")
struct OrderFlowFeedTests {
  private func makeFeed(_ adapters: [ScriptAdapter], facts: OrderFlowFacts = eth, override: OrderFlowOverride? = nil,
                        dir: URL?, frames: Frames, handed: Handed = Handed(),
                        close: Double? = 1_250) -> OrderFlowFeed {
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
      loadClose: { _ in close }, evaluateEveryMs: 10,
      sink: { await frames.add($0) })
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
    await feed.stop()

    let file = OrderFlowFeed.journalFile(in: dir, symbol: symbolKey)
    let saved = try #require(OrderFlowJournal.decode(try Data(contentsOf: file)))
    #expect(saved.orders.count == 2)
    #expect(saved.step == 1)
    let again = makeFeed([binance, okx], dir: dir, frames: Frames())
    #expect(await again.modelForTests().orders.map(\.id).sorted() == saved.orders.map(\.id).sorted())
  }

  @Test("流内快照断档：整条连接重拨，新快照到了照常；挂着的单不因为重连被判结束", .timeLimit(.minutes(1)))
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
    await feed.stop()
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
      sockets: DialFactory(log: dials), policy: .direct)
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
    try await Task.sleep(for: .milliseconds(300))
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
    await routed.stop()
  }
}
