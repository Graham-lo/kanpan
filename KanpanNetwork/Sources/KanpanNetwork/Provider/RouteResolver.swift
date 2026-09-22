import Foundation
import KanpanCore

/// 线路 × 交易所 → 提供者。
///
/// 线路（直连 / 网关）是用户在设置里定的全局开关，对所有交易所生效；某家交易所在
/// 网关上实际由谁供数（比如币安在网关上被封、服务端换替身顶上），在那一家自己的
/// 工厂里决定，上层只看得到提供者的 `capabilities`。
///
/// 提供者对一组 (交易所, 线路, 主机) 是不可变的：换线路就再要一个新的。
public struct RouteResolver: Sendable {
  public var policy: MarketRoutePolicy
  public var endpoints: MarketEndpoints
  public var log: FeedLog

  public init(policy: MarketRoutePolicy = MarketRoutePolicyStore.current,
              endpoints: MarketEndpoints = .default, log: FeedLog = .silent) {
    self.policy = policy; self.endpoints = endpoints; self.log = log
  }

  public func provider(venue: String) -> any MarketProvider {
    (VenueRegistry.descriptor(venue) ?? VenueRegistry.default).make(policy, endpoints, log)
  }

  /// 某个品种（`InstrumentID.key`，旧的裸符号也认）该找谁要行情。
  public func provider(forSymbol key: String) -> any MarketProvider {
    VenueRegistry.descriptor(forSymbol: key).make(policy, endpoints, log)
  }

  /// 这家本家的数据（不拿替身顶），走用户选的线路。复盘回放用。
  /// 认不出的交易所给 nil。
  public func ownDataProvider(venue: String) -> (any MarketProvider)? {
    VenueRegistry.descriptor(venue).map { $0.makeOwn(policy, endpoints, log) }
  }

  /// 默认交易所。
  public var defaultProvider: any MarketProvider { VenueRegistry.default.make(policy, endpoints, log) }
}
