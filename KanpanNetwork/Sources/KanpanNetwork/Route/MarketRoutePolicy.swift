import Foundation

/// 行情线路：这台手机怎么去拿行情。用户在设置里选，选了哪条就走哪条。
///
/// 没有「自动」档。原来那套「直连优先、失败退网关、探不通整套切 OKX」的智能切换
/// 在网络本来就通的机器上会误判——一次探测超时就整套换了上游，还要等好几分钟
/// 才肯回头。现在线路是用户定的：直连就只走交易所直连，网关就只走 VPS 网关，
/// 代码不再替他做判断。
///
/// 某家交易所在网关上连哪台、能给出哪些能力，是那一家提供者自己的事，见 `RouteResolver`，这里不管。
public enum MarketRoutePolicy: String, Codable, Sendable, CaseIterable {
  /// 只走自己的网络直连交易所：不算网关、不记冷却、也不会被换上游。
  /// 2026-10-08 前是出厂默认；国内不开代理拿不到币安合约 REST（`fapi.binance.com` 没有国内能到的入口），
  /// 新装的手机第一次打开整页是空的，所以出厂改成网关（`MarketRoutePolicyStore.factoryDefault`），和网页版一致。
  case direct
  /// 出厂默认（2026-10-08 起）。只走 VPS 网关（新加坡 `ServerHosts.gateways`）。
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

  /// 出厂线路。2026-10-08 从直连改成网关（用户：「肯定也要一样」，和网页版 10-02 的改法一致）：
  /// 国内不开代理直连拿不到币安合约 REST，朋友拉代码打真机包第一次打开就是整页空白、板块页刷不出来。
  /// 选了哪条仍一直走哪条，没有自动切换；老档的迁移在 app 的 `PrefsCodec.migrate`（版本 5）。
  public static let factoryDefault: MarketRoutePolicy = .gateway

  /// 还没存过任何选择时从哪一档起步。
  ///
  /// 正式包就是 `factoryDefault`。**UI 测试沙盒**（`KANPAN_TEST_PROFILE=1`）仍按直连起步，
  /// 由 `KANPAN_TEST_ROUTE_POLICY` 点名换：契约用例（`ChartFoundationUITests` 等）验的是盘口、
  /// 外部统计这些直连才有的东西，和沙盒里常用行自己铺一套是同一个道理（`PrefsStore.uiTestQuick`）；
  /// 真正的出厂默认由 `PrefsDefaultsTests` / `MarketRoutePolicyTests` 在单元层面守。只在 DEBUG 构建里有这条岔路。
  public static var launchDefault: MarketRoutePolicy {
    #if DEBUG
    let env = ProcessInfo.processInfo.environment
    if env["KANPAN_TEST_PROFILE"] == "1" {
      return env["KANPAN_TEST_ROUTE_POLICY"].flatMap(MarketRoutePolicy.init(rawValue:)) ?? .direct
    }
    #endif
    return factoryDefault
  }

  /// 没存过、或者存的是旧版本的「自动」这种认不出的值，一律按 `launchDefault`。
  public static var current: MarketRoutePolicy {
    guard let raw = defaults.string(forKey: key),
          let policy = MarketRoutePolicy(rawValue: raw) else { return launchDefault }
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
