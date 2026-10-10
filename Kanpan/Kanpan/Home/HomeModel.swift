import Foundation
import KanpanCore
import KanpanNetwork

/// 首页（PROJECT.md §79）：「异动」一列 + 「榜单」三张卡。挂在 `MainScreen` 的 `@State` 上——
/// 首页每切走一次整页拆掉重建，列表的顺序、拉到的数、选的窗口都得活在页外面。
///
/// 「异动」打开时定序，之后每 60 秒拉一次：已在列表里的行就地换数、不换位；新出现的、或同一只又有了更新的
/// 只计数（浮「有 N 条新异动」药丸），点药丸 / 下拉刷新才按服务端顺序重排（和手机网页 `highlights/home.ts` 同一套）。
@MainActor
@Observable
final class HomeModel {
  enum Segment: String, CaseIterable { case moves, board }
  enum Chip: Hashable { case all, cat(HighlightsBoard.Category) }

  typealias BoardFetch = @MainActor ([String]) async -> HighlightsBoard?
  typealias MarketFetch = @MainActor (MarketBoard.Kind, MarketBoard.Window) async -> MarketBoard?

  static let windowKey = "kanpan.home.boardWindow"
  static let pollSeconds = 60

  var segment: Segment = .moves
  var chip: Chip = .all

  // MARK: 异动

  /// 正在显示的那一列（定序后的）。nil = 还没拉到过。
  private(set) var shown: [HighlightsBoard.Row]?
  private(set) var latest: [HighlightsBoard.Row]?
  private(set) var generatedAtMs: Int64 = 0
  /// 最近一次没取到。手里有旧的就照摆、写「停于」。
  private(set) var failed = false
  /// 每次重排加一：列表滚回顶。
  private(set) var reorderToken = 0
  /// 上一次带去的自选币名（换人、加减自选之后第一轮直接重排）。
  @ObservationIgnored private var lastBases: [String]?

  /// 还没算进列表的新异动条数。
  var fresh: Int {
    guard let shown, let latest else { return 0 }
    return Self.merge(shown: shown, latest: latest).fresh
  }

  var visibleRows: [HighlightsBoard.Row] {
    let rows = shown ?? []
    switch chip {
    case .all: return rows
    case .cat(let c): return rows.filter { $0.cat == c }
    }
  }

  func count(_ chip: Chip) -> Int {
    let rows = shown ?? []
    switch chip {
    case .all: return rows.count
    case .cat(let c): return rows.lazy.filter { $0.cat == c }.count
    }
  }

  /// 新拉到的并进正在显示的：顺序不动，已有的换成新数据；没了的留着旧数据；新来的（或同一只更新了的）只计数。
  static func merge(shown: [HighlightsBoard.Row], latest: [HighlightsBoard.Row]) -> (rows: [HighlightsBoard.Row], fresh: Int) {
    let byBase = Dictionary(latest.map { ($0.base, $0) }, uniquingKeysWith: { a, _ in a })
    let had = Dictionary(shown.map { ($0.base, $0) }, uniquingKeysWith: { a, _ in a })
    let fresh = latest.reduce(0) { n, r in
      guard let old = had[r.base] else { return n + 1 }
      return r.atMs > old.atMs ? n + 1 : n
    }
    return (shown.map { byBase[$0.base] ?? $0 }, fresh)
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

  /// 拉一份。`reorder` = 按服务端顺序重排（首次、点药丸、下拉刷新、换了自选）。
  func load(bases: [String], reorder: Bool, fetch: BoardFetch) async {
    let changed = lastBases != nil && lastBases != bases
    lastBases = bases
    guard let board = await fetch(bases) else { failed = true; return }
    failed = false
    generatedAtMs = board.generatedAtMs
    latest = board.rows
    if reorder || changed || shown == nil {
      shown = board.rows
      reorderToken += 1
    } else if let shown {
      self.shown = Self.merge(shown: shown, latest: board.rows).rows
    }
  }

  /// 点「有 N 条新异动」：按服务端顺序重排、滚回顶。
  func reorderNow() {
    guard let latest else { return }
    shown = latest
    reorderToken += 1
  }

  /// 一轮一轮拉，直到任务取消（离开首页、换段、换自选）。
  func pollMoves(bases: [String], fetch: BoardFetch) async {
    while !Task.isCancelled {
      await load(bases: bases, reorder: false, fetch: fetch)
      try? await Task.sleep(for: .seconds(Self.pollSeconds))
    }
  }

  // MARK: 榜单

  /// 榜单窗口：只记在本机（不进同步字段），出厂 4 时。
  var window: MarketBoard.Window {
    didSet { if window != oldValue { defaults.set(window.rawValue, forKey: Self.windowKey) } }
  }
  private(set) var boards: [MarketBoard.Kind: MarketBoard] = [:]
  /// 每张卡最近一次是不是没取到。
  private(set) var boardFailed: Set<MarketBoard.Kind> = []
  /// 哪几张卡点了「全部」。
  var expanded: Set<MarketBoard.Kind> = []
  @ObservationIgnored private var boardsWindow: MarketBoard.Window?
  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    window = defaults.string(forKey: Self.windowKey).flatMap(MarketBoard.Window.init(rawValue:)) ?? .h4
  }

  func loadBoards(fetch: @escaping MarketFetch) async {
    let w = window
    if boardsWindow != w { boards = [:]; boardFailed = []; boardsWindow = w }
    // 三张卡一起问（各自独立成败）。
    async let oi = fetch(.oi, w)
    async let gainers = fetch(.gainers, w)
    async let losers = fetch(.losers, w)
    let answers: [(MarketBoard.Kind, MarketBoard?)] = [(.oi, await oi), (.gainers, await gainers), (.losers, await losers)]
    guard window == w else { return }
    for (kind, board) in answers {
      if let board { boards[kind] = board; boardFailed.remove(kind) } else { boardFailed.insert(kind) }
    }
  }

  func pollBoards(fetch: @escaping MarketFetch) async {
    while !Task.isCancelled {
      await loadBoards(fetch: fetch)
      try? await Task.sleep(for: .seconds(Self.pollSeconds))
    }
  }
}
