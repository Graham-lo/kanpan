import Foundation

/// 行情线路策略：这台手机该怎么去拿币安的行情。
///
/// 背景：`MarketRESTTransport` 平时会在「直连交易所」和「走 VPS 网关」之间对冲，
/// 探测失败就把整条线路切到 OKX（`RoutedMarketFeed.checkSource`）。这套自动判断
/// 在网络本来就通的机器上偶尔会误判——一次探测超时就整套换到 OKX，还要等
/// `MarketRecoverySchedule` 排的 5/10/15 分钟才肯回头。
///
/// 所以留一个手动开关：用户自己知道网络行不行，让他说了算。
public enum MarketRoutePolicy: String, Codable, Sendable, CaseIterable {
  /// 现在这套：直连与网关对冲，币安不行就切 OKX。
  case auto
  /// 只走自己的网络直连币安。不算网关、不吃直连冷却、也不会被自动切到 OKX。
  case direct
  /// 只走 VPS 网关。注意两台网关上币安是被封的（451），实际只供得起 OKX。
  case gateway

  public var title: String {
    switch self {
    case .auto: return "自动"
    case .direct: return "直连"
    case .gateway: return "网关"
    }
  }
}

/// 策略存哪儿。只有一个键，不值得往 `Prefs` 那套里塞。
public enum MarketRoutePolicyStore {
  public static let key = "market.routePolicy"

  public static var current: MarketRoutePolicy {
    guard let raw = UserDefaults.standard.string(forKey: key),
          let policy = MarketRoutePolicy(rawValue: raw) else { return .auto }
    return policy
  }

  /// 写入并广播。`RoutedMarketFeed` 自己听这条通知，所以 app 侧改完就完了，
  /// 不用再把新值一路传下去。
  public static func set(_ policy: MarketRoutePolicy) {
    UserDefaults.standard.set(policy.rawValue, forKey: key)
    NotificationCenter.default.post(name: .marketRoutePolicyDidChange, object: nil)
  }
}

public extension Notification.Name {
  static let marketRoutePolicyDidChange = Notification.Name("kanpan.market.routePolicyDidChange")
}
