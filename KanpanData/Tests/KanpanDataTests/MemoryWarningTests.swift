import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 内存警告（压测 2026-09-26 第 9 项）：整条路由的 K 线缓存只留当前那一对，
// 还在路上的预热（行情页各槽、板块列表、自选、换周期）一并叫停，不许在清完之后又把缓存灌回去；
// 路由正在换 feed（`feed` 还是空的）那一拍来的警告也得清。只数份数，不量墙钟。

/// K 线请求里带着这些代号的，挂在闸上等测试放行——模拟「清缓存那一刻预热还在路上」。
private struct HeldTransport: HTTPTransport {
  let server: FakeServer
  let gate: Gate
  let held: Set<String>
  /// 过了闸、拿到回复的几笔。
  let released = Counter()
  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    if url.path.contains("klines"),
       let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "symbol" })?.value,
       held.contains(name) {
      await gate.wait()
      defer { released.bump() }
      return await server.serve(url)
    }
    return await server.serve(url)
  }
}

@Suite("内存警告：整条路由的 K 线缓存与预热槽一起放")
struct MemoryWarningTests {
  private static let step: Int64 = 3_600_000

  /// 300 根 1h，最后一根就是此刻这一小时（够新，当前品种不会去翻页补缺）。
  private static func klines() -> HTTPReply {
    let last = (Int64(Date().timeIntervalSince1970 * 1000) / step) * step
    let rows = (0..<300).map { i -> String in
      let t = last - Int64(299 - i) * step
      return "[\(t),\"1\",\"1\",\"1\",\"1\",\"1\",\(t + step - 1),\"1\",1,\"1\",\"1\",\"0\"]"
    }
    return json("[" + rows.joined(separator: ",") + "]")
  }

  private static let held: Set<String> = ["H1USDT", "H2USDT", "H3USDT", "H4USDT", "H5USDT", "L1USDT", "L2USDT", "L3USDT"]

  private func make() -> (RoutedMarketFeed, Gate, Paths, Counter) {
    let server = FakeServer { url in url.path.contains("klines") ? MemoryWarningTests.klines() : json("[]") }
    let gate = Gate()
    let transport = HeldTransport(server: server, gate: gate, held: Self.held)
    let hosts = BinanceHosts()
    let paths = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let feed = RoutedMarketFeed(
      hosts: hosts, paths: paths, log: .silent,
      primary: BinanceREST(hosts: hosts, transport: transport, limiter: RateLimiter()),
      backup: BinanceREST(hosts: hosts, transport: transport, limiter: RateLimiter()),
      sockets: GateSocketBench(), http: FakeTransport(server), policy: .direct)
    return (feed, gate, paths, transport.released)
  }

  @Test("路上的预热在清完之后不许把缓存灌回去；只留当前那一对，预热槽全空", .timeLimit(.minutes(1)))
  func inFlightWarmupsDoNotRefill() async throws {
    let (feed, gate, paths, released) = make()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let current = SeriesKey("BTCUSDT", .h1)
    await feed.start(symbol: "BTCUSDT", interval: .h1)
    #expect(await waitUntil(5) { await feed.cacheKeysForTests().contains(current) })

    // 先热三份别的（放行的），缓存里就有 4 对。
    await feed.prewarm(symbols: ["W1USDT", "W2USDT", "W3USDT"], interval: .h1, slot: "seed")
    #expect(await waitUntil(5) { await feed.cacheKeysForTests().count >= 4 })

    // 再起三个槽，每个槽第一份都卡在闸上：扫图邻居、「看细节」、板块列表。
    await feed.prewarm(symbols: ["H1USDT", "H2USDT", "H3USDT"], interval: .h1, slot: "neighbors")
    await feed.prewarm(symbols: ["H4USDT", "H5USDT"], interval: .h1, slot: "detail")
    await feed.prefetchList(symbols: ["L1USDT", "L2USDT", "L3USDT"], interval: .h1)
    #expect(await waitUntil(5) { await gate.waiting >= 3 })
    let before = await feed.cacheKeysForTests().count
    let slotsBefore = await feed.warmSlotsForTests

    await feed.memoryWarning()
    let right = await feed.cacheKeysForTests().count
    let slots = await feed.warmSlotsForTests

    // 放行：路上那几份回来了。原来它们照样落盘、照样塞回内存缓存，后面排着的也接着拉。
    await gate.open()
    // 等卡着的那三笔真的回来（回来之后原来的代码会接着塞缓存、接着拉下一份），再看一小会儿。
    #expect(await waitUntil(5) { released.value >= 3 })
    _ = await staysFalse(for: 0.5) { await feed.cacheKeysForTests().count >= 1 + Self.held.count }
    let settled = await feed.cacheKeysForTests()
    print("[memory-warning] 警告前缓存 \(before) 对、预热槽 \(slotsBefore) 个；警告后当下 \(right) 对、槽 \(slots) 个；路上的预热回来之后 \(settled.count) 对")

    #expect(right == 1)
    #expect(slots == 0, "预热槽要全部叫停")
    #expect(settled == [current], "只留当前那一对，路上的预热不许灌回来")
    #expect(await staysFalse(for: 0.5) { await feed.cacheKeysForTests().count > 1 })

    // 叫停不是永久关掉：之后新起的预热照常进缓存。
    await feed.prewarm(symbols: ["W4USDT"], interval: .h1, slot: "seed")
    #expect(await waitUntil(5) { await feed.cacheKeysForTests().contains(SeriesKey("W4USDT", .h1)) })
    await feed.stop()
  }

  @Test("路由上还没挂 feed（首次起图前 / 换线路换 feed 的那一拍）来的警告也要清", .timeLimit(.minutes(1)))
  func warningWithoutFeed() async throws {
    let (feed, _, paths, _) = make()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    await feed.prewarm(symbols: ["W1USDT", "W2USDT", "W3USDT"], interval: .h1, slot: "seed")
    #expect(await waitUntil(5) { await feed.cacheKeysForTests().count >= 3 })
    await feed.memoryWarning()
    let left = await feed.cacheKeysForTests().count
    print("[memory-warning] 没挂 feed 时警告后缓存剩 \(left) 对")
    #expect(left == 0)
    await feed.stop()
  }
}
