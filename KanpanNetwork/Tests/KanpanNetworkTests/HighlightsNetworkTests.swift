import Foundation
import Testing
import KanpanCore
@testable import KanpanNetwork
import KanpanNetworkTestSupport

@Suite("要点引擎接口")
struct HighlightsNetworkTests {
  let page = #"{"base":"BTC","generatedAtMs":1791621612002,"tracked":true,"staleMs":null,"flow":{"rows":[{"w":"15m","netUsd":-7926786.0,"pxPct":-0.04,"oiPct":-0.07,"diverge":false}]},"range":null,"levels":[],"position":null,"events":[]}"#

  @Test func highlightsRouteAndIdentity() async throws {
    let server = FakeServer { _ in json(page) }
    let p = try #require(await OrderFlowAdapterTests.catalog(.direct, server: server).highlights(base: "BTC"))
    #expect(p.flow?.rows.first?.netUsd == -7_926_786)
    #expect(await server.urls().map(\.absoluteString) == ["https://gw-a.example/v1/market/orderflow/highlights?base=BTC"])
    #expect(OrderFlowCatalog.parseHighlights(Data(page.utf8), base: "ETH") == nil)
    #expect(OrderFlowCatalog.parseHighlights(Data("oops".utf8), base: "BTC") == nil)
    let dead = FakeServer { _ in json("{}", status: 404) }
    #expect(await OrderFlowAdapterTests.catalog(.gateway, server: dead).highlights(base: "BTC") == nil)
  }

  @Test func boardSendsDedupedValidBases() async throws {
    let server = FakeServer { _ in json(#"{"generatedAtMs":1,"rows":[]}"#) }
    let b = try #require(await OrderFlowAdapterTests.catalog(.direct, server: server).highlightsBoard(bases: ["BTC", "ETH", "BTC", "bad base"]))
    #expect(b.rows.isEmpty)
    #expect(await server.urls().map(\.absoluteString) == ["https://gw-a.example/v1/market/orderflow/highlights/board?bases=BTC,ETH"])
  }

  @Test func marketBoardQuery() async throws {
    let server = FakeServer { _ in json(#"{"generatedAtMs":1,"rows":[{"base":"WLD","changePct":174.1,"oiUsd":141000000,"price":1.284}]}"#) }
    let b = try #require(await OrderFlowAdapterTests.catalog(.direct, server: server).marketBoard(kind: .oi, window: .h4))
    #expect(b.rows.first?.base == "WLD")
    #expect(await server.urls().map(\.absoluteString) == ["https://gw-a.example/v1/market/board?kind=oi&window=4h"])
  }
}
