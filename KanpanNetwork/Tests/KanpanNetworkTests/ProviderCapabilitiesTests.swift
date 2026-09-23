import Foundation
import Testing
import KanpanCore
@testable import KanpanNetwork

/// 多交易所 阶段 2：上层只看能力位。这里钉住币安两条线路的能力位，
/// 以及交易所清单 / 线路解析的几条约定——它们一变，上层的行为就跟着变。
@Suite("提供者能力位与交易所清单")
struct ProviderCapabilitiesTests {

  /// 裸代号归哪一家，Core 里只有 `InstrumentID.defaultMarketKey` 一份（下层不知道有哪些
  /// 交易所）；交易所清单里排第一的那一家必须就是它，否则老存档的裸代号会被读成一家、
  /// 却被当成另一家去取数。
  @Test("默认交易所 = InstrumentID 的裸代号归属")
  func defaultVenueIsTheBareKeyDefault() {
    #expect(VenueRegistry.default.marketKey == InstrumentID.defaultMarketKey)
    #expect(VenueRegistry.default.id == InstrumentID.defaultVenue)
    #expect(VenueRegistry.default.market == InstrumentID.defaultMarket)
  }

  @Test("直连：币安本家，能力位全开")
  func directIsBinanceWithEverything() {
    let caps = RouteResolver(policy: .direct).provider(venue: "binance").capabilities
    #expect(caps.venue == "binance" && caps.market == "usd_m" && caps.upstream == "binance")
    #expect(!caps.isSubstitute)
    #expect(caps.initialKlines == 1800 && caps.maxKlines == 1500)
    #expect(caps.hasTickerStream && caps.hasMarkPrice && caps.hasFunding)
    #expect(caps.hasMicrostructure && caps.hasDerivativeMetrics && caps.hasBulkTickers)
    #expect(caps.hasOpenInterestHistory && caps.hasOpenInterestArchive)
    #expect(caps.probesHistoryBoundary)
    #expect(caps.snapshotNamespace == nil)
    #expect(caps.openInterestSource == "binance")
  }

  @Test("网关：同一个 venue，替身上游，能力位按替身收窄")
  func gatewayIsSubstitute() {
    let caps = RouteResolver(policy: .gateway).provider(venue: "binance").capabilities
    #expect(caps.venue == "binance" && caps.upstream == "okx")
    #expect(caps.isSubstitute)
    #expect(caps.initialKlines == 300)
    // 网关的 OKX 组合流转 24h 行情（不带成交额，「额」由 `GatewayTicker` 补）；没有标记价。
    #expect(caps.hasTickerStream && !caps.hasMarkPrice)
    // 费率由网关按替身自己的整表给（`GatewayFunding`），不是没有。
    #expect(caps.hasFunding)
    #expect(!caps.hasMicrostructure && !caps.hasDerivativeMetrics && !caps.hasBulkTickers)
    // 持仓量副图有替身自己的历史（`GatewayOIHistory`），没有币安那份归档。
    #expect(caps.hasOpenInterestHistory && !caps.hasOpenInterestArchive)
    #expect(!caps.probesHistoryBoundary)
    #expect(caps.snapshotNamespace == "okx")
    #expect(caps.openInterestSource == "okx")
  }

  @Test("回放要本家数据：网关线路上也不拿替身顶")
  func ownDataIsNeverSubstitute() {
    for policy in MarketRoutePolicy.allCases {
      let caps = RouteResolver(policy: policy).ownDataProvider(venue: "binance")?.capabilities
      #expect(caps?.upstream == "binance")
    }
    #expect(RouteResolver(policy: .direct).ownDataProvider(venue: "nowhere") == nil)
  }

  @Test("1y 从 1M 聚，其余原生")
  func aggregation() {
    let caps = BinanceProvider.capabilities(.binance)
    #expect(caps.source(for: .y1) == .mo1)
    #expect(caps.isAggregated(.y1))
    #expect(!caps.isAggregated(.h1))
    for iv in Interval.allCases { #expect(caps.supports(iv)) }
  }

  @Test("品种键 → 交易所；裸符号与认不出的交易所归默认那一家")
  func descriptorForSymbol() {
    #expect(VenueRegistry.descriptor(forSymbol: "binance/usd_m/BTCUSDT").id == "binance")
    #expect(VenueRegistry.descriptor(forSymbol: "BTCUSDT").id == VenueRegistry.default.id)
    #expect(VenueRegistry.descriptor(forSymbol: "nowhere/spot/BTC-USD").id == VenueRegistry.default.id)
    #expect(VenueRegistry.default.defaultSymbol == "binance/usd_m/BTCUSDT")
    #expect(VenueRegistry.sectorVenue.joinsSectors)
  }

  @Test("提供者按品种键选")
  func providerForSymbol() {
    let resolver = RouteResolver(policy: .direct)
    #expect(resolver.provider(forSymbol: "binance/usd_m/ETHUSDT").capabilities.venue == "binance")
    #expect(resolver.defaultProvider.capabilities.venue == VenueRegistry.default.id)
  }

  @Test("网关清单去重、去空")
  func endpointsDedupGateways() {
    let e = MarketEndpoints(gateways: ["a", "", "b", "a"])
    #expect(e.gateways == ["a", "b"])
  }

  @Test("RouteResolver 的出口：直连给币安本家与出厂域名，网关给替身与两台线上网关")
  func resolverOutputs() {
    let direct = RouteResolver(policy: .direct)
    #expect(direct.route.restHosts(direct: "fapi.binance.com") == ["fapi.binance.com"])
    #expect(direct.defaultProvider.capabilities.upstream == "binance")
    let gateway = RouteResolver(policy: .gateway)
    #expect(gateway.route.gateways == MarketEndpoints.production.gateways)
    #expect(gateway.route.gateways.count == 2)
    #expect(gateway.route.restHosts(direct: "fapi.binance.com") == MarketEndpoints.production.gateways)
    #expect(gateway.defaultProvider.capabilities.upstream == "okx")
    // 线上网关表里绝不能混进合约测试网。
    #expect(!MarketEndpoints.production.gateways.contains { $0.contains("binancefuture") })
  }

  @Test("冷启动热身跟线路走：直连热币安两台，网关热两台网关")
  func prewarmFollowsRoute() {
    let direct = RouteResolver(policy: .direct).defaultProvider.prewarmTargets
    #expect(direct.map { $0.url.host ?? "" } == ["fapi.binance.com", "dstream.binance.me"])
    #expect(direct.first?.url.path == "/fapi/v1/ping")
    let gateway = RouteResolver(policy: .gateway).defaultProvider.prewarmTargets
    #expect(gateway.map { $0.url.host ?? "" } == MarketEndpoints.production.gateways.map {
      String($0.split(separator: ":").first ?? "")
    })
    #expect(gateway.allSatisfy { $0.method == "HEAD" })
  }

  @Test("小组件补价跟线路走：直连打 /fapi，网关打 /market/v1 并从信封取")
  func widgetRefreshFollowsRoute() throws {
    let direct = try #require(RouteResolver(policy: .direct).defaultProvider.widgetRefresh)
    #expect(direct.hosts == ["fapi.binance.com"])
    #expect(direct.tickerURL(host: direct.hosts[0], symbol: "BTCUSDT")?.path == "/fapi/v1/ticker/24hr")
    #expect(direct.tickerField == nil)
    #expect(direct.market == VenueRegistry.default.marketKey)
    let gateway = try #require(RouteResolver(policy: .gateway).defaultProvider.widgetRefresh)
    #expect(gateway.hosts == MarketEndpoints.production.gateways)
    let url = try #require(gateway.tickerURL(host: gateway.hosts[0], symbol: "BTCUSDT"))
    #expect(url.path == "/market/v1/ticker")
    #expect(url.query?.contains("source=okx") == true)
    #expect(gateway.tickerField == "ticker" && gateway.closesField == "bars")
  }
}
