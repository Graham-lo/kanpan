import Foundation
import KanpanCore

/// 一家行情提供者**能做什么**。
///
/// 上层（图表数据流、报价簿、行情页、品种表）只看这些能力位做决定，
/// 从不问「这是哪家交易所」。接一家新交易所时，这里就是它对上层说清楚
/// 「我有什么、没有什么」的唯一地方：没有资金费率就 `hasFunding = false`，
/// 界面自己把那一格写成「—」，谁也不用写 `if venue == ...`。
public struct ProviderCapabilities: Sendable, Equatable {
  /// 品种身份里的交易所（`InstrumentID.venue`）。
  public var venue: String
  /// 品种身份里的市场（`InstrumentID.market`）。
  public var market: String
  /// 这份数据实际是谁供的。2026-10-08 起各家两条线路供的都是自己的数（币安网关档不再有 OKX 替身），
  /// 所以恒等于 `venue`；字段留着，是因为 app 层拿它给报价簿、费率簿分区，删它要连 app 一起改。
  public var upstream: String
  /// 交易所原生支持的周期。
  public var nativeIntervals: Set<Interval>
  /// 聚出来的周期 → 拿哪一档原生周期去聚（`Aggregator.bucket`）。
  public var aggregatedFrom: [Interval: Interval]
  /// 一次 `klines` 调用最多要多少根（按源周期计）。超过交易所单页上限时由提供者自己翻页。
  public var maxKlines: Int
  /// `contiguousTail` 一次最多能接上多长的缺口（按源周期计）。超过它就接不上了：
  /// 快照不拿来打底、补缺直接整段重拉一屏换掉，不然图上会留一个永久的洞。
  public var maxTailBars: Int
  /// 首屏第一发要多深（按源周期计）。浅的一发先画出来，深度交给后台加深。
  public var initialKlines: Int
  /// 有原生实时 K 线推送的源周期。不在里面的周期靠逐笔成交在本地拼末根，
  /// 外加定时 REST 对表。
  public var liveKlineIntervals: Set<Interval>
  /// 有 24h 行情推送。没有的话由上层定时 REST 补。
  public var hasTickerStream: Bool
  /// 有标记价推送（永续才有）。
  public var hasMarkPrice: Bool
  /// 有资金费率与结算时间（永续才有）。
  public var hasFunding: Bool
  /// 一期资金费率多长（秒）。币安 / OKX / Bybit 的标准档 8 小时，Hyperliquid 每小时一期。
  /// 费率帧自己带下一次结算时刻，这个数只用在「刚结算完、下一帧还没到」那几秒的倒计时往后滚：
  /// 按 8 小时滚，Hyperliquid 就会在整点后短暂写出「7时59分」。
  public var fundingPeriod: TimeInterval
  /// 持仓量统计接口用的上游名（服务端 `/v1/market/open-interest?source=`）。nil = 没有持仓量。
  public var openInterestSource: String?
  /// 有逐笔主动方向与五档盘口推送（主动买卖量、盘口副图）。
  public var hasMicrostructure: Bool
  /// 有持仓量历史、多空比、主动买卖比、基差这类衍生统计（持仓量副图与那几个外部指标）。
  /// 没有的话界面上干脆不给这几个副图，不报错。
  public var hasDerivativeMetrics: Bool
  /// 有持仓量历史（持仓量副图）。和 `hasDerivativeMetrics` 分开：有的交易所给得出持仓量历史，
  /// 却没有多空比、主动买卖比、基差。
  public var hasOpenInterestHistory: Bool
  /// 持仓量历史更早的那段有归档（币安每日 metrics zip、看盘网关按它聚好的区间）。
  /// 没有的话整段都问 `openInterestHist`，问到头就是头，不拿别家的归档来接。
  public var hasOpenInterestArchive: Bool
  /// 一次请求就能拿全市场 24h 行情。
  public var hasBulkTickers: Bool
  /// 行情巡检判断「线路恢复」时，要不要连更早那段历史也探一下。
  public var probesHistoryBoundary: Bool
  /// K 线快照的独立分区。nil = 和同交易所的其它线路共用（品种键里已经带着交易所，不会串）。
  /// 原来给网关替身单独分区用；替身删了以后没有人再给非 nil，留着字段是因为 app 层还在读它。
  public var snapshotNamespace: String?
  /// 收哪些计价资产。
  public var quoteAssets: [String]
  /// 有盘口可聚（主力订单流那一层）。没有盘口的品种（指数）干脆不给这一层，
  /// 行情页上不画、不转圈、不报错。
  public var hasOrderFlow: Bool
  /// 行情帧里的涨跌幅已经是**按交易日**算好的（相对上一交易日收盘，美元指数由服务端算）。
  /// 上层照原样用，不再拿 UTC 0 点那根 K 线的开盘价重算。
  public var hasSessionChange: Bool
  /// K 线带成交量。没有的（美元指数：一个算出来的指数，谁也没在「成交」它）不给成交量副图、
  /// 均量、量差、均价线，顶栏「额」那格也给不出；指标布局本身不动，切回有量的品种原样回来。
  public var hasVolume: Bool

  public init(venue: String, market: String, upstream: String? = nil,
              nativeIntervals: Set<Interval>, aggregatedFrom: [Interval: Interval] = [:],
              maxKlines: Int, maxTailBars: Int? = nil, initialKlines: Int, liveKlineIntervals: Set<Interval>,
              hasTickerStream: Bool, hasMarkPrice: Bool, hasFunding: Bool, fundingPeriod: TimeInterval = 8 * 3600,
              openInterestSource: String?, hasMicrostructure: Bool, hasDerivativeMetrics: Bool,
              hasOpenInterestHistory: Bool = false, hasOpenInterestArchive: Bool = false,
              hasBulkTickers: Bool, probesHistoryBoundary: Bool, snapshotNamespace: String? = nil,
              quoteAssets: [String], hasOrderFlow: Bool = true, hasSessionChange: Bool = false,
              hasVolume: Bool = true) {
    self.venue = venue; self.market = market; self.upstream = upstream ?? venue
    self.nativeIntervals = nativeIntervals; self.aggregatedFrom = aggregatedFrom
    self.maxKlines = maxKlines; self.maxTailBars = maxTailBars ?? maxKlines; self.initialKlines = initialKlines
    self.liveKlineIntervals = liveKlineIntervals
    self.hasTickerStream = hasTickerStream; self.hasMarkPrice = hasMarkPrice; self.hasFunding = hasFunding
    self.fundingPeriod = fundingPeriod
    self.openInterestSource = openInterestSource; self.hasMicrostructure = hasMicrostructure
    self.hasDerivativeMetrics = hasDerivativeMetrics; self.hasBulkTickers = hasBulkTickers
    self.hasOpenInterestHistory = hasOpenInterestHistory; self.hasOpenInterestArchive = hasOpenInterestArchive
    self.probesHistoryBoundary = probesHistoryBoundary; self.snapshotNamespace = snapshotNamespace
    self.quoteAssets = quoteAssets; self.hasOrderFlow = hasOrderFlow
    self.hasSessionChange = hasSessionChange
    self.hasVolume = hasVolume
  }

  /// 真正去网上拉哪一档。原生周期就是它自己，聚出来的周期是它的源周期。
  public func source(for interval: Interval) -> Interval { aggregatedFrom[interval] ?? interval }

  /// 这一档是不是聚出来的（没有原生数据）。
  public func isAggregated(_ interval: Interval) -> Bool { source(for: interval) != interval }

  /// 这一档的末根有没有原生推送。
  public func hasLiveKline(_ interval: Interval) -> Bool { liveKlineIntervals.contains(source(for: interval)) }

  /// 这份数据是不是替身上游供的。替身已经删了（2026-10-08），恒为 false；
  /// app 层还按它分支，等那边收掉再删。
  public var isSubstitute: Bool { upstream != venue }

  /// 这家有没有持仓量。
  public var hasOpenInterest: Bool { openInterestSource != nil }

  /// 这一档在这家能不能看（原生或能聚出来）。
  public func supports(_ interval: Interval) -> Bool {
    nativeIntervals.contains(interval) || aggregatedFrom[interval].map(nativeIntervals.contains) == true
  }
}
