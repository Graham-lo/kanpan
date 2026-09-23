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

  /// 网关候选，主在前、备在后。两条线路都有：网关专属的只读接口（供应量、持仓量、
  /// 板块历史、替身的费率表）本来就只在网关上，和行情走哪条路无关。
  public var gateways: [String] { endpoints.gateways }

  /// 某一家行情 REST 的候选主机：直连是它自己的域名，网关线路上是网关候选。
  public func restHosts(direct: String) -> [String] { viaGateway ? gateways : [direct] }

  /// 某一家行情推送的候选主机，规则同 `restHosts`。
  public func streamHosts(direct: String) -> [String] { viaGateway ? gateways : [direct] }
}
