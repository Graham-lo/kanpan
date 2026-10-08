import Foundation
import KanpanCore

/// Bybit 这一家的**唯一事实来源**：身份、地址、限速、代号与周期互译、推送的帧格式参数。
/// 行情提供者（`BybitProvider`）、推送（`BybitWire`）、订单流（`BybitBooksAdapter`）全从这里取，
/// 不许各写一份域名或路径。
///
/// 行情只接 v5 的 USDT 线性永续（`category=linear`），键 `bybit/usd_m/BTCUSDT`——Bybit 原生代号就是这形状，
/// 不用互译，只换前缀。直连打 Bybit 自己的域名；网关线路走看盘自己的 kanpan-api
/// （`Backend/kanpan-api/src/venues/bybit/`）：REST 原样透传 `/v1/market/raw/v5/...?source=bybit`、
/// 推送是一条手机连接对一条上游连接的中继 `/v1/market/ws/bybit?category=linear`，报文与 Bybit 原生一字不差，
/// 所以解码（`BybitDTO`）两条线路共用一份，差别只在 URL。
public enum BybitVenue {
  public static let id = "bybit"
  public static let market = "usd_m"
  public static let displayName = "Bybit"
  /// 品种展示里的缩写（见 `VenueDescriptor.shortName`）。
  public static let shortName = "Bybit"
  /// 只收 USDT 线性永续（USDC 永续、交割不收）。
  public static let quote = "USDT"
  /// 行情这一支用的 category（订单流另外按产品分三类，见 `BybitBooksAdapter.Category`）。
  public static let category = "linear"

  /// 直连 REST 主机。官方备用域名 `api.bytick.com` 同一套接口；通用地址表一家只认一台直连主机，
  /// 所以 REST 不带它（服务端透传那一截会在两台之间换）。
  public static let restHost = "api.bybit.com"
  public static let backupRestHost = "api.bytick.com"
  /// 公开行情推送的主、备域名（后面拼 `/v5/public/<category>`）。
  static let streamHosts = ["stream.bybit.com", "stream.bytick.com"]

  /// 直连推送：某个 category 的公开行情，主、备两个域名。
  static func directStreams(category: String) -> [URL] {
    streamHosts.compactMap { URL(string: "wss://\($0)/v5/public/\(category)") }
  }

  /// 地址表：REST 前缀就是根（`v5/market/...` 整段都是 path），网关上是中继。
  public static let spec = VenueEndpoints.Spec(
    source: id, restHost: restHost, restPrefix: "/",
    directStreams: directStreams(category: category), gatewayStream: .relay)

  public static func endpoints(_ route: MarketRoute) -> VenueEndpoints { VenueEndpoints(spec, route: route) }

  /// 测试与命令行用：线路档位 + 网关表（网关表同时当 kanpan-api 主机用）。
  public static func endpoints(policy: MarketRoutePolicy, gateways: [String]) -> VenueEndpoints {
    endpoints(MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: gateways, api: gateways)))
  }

  /// 中继查询：上游按 category 分连接，中继靠这一项决定连哪一条。
  static func categoryQuery(_ category: String) -> [URLQueryItem] { [URLQueryItem(name: "category", value: category)] }

  /// kanpan-api 中继地址（`/v1/market/ws/bybit?category=…`），按 `hosts` 的顺序。
  /// 订单流不分线路一律走它（国内直连不了 Bybit），所以不经 `VenueEndpoints.streams`。
  static func relayStreams(hosts: [String], category: String) -> [URL] {
    VenueEndpoints.gatewayURLs(hosts, path: VenueEndpoints.relayPrefix + id, query: categoryQuery(category))
  }

  /// 官方（v5 Rate Limit › IP Limit）：REST 按 IP、**所有接口共用一个窗口**，任意 5 秒 ≤ 600 次，
  /// `api.bybit.com` 与 `api.bytick.com` 合计算，超了 403 封约 10 分钟；公共行情没有按 UID 的限制；WS 不计入 REST。
  /// 这里取 20 次 / 秒（= 100 / 5 秒，官方上限的六分之一，与服务端那把 `PACER` 同一个数）。
  /// 一家一把、整个进程共用：行情、订单流、探测都经它；换主机（网关主 → 备）不换这把，窗口不重置。
  public static let perSecond: Double = 20
  /// 直连：花的是手机自己出口 IP 的额度。
  public static let limiter = VenueRateLimiter(perSecond: perSecond)
  /// 网关：透传花的是 kanpan-api 出口 IP 的额度，和直连那把分开记（接入指南第 6 节：直连与网关是两把）。
  /// 原来两条线路共用一把：网关线路上的请求平白替直连排队，切线路时上一条线路攒下的间隔也带了过来。
  public static let gatewayLimiter = VenueRateLimiter(perSecond: perSecond)
  /// 这条线路上用哪一把（同一条线路上行情、订单流、探测共用）。
  public static func limiter(_ route: MarketRoute) -> VenueRateLimiter {
    endpoints(route).viaGateway ? gatewayLimiter : limiter
  }

  // ---------------------------------------------------------------- 推送帧格式

  /// 两条控制帧之间至少隔多久：官方每条连接每秒最多 10 条入站消息，留余量取 150 毫秒。
  /// 新连接数（官方每 IP 每 5 分钟 ≤ 500 次）由 `VenueStream` 的退避管：一条连接多订阅，切品种不重连。
  static let controlGapMs: Double = 150
  /// 一条订阅消息最多几个 args（现货的硬限是 10，中继三个 category 统一按 10 放行）。
  static let maxArgsPerMessage = 10
  /// 应用层保活：每 20 秒一句（官方建议），回来的 pong 解码时忽略。
  static let pingText = #"{"op":"ping"}"#
  static let pingEveryMs: Double = 20_000

  static func tickerTopic(_ symbol: String) -> String { "tickers.\(symbol)" }
  static func tradeTopic(_ symbol: String) -> String { "publicTrade.\(symbol)" }
  static func klineTopic(_ interval: String, _ symbol: String) -> String { "kline.\(interval).\(symbol)" }
  static func bookTopic(levels: Int, _ symbol: String) -> String { "orderbook.\(levels).\(symbol)" }

  // ---------------------------------------------------------------- 代号与周期

  /// Bybit 代号（`BTCUSDT`）→ 品种键（`bybit/usd_m/BTCUSDT`）。
  static func key(_ symbol: String) -> String {
    InstrumentID(venue: id, market: market, symbol: symbol).key
  }

  /// 品种键 → Bybit 代号（`BTCUSDT`）。
  static func symbol(_ key: String) -> String { InstrumentID(key).symbol }

  /// 看盘收的代号形状：大写字母数字、以 USDT 结尾、长度 5…30（和服务端 `bybit::symbol_ok`、中继的 topic 规则同口径；
  /// `BTCPERP` 这类 USDC 永续、`BTCUSDT-26DEC25` 这类交割都不进来）。
  static func isListedSymbol(_ s: String) -> Bool {
    (5...30).contains(s.utf8.count) && s.hasSuffix(quote)
      && s.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
  }

  /// K 线 `interval`。没有 1y（由 1M 聚）。
  static func interval(_ interval: Interval) -> String? {
    switch interval {
    case .m1: "1"
    case .m3: "3"
    case .m5: "5"
    case .m15: "15"
    case .m30: "30"
    case .h1: "60"
    case .h2: "120"
    case .h4: "240"
    case .h6: "360"
    case .h12: "720"
    case .d1: "D"
    case .w1: "W"
    case .mo1: "M"
    case .y1: nil
    }
  }

  /// 推送里的 `interval` → 看盘的周期。
  static func interval(wire: String) -> Interval? {
    Interval.allCases.first { interval($0) == wire }
  }

  /// 持仓量历史的 `intervalTime`：Bybit 只有 5min 15min 30min 1h 4h 1d。上层按币安口径给 `period`
  /// （`Interval.oiPeriod`：5m … 1d）；Bybit 没有的那几档取能整除它的更细一档（2h / 6h ← 1h、12h ← 4h），
  /// 点多一些，上层按 K 线桶对齐时一样取「不晚于开盘」的那一条。
  static func oiInterval(period: String) -> String? {
    switch period {
    case "5m": "5min"
    case "15m": "15min"
    case "30m": "30min"
    case "1h", "2h", "6h": "1h"
    case "4h", "12h": "4h"
    case "1d": "1d"
    default: nil
    }
  }
}
