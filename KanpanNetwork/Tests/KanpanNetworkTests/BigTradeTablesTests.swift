import Foundation
import Testing
import KanpanCore
@testable import KanpanNetwork
import KanpanNetworkTestSupport

@Suite("大单与爆仓 · 服务端分钟表")
struct BigTradeTablesTests {
  @Test("/flow：带 base/from/to 问主机，大买大卖两列成页；bigUsd 为 null 时没有服务端大单线；坏行丢、负数当 0；别的币、坏数据、主机都不通当没有")
  func flow() async throws {
    let body = #"{"base":"SOL","bigUsd":50000,"smallUsd":10000,"tracked":true,"rows":[[60000,150000,0,5001,1],[120000,-3,"20",0,0],[180000,1],["x",1,2]]}"#
    let server = FakeServer { _ in json(body) }
    let page = try #require(await OrderFlowAdapterTests.catalog(.direct, server: server).flow(base: "SOL", fromMs: 10, toMs: 20))
    #expect(page.tracked && page.bigUsd == 50_000)
    #expect(page.rows == [.init(minuteMs: 60_000, buyUsd: 150_000, sellUsd: 0), .init(minuteMs: 120_000, buyUsd: 0, sellUsd: 20)])
    #expect(await server.urls().map(\.absoluteString) == ["https://gw-a.example/v1/market/orderflow/flow?base=SOL&from=10&to=20"])

    let untracked = OrderFlowCatalog.parseFlow(Data(#"{"base":"MU","bigUsd":null,"smallUsd":10000,"tracked":false,"rows":[]}"#.utf8), base: "MU")
    #expect(untracked == BigTradeFlowPage(tracked: false, bigUsd: nil, rows: []))
    #expect(OrderFlowCatalog.parseFlow(Data(body.utf8), base: "BTC") == nil)
    #expect(OrderFlowCatalog.parseFlow(Data("oops".utf8), base: "SOL") == nil)
    #expect(await OrderFlowAdapterTests.catalog(.direct, server: server).flow(base: "SOL", fromMs: 30, toMs: 20) == nil)
    let dead = FakeServer { _ in json("oops", status: 503) }
    #expect(await OrderFlowAdapterTests.catalog(.gateway, server: dead, api: OrderFlowAdapterTests.gateways)
      .flow(base: "SOL", fromMs: 0, toMs: 1) == nil)
    #expect(await dead.urls().count == 2)
  }

  @Test("/liq：八列成行，哪边 0 多 / 1 空、哪家 0 币安 / 1 OKX，别的值当 0；缺后四列当 0；不足四列丢行")
  func liquidations() async throws {
    let body = #"{"base":"SOL","tracked":true,"rows":[[60000,150000,1,3,120001,142.375,0,1],[120000,0,9000,1,9000,140.5,1,0],[180000,5,6,1],[240000,1,2],[300000,-1,2,2,7,1,5,9]]}"#
    let server = FakeServer { _ in json(body) }
    let page = try #require(await OrderFlowAdapterTests.catalog(.direct, server: server).liquidations(base: "SOL", fromMs: 0, toMs: 1))
    #expect(page.tracked && page.rows.count == 4)
    #expect(page.rows[0] == LiquidationRow(minuteMs: 60_000, longUsd: 150_000, shortUsd: 1, count: 3, maxUsd: 120_001,
                                            maxPrice: 142.375, maxIsLong: true, maxExchange: .okx))
    #expect(page.rows[1].maxIsLong == false && page.rows[1].maxExchange == .binance)
    #expect(page.rows[2] == LiquidationRow(minuteMs: 180_000, longUsd: 5, shortUsd: 6, count: 1))
    #expect(page.rows[3].longUsd == 0 && page.rows[3].maxIsLong && page.rows[3].maxExchange == .binance)
    #expect(await server.urls().map(\.absoluteString) == ["https://gw-a.example/v1/market/orderflow/liq?base=SOL&from=0&to=1"])
    #expect(OrderFlowCatalog.parseLiquidations(Data(body.utf8), base: "ETH") == nil)
  }
}
