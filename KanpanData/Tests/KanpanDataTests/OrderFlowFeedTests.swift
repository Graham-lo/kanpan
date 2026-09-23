import Foundation
import Testing
@testable import KanpanData
import KanpanCore
import KanpanNetwork
import KanpanNetworkTestSupport

// MARK: - 假件

/// 深度适配器假件：连接是 `GateSocket`，测试往里推「脚本名」，解码按脚本表翻成 `DepthMessage`。
private final class ScriptAdapter: DepthFeedAdapter, @unchecked Sendable {
  let upstream = "fake"
  let symbol: String
  let sequenceModel: DepthSequenceModel
  let snapshotInBand: Bool
  var streamURLs: [URL] { [URL(string: "wss://depth.test/\(symbol)")!] }
  let script: [String: [DepthMessage]]
  let snapshots: Snapshots

  actor Snapshots {
    var replies: [Result<BookSnapshot, DepthSnapshotError>]
    private(set) var calls = 0
    private(set) var sockets: [GateSocket] = []
    init(_ replies: [Result<BookSnapshot, DepthSnapshotError>]) { self.replies = replies }
    func next() throws -> BookSnapshot {
      calls += 1
      let reply = replies.count > 1 ? replies.removeFirst() : replies[0]
      return try reply.get()
    }
    func add(_ s: GateSocket) { sockets.append(s) }
    func socket(_ i: Int) -> GateSocket? { i < sockets.count ? sockets[i] : nil }
    var connects: Int { sockets.count }
  }

  init(symbol: String, sequenceModel: DepthSequenceModel, snapshotInBand: Bool,
       script: [String: [DepthMessage]], snapshots: [Result<BookSnapshot, DepthSnapshotError>] = []) {
    self.symbol = symbol; self.sequenceModel = sequenceModel; self.snapshotInBand = snapshotInBand
    self.script = script
    self.snapshots = Snapshots(snapshots.isEmpty ? [.failure(DepthSnapshotError(status: 404))] : snapshots)
  }

  func connect(candidate: Int) async throws -> any WSSocket {
    let n = await snapshots.connects
    let s = GateSocket(id: n + 1, url: streamURLs[0])
    await snapshots.add(s)
    return s
  }
  func decode(_ text: String) -> [DepthMessage] { script[text] ?? [] }
  func fetchSnapshot() async throws -> BookSnapshot { try await snapshots.next() }
}

private actor Frames {
  private(set) var all: [OrderFlowSnapshot] = []
  func add(_ f: OrderFlowSnapshot) { all.append(f) }
  var last: OrderFlowSnapshot? { all.last }
  var sawLoading: Bool { all.contains { $0.phase == .loading } }
}

private func level(_ price: Double, _ quantity: Double) -> BookLevel { BookLevel(price: price, quantity: quantity) }

/// 买侧 1600 往下每 1 美元一档；1590 那档挂一堵 12 000 个币的墙。卖侧对称没墙（与 Core 用例同一本簿）。
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

// MARK: - OrderFlowFeed

@Suite("主力订单流 · 数据层")
struct OrderFlowFeedTests {
  private func makeFeed(_ adapter: ScriptAdapter, dir: URL?, frames: Frames) -> OrderFlowFeed {
    OrderFlowFeed(symbol: symbolKey, adapter: adapter, tick: 1, directory: dir,
                  loadClose: { _ in 1_250 }, evaluateEveryMs: 10,
                  sink: { await frames.add($0) })
  }

  @Test("REST 快照这一路：连上就拉快照，与缓冲增量对上后吐出那堵墙；停时标定落盘", .timeLimit(.minutes(1)))
  func restPath() async throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let adapter = ScriptAdapter(
      symbol: symbolKey, sequenceModel: .previousFinalOverlap, snapshotInBand: false,
      script: ["d1": [.delta(BookDelta(firstUpdateID: 95, finalUpdateID: 101, previousFinalUpdateID: 94))]],
      snapshots: [.success(deepSnapshot(last: 100))])
    let frames = Frames()
    let feed = makeFeed(adapter, dir: dir, frames: frames)
    await feed.start()
    #expect(await waitUntil(5) { await adapter.snapshots.connects == 1 })
    #expect(await waitUntil(5) { await frames.sawLoading })
    #expect(await waitUntil(5) { await adapter.snapshots.calls == 1 })
    await adapter.snapshots.socket(0)?.push(.text("d1"))
    #expect(await waitUntil(5) { await frames.last?.phase == .ready })
    let last = try #require(await frames.last)
    #expect(last.symbol == symbolKey)
    #expect(last.orders.map(\.low) == [1_590])
    #expect(last.orders.first?.side == .bid)
    await feed.stop()
    let file = OrderFlowFeed.calibrationFile(in: dir, upstream: "fake", symbol: symbolKey)
    let saved = try #require(FloorCalibration(encoded: try Data(contentsOf: file)))
    #expect(!saved.samples(.bid).isEmpty)
    #expect(!saved.samples(.ask).isEmpty)
    // 再起一条：落盘的标定被读回来。
    let again = makeFeed(adapter, dir: dir, frames: Frames())
    #expect(await again.modelForTests().calibration.samples(.bid).count == saved.samples(.bid).count)
  }

  @Test("流内快照这一路：快照一到就就绪；断档要求重订，会重新拨号并回到拉快照中", .timeLimit(.minutes(1)))
  func inBandPath() async throws {
    let adapter = ScriptAdapter(
      symbol: symbolKey, sequenceModel: .previousFinalExact, snapshotInBand: true,
      script: ["early": [.delta(BookDelta(firstUpdateID: 7, finalUpdateID: 7, previousFinalUpdateID: 6))],
               "snap": [.snapshot(deepSnapshot(last: 100))],
               "gap": [.reset]])
    let frames = Frames()
    let feed = makeFeed(adapter, dir: nil, frames: frames)
    await feed.start()
    #expect(await waitUntil(5) { await adapter.snapshots.connects == 1 })
    let first = try #require(await adapter.snapshots.socket(0))
    await first.push(.text("early"))  // 快照前的增量直接丢，不拉 REST
    await first.push(.text("snap"))
    #expect(await waitUntil(5) { await frames.last?.orders.map(\.low) == [1_590] })
    #expect(await adapter.snapshots.calls == 0)
    await first.push(.text("gap"))
    #expect(await waitUntil(5) { await adapter.snapshots.connects == 2 })
    #expect(await waitUntil(5) { await frames.last?.phase == .loading })
    await adapter.snapshots.socket(1)?.push(.text("snap"))
    #expect(await waitUntil(5) { await frames.last?.phase == .ready })
    await feed.stop()
  }

  @Test("快照 503 按 Retry-After 再拉一次；4xx 就不再重试", .timeLimit(.minutes(1)))
  func snapshotRetry() async throws {
    let delta = BookDelta(firstUpdateID: 95, finalUpdateID: 101, previousFinalUpdateID: 94)
    let adapter = ScriptAdapter(
      symbol: symbolKey, sequenceModel: .previousFinalOverlap, snapshotInBand: false,
      script: ["d1": [.delta(delta)]],
      snapshots: [.failure(DepthSnapshotError(status: 503, retryAfterMs: 20)), .success(deepSnapshot(last: 100))])
    let frames = Frames()
    let feed = makeFeed(adapter, dir: nil, frames: frames)
    await feed.start()
    #expect(await waitUntil(5) { await adapter.snapshots.connects == 1 })
    await adapter.snapshots.socket(0)?.push(.text("d1"))
    #expect(await waitUntil(5) { await frames.last?.phase == .ready })
    #expect(await adapter.snapshots.calls == 2)
    await feed.stop()

    let refused = ScriptAdapter(symbol: symbolKey, sequenceModel: .previousFinalOverlap, snapshotInBand: false,
                                script: [:], snapshots: [.failure(DepthSnapshotError(status: 400))])
    let quiet = makeFeed(refused, dir: nil, frames: Frames())
    await quiet.start()
    #expect(await waitUntil(5) { await refused.snapshots.calls == 1 })
    try await Task.sleep(for: .milliseconds(200))
    #expect(await refused.snapshots.calls == 1)
    await quiet.stop()
  }

  @Test("桶宽兜底：没有 tick 时按价格量级取 10 的整数次幂")
  func guessTick() {
    #expect(OrderFlowFeed.guessTick(78_450) == 0.1)
    #expect(OrderFlowFeed.guessTick(1.25) == 0.00001)
  }
}

// MARK: - 路由接线

/// 记下每一次拨号的地址；K 线那条先吐一帧真 K 线（线路择优要认），深度那条挂着。
private actor DialLog {
  private(set) var urls: [String] = []
  func add(_ u: URL) { urls.append(u.absoluteString) }
  func depthDials(_ symbol: String) -> Int { urls.filter { $0.contains("\(symbol)@depth@100ms") }.count }
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
    await routed.setOrderFlow(enabled: true, tick: { _ in 0.01 })

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
    #expect(await waitUntil(5) { await dials.depthDials("ethusdt") == 1 })
    #expect(await waitUntil(5) { await seen.flow.first??.phase == .loading })

    // 换品种：先发一帧 nil 清掉，新品种的 K 线到了再订它的簿。
    let before = await seen.flow.count
    await routed.switchTo(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(5) { await seen.flow.dropFirst(before).contains { $0 == nil } })
    #expect(await waitUntil(5) { await dials.depthDials("btcusdt") == 1 })
    #expect(await waitUntil(5) { await seen.lastFlow??.symbol == "binance/usd_m/BTCUSDT" })

    // 关开关：退订并清图。
    await routed.setOrderFlow(enabled: false, tick: { _ in 0.01 })
    #expect(await waitUntil(5) { await seen.lastFlow == .some(nil) })
    await routed.stop()
  }
}
