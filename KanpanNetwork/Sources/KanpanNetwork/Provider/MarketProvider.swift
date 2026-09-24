import Foundation
import KanpanCore

/// 一家交易所的行情提供者。上层只跟这个协议和 `ProviderCapabilities` 说话。
///
/// 约定：
/// - 进出的品种一律是 `InstrumentID.key`（`venue/market/symbol`）。向交易所发请求时
///   由提供者自己取裸符号。
/// - `klines` 返回的是**源周期**（`capabilities.source(for:)`）的 K 线，按开盘时间升序、
///   毫秒时间戳、数值已经是 `Double`。聚合（3m←1m、1y←1M……）由上层的
///   `MarketSeries.series` / `MarketFeed` 做，提供者不做。
/// - `limit` 按源周期根数计，最多 `capabilities.maxKlines`；超过交易所单页上限时
///   提供者自己翻页。
/// - 没有的能力（持仓量、资金费率、衍生统计）不用实现，默认抛 `FeedError.unsupported`，
///   上层按能力位根本不会来问。
public protocol MarketProvider: Sendable {
  var capabilities: ProviderCapabilities { get }

  /// 这家交易所可交易的品种表（已经按 `quoteAssets` / 上线状态筛过）。
  func instruments() async throws -> [SymbolInfo]

  func klines(symbol: String, interval: Interval, limit: Int,
              startTime: Int64?, endTime: Int64?) async throws -> [Bar]
  /// 从 `from` 起一直补到现在（可能翻好几页）。断线补缺用。
  func contiguousTail(symbol: String, interval: Interval, from: Int64) async throws -> [Bar]
  /// 向前翻 `pages` 页（每页 `capabilities.maxKlines` 根），返回从早到晚、无重复的一段。
  func history(symbol: String, interval: Interval, pages: Int, before firstOpen: Int64) async throws -> [Bar]

  func ticker24h(symbol: String, timeout: TimeInterval) async throws -> Ticker
  func tickers24h(timeout: TimeInterval) async throws -> [Ticker]

  func funding(symbol: String) async throws -> FundingSnapshot
  /// 全市场资金费率一次拿回（键是这家的完整品种 key）。只有 `hasFunding` 的那家才有，
  /// 且不是每家都给得出整表——给不出就抛 `unsupported`，调用方只少一份「先垫上」的数。
  func fundingAll() async throws -> [String: FundingSnapshot]
  func openInterestHist(symbol: String, period: String, limit: Int,
                        startTime: Int64?, endTime: Int64?) async throws -> [OIPoint]
  func globalLongShortAccountRatio(symbol: String, period: String, limit: Int,
                                   startTime: Int64?, endTime: Int64?) async throws -> [LongShortRatioPoint]
  func takerLongShortRatio(symbol: String, period: String, limit: Int,
                           startTime: Int64?, endTime: Int64?) async throws -> [TakerRatioPoint]
  func basis(symbol: String, period: String, limit: Int,
             startTime: Int64?, endTime: Int64?) async throws -> [BasisPoint]
  /// 持仓量等统计的逐日归档（公开归档站）。没有就返回 nil。
  func metricsArchiveURL(symbol: String, day: String) -> URL?

  /// 只清线路冷却（用户点「点此重试」）。不动上游给的限流封禁。
  func resetRouteCooldowns() async

  /// 新建一条推送连接。`silenceMs` 是连上之后等第一帧行情的窗口。
  func makeStream(silenceMs: Double?, log: FeedLog) -> any MarketStream
  /// 这条线路上的推送此刻能不能连上（巡检用）。只握手，不订阅也不等帧。
  func probeStream(symbol: String, interval: Interval) async -> Bool
  /// 一条已经带好订阅、连上就推的原始推送地址（命令行录回放报文用）。做不到就给 nil。
  func rawStreamURL(topics: [StreamTopic]) -> URL?
  /// 主力订单流的深度接入（实现在 `OrderFlow/`）。这条线路上没有深度就是 nil。
  func orderFlowAdapter(symbol: String) -> (any DepthFeedAdapter)?

  /// 冷启动热身：这条线路上首屏最先要连的那几台主机（只握手，回什么都不管）。
  /// 由线路决定——直连热交易所自己的域名，网关热网关；不给就不热。
  var prewarmTargets: [PrewarmTarget] { get }
  /// 桌面小组件在 app 不在前台时自己补价的取数方式（也由线路决定）。做不到就 nil。
  var widgetRefresh: WidgetSnapshot.Refresh? { get }
}

/// 冷启动热身的一笔请求。
public struct PrewarmTarget: Sendable, Equatable {
  public let url: URL
  public let method: String
  public init(url: URL, method: String) { self.url = url; self.method = method }

  /// `host` 可以带端口；形状不对（带路径、账号、查询）就不给。
  public static func make(host: String, path: String, method: String) -> PrewarmTarget? {
    guard host.range(of: "^[A-Za-z0-9.-]+(:[0-9]+)?$", options: .regularExpression) != nil,
          var parts = URLComponents(string: "https://" + host), parts.host != nil else { return nil }
    parts.path = path
    return parts.url.map { PrewarmTarget(url: $0, method: method) }
  }
}

public extension MarketProvider {
  var prewarmTargets: [PrewarmTarget] { [] }
  var widgetRefresh: WidgetSnapshot.Refresh? { nil }

  func klines(symbol: String, interval: Interval, limit: Int) async throws -> [Bar] {
    try await klines(symbol: symbol, interval: interval, limit: limit, startTime: nil, endTime: nil)
  }
  func klines(symbol: String, interval: Interval, limit: Int, startTime: Int64) async throws -> [Bar] {
    try await klines(symbol: symbol, interval: interval, limit: limit, startTime: startTime, endTime: nil)
  }
  func klines(symbol: String, interval: Interval, limit: Int, endTime: Int64) async throws -> [Bar] {
    try await klines(symbol: symbol, interval: interval, limit: limit, startTime: nil, endTime: endTime)
  }
  func ticker24h(symbol: String) async throws -> Ticker { try await ticker24h(symbol: symbol, timeout: 15) }
  func tickers24h() async throws -> [Ticker] { try await tickers24h(timeout: 8) }

  /// 最新一屏，聚好周期。
  func latestSeries(symbol: String, interval: Interval, limit: Int) async throws -> BarSeries {
    let bars = try await klines(symbol: symbol, interval: interval, limit: limit)
    return MarketSeries.series(symbol: symbol, interval: interval, bars: bars, capabilities: capabilities)
  }

  func funding(symbol: String) async throws -> FundingSnapshot { throw FeedError.unsupported("资金费率") }
  func fundingAll() async throws -> [String: FundingSnapshot] { throw FeedError.unsupported("全市场资金费率") }
  func openInterestHist(symbol: String, period: String, limit: Int,
                        startTime: Int64?, endTime: Int64?) async throws -> [OIPoint] {
    throw FeedError.unsupported("持仓量")
  }
  func globalLongShortAccountRatio(symbol: String, period: String, limit: Int,
                                   startTime: Int64?, endTime: Int64?) async throws -> [LongShortRatioPoint] {
    throw FeedError.unsupported("多空比")
  }
  func takerLongShortRatio(symbol: String, period: String, limit: Int,
                           startTime: Int64?, endTime: Int64?) async throws -> [TakerRatioPoint] {
    throw FeedError.unsupported("主动买卖比")
  }
  func basis(symbol: String, period: String, limit: Int,
             startTime: Int64?, endTime: Int64?) async throws -> [BasisPoint] {
    throw FeedError.unsupported("基差")
  }
  func metricsArchiveURL(symbol: String, day: String) -> URL? { nil }
  func rawStreamURL(topics: [StreamTopic]) -> URL? { nil }
  func tickers24h(timeout: TimeInterval) async throws -> [Ticker] { throw FeedError.unsupported("全市场行情") }
}

/// 一条行情推送连接。切品种、切周期只换订阅，不重连。
public protocol MarketStream: AnyObject, Sendable {
  func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent>
  func replace(topics: [StreamTopic]) async
  func stop() async
  /// 连上之后等第一帧行情的窗口（毫秒）。
  var firstFrameSilenceMs: Double { get async }
  var currentConnectionID: Int { get async }
}

/// 行情线路要用到的主机。和哪家交易所无关：各家提供者自己从这里取自己要的那部分。
///
/// 只有网关这一样。各家交易所的直连域名是那一家提供者自己的出厂值（写死在它的目录里），
/// 原来这里还有「用户自定义 REST / 推送域名」两栏，设置页早就没有入口，只剩一整层
/// 往下透传的死配置，2026-09-24 按审查 18a 收掉。
public struct MarketEndpoints: Sendable, Equatable {
  /// 看盘自己的网关，主在前、备在后。
  public var gateways: [String]
  /// kanpan-api 完整版所在的主机（`MarketRoute.apiHosts`）。不给就取网关表的第一台（主机）。
  public var api: [String]

  public init(gateways: [String] = [], api: [String]? = nil) {
    self.gateways = Self.unique(gateways)
    self.api = Self.unique(api ?? Array(self.gateways.prefix(1)))
  }

  private static func unique(_ hosts: [String]) -> [String] {
    var seen = Set<String>()
    return hosts.filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  /// 没有网关的空表：只给测试和「只走直连」的离线工具用。app 里一律用 `production`。
  public static let `default` = MarketEndpoints()

  /// 线上那两台网关（美国 VPS），主在前、备在后。app 里所有取数件都从 `RouteResolver.current`
  /// 拿到这一份，不再各自拼。
  /// 地址本身只在 `ServerHosts` 一处。
  public static let production = MarketEndpoints(gateways: ServerHosts.gateways, api: ServerHosts.api)
}

/// 与交易所无关的 K 线序列小工具。
public enum MarketSeries {
  /// 一串源周期 K 线 → 目标周期的 `BarSeries`（聚出来的周期在这儿聚）。
  public static func series(symbol: String, interval: Interval, bars: [Bar],
                            capabilities: ProviderCapabilities) -> BarSeries {
    series(symbol: symbol, interval: interval, source: capabilities.source(for: interval), bars: bars)
  }

  public static func series(symbol: String, interval: Interval, source: Interval, bars: [Bar]) -> BarSeries {
    let src = BarSeries(symbol: symbol, interval: source, bars: dedup(bars))
    if source != interval {
      return Aggregator.bucket(series: src, into: interval)
    }
    return src
  }

  /// 按 openTime 升序去重，同一 openTime 留最后出现的那根（网络上后到的更新）。
  public static func dedup(_ bars: [Bar]) -> [Bar] {
    guard bars.count > 1 else { return bars }
    var byTime: [Int64: Bar] = [:]
    byTime.reserveCapacity(bars.count)
    for b in bars { byTime[b.openTime] = b }
    return byTime.keys.sorted().map { byTime[$0]! }
  }
}
