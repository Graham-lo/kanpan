import Foundation
import Observation
import KanpanCore

/// 冷切到一只品种之后，「哪几样还在路上」的那块公告板。
///
/// 顶栏六格（`PriceRow`）和图表宿主（`ChartHost`）都在不许改的那一层被造出来
/// （`MainScreenParts`），只拿得到完整品种键，拿不到 `MarketModel`。所以「还在路上」
/// 这件事由 `MarketModel` 写到这儿，按品种键贴；读的人按自己手里那只的键来查，
/// 键不对就当没有——上一只留下的条目不会被下一只认领。
///
/// 只表达「在路上」：真到了、真没有（后端答了空）或者等过了 `deadline`，条目就撤掉，
/// 那一格回到破折号。骨架永远不会一直挂着。
@MainActor @Observable
final class ArrivalBoard {
  static let live = ArrivalBoard()

  /// 顶栏还在路上的几样。按数据来源分，不按格子分：一样数据可能喂好几格（供应量喂市值与估值）。
  struct HeaderPending: OptionSet, Hashable, Sendable {
    let rawValue: Int
    /// 持仓量（仓、O/M）。
    static let openInterest = HeaderPending(rawValue: 1 << 0)
    /// 供应量 / 估值底数（市值、O/M、FPE、P/S）。
    static let meta = HeaderPending(rawValue: 1 << 1)
    /// 资金费率与下次结算（费率、结算）。
    static let funding = HeaderPending(rawValue: 1 << 2)
    /// 24h 统计帧（额；市值要乘的那口价）。
    static let ticker = HeaderPending(rawValue: 1 << 3)
    static let all: HeaderPending = [.openInterest, .meta, .funding, .ticker]
  }

  /// 图还没有一根 K 线时摆的那张占位图：这只的 24h 区间与最新价（都可能还没有）。
  struct ChartPlaceholder: Equatable, Sendable {
    var instrument: String
    var last: Double?
    var low: Double?
    var high: Double?
  }

  /// 等多久还没到就不再算「在路上」：骨架撤掉，那一格回到破折号。
  static let deadline: Duration = .seconds(6)

  private(set) var headerInstrument: String?
  private(set) var header: HeaderPending = []
  private(set) var chart: ChartPlaceholder?

  /// 这只品种顶栏还有哪几样在路上。键对不上就是空。
  func header(for instrument: String) -> HeaderPending {
    headerInstrument == instrument ? header : []
  }

  /// 这只品种眼下要不要摆占位图。
  func chartPlaceholder(for instrument: String?) -> ChartPlaceholder? {
    guard let chart, instrument == nil || chart.instrument == instrument else { return nil }
    return chart
  }

  /// 全局那一份只给图表宿主读（它手里没有品种键，`state == nil` 时只知道「图是空的」）。
  var currentChartPlaceholder: ChartPlaceholder? { chart }

  func setHeader(_ pending: HeaderPending, for instrument: String) {
    if headerInstrument != instrument { headerInstrument = instrument }
    if header != pending { header = pending }
  }

  func setChart(_ placeholder: ChartPlaceholder?) {
    if chart != placeholder { chart = placeholder }
  }
}

extension ArrivalBoard.HeaderPending {
  /// 六格各自在等哪几样（`PriceRow` 照它决定画骨架还是破折号）。
  func covers(_ cell: ArrivalBoard.HeaderCell, hasPrice: Bool) -> Bool {
    switch cell {
    case .openInterest: contains(.openInterest)
    case .turnover, .price, .change: contains(.ticker)
    case .funding, .settlement: contains(.funding)
    case .marketCap: contains(.meta) || (!hasPrice && contains(.ticker))
    case .valuation: contains(.meta) || contains(.openInterest) || (!hasPrice && contains(.ticker))
    }
  }
}

extension ArrivalBoard {
  /// 右侧六格，加上左边的最新价与涨跌那一行（逐笔成交先到、24h 统计还在路上时，涨跌那行也是骨架）。
  enum HeaderCell: CaseIterable, Sendable {
    case openInterest, marketCap, settlement, turnover, funding, valuation, price, change
  }

  /// 这一格画骨架吗：值还没有，而它等的那样东西还在路上。
  nonisolated static func showsSkeleton(_ cell: HeaderCell, hasValue: Bool, pending: HeaderPending, hasPrice: Bool) -> Bool {
    !hasValue && pending.covers(cell, hasPrice: hasPrice)
  }
}
