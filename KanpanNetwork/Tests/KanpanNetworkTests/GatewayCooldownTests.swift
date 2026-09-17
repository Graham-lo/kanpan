import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

@Suite("网关冷却：听 Retry-After")
struct GatewayCooldownTests {

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
}
