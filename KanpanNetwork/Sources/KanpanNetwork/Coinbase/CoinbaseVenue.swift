import Foundation
import KanpanCore

/// Coinbase 这一家的**唯一事实来源**：身份、地址、限速、代号与周期互译。
/// 行情提供者（`CoinbaseProvider`）、推送（`CoinbaseWire`）、订单流（`CoinbaseLevel2Adapter`）、
/// 小组件补价全从这里取，不许各写一份域名或路径。
///
/// 直连打 Coinbase Advanced Trade 的公开行情；网关线路走看盘自己的 kanpan-api
/// （`Backend/kanpan-api/src/venues/coinbase/`）：REST 原样透传、推送是一条上游共享给所有手机的 hub，
/// 报文与 Coinbase 原生一字不差——所以解码（`CoinbaseDTO`）两条线路共用一份，差别只在 URL。
public enum CoinbaseVenue {
  public static let id = "coinbase"
  public static let market = "spot"
  public static let displayName = "Coinbase"
  /// 品种展示里的缩写（见 `VenueDescriptor.shortName`）。
  public static let shortName = "CB"
  /// 只收美元计价。`BTC-USDC` 这类不收（已拍板）。
  public static let quote = "USD"

  public static let restHost = "api.coinbase.com"
  public static let streamHost = "advanced-trade-ws.coinbase.com"
  /// 直连推送（行情与 `level2` 同一个服务）。
  public static let streamURL = URL(string: "wss://\(streamHost)")!

  /// 地址表：REST 前缀是公开行情（无鉴权）那一段；网关上是共享 hub。
  public static let spec = VenueEndpoints.Spec(
    source: id, restHost: restHost, restPrefix: "/api/v3/brokerage/market/",
    directStreams: [streamURL], gatewayStream: .hub)

  public static func endpoints(_ route: MarketRoute) -> VenueEndpoints { VenueEndpoints(spec, route: route) }

  /// 测试与命令行用：线路档位 + 网关表（网关表同时当 kanpan-api 主机用）。
  public static func endpoints(policy: MarketRoutePolicy, gateways: [String]) -> VenueEndpoints {
    endpoints(MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: gateways, api: gateways)))
  }

  /// 公开行情按 IP 10 次/秒（官方公开端点的保守值）。整个进程共用这一把：
  /// 行情、订单流、小组件补价、探测都经它（Coinbase 按出口 IP 记账）。
  public static let perSecond: Double = 10
  public static let limiter = VenueRateLimiter(perSecond: perSecond)

  /// 推送：两条控制帧之间至少隔多久（Coinbase 对入站消息有每秒条数上限）。
  static let controlGapMs: Double = 150

  // ---------------------------------------------------------------- 代号与周期

  /// 交易所原生代号（`BTC-USD`）→ 品种键（`coinbase/spot/BTC-USD`）。
  static func key(_ productID: String) -> String {
    InstrumentID(venue: id, market: market, symbol: productID).key
  }

  /// 品种键 → Coinbase 的 product_id（`BTC-USD`）。
  static func productID(_ key: String) -> String { InstrumentID(key).symbol }

  /// Coinbase 的 `granularity`。只有这 9 档是原生的。
  static func granularity(_ interval: Interval) -> String? {
    switch interval {
    case .m1: "ONE_MINUTE"
    case .m5: "FIVE_MINUTE"
    case .m15: "FIFTEEN_MINUTE"
    case .m30: "THIRTY_MINUTE"
    case .h1: "ONE_HOUR"
    case .h2: "TWO_HOUR"
    case .h4: "FOUR_HOUR"
    case .h6: "SIX_HOUR"
    case .d1: "ONE_DAY"
    default: nil
    }
  }

  /// 有原生 K 线推送的那一档（`candles` 频道固定 5 分钟）。
  static let candleInterval: Interval = .m5
}
