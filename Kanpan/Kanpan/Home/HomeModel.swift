import Foundation
import KanpanCore
import KanpanNetwork

/// 首页（PROJECT.md §79）：「异动」一列 +「涨跌」「持仓」两段榜单（各两张、各自记窗口）+「板块」（原底栏「板块分类」那一页，2026-10-10 并进来）。挂在 `MainScreen` 的 `@State` 上——
/// 首页每切走一次整页拆掉重建，列表的顺序、拉到的数、选的窗口都得活在页外面。
///
/// 「异动」每 60 秒自动更新，直接展示最新数据；后台更新不要求确认，也不触发滚回顶部。
@MainActor
@Observable
final class HomeModel {
  enum Segment: String, CaseIterable {
    case moves, change, oi, sectors

    /// 这一段摆哪两张榜（异动、板块两段没有）。
    var kinds: [MarketBoard.Kind] {
      switch self {
      case .moves, .sectors: []
      case .change: [.gainers, .losers]
      case .oi: [.oi, .oidown]
      }
    }

    /// 窗口记在本机的键。涨跌沿用旧「榜单」的键，升级上来的人选过的窗口不丢。
    var windowKey: String? {
      switch self {
      case .moves, .sectors: nil
      case .change: "kanpan.home.boardWindow"
      case .oi: "kanpan.home.oiWindow"
      }
    }
  }
  enum Chip: Hashable { case all, cat(HighlightsBoard.Category) }

  typealias BoardFetch = @MainActor ([String]) async -> HighlightsBoard?
  typealias MarketFetch = @MainActor (MarketBoard.Kind, MarketBoard.Window) async -> MarketBoard?

  static let windowKey = "kanpan.home.boardWindow"
  static let pollSeconds = 60

  var segment: Segment = .moves
  var chip: Chip = .all

  // MARK: 异动

  /// 正在显示的最新一列。nil = 还没拉到过。
  private(set) var shown: [HighlightsBoard.Row]?
  private(set) var generatedAtMs: Int64 = 0
  /// 最近一次没取到。手里有旧的就照摆、写「停于」。
  private(set) var failed = false
  /// 手动下拉刷新加一：列表滚回顶。
  private(set) var reorderToken = 0
  var visibleRows: [HighlightsBoard.Row] {
    let rows = shown ?? []
    switch chip {
    case .all: return rows
    case .cat(let c): return rows.filter { $0.cat == c }
    }
  }

  /// 自选里的币名（去掉缩放前缀、去重、保序，最多 60 只）。
  static func favoriteBases(_ favorites: [String]) -> [String] {
    var out: [String] = []
    for key in favorites {
      let base = OrderFlowBase.normalize(Alert.base(of: key)).base
      if OrderFlowBase.isValid(base), !out.contains(base) { out.append(base) }
      if out.count >= OrderFlowCatalog.highlightsMaxBases { break }
    }
    return out
  }

  /// 点异动行要不要自动升「盘口要点」半页：波动行只开图（它说的是价格本身，半页里没有对应的那条）。
  static func opensSheet(_ row: HighlightsBoard.Row) -> Bool { row.cat != .move }

  /// 拉一份最新列表。只有手动刷新（reorder）才通知界面滚回顶。
  func load(bases: [String], reorder: Bool, fetch: BoardFetch) async {
    guard let board = await fetch(bases) else { failed = true; return }
    failed = false
    generatedAtMs = board.generatedAtMs
    shown = board.rows
    if reorder { reorderToken += 1 }
  }

  /// 一轮一轮拉，直到任务取消（离开首页、换段、换自选）。
  func pollMoves(bases: [String], fetch: BoardFetch) async {
    while !Task.isCancelled {
      await load(bases: bases, reorder: false, fetch: fetch)
      try? await Task.sleep(for: .seconds(Self.pollSeconds))
    }
  }

  // MARK: 榜单

  /// 涨跌、持仓两段各记各的窗口：只记在本机（不进同步字段），出厂 4 时。
  private(set) var windows: [Segment: MarketBoard.Window] = [:]
  private(set) var boards: [MarketBoard.Kind: MarketBoard] = [:]
  /// 每张榜最近一次是不是没取到。
  private(set) var boardFailed: Set<MarketBoard.Kind> = []
  /// 哪几张榜点了「全部」。
  var expanded: Set<MarketBoard.Kind> = []
  /// 每张榜手里那份是按哪个窗口拉的（换窗口先清掉，免得新窗口下摆旧数）。
  @ObservationIgnored private var boardsWindow: [MarketBoard.Kind: MarketBoard.Window] = [:]
  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    for seg in Segment.allCases {
      guard let key = seg.windowKey else { continue }
      windows[seg] = defaults.string(forKey: key).flatMap(MarketBoard.Window.init(rawValue:)) ?? .h4
    }
  }

  func window(for segment: Segment) -> MarketBoard.Window { windows[segment] ?? .h4 }

  func setWindow(_ w: MarketBoard.Window, for segment: Segment) {
    guard let key = segment.windowKey, windows[segment] != w else { return }
    windows[segment] = w
    defaults.set(w.rawValue, forKey: key)
  }

  /// 拉这一段的两张榜（一起问、各自成败）。
  func loadBoards(segment: Segment, fetch: @escaping MarketFetch) async {
    let kinds = segment.kinds
    guard kinds.count == 2 else { return }
    let w = window(for: segment)
    for kind in kinds where boardsWindow[kind] != w {
      boards[kind] = nil; boardFailed.remove(kind); boardsWindow[kind] = w
    }
    async let first = fetch(kinds[0], w)
    async let second = fetch(kinds[1], w)
    let answers: [(MarketBoard.Kind, MarketBoard?)] = [(kinds[0], await first), (kinds[1], await second)]
    guard window(for: segment) == w else { return }
    for (kind, board) in answers {
      if let board { boards[kind] = board; boardFailed.remove(kind) } else { boardFailed.insert(kind) }
    }
  }

  func pollBoards(segment: Segment, fetch: @escaping MarketFetch) async {
    while !Task.isCancelled {
      await loadBoards(segment: segment, fetch: fetch)
      try? await Task.sleep(for: .seconds(Self.pollSeconds))
    }
  }
}
