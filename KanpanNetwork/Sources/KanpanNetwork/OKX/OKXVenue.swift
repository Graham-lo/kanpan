import Foundation
import KanpanCore

/// OKX 这一家的**唯一事实来源**：身份、地址、限速、代号与周期互译、推送的两个端点与保活。
/// 行情提供者（`OKXProvider`）、推送（`OKXWire`）、订单流（`OKXBooksAdapter`）全从这里取，
/// 不许各写一份域名或路径。
///
/// 只收 **USDT 线性永续**（`market = usd_m`）。看盘键是币安形状的 `BTCUSDT`（`okx/usd_m/BTCUSDT`，
/// 同一只币和币安只差 venue），OKX 原生的 `instId` 是 `BTC-USDT-SWAP`，两者的互译只在这里
/// （和服务端 `venues/okx/mod.rs` 的 `inst_id` / `key_of` 同一口径）。
///
/// 两条线路：直连打 OKX 自己的域名；网关打看盘自己的 kanpan-api（REST 原样透传
/// `/v1/market/raw/api/v5/…?source=okx`，推送是帧原样转发的中继 `/v1/market/ws/okx`），
/// 报文一字不差——解码（`OKXDTO`）两条线路共用一份，差别只在 URL。
///
/// 推送分两个端点（官方文档 WebSocket › Overview）：行情 / 逐笔 / 标记价 / 资金费率在 public，
/// K 线（`candle*`）2023 年起只在 business。中继上 business 端点加 `?endpoint=business`。
public enum OKXVenue {
  public static let id = "okx"
  public static let market = "usd_m"
  public static let displayName = "OKX"
  /// 品种展示里的缩写（见 `VenueDescriptor.shortName`）。
  public static let shortName = "OKX"
  /// 只收 USDT 结算的线性永续。
  public static let quote = "USDT"
  /// instId 的后缀：`BTC-USDT-SWAP`。
  static let swapSuffix = "-USDT-SWAP"

  public static let restHost = "www.okx.com"
  public static let streamHost = "ws.okx.com:8443"
  /// 直连推送：public 端点（行情、逐笔、标记价、资金费率、订单流的盘口）。
  public static let publicStreamURL = URL(string: "wss://\(streamHost)/ws/v5/public")!
  /// 直连推送：business 端点（K 线）。
  public static let businessStreamURL = URL(string: "wss://\(streamHost)/ws/v5/business")!

  /// 推送的两个端点。
  public enum Endpoint: String, Sendable, CaseIterable {
    case `public`, business
  }

  /// 地址表：REST 路径从 `api/v5/` 写起（透传白名单认的就是这一截），前缀只是 `/`；网关上是中继。
  public static let spec = VenueEndpoints.Spec(
    source: id, restHost: restHost, restPrefix: "/",
    directStreams: [publicStreamURL], gatewayStream: .relay)
  /// business 端点的地址表：只有直连推送地址不同；中继上同一条路径加 `?endpoint=business`。
  static let businessSpec = VenueEndpoints.Spec(
    source: id, restHost: restHost, restPrefix: "/",
    directStreams: [businessStreamURL], gatewayStream: .relay)

  public static func endpoints(_ route: MarketRoute) -> VenueEndpoints { VenueEndpoints(spec, route: route) }

  /// 测试与命令行用：线路档位 + 网关表（网关表同时当 kanpan-api 主机用）。
  public static func endpoints(policy: MarketRoutePolicy, gateways: [String]) -> VenueEndpoints {
    endpoints(MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: gateways, api: gateways)))
  }

  /// 这条线路上某个端点的推送地址，按顺序试。
  public static func streams(_ endpoint: Endpoint, route: MarketRoute) -> [URL] {
    switch endpoint {
    case .public: return VenueEndpoints(spec, route: route).streams
    case .business:
      return VenueEndpoints(businessSpec, route: route)
        .streams(query: [URLQueryItem(name: "endpoint", value: Endpoint.business.rawValue)])
    }
  }

  /// 订单流的中继地址（不分线路一律经 kanpan-api：国内直连不了 OKX）。`hosts` 是 kanpan-api 主机表。
  static func relayStreams(hosts: [String]) -> [URL] {
    VenueEndpoints.gatewayURLs(hosts, path: VenueEndpoints.relayPrefix + id, query: [])
  }

  /// 公共 REST 按 IP、**按接口各算各的**（官方文档 v5，2026-09 现行）：
  ///
  /// | 接口 | 官方上限 | 客户端用不用 |
  /// |---|---|---|
  /// | `market/candles` | 40 次 / 2 秒 | 首屏、补缺、近处翻页 |
  /// | `market/history-candles` | 20 次 / 2 秒 | 更早的翻页 |
  /// | `market/ticker`、`market/tickers`、`public/instruments`、`public/funding-rate` | 各 20 次 / 2 秒 | 用 |
  /// | `public/mark-price` | 10 次 / 2 秒 | **不用**（标记价只走推送） |
  ///
  /// 通用限速器只有一把总闸，取 8 次 / 秒（= 16 次 / 2 秒）：低于客户端实际会打的每一个接口里最紧的那个
  /// （20 次 / 2 秒），所有接口加起来也不会让任何一个超额。`market/candles` 本可到 40 次 / 2 秒，总闸让
  /// 首屏与后台加深并行的两页错开 125 毫秒，代价可以接受。将来要在 REST 上打 `mark-price`（10 次 / 2 秒）
  /// 必须给它单独一把 ≤ 5 次 / 秒的，或者把总闸压到它之下。
  public static let perSecond: Double = 8
  /// 直连：花的是手机自己出口 IP 的额度。整个进程共用这一把：行情、探测都经它
  /// （订单流不打 REST：盘口快照随推送下发）。
  public static let limiter = VenueRateLimiter(perSecond: perSecond)
  /// 网关：透传花的是服务端出口 IP 的额度（服务端另有这一家的出站节拍），和直连那把分开记。
  public static let gatewayLimiter = VenueRateLimiter(perSecond: perSecond)
  /// 这条线路上用哪一把。
  public static func limiter(_ route: MarketRoute) -> VenueRateLimiter {
    route.viaGateway ? gatewayLimiter : limiter
  }

  /// 推送：两条控制帧之间至少隔多久。OKX 每条连接 subscribe + unsubscribe **合计 480 次 / 小时**
  /// （按请求帧计，不按 args；public、business 两条连接各算各的）。`OKXWire.nextBatch` 一帧装满 12 个 args
  /// 才分下一帧，切一次品种 / 周期就是「一帧退订 + 一帧订阅」；这里再留 350 毫秒间隔（≤ 3 帧 / 秒），
  /// 不让连点切换在一秒里把额度打穿。
  static let controlGapMs: Double = 350
  /// 一条订阅帧最多几个 args：中继放行上限（`relay.rs` 的 `MAX_ARGS`）。
  static let maxArgsPerFrame = 12
  /// 应用层保活：OKX 30 秒没有帧就断。发字面量 `ping`，回字面量 `pong`（不是 JSON）。
  /// 行情推送与订单流两条连接用同一套（中继只放行这一句）。
  static let pingText = "ping"
  static let pongText = "pong"
  static let pingEveryMs: Double = 20_000

  // ---------------------------------------------------------------- 代号

  /// 交易所原生 instId（`BTC-USDT-SWAP`）→ 品种键（`okx/usd_m/BTCUSDT`）。不是 USDT 线性永续的给 nil。
  static func key(instID: String) -> String? {
    guard let base = baseOf(instID: instID) else { return nil }
    return InstrumentID(venue: id, market: market, symbol: base + quote).key
  }

  /// instId 的底名（`BTC-USDT-SWAP` → `BTC`）。不是 `BASE-USDT-SWAP` 形状的给 nil。
  static func baseOf(instID: String) -> String? {
    let upper = instID.uppercased()
    guard upper.hasSuffix(swapSuffix) else { return nil }
    let base = String(upper.dropLast(swapSuffix.count))
    guard !base.isEmpty, base.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else { return nil }
    return base
  }

  /// 品种键（或裸的 `BTCUSDT`）→ OKX 的 instId（`BTC-USDT-SWAP`）。
  static func instID(_ key: String) -> String {
    let symbol = InstrumentID(key).symbol
    let base = symbol.hasSuffix(quote) ? String(symbol.dropLast(quote.count)) : symbol
    return base + swapSuffix
  }

  // ---------------------------------------------------------------- 周期

  /// OKX 的 `bar`。日以上用 UTC 对齐的 `…utc` 那一族（不带后缀的按 UTC+8 开盘，和币安的桶头差八小时）。
  /// 没有 8h / 3d / 1y；1y 由上层从 1M 聚。
  static func bar(_ interval: Interval) -> String? {
    switch interval {
    case .m1: "1m"
    case .m3: "3m"
    case .m5: "5m"
    case .m15: "15m"
    case .m30: "30m"
    case .h1: "1H"
    case .h2: "2H"
    case .h4: "4H"
    case .h6: "6Hutc"
    case .h12: "12Hutc"
    case .d1: "1Dutc"
    case .w1: "1Wutc"
    case .mo1: "1Mutc"
    case .y1: nil
    }
  }

  /// `bar` → 周期（K 线推送的频道名 `candle1H` 去掉前缀之后）。
  static func interval(bar: String) -> Interval? {
    Interval.allCases.first { self.bar($0) == bar }
  }

  /// K 线推送的频道名。
  static func candleChannel(_ interval: Interval) -> String? { bar(interval).map { "candle" + $0 } }

  // ---------------------------------------------------------------- 合约面值

  /// instId → 合约面值（一张合约是多少个币，`ctVal`）。逐笔推送的 `sz` 是张数，要乘它才是币数
  /// （K 线的成交量用的是 `volCcy` 币数，两边单位要一致）。`OKXProvider.instruments()` 拉完品种表后填。
  static let contractValues = ContractValues()

  final class ContractValues: @unchecked Sendable {
    private let lock = NSLock()
    private var table: [String: Double] = [:]
    func set(_ rows: [String: Double]) { lock.lock(); table.merge(rows) { $1 }; lock.unlock() }
    func value(_ instID: String) -> Double? { lock.lock(); defer { lock.unlock() }; return table[instID] }
  }
}
