import Foundation
import Testing
import KanpanCore
@testable import KanpanNetwork

/// 多交易所 阶段 2：上层只看能力位。这里钉住币安两条线路的能力位，
/// 以及交易所清单 / 线路解析的几条约定——它们一变，上层的行为就跟着变。
@Suite("提供者能力位与交易所清单")
struct ProviderCapabilitiesTests {

  @Test("直连：币安本家，能力位全开")
  func directIsBinanceWithEverything() {
    let caps = RouteResolver(policy: .direct).provider(venue: "binance").capabilities
    #expect(caps.venue == "binance" && caps.market == "usd_m" && caps.upstream == "binance")
    #expect(!caps.isSubstitute)
    #expect(caps.initialKlines == 1800 && caps.maxKlines == 1500)
    #expect(caps.hasTickerStream && caps.hasMarkPrice && caps.hasFunding)
    #expect(caps.hasMicrostructure && caps.hasDerivativeMetrics && caps.hasBulkTickers)
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
    #expect(!caps.hasTickerStream && !caps.hasMarkPrice && !caps.hasFunding)
    #expect(!caps.hasMicrostructure && !caps.hasDerivativeMetrics && !caps.hasBulkTickers)
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
}
