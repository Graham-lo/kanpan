import Foundation
import KanpanCore

/// Hyperliquid 这一家的**唯一事实来源**：身份、地址、限速、保活、代号与周期互译。
/// 行情提供者（`HyperliquidProvider`）、推送（`HyperliquidWire`）、订单流（`HyperliquidBookAdapter`）全从这里取，
/// 不许各写一份域名或路径。
///
/// 只有 USDC 保证金的永续，看盘里按 U 本位永续记（`hyperliquid/usd_m/<COIN>`）。
/// 直连打 Hyperliquid 自己的 `api.hyperliquid.xyz`；网关线路走看盘自己的 kanpan-api
/// （`Backend/kanpan-api/src/venues/hyperliquid/`）：REST 是 `POST /v1/market/raw/info?source=hyperliquid` 白名单透传
/// （正文与直连同形），推送是中继 `/v1/market/ws/hyperliquid`（上行白名单 `candle` / `trades` / `activeAssetCtx` /
/// `l2Book` / `ping`，帧原样转发）——所以解码（`HyperliquidDTO`）两条线路共用一份，差别只在 URL。
public enum HyperliquidVenue {
  public static let id = "hyperliquid"
  public static let market = "usd_m"
  public static let displayName = "Hyperliquid"
  /// 品种展示里的缩写（见 `VenueDescriptor.shortName`）。
  public static let shortName = "HL"
  /// 只有 USDC 保证金的永续。
  public static let quote = "USDC"

  public static let restHost = "api.hyperliquid.xyz"
  /// 直连推送（行情与订单流同一个服务）。
  public static let streamURL = URL(string: "wss://api.hyperliquid.xyz/ws")!

  /// 地址表：全部 REST 是 `POST /info`（前缀 `/`）；网关上是中继（一条手机连接对一条 hub 订阅，帧原样转发）。
  public static let spec = VenueEndpoints.Spec(
    source: id, restHost: restHost, restPrefix: "/",
    directStreams: [streamURL], gatewayStream: .relay)

  /// `info` 查询的路径（`VenueREST.post` 的 `path`）。
  static let infoPath = "info"

  public static func endpoints(_ route: MarketRoute) -> VenueEndpoints { VenueEndpoints(spec, route: route) }

  /// 测试与命令行用：线路档位 + 网关表（网关表同时当 kanpan-api 主机用）。
  public static func endpoints(policy: MarketRoutePolicy, gateways: [String]) -> VenueEndpoints {
    endpoints(MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: gateways, api: gateways)))
  }

  /// 中继地址，按主机表逐台（主在前）。订单流不分线路一律走它（拿的是 kanpan-api 主机 `route.apiHosts`）。
  static func relayStreams(_ hosts: [String]) -> [URL] {
    VenueEndpoints.gatewayURLs(hosts, path: VenueEndpoints.relayPrefix + id, query: [])
  }

  // ---------------------------------------------------------------- 限速（官方 Rate limits and user limits）

  /// REST 按 IP 记**权重**、每分钟 1200；客户端预算取 1000 留余量（同一出口上还有网页、别的设备）。
  public static let weightPerMinute: Double = 1000

  /// 各类 `info` 查询的权重（官方表）。
  public enum Weight {
    /// `meta`、`metaAndAssetCtxs`、`fundingHistory` 以及 `candleSnapshot` 的底数。
    public static let info: Double = 20
    /// `allMids`、`l2Book`、`clearinghouseState`、`orderStatus` 这几种轻的。
    public static let light: Double = 2
    /// `candleSnapshot`：20 + 每返回 60 根加 1（按这一页最多能返回的根数记，宁多勿少）。
    public static func candles(_ count: Int) -> Double { info + Double((max(0, count) + 59) / 60) }
  }

  /// 直连那一把：花的是手机自己出口 IP 的额度。行情、订单流（拉 REST 快照的话）、探测都经它。
  public static let directLimiter = VenueRateLimiter(weightPerMinute: weightPerMinute)
  /// 网关那一把：花的是 kanpan-api 出口的额度（服务端另有自己的 `PACER`，这一把只管这台手机别把网关打爆）。
  public static let gatewayLimiter = VenueRateLimiter(weightPerMinute: weightPerMinute)
  /// 这条线路上的那一把（直连与网关是两个出口，各记各的；同一条线路上行情与订单流共用）。
  public static func limiter(_ route: MarketRoute) -> VenueRateLimiter {
    endpoints(route).viaGateway ? gatewayLimiter : directLimiter
  }

  // ---------------------------------------------------------------- 推送（WS 单独计，不占 REST 权重）
  //
  // 官方：每 IP ≤ 10 条连接、每分钟 ≤ 30 次新连接、≤ 1000 个订阅、每分钟 ≤ 2000 条上行。
  // 行情一条连接（`VenueStream` 一条连接多订阅、退避重连），订单流按 8 本一条（`HyperliquidBookAdapter.maxBooks`）。

  /// 推送：两条控制帧之间至少隔多久。官方每 IP 每分钟最多 2000 条上行（≈ 33 条 / 秒），
  /// Hyperliquid 一帧只能说一个订阅，取 100ms（10 条 / 秒）留足余量。
  static let controlGapMs: Double = 100

  /// 应用层保活：Hyperliquid 60 秒收不到任何上行就断开；回 `{"channel":"pong"}`（中继就地答）。
  static let pingText = #"{"method":"ping"}"#
  /// 行情推送每 20 秒一句（官方要求 60 秒内至少一条上行，文档示例 30 秒）：传输层看门狗是 30 秒没帧就重连，
  /// 冷门币可能半分钟一帧行情都没有，pong 要赶在看门狗之前回来。一分钟 3 条，离 2000 条的上限很远。
  static let streamPingEveryMs: Double = 20_000
  /// 订单流那条连接每 30 秒一句（它的静默窗口是 60 秒，见 `orderFlowSilenceMs`）。
  static let orderFlowPingEveryMs: Double = 30_000
  /// 订单流：冷门币可能很久没有成交、盘口也不动（整本没变就不推），60 秒没帧才算断。
  static let orderFlowSilenceMs: Double = 60_000

  /// 资金费率每小时结算一次。
  static let fundingIntervalMs: Int64 = 3_600_000

  /// 下一次结算：下一个整点（UTC）。
  static func nextFundingTimeMs(nowMs: Int64) -> Int64 {
    (Int64(floor(Double(nowMs) / Double(fundingIntervalMs))) + 1) * fundingIntervalMs
  }

  // ---------------------------------------------------------------- 代号

  /// 看盘键里的代号是 coin 名的大写（`InstrumentID` 一律大写：`kPEPE` → `KPEPE`），上游要原名。
  /// 「大写 → 原名」这张表从品种表（`meta.universe`）来：提供者每拉到一次 `meta` / `metaAndAssetCtxs` 就记一次。
  static let names = HyperliquidNames()

  /// 交易所原名（`kPEPE`）→ 品种键（`hyperliquid/usd_m/KPEPE`）。
  static func key(_ coin: String) -> String {
    InstrumentID(venue: id, market: market, symbol: coin).key
  }

  /// 品种键 → 上游原名。表里没有就用大写原样（绝大多数币本来就是大写）。
  static func coin(_ key: String, names: HyperliquidNames = HyperliquidVenue.names) -> String {
    let upper = InstrumentID(key).symbol
    return names.original(upper) ?? upper
  }

  /// 这个大写代号译回原名之前要不要先拉一次品种表：表还没拉过、又是 `K` 开头（千枚计价 `kPEPE` 这类
  /// 唯一会有小写的形状）才要。别的币首屏照样一发。
  static func needsNames(_ key: String, names: HyperliquidNames = HyperliquidVenue.names) -> Bool {
    let upper = InstrumentID(key).symbol
    return upper.hasPrefix("K") && names.original(upper) == nil && !names.loaded
  }

  // ---------------------------------------------------------------- 周期

  /// Hyperliquid `candleSnapshot` / `candle` 认的周期名。看盘 14 档里 6h、1y 没有（6h ← 2h、1y ← 1M 由上层聚）；
  /// 它另有的 8h、3d 看盘不用。
  static func interval(_ interval: Interval) -> String? {
    switch interval {
    case .m1, .m3, .m5, .m15, .m30, .h1, .h2, .h4, .h12, .d1, .w1, .mo1: interval.rawValue
    case .h6, .y1: nil
    }
  }
}

/// 「大写 → 原名」表（`KPEPE` → `kPEPE`）。推送协议（`HyperliquidWire.subs`）是同步的，所以用锁不用 actor。
final class HyperliquidNames: @unchecked Sendable {
  private let lock = NSLock()
  private var table: [String: String] = [:]
  private var didLoad = false

  /// 拉到过一次品种表没有。
  var loaded: Bool { lock.lock(); defer { lock.unlock() }; return didLoad }

  func original(_ upper: String) -> String? {
    lock.lock(); defer { lock.unlock() }
    return table[upper]
  }

  /// 记一份品种表里的全部原名（下架的也记：历史 K 线还拿得到）。只增不删。
  func record(_ coins: [String]) {
    lock.lock(); defer { lock.unlock() }
    for coin in coins where !coin.isEmpty { table[coin.uppercased()] = coin }
    if !coins.isEmpty { didLoad = true }
  }
}
