import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

// 「行情线路」两档：直连 / 网关，出厂默认直连，没有「自动」。
// 用户真机自己的网络能直连币安，但原来的自动探测偶发失败就把整套切到 OKX 且卡很久；
// 这套用例守的是「他选了哪条就走哪条，代码不许再自作主张」。

// 线路策略的存取与 REST/WS 传输层用例在 `KanpanNetwork` 包里；这里只守整条路由：
// `RoutedMarketFeed` 拿到策略之后，到底叫起了哪条线路。
@Suite("行情线路：整条路由")
struct RoutedFeedPolicyTests {

  // ---------------------------------------------------------------- 整条路由

  /// WS 一律连不上：这套用例只看 REST 的线路决策，别让 socket 掺和进来。
  private struct DeadSockets: WSSocketFactory {
    func connect(to url: URL) async throws -> WSSocket { throw FeedError.badResponse("测试：WS 不可用") }
  }

  private struct Rig {
    let dir: URL
    let hosts: BinanceHosts
    let binance: FakeServer
    let okx: FakeServer

    init() {
      dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      hosts = BinanceHosts(oiProxy: "gw.test")
      // 两条线路都答 500：只看「哪条线路被叫起来了」，答什么不重要。
      binance = FakeServer { _ in json("{}", status: 500) }
      okx = FakeServer { _ in json("{}", status: 500) }
    }

    func feed(_ policy: MarketRoutePolicy) -> RoutedMarketFeed {
      RoutedMarketFeed(
        hosts: hosts, paths: Paths(root: dir), log: .silent,
        primary: BinanceREST(hosts: hosts, transport: FakeTransport(binance), limiter: RateLimiter()),
        backup: BinanceREST(hosts: hosts, transport: FakeTransport(okx), limiter: RateLimiter()),
        sockets: DeadSockets(), policy: policy)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: dir) }
  }

  @Test("直连：币安探测失败也不切 OKX，照实说「点此重试」", .timeLimit(.minutes(1)))
  func directNeverSwitchesToOKX() async throws {
    let rig = Rig()
    defer { rig.cleanUp() }

    let feed = rig.feed(.direct)
    let events = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)

    var sawUnavailable = false
    var sawOKX = false
    for await update in events {
      if case .provider(let caps) = update.event, caps.upstream == "okx" { sawOKX = true }
      if case .historyError(let message) = update.event, message == "暂时无法连接，点此重试" {
        sawUnavailable = true
        break
      }
    }
    await feed.stop()

    #expect(sawUnavailable)      // 照实说「点此重试」，而不是偷偷换线路
    #expect(!sawOKX)
    #expect(await rig.okx.urls().isEmpty)   // OKX 那条线路一笔都没发出去
  }

  @Test("网关：开机就走 OKX 那条线路，币安一笔都不碰", .timeLimit(.minutes(1)))
  func gatewayStartsOnOKX() async throws {
    let rig = Rig()
    defer { rig.cleanUp() }

    let feed = rig.feed(.gateway)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    let onOKX = await waitUntil(20) { await !rig.okx.urls().isEmpty }
    await feed.stop()

    #expect(onOKX)
    #expect(await rig.binance.urls().isEmpty)
  }

  @Test("运行中换档：直连 → 网关，线路立刻换到 OKX", .timeLimit(.minutes(1)))
  func switchingRouteMovesExchangeAtOnce() async throws {
    let rig = Rig()
    defer { rig.cleanUp() }

    let feed = rig.feed(.direct)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(20) { await !rig.binance.urls().isEmpty })
    #expect(await rig.okx.urls().isEmpty)

    await feed.setRoutePolicy(.gateway)
    let moved = await waitUntil(20) { await !rig.okx.urls().isEmpty }
    await feed.stop()
    #expect(moved)
  }

  @Test("运行中换档：Coinbase 直连 → 网关，上游没变也要换到 kanpan-api 透传口", .timeLimit(.minutes(1)))
  func coinbaseSwitchingRouteMovesToGateway() async throws {
    // Coinbase 两条线路的上游都是 coinbase。原来 feed 的身份只看「交易所|上游」，
    // 切到网关之后以为「供数的没变」就不重起，直连那份 feed 原样接着打 coinbase.com。
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    // 两条线路都答得好好的：直连一切正常时没有报错、没有探测，正是真机上漏网的那条路
    // （答 500 的话，出错后的健康探测会顺手打到新线路上，把这个毛病盖住）。
    let server = FakeServer { url in
      guard url.path.hasSuffix("/candles") else { return json("{}") }
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      func q(_ k: String) -> Int64? { items.first { $0.name == k }?.value.flatMap { Int64($0) } }
      guard let start = q("start"), let end = q("end"), end >= start else { return json(#"{"candles":[]}"#) }
      let rows = stride(from: end - end % 60, through: start, by: -60).prefix(349).map {
        #"{"start":"\#($0)","low":"1","high":"2","open":"1","close":"2","volume":"1"}"#
      }
      return json(#"{"candles":[\#(rows.joined(separator: ","))]}"#)
    }
    let endpoints = MarketEndpoints(gateways: ["gw.test"])
    let feed = RoutedMarketFeed(paths: Paths(root: dir), policy: .direct) { _, policy in
      CoinbaseProvider(policy: policy, endpoints: endpoints,
                       transport: FakeTransport(server), sockets: DeadSockets())
    }
    _ = await feed.events()
    await feed.start(symbol: "coinbase/spot/BTC-USD", interval: .m1)
    #expect(await waitUntil(20) { await server.urls().contains { $0.host == "api.coinbase.com" } })
    #expect(await !server.urls().contains { $0.host == "gw.test" })

    await feed.setRoutePolicy(.gateway)
    let moved = await waitUntil(20) {
      await server.urls().contains { $0.host == "gw.test" && $0.path.hasPrefix("/v1/market/raw/") }
    }
    await feed.stop()
    #expect(moved)
  }
}
