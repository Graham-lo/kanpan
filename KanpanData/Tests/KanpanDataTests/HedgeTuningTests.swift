import Foundation
import Testing
@testable import KanpanData

@Suite("对冲与超时：分档、快速失败、听 Retry-After")
struct HedgeTuningTests {

  // ---------------------------------------------------------------- 超时分档

  @Test("大请求给 8 秒，小请求还是 3 秒")
  func tieredDirectTimeout() {
    func url(_ s: String) -> URL { URL(string: s)! }
    let big = url("https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=1500")
    let quick = url("https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=300")
    let info = url("https://fapi.binance.com/fapi/v1/exchangeInfo")
    let ticker = url("https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=BTCUSDT")

    #expect(MarketRESTTransport.directTimeout(for: big) == 8)
    #expect(MarketRESTTransport.directTimeout(for: info) == 8)
    #expect(MarketRESTTransport.directTimeout(for: quick) == 3)
    #expect(MarketRESTTransport.directTimeout(for: ticker) == 3)
    // 没写 limit 的 klines 按币安默认 500 算，还是小请求。
    #expect(MarketRESTTransport.directTimeout(for: url("https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m")) == 3)
  }

  // ---------------------------------------------------------------- 网关冷却

  @Test("429 / 503 听网关自己报的 Retry-After，封顶 10 秒")
  func gatewayCooldownHonoursHeader() {
    #expect(MarketRESTTransport.gatewayCooldown(json("{}", status: 503, headers: ["Retry-After": "2"])) == 2)
    #expect(MarketRESTTransport.gatewayCooldown(json("{}", status: 429, headers: ["Retry-After": "1.5"])) == 1.5)
    // 报得比上限还长：按上限算，整条线路的退避不该由一台网关说了算。
    #expect(MarketRESTTransport.gatewayCooldown(json("{}", status: 429, headers: ["Retry-After": "600"])) == 10)
    // 没报、报得不合法、或者根本不是限流状态码：退回 10 秒。
    #expect(MarketRESTTransport.gatewayCooldown(json("{}", status: 503)) == 10)
    #expect(MarketRESTTransport.gatewayCooldown(json("{}", status: 429, headers: ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"])) == 10)
    #expect(MarketRESTTransport.gatewayCooldown(json("{}", status: 500, headers: ["Retry-After": "2"])) == 10)
  }

  // ---------------------------------------------------------------- 快速失败

  /// 直连一发就报错（DNS 解不开 / 连接被拒都是这个形状），网关正常。
  private actor FailFastDirect: HTTPTransport {
    var hosts: [String] = []
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      hosts.append(url.host!)
      if url.host == "fapi.binance.com" { throw URLError(.cannotFindHost) }
      return json(#"{"source":"binance","symbol":"BTCUSDT","interval":"1m","bars":[]}"#)
    }
  }

  @Test("直连快速失败时网关立刻跟上，不等满 0.7 秒")
  func failFastStartsGatewayImmediately() async throws {
    let network = FailFastDirect()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gateway.test"], transport: network)
    let url = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=300")!

    let began = Date()
    _ = try await transport.get(url, timeout: 10)
    let elapsed = -began.timeIntervalSinceNow

    #expect(await network.hosts == ["fapi.binance.com", "gateway.test"])
    // 旧实现里网关那一腿雷打不动先睡 hedgeDelay = 0.7s。
    #expect(elapsed < 0.3)
  }
}
