import Foundation

/// 线路决策的唯一产物：用户选的线路 + 主机 → 这一刻行情请求该往哪儿发。
///
/// 从前「走不走网关」在七八个地方各判一遍（REST 竞速、推送拨号、各家提供者的地址、
/// 板块、报价簿、默认自选、小组件……），其中三处干脆绕开了用户的选择，用出厂的
/// 「直连 + 空网关表」自己取数（审查 1.1）。现在只在这里判：各家提供者、各个取数件
/// 只问它要 REST 主机、推送主机和网关候选，自己不再写 `policy == .gateway`。
public struct MarketRoute: Sendable, Equatable {
  /// 用户选的线路，原样。
  public let policy: MarketRoutePolicy
  public let endpoints: MarketEndpoints

  public init(policy: MarketRoutePolicy, endpoints: MarketEndpoints) {
    self.policy = policy; self.endpoints = endpoints
  }

  /// 行情请求走不走网关。直连就只直连，网关就只网关，没有回退。
  public var viaGateway: Bool { policy == .gateway }

  /// 网关候选，主在前、备在后：币安主行情在网关线路上的 REST / 推送，以及两台都有的只读接口
  /// （`/oi/v1/metrics`、`/v1/market/{funding,ticker,open-interest/history,raw,stream}`、
  /// `/market/v1/*`、`/market/okx/stream`）。只在主机上的 `/v1/*` 不要用它，用 `apiHosts`。
  public var gateways: [String] { endpoints.gateways }

  /// kanpan-api 的主机，**和线路无关**，恒为主机（`ServerHosts.api`）。
  ///
  /// 线路两档只管币安主行情；订单流的 OKX 中继、币安中继、品种表、深度快照任何线路下都经
  /// kanpan-api，因为 OKX 国内直连不通且订单流必须三家聚合。账号、板块历史、元数据、持仓量这些
  /// `/v1/*` 也一样。这些只有主机上有（备机是 metrics 模式，一律 404），所以这里没有备机。
  public var apiHosts: [String] { endpoints.api }

  /// 某一家行情 REST 的候选主机：直连是它自己的域名，网关线路上是网关候选。
  public func restHosts(direct: String) -> [String] { viaGateway ? gateways : [direct] }

  /// 某一家行情推送的候选主机，规则同 `restHosts`。
  public func streamHosts(direct: String) -> [String] { viaGateway ? gateways : [direct] }
}
