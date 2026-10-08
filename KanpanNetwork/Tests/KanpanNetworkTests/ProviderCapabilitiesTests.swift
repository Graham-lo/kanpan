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

  @Test("网关：同样是币安本家（REST 透传、推送 hub），只少盘口与逐笔方向；首屏一发 300 根")
  func gatewayIsBinanceWithoutMicrostructure() {
    let caps = RouteResolver(policy: .gateway).provider(venue: "binance").capabilities
    #expect(caps.venue == "binance" && caps.market == "usd_m" && caps.upstream == "binance")
    #expect(!caps.isSubstitute)
    #expect(caps.snapshotNamespace == nil)
    // hub 不转 `@depth5` 与 `@trade`。
    #expect(!caps.hasMicrostructure)
    // 其余照直连：标记价、费率、持仓量、衍生统计、归档都有（REST 经透传、标记价经 hub）。
    #expect(caps.hasTickerStream && caps.hasMarkPrice && caps.hasFunding)
    #expect(caps.hasDerivativeMetrics && caps.hasBulkTickers)
    #expect(caps.hasOpenInterestHistory && caps.hasOpenInterestArchive)
    #expect(caps.openInterestSource == "binance")
    #expect(caps.probesHistoryBoundary)
    #expect(caps.maxKlines == 1500 && caps.liveKlineIntervals == BinanceProvider.directCapabilities.liveKlineIntervals)
    // 首屏不比原来多发：一发 300 根，深度交给后台加深（直连 1800 会并行再发一发小页）。
    #expect(caps.initialKlines == 300)
    var same = caps
    same.hasMicrostructure = true
    same.initialKlines = BinanceProvider.directCapabilities.initialKlines
    #expect(same == BinanceProvider.directCapabilities)
  }

  @Test("回放要本家数据：两条线路都是币安本家")
  func ownDataIsNeverSubstitute() {
    for policy in MarketRoutePolicy.allCases {
      let caps = RouteResolver(policy: policy).ownDataProvider(venue: "binance")?.capabilities
      #expect(caps?.upstream == "binance")
      #expect(caps == RouteResolver(policy: policy).provider(venue: "binance").capabilities)
    }
    #expect(RouteResolver(policy: .direct).ownDataProvider(venue: "nowhere") == nil)
  }

  @Test("1y 从 1M 聚，其余原生")
  func aggregation() {
    let caps = BinanceProvider.directCapabilities
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

  @Test("RouteResolver 的出口：直连给出厂域名，网关给新加坡那一台网关（2026-10-02 起没有备机），两档都是币安本家")
  func resolverOutputs() {
    let direct = RouteResolver(policy: .direct)
    #expect(direct.route.restHosts(direct: "fapi.binance.com") == ["fapi.binance.com"])
    #expect(direct.defaultProvider.capabilities.upstream == "binance")
    let gateway = RouteResolver(policy: .gateway)
    #expect(gateway.route.gateways == MarketEndpoints.production.gateways)
    #expect(gateway.route.gateways == [ServerHosts.primary])
    #expect(gateway.route.restHosts(direct: "fapi.binance.com") == MarketEndpoints.production.gateways)
    #expect(gateway.defaultProvider.capabilities.upstream == "binance")
    // 线上网关表里绝不能混进合约测试网。
    #expect(!MarketEndpoints.production.gateways.contains { $0.contains("binancefuture") })
    // 地址只在 ServerHosts 一处；账号 API 走的就是主网关那台。
    #expect(MarketEndpoints.production.gateways == ServerHosts.gateways)
    #expect(MarketEndpoints.production.gateways.first == ServerHosts.accountAPI.host)
  }

  @Test("冷启动热身跟线路走：直连热币安两台，网关热线上网关表里的每一台")
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

  @Test("小组件补价跟线路走：直连打 /fapi，网关打 kanpan-api 的原样透传（载荷同形，不包信封）")
  func widgetRefreshFollowsRoute() throws {
    let direct = try #require(RouteResolver(policy: .direct).defaultProvider.widgetRefresh)
    #expect(direct.hosts == ["fapi.binance.com"])
    #expect(direct.tickerURL(host: direct.hosts[0], symbol: "BTCUSDT")?.path == "/fapi/v1/ticker/24hr")
    #expect(direct.tickerField == nil)
    #expect(direct.market == VenueRegistry.default.marketKey)
    let gateway = try #require(RouteResolver(policy: .gateway).defaultProvider.widgetRefresh)
    #expect(gateway.hosts == MarketEndpoints.production.api)
    let url = try #require(gateway.tickerURL(host: gateway.hosts[0], symbol: "BTCUSDT"))
    #expect(url.path == "/v1/market/raw/fapi/v1/ticker/24hr")
    #expect(url.query == "symbol=BTCUSDT&source=binance")
    let closes = try #require(gateway.closesURL(host: gateway.hosts[0], symbol: "BTCUSDT"))
    #expect(closes.path == "/v1/market/raw/fapi/v1/klines")
    #expect(closes.query == "symbol=BTCUSDT&interval=1h&limit=\(WidgetSnapshot.sparkBars)&source=binance")
    #expect(gateway.tickerField == nil && gateway.closesField == nil && gateway.format == .binance)
    // 和 `MarketRESTTransport` 改写出来的地址一模一样。
    let rewritten = MarketRESTTransport.rawURL(
      for: URL(string: "https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=BTCUSDT")!, host: gateway.hosts[0])
    #expect(url == rewritten)
  }

  @Test("Coinbase 现货也有小组件补价，跟线路走、地址与取数件用的同一条（E-10）")
  func coinbaseWidgetRefreshFollowsRoute() throws {
    let now = Date(timeIntervalSince1970: 1_700_003_700)
    for policy in [MarketRoutePolicy.direct, .gateway] {
      let resolver = RouteResolver(policy: policy)
      let plans = resolver.venueWidgetRefreshes
      #expect(plans.allSatisfy { $0.market != VenueRegistry.default.marketKey })
      let plan = try #require(plans.first { $0.market == VenueRegistry.coinbase.marketKey })
      #expect(plan.format == .coinbase)
      let endpoints = CoinbaseVenue.endpoints(resolver.route)
      #expect(plan.hosts == endpoints.restHosts)
      let host = plan.hosts[0]
      // 和 `ticker24h` / `fetchBars` 拼出来的地址一模一样，网关透传也就一样。
      #expect(plan.tickerURL(host: host, symbol: "BTC-USD", now: now)
              == endpoints.rest("products/BTC-USD", host: host))
      let closes = try #require(plan.closesURL(host: host, symbol: "BTC-USD", now: now))
      let expected = try #require(endpoints.rest("products/BTC-USD/candles", query: [
        URLQueryItem(name: "granularity", value: "ONE_HOUR"),
        URLQueryItem(name: "start", value: "1699920000"),
        URLQueryItem(name: "end", value: "1700002800"),
      ], host: host))
      #expect(closes == expected)
    }
  }
}
