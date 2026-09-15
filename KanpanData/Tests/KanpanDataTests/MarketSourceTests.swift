import Foundation
import Testing
@testable import KanpanData

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
    let transport = MarketRESTTransport(source: .binance, gateways: ["gateway.test"], transport: network)
    await #expect(throws: CancellationError.self) { try await transport.get(url, timeout: 10) }
    _ = try await transport.get(url, timeout: 10)
    #expect(await network.hosts == ["fapi.binance.com", "fapi.binance.com"])
  }
  @Test func oneTimeoutCannotDisableDirectAccessForOtherSymbols() async throws {
    let network = CancelFirst(.timedOut)
    let transport = MarketRESTTransport(source: .binance, gateways: [], transport: network)
    await #expect(throws: (any Error).self) { try await transport.get(url, timeout: 10) }
    let next = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=ETHUSDT&interval=1m&limit=3")!
    _ = try await transport.get(next, timeout: 10)
    #expect(await network.hosts == ["fapi.binance.com", "fapi.binance.com"])
  }
  @Test func blockedBinanceUsesOnlyBinanceGateway() async throws {
    let server = FakeServer { url in
      if url.host == "fapi.binance.com" { return json("{}", status: 451) }
      return json(#"{"source":"binance","symbol":"BTCUSDT","interval":"1m","bars":[]}"#)
    }
    let transport = MarketRESTTransport(source: .binance, gateways: ["gateway.test"], transport: FakeTransport(server))
    _ = try await transport.get(url, timeout: 10)
    let urls = await server.urls()
    #expect(urls.count == 2)
    #expect(urls.last?.query?.contains("source=binance") == true)
  }
  @Test func rejectsWrongSourceAndRange() async throws {
    for body in [#"{"source":"binance","symbol":"BTCUSDT","interval":"1m","bars":[]}"#, #"{"source":"okx","symbol":"ETHUSDT","interval":"1m","bars":[]}"#] {
      let server = FakeServer { _ in json(body) }
      let transport = MarketRESTTransport(source: .okx, gateways: ["gateway.test"], transport: FakeTransport(server))
      await #expect(throws: (any Error).self) { try await transport.get(url, timeout: 10) }
      #expect(await server.urls().count == 1)
    }
  }
  @Test func failedGatewayUsesBackupWithSameSource() async throws {
    let server = FakeServer { url in
      if url.host == "one.test" { return json("{}", status: 503) }
      return json(#"{"source":"okx","symbol":"BTCUSDT","interval":"1m","bars":[]}"#)
    }
    let transport = MarketRESTTransport(source: .okx, gateways: ["one.test", "two.test:8443"], transport: FakeTransport(server))
    _ = try await transport.get(url, timeout: 10)
    _ = try await transport.get(url, timeout: 10)
    let urls = await server.urls()
    #expect(urls.map(\.host) == ["one.test", "two.test", "two.test"])
    #expect(urls.allSatisfy { $0.query?.contains("source=okx") == true })
    #expect(urls.last?.port == 8443)
  }
}
