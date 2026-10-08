import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

@Suite("行情来源隔离") struct MarketSourceTests {
  let url = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=3")!
  actor CancelFirst: HTTPTransport {
    let failure: URLError.Code
    init(_ failure: URLError.Code = .cancelled) { self.failure = failure }
    var calls = 0
    var hosts: [String] = []
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      calls += 1; hosts.append(url.host!)
      if calls == 1 { throw URLError(failure) }
      return json("[]")
    }
  }
  @Test func cancelledSelectionDoesNotPoisonHealthyDirectRoute() async throws {
    let network = CancelFirst()
    let transport = MarketRESTTransport(gateways: ["gateway.test"], transport: network)
    await #expect(throws: CancellationError.self) { try await transport.get(url, timeout: 10) }
    _ = try await transport.get(url, timeout: 10)
    #expect(await network.hosts == ["fapi.binance.com", "fapi.binance.com"])
  }
  /// 直连是用户定的：超时也不记冷却、也不退网关，下一笔照样直连。
  @Test func timeoutDoesNotCoolDownDirectRoute() async throws {
    let network = CancelFirst(.timedOut)
    let transport = MarketRESTTransport(gateways: ["gateway.test"], transport: network)
    await #expect(throws: (any Error).self) { try await transport.get(url, timeout: 10) }
    let next = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=ETHUSDT&interval=1m&limit=3")!
    _ = try await transport.get(next, timeout: 10)
    #expect(await network.hosts == ["fapi.binance.com", "fapi.binance.com"])
  }
  /// 网关档：币安地址原样改写成 kanpan-api 的透传，查询一个不少、末尾带 `source=binance`，一笔都不打币安本家。
  @Test func gatewayRouteRewritesToRawPassthrough() async throws {
    let server = FakeServer { url in
      if url.host == "fapi.binance.com" { return json("{}", status: 451) }
      return json("[]")
    }
    let transport = MarketRESTTransport(gateways: ["gateway.test"], transport: FakeTransport(server), policy: .gateway)
    _ = try await transport.get(url, timeout: 10)
    let urls = await server.urls()
    #expect(urls.count == 1)
    #expect(urls[0].host == "gateway.test")
    #expect(urls[0].path == "/v1/market/raw/fapi/v1/klines")
    #expect(urls[0].query == "symbol=BTCUSDT&interval=1m&limit=3&source=binance")
  }

  /// `futures/data/*` 与币本位 `dapi` 也在透传白名单里；归档站不在，网关档就没有路线，不偷偷直连。
  @Test func gatewayRawCoversFuturesDataAndDapiButNotArchives() async throws {
    let server = FakeServer { _ in json("[]") }
    let transport = MarketRESTTransport(gateways: ["gateway.test"], transport: FakeTransport(server), policy: .gateway)
    let oi = URL(string: "https://fapi.binance.com/futures/data/openInterestHist?symbol=BTCUSDT&period=5m&limit=500")!
    let cm = URL(string: "https://dapi.binance.com/dapi/v1/klines?symbol=BTCUSD_PERP&interval=1h&limit=10")!
    _ = try await transport.get(oi, timeout: 10)
    _ = try await transport.get(cm, timeout: 10)
    let archive = URL(string: "https://data.binance.vision/data/futures/um/daily/metrics/BTCUSDT/BTCUSDT-metrics-2026-10-01.zip")!
    await #expect(throws: FeedError.self) { _ = try await transport.get(archive, timeout: 10) }
    let ping = URL(string: "https://fapi.binance.com/fapi/v1/ping")!
    await #expect(throws: FeedError.self) { _ = try await transport.get(ping, timeout: 10) }
    let urls = await server.urls()
    #expect(urls.map(\.path) == ["/v1/market/raw/futures/data/openInterestHist", "/v1/market/raw/dapi/v1/klines"])
    #expect(urls.allSatisfy { $0.host == "gateway.test" && $0.query?.hasSuffix("&source=binance") == true })
  }

  /// 主机按顺序试：5xx、连不上换下一台（带端口的照样拼得出来）；4xx 是这一笔本身的问题，原样交回、不换主机。
  @Test func gatewayHostsAreTriedInOrder() async throws {
    let server = FakeServer { url in
      if url.host == "one.test" { return json(#"{"error":"upstream_unavailable"}"#, status: 502) }
      if url.query?.contains("symbol=NOPE") == true { return json(#"{"code":-1121,"msg":"Invalid symbol."}"#, status: 400) }
      return json("[]")
    }
    let transport = MarketRESTTransport(gateways: ["one.test", "two.test:8443"], transport: FakeTransport(server), policy: .gateway)
    let ok = try await transport.get(url, timeout: 10)
    #expect(ok.status == 200)
    var urls = await server.urls()
    #expect(urls.map(\.host) == ["one.test", "two.test"])
    #expect(urls.last?.port == 8443)

    let bad = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=NOPE&interval=1m&limit=3")!
    await server.setHandler { url in
      url.query?.contains("symbol=NOPE") == true ? json(#"{"code":-1121,"msg":"Invalid symbol."}"#, status: 400) : json("[]")
    }
    let reply = try await transport.get(bad, timeout: 10)
    #expect(reply.status == 400)
    urls = await server.urls()
    #expect(urls.count == 3)
    #expect(urls.last?.host == "one.test")
  }

  /// 每台都不行：最后那台的 5xx 原样交回（`BinanceREST` 据此报错），都连不上就抛传输层的错。
  @Test func gatewayAllDownSurfacesTheLastAnswer() async throws {
    let server = FakeServer { _ in json(#"{"error":"upstream_unavailable"}"#, status: 502) }
    let transport = MarketRESTTransport(gateways: ["one.test", "two.test"], transport: FakeTransport(server), policy: .gateway)
    let reply = try await transport.get(url, timeout: 10)
    #expect(reply.status == 502)
    #expect(await server.urls().count == 2)

    let dead = CancelFirst(.cannotConnectToHost)
    let offline = MarketRESTTransport(gateways: ["one.test"], transport: dead, policy: .gateway)
    await #expect(throws: URLError.self) { _ = try await offline.get(url, timeout: 10) }
  }
}
