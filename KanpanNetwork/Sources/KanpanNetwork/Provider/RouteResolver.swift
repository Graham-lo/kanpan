import Foundation
import KanpanCore

/// 线路 × 交易所 → 提供者。**行情线路的唯一决策点。**
///
/// 线路（直连 / 网关）是用户在设置里定的全局开关，对所有交易所生效；某家交易所在
/// 网关上实际由谁供数（比如币安在网关上被封、服务端换替身顶上），在那一家自己的
/// 工厂里决定，上层只看得到提供者的 `capabilities`。
///
/// 输入是用户选的线路 + 主机，输出是 `route`（REST / 推送主机与网关候选）和按它建好的
/// 提供者。app 里任何取数件都从这儿拿，不再自己拼 `.direct` / `.default`——那样的旁路
/// 会在用户选了网关时偷偷直连交易所，或者拿着一张空网关表去问网关专属的接口。
///
/// 提供者对一组 (交易所, 线路, 主机) 是不可变的：换线路就再要一个新的。
public struct RouteResolver: Sendable {
  public var route: MarketRoute
  public var log: FeedLog

  public init(policy: MarketRoutePolicy = MarketRoutePolicyStore.current,
              endpoints: MarketEndpoints = .production, log: FeedLog = .silent) {
    self.route = MarketRoute(policy: policy, endpoints: endpoints); self.log = log
  }

  public init(route: MarketRoute, log: FeedLog = .silent) {
    self.route = route; self.log = log
  }

  /// 这台设备此刻的线路：本机存的线路选择 + 线上网关。app 里默认就用它。
  public static var current: RouteResolver { RouteResolver() }

  /// 同一条线路，换一份日志。
  public func logging(to log: FeedLog) -> RouteResolver { RouteResolver(route: route, log: log) }

  public var policy: MarketRoutePolicy { route.policy }
  public var endpoints: MarketEndpoints { route.endpoints }

  public func provider(venue: String) -> any MarketProvider {
    (VenueRegistry.descriptor(venue) ?? VenueRegistry.default).make(route, log)
  }

  /// 某个品种（`InstrumentID.key`，旧的裸符号也认）该找谁要行情。
  public func provider(forSymbol key: String) -> any MarketProvider {
    VenueRegistry.descriptor(forSymbol: key).make(route, log)
  }

  /// 这家本家的数据（不拿替身顶），走用户选的线路。复盘回放用（只取 K 线，不开推送）。
  /// 认不出的交易所给 nil。
  public func ownDataProvider(venue: String) -> (any MarketProvider)? {
    VenueRegistry.descriptor(venue).map { $0.makeOwn(route, log) }
  }

  /// 看盘自己的后端（`kanpan-api` 的 `/v1/*` 只读接口）。不随线路档位变——直连线路下问板块历史、
  /// 供应量也是问它；而且只在主机上（`MarketRoute.apiHosts`），备机上这些路径是 404。
  public var backend: BackendClient { BackendClient(hosts: route.apiHosts, log: log) }

  /// 默认交易所。
  public var defaultProvider: any MarketProvider { VenueRegistry.default.make(route, log) }
}
