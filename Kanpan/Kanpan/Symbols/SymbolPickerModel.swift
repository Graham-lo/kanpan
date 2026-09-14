import Foundation
import Observation
import KanpanCore

// ============================================================ 品种页的状态
//
// 一个自包含的 ViewModel：品种表 + 行情 + 自选/最近 + 搜索词 → 分区列表。
// 不认识网络，也不认识 KanpanData——品种表和行情都是灌进来的，
// 所以离线可测，宿主想怎么接都行（A5.7 的 `!ticker@arr` 见 SymbolTickerFeed）。

@MainActor
@Observable
final class SymbolPickerModel {
  /// 品种表（USDT 永续），顺序即 `exchangeInfo` 给的顺序。
  private(set) var catalog: [SymbolInfo] = []
  /// symbol（大写）→ 24h 行情。
  private(set) var tickers: [String: Ticker] = [:]
  /// 自选与最近。改完立刻落盘。
  private(set) var prefs = SymbolPrefs()
  /// 搜索框里的原文。改它分区就重算。
  var query: String = "" { didSet { if query != oldValue { rebuild() } } }
  /// 当前要显示的分区。
  private(set) var sections: [SymbolSection] = []
  /// 页头右边的小字：`571 个永续合约`。
  var countText: String { SymbolSections.countText(catalog) }
  /// 搜到 0 个时显示的那一行。
  var emptyText: String { SymbolSections.emptyText }
  /// 一条都没有（没搜到，或者品种表还没到）。
  var isEmpty: Bool { sections.allSatisfy(\.rows.isEmpty) }

  /// 选中一个品种后通知宿主（宿主负责切图、关页）。
  var onPick: ((SymbolInfo) -> Void)?
  /// 订阅 / 退订的日志钩子，A5.7 要求「出页面后退订（日志确认）」。
  var log: ((String) -> Void)?

  private let store: SymbolPrefsStore
  private let feed: SymbolTickerFeed?
  /// 品种表的来源，宿主用 `KanpanData.SymbolCatalog` 填。
  private var catalogLoader: (@Sendable () async -> [SymbolInfo])?
  private var subscribed = false

  init(catalog: [SymbolInfo] = [],
       tickers: [Ticker] = [],
       store: SymbolPrefsStore = SymbolPrefsStore(),
       feed: SymbolTickerFeed? = nil,
       catalogLoader: (@Sendable () async -> [SymbolInfo])? = nil) {
    self.catalog = catalog
    self.store = store
    self.feed = feed
    self.catalogLoader = catalogLoader
    self.prefs = store.load()
    apply(tickers)
    rebuild()
  }

  /// 品种表的来源晚一步才知道（宿主要先把 `KanpanData` 那侧建起来）。
  /// 只在还没进过页面时补得上，进过之后 `catalog` 已经填好了，换不换都无所谓。
  func setLoader(_ loader: @escaping @Sendable () async -> [SymbolInfo]) {
    catalogLoader = loader
  }

  // ---------------------------------------------------------------- 生命周期

  /// 进页：补品种表、订阅行情。
  func appear() async {
    subscribe()
    if let catalogLoader, catalog.isEmpty {
      let list = await catalogLoader()
      setCatalog(list)
    }
  }

  /// 出页：退订。图不受影响，自选 / 最近已经落过盘了。
  func disappear() {
    guard subscribed else { return }
    subscribed = false
    feed?.stop()
    log?("品种页退订 !ticker@arr")
  }

  private func subscribe() {
    guard !subscribed, let feed else { return }
    subscribed = true
    log?("品种页订阅 !ticker@arr")
    feed.start { [weak self] batch in
      self?.apply(batch)
      self?.rebuild()
    }
  }

  // ---------------------------------------------------------------- 灌数据

  func setCatalog(_ list: [SymbolInfo]) {
    catalog = list
    rebuild()
  }

  /// 行情按 symbol 覆盖写；`!ticker@arr` 每 1s 推一批，只推变动的。
  func apply(_ batch: [Ticker]) {
    guard !batch.isEmpty else { return }
    for t in batch { tickers[t.symbol.uppercased()] = t }
  }

  func ticker(for symbol: String) -> Ticker? { tickers[SymbolPrefs.key(symbol)] }

  // ---------------------------------------------------------------- 自选

  func isFavorite(_ symbol: String) -> Bool { prefs.isFavorite(symbol) }

  /// 星星：一点加、再点移除（§10.5）。
  @discardableResult
  func toggleFavorite(_ symbol: String) -> Bool {
    prefs.toggleFavorite(symbol)
    commit()
    return prefs.isFavorite(symbol)
  }

  func removeFavorite(_ symbol: String) {
    prefs.removeFavorite(symbol)
    commit()
  }

  /// 自选分区左滑删除（`onDelete` 给的是分区内下标）。
  func removeFavorites(at offsets: IndexSet) {
    let doomed = offsets.compactMap { $0 < prefs.favorites.count ? prefs.favorites[$0] : nil }
    for s in doomed { prefs.removeFavorite(s) }
    commit()
  }

  func moveFavorites(from source: IndexSet, to destination: Int) {
    prefs.moveFavorites(from: source, to: destination)
    commit()
  }

  /// 长按拖动落在某一行上。
  func moveFavorite(_ symbol: String, onto target: String) {
    prefs.moveFavorite(symbol, onto: target)
    commit()
  }

  // ---------------------------------------------------------------- 最近

  /// 点一行：记进最近、落盘、通知宿主。
  func pick(_ info: SymbolInfo) {
    prefs.visit(info.symbol)
    commit()
    onPick?(info)
  }

  func pick(symbol: String) {
    guard let info = catalog.first(where: { $0.symbol.uppercased() == SymbolPrefs.key(symbol) }) else { return }
    pick(info)
  }

  // ---------------------------------------------------------------- 内务

  private func commit() {
    store.save(prefs)
    rebuild()
  }

  private func rebuild() {
    sections = SymbolSections.build(catalog: catalog, tickers: tickers, prefs: prefs, query: query)
  }
}
