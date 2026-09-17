import Foundation

/// 行情线路：这台手机怎么去拿行情。用户在设置里选，选了哪条就走哪条。
///
/// 没有「自动」档。原来那套「直连优先、失败退网关、探不通整套切 OKX」的智能切换
/// 在网络本来就通的机器上会误判——一次探测超时就整套换到 OKX，还要等好几分钟
/// 才肯回头。现在线路是用户定的：直连就只走币安直连，网关就只走 VPS 网关，
/// 代码不再替他做判断。
public enum MarketRoutePolicy: String, Codable, Sendable, CaseIterable {
  /// 出厂默认。只走自己的网络直连币安：不算网关、不记冷却、也不会被切到 OKX。
  case direct
  /// 只走 VPS 网关。两台网关上币安是被封的（451），实际供的是 OKX 的行情。
  case gateway

  public var title: String {
    switch self {
    case .direct: return "直连"
    case .gateway: return "网关"
    }
  }

  /// 这条线路对应哪家交易所的行情。
  public var source: MarketSource { self == .gateway ? .okx : .binance }
}

/// 线路的进程级镜像，给 `KanpanData` 这边直接读。
///
/// 真正的存档在 app 的 `Prefs.routePolicy` 里：登录了跟着账号同步，没登录就在本机
/// 的访客档案里。`PrefsStore` 每次设置一变就把它镜像到这里，`RoutedMarketFeed`
/// 只认这里，不用知道 `Prefs` 的存在。
public enum MarketRoutePolicyStore {
  public static let key = "market.routePolicy"

  /// 测试沙盒（`KANPAN_TEST_PROFILE=1` + `KANPAN_PERSISTENCE_PROFILE`）用自己的
  /// 一份 defaults，和 `PrefsStore` 的选法一致——UI 用例里切到「网关」不会
  /// 把这台真机真正的线路改掉。
  static var defaults: UserDefaults {
    let env = ProcessInfo.processInfo.environment
    if env["KANPAN_TEST_PROFILE"] == "1", let profile = env["KANPAN_PERSISTENCE_PROFILE"],
       UUID(uuidString: profile) != nil, let suite = UserDefaults(suiteName: "kanpan.tests." + profile) {
      return suite
    }
    return .standard
  }

  /// 没存过、或者存的是旧版本的「自动」这种认不出的值，一律按直连。
  public static var current: MarketRoutePolicy {
    guard let raw = defaults.string(forKey: key),
          let policy = MarketRoutePolicy(rawValue: raw) else { return .direct }
    return policy
  }

  /// 写入并广播。没变就什么都不做——`PrefsStore` 每次落盘都会调一次，
  /// 不能让每改一个无关设置就把行情线路重开一遍。
  public static func set(_ policy: MarketRoutePolicy) {
    guard current != policy else { return }
    defaults.set(policy.rawValue, forKey: key)
    NotificationCenter.default.post(name: .marketRoutePolicyDidChange, object: nil)
  }
}

public extension Notification.Name {
  static let marketRoutePolicyDidChange = Notification.Name("kanpan.market.routePolicyDidChange")
}

/// 换线路时给界面的提示状态：切换中 / 切好了 / 没在切。
public enum MarketRoutingState: Sendable, Equatable {
  case idle, switching, switched
}
