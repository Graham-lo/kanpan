import Foundation
import Testing
import KanpanCore
@testable import KanpanNetwork
import KanpanNetworkTestSupport

@Suite("真实大额成交洞察接口")
struct OrderFlowInsightsNetworkTests {
  let valid = #"{"base":"BTC","generatedAtMs":1791424800000,"dayStartMs":1791388800000,"tracked":true,"coverageSinceMs":1791420000000,"lastTradeMs":null,"bigUsd":100000,"windows":[{"minutes":5,"sources":[]}],"zones":[]}"#
  @Test func routeAndMissingEndpoint() async throws {
    let server = FakeServer { _ in json(valid) }
    let page = try #require(await OrderFlowAdapterTests.catalog(.direct, server: server).insights(base: "BTC"))
    #expect(page.base == "BTC" && page.lastTradeMs == nil)
    #expect(await server.urls().map(\.absoluteString) == ["https://gw-a.example/v1/market/orderflow/insights?base=BTC"])
    let dead = FakeServer { _ in json("{}", status: 404) }
    #expect(await OrderFlowAdapterTests.catalog(.gateway, server: dead).insights(base: "BTC") == nil)
  }
  @Test func rejectWrongIdentityInvalidCoverageAndMalformedData() {
    #expect(OrderFlowCatalog.parseInsights(Data(valid.utf8), base: "ETH") == nil)
    #expect(OrderFlowCatalog.parseInsights(Data("oops".utf8), base: "BTC") == nil)
    let future = valid.replacingOccurrences(of: "1791420000000", with: "1791424800001")
    #expect(OrderFlowCatalog.parseInsights(Data(future.utf8), base: "BTC") == nil)
  }
}
