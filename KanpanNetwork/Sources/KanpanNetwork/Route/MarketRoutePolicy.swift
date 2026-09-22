import Foundation

/// 行情线路：这台手机怎么去拿行情。用户在设置里选，选了哪条就走哪条。
///
/// 没有「自动」档。原来那套「直连优先、失败退网关、探不通整套切 OKX」的智能切换
/// 在网络本来就通的机器上会误判——一次探测超时就整套换了上游，还要等好几分钟
/// 才肯回头。现在线路是用户定的：直连就只走交易所直连，网关就只走 VPS 网关，
/// 代码不再替他做判断。
///
/// 某家交易所在网关上实际由谁供数（比如币安在网关上被封、由替身顶上），是那一家
/// 提供者自己的事，见 `RouteResolver`，这里不管。
public enum MarketRoutePolicy: String, Codable, Sendable, CaseIterable {
  /// 出厂默认。只走自己的网络直连交易所：不算网关、不记冷却、也不会被换上游。
  case direct
  /// 只走 VPS 网关。
  case gateway

  public var title: String {
    switch self {
    case .direct: return "直连"
    case .gateway: return "网关"
    }
  }
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
  ///
  /// **只在 DEBUG 构建里有这条岔路**（审查 C-02）：从前它不受编译边界保护，于是同一个
  /// Release 包注入环境变量后就成了「一半测试档、一半正式档」的混合态——`PrefsStore`
  /// 和账号那两处早已 `#if DEBUG`，只有这儿还跟着环境走，那样的绿谁也说不清测的是谁。
  static var defaults: UserDefaults {
    #if DEBUG
    let env = ProcessInfo.processInfo.environment
    if env["KANPAN_TEST_PROFILE"] == "1", let profile = env["KANPAN_PERSISTENCE_PROFILE"],
       UUID(uuidString: profile) != nil, let suite = UserDefaults(suiteName: "kanpan.tests." + profile) {
      return suite
    }
    #endif
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
