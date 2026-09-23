import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 板块品种列表的 K 线预热（Lane D · D4）：单独一个槽位，只热前十行，
// 不许把自选那一轮掐掉，离开列表时掐得掉自己。
@Suite("板块列表预热：独立槽位、只热前十行")
struct ListPrefetchTests {
  private static let step: Int64 = 60_000

  private static func klines() -> HTTPReply {
    let last: Int64 = 1_700_000_000_000
    let rows = (0..<300).map { i -> String in
      let t = last - Int64(299 - i) * step
      return "[\(t),\"1\",\"1\",\"1\",\"1\",\"1\",\(t + step - 1),\"1\",1,\"1\",\"1\",\"0\"]"
    }
    return json("[" + rows.joined(separator: ",") + "]")
  }

  private func make() -> (RoutedMarketFeed, FakeServer, Paths) {
    let server = FakeServer { url in
      url.path.contains("klines") ? ListPrefetchTests.klines() : json("[]")
    }
    let hosts = BinanceHosts()
    let paths = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let feed = RoutedMarketFeed(
      hosts: hosts, paths: paths, log: .silent,
      primary: BinanceREST(hosts: hosts, transport: FakeTransport(server), limiter: RateLimiter()),
      backup: BinanceREST(hosts: hosts, transport: FakeTransport(server), limiter: RateLimiter()),
      sockets: GateSocketBench(), policy: .direct)
    return (feed, server, paths)
  }

  private func requested(_ server: FakeServer) async -> Set<String> {
    Set(await server.urls().filter { $0.path.contains("klines") }.compactMap {
      URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "symbol" }?.value
    })
  }

  @Test("只热前十行（去重），每一份都落进快照目录", .timeLimit(.minutes(1)))
  func warmsTopTenOnly() async {
    let (feed, server, paths) = make()
    let names = (0..<14).map { "L\($0)USDT" }
    await feed.prefetchList(symbols: [names[0]] + names, interval: .m15)
    #expect(await waitUntil(5) { await requested(server).count >= 10 })
    #expect(await staysFalse(for: 0.6) { await requested(server).count > 10 })
    #expect(await requested(server) == Set(names.prefix(RoutedMarketFeed.listPrefetchLimit)))
    for name in names.prefix(10) {
      #expect(SeriesStore.read(symbol: InstrumentID.canonical(name), interval: .m15, in: paths.series) != nil)
    }
    await feed.stop()
  }

  @Test("跟自选预热各占一个槽：谁也不掐谁", .timeLimit(.minutes(1)))
  func doesNotCancelFavorites() async {
    let (feed, server, _) = make()
    await feed.prefetch(symbols: ["FAVAUSDT", "FAVBUSDT"], interval: .m15)
    await feed.prefetchList(symbols: ["LISTAUSDT", "LISTBUSDT"], interval: .m15)
    // 自选那一轮延迟 1.2 秒才开始；列表那轮 0.4 秒。两轮都得跑完。
    #expect(await waitUntil(8) { await requested(server).count >= 4 })
    #expect(await requested(server) == ["FAVAUSDT", "FAVBUSDT", "LISTAUSDT", "LISTBUSDT"])
    await feed.stop()
  }

  @Test("离开列表就掐掉还没开始的那几份", .timeLimit(.minutes(1)))
  func cancelStopsPending() async {
    let (feed, server, _) = make()
    await feed.prefetchList(symbols: ["LISTAUSDT", "LISTBUSDT"], interval: .m15)
    await feed.cancelListPrefetch()
    #expect(await staysFalse(for: 1.0) { await !requested(server).isEmpty })
    await feed.stop()
  }

  @Test("关掉快照：排队的预热不再拉，跑着的也不会把快照写回盘上", .timeLimit(.minutes(1)))
  func disablingSnapshotsStopsPrefetch() async {
    let (feed, server, paths) = make()
    // 列表那一轮延迟 0.4 秒；行情页邻居那一轮立刻开跑（可能已经发出请求）。
    await feed.prefetchList(symbols: ["LISTAUSDT", "LISTBUSDT"], interval: .m15)
    await feed.prewarm(symbols: ["NEXTAUSDT", "NEXTBUSDT"], interval: .m15, slot: "scan")
    await feed.setSnapshotEnabled(false)
    #expect(await staysFalse(for: 1.0) {
      await requested(server).contains { $0.hasPrefix("LIST") }
    })
    for name in ["LISTAUSDT", "LISTBUSDT", "NEXTAUSDT", "NEXTBUSDT"] {
      #expect(SeriesStore.read(symbol: name, interval: .m15, in: paths.series) == nil,
              "\(name) 在快照关掉之后又被写回了盘上")
    }
    await feed.stop()
  }
}
