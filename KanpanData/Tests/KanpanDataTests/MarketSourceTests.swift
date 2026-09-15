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
  actor TimeoutThenGateway: HTTPTransport {
    var hosts: [String] = []
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      hosts.append(url.host!)
      if hosts.count == 1 { throw URLError(.timedOut) }
      return json(#"{"source":"binance","symbol":"BTCUSDT","interval":"1m","bars":[]}"#)
    }
  }
  actor RacingGateways: HTTPTransport {
    var hosts: [String] = []
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      hosts.append(url.host!)
      if url.host == "one.test" { try await Task.sleep(for: .milliseconds(800)) }
      return json(#"{"source":"okx","symbol":"BTCUSDT","interval":"1m","bars":[]}"#)
    }
  }
  @Test func cancelledSelectionDoesNotPoisonHealthyDirectRoute() async throws {
    let network = CancelFirst()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gateway.test"], transport: network)
    await #expect(throws: CancellationError.self) { try await transport.get(url, timeout: 10) }
    _ = try await transport.get(url, timeout: 10)
    #expect(await network.hosts == ["fapi.binance.com", "fapi.binance.com"])
  }
  @Test func timeoutEntersCooldownAndDoesNotRepeatDirectAttempt() async throws {
    let network = CancelFirst(.timedOut)
    let transport = MarketRESTTransport(source: .binance, gateways: [], transport: network)
    await #expect(throws: (any Error).self) { try await transport.get(url, timeout: 10) }
    let next = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=ETHUSDT&interval=1m&limit=3")!
    await #expect(throws: (any Error).self) { try await transport.get(next, timeout: 10) }
    #expect(await network.hosts == ["fapi.binance.com"])
  }
  @Test func timeoutFallsBackAndNextRequestReusesGateway() async throws {
    let network = TimeoutThenGateway()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gateway.test"], transport: network)
    _ = try await transport.get(url, timeout: 10)
    _ = try await transport.get(url, timeout: 10)
    #expect(await network.hosts == ["fapi.binance.com", "gateway.test", "gateway.test"])
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
    #expect(Set(urls.map(\.host)) == ["one.test", "two.test"])
    #expect(urls.last?.host == "two.test")
    #expect(urls.allSatisfy { $0.query?.contains("source=okx") == true })
    #expect(urls.last?.port == 8443)
  }
  @Test func gatewaysRaceSoFastBackupAvoidsSlowPrimary() async throws {
    let network = RacingGateways()
    let transport = MarketRESTTransport(source: .okx,
      gateways: ["one.test", "two.test"], transport: network)
    let began = Date()
    _ = try await transport.get(url, timeout: 10)
    let elapsed = Date().timeIntervalSince(began)
    #expect(elapsed < 0.5)
    #expect(Set(await network.hosts) == ["one.test", "two.test"])
  }
}
