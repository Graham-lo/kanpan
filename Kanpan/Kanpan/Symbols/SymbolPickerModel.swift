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
  /// symbol（大写）→ 品种信息。
  ///
  /// 自选行渲染要问好几次品种信息（基础币名、价格精度、计价币）。品种表有
  /// 五百多行，`catalog.first { $0.symbol == symbol }` 是一次线性扫描；一行问
  /// 三四次、一屏二十几行、每来一批报价重算一次，就是每秒几万次字符串比较，
  /// 全落在主线程上——列表正在填数字的时候恰好最忙。查表把它压成常数。
  @ObservationIgnored private var index: [String: SymbolInfo] = [:]
  /// 按 symbol 取品种信息。取不到返回 `nil`，调用方自己兜底。
  func info(for symbol: String) -> SymbolInfo? { index[symbol.uppercased()] }
  /// `catalog` 只在 `setCatalog` 和初始化时换，索引跟着换。不用 `didSet`：
  /// `@Observable` 会把存储属性改写成计算属性，属性观察器放在这儿只会让人猜。
  private func reindex() {
    index = Dictionary(catalog.map { ($0.symbol.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
  }
  /// symbol（大写）→ 24h 行情。
  private(set) var tickers: [String: Ticker] = [:]
  private(set) var historyBars: [String: [Bar]] = [:]
  /// 自选与最近。改完立刻落盘。
  private(set) var prefs = SymbolPrefs()
  /// 搜索框里的原文。改它分区就重算。
  var query: String = "" { didSet { if query != oldValue { rebuild() } } }
  var marketFilter = "all" { didSet { sectorFilter = nil; rebuildFilter() } }
  var sectorFilter: String? { didSet { rebuildFilter() } }
  private(set) var markets: [String] = []
  private(set) var sectors: [String] = []
  private var filteredCatalog: [SymbolInfo] = []
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

  private var store: SymbolPrefsStore
  @ObservationIgnored var onPrefsChange: ((SymbolPrefs) -> Void)?
  private let feed: SymbolTickerFeed?
  /// 品种表的来源，宿主用 `KanpanData.SymbolCatalog` 填。
  private var catalogLoader: (@Sendable () async -> [SymbolInfo])?
  private var subscribed = false
  private var sectionsActive = true

  /// 自选直接读取报价字典，隐藏的全市场搜索表不必随每笔价格重建。
  func setSectionsActive(_ active: Bool) {
    sectionsActive = active
    if active { rebuild() }
  }

  init(catalog: [SymbolInfo] = [],
       tickers: [Ticker] = [],
       store: SymbolPrefsStore = SymbolPrefsStore(),
       feed: SymbolTickerFeed? = nil,
       catalogLoader: (@Sendable () async -> [SymbolInfo])? = nil) {
    self.catalog = catalog
    self.filteredCatalog = catalog
    self.store = store
    self.feed = feed
    self.catalogLoader = catalogLoader
    reindex()
    self.prefs = store.load()
    classifyUnassigned()
    store.save(self.prefs)
    apply(tickers)
    rebuildFilter()
  }

  /// 品种表的来源晚一步才知道（宿主要先把 `KanpanData` 那侧建起来）。
  /// 只在还没进过页面时补得上，进过之后 `catalog` 已经填好了，换不换都无所谓。
  func setLoader(_ loader: @escaping @Sendable () async -> [SymbolInfo]) {
    catalogLoader = loader
    // 自选页现在从第一帧就盖着（见 `MainScreen.startsOnFavorites`），它的 `appear()`
    // 可能比宿主接线还早跑一步，那一趟手里没有 loader，品种表就会一直空到下次进页。
    // 补上 loader 的时候如果还空着，自己补一趟。
    guard catalog.isEmpty else { return }
    Task { [weak self] in
      let list = await loader()
      self?.setCatalog(list)
    }
  }

  // ---------------------------------------------------------------- 生命周期

  /// 进页：补品种表、订阅行情。
  func appear() async {
    subscribe()
    if let catalogLoader {
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
    reindex()
    rebuildFilter()
  }

  /// 行情按 symbol 覆盖写；`!ticker@arr` 每 1s 推一批，只推变动的。
  func apply(_ batch: [Ticker]) {
    guard !batch.isEmpty else { return }
    for t in batch {
      let symbol = t.symbol.uppercased()
      tickers[symbol] = t

    }
  }

  /// 展开详情里的 1h / 4h 涨跌用的分钟线。一份 245 根约 8 KB，
  /// 三十几份也就几百 KB——按「机器资源可以大方用」的口径，够整张自选表
  /// 全展开也不用互相挤掉。
  static let historyCapacity = 40

  func setHistory(_ symbol: String, _ bars: [Bar]) {
    if historyBars[symbol] == nil, historyBars.count >= Self.historyCapacity,
       let victim = historyBars.keys.sorted().first {
      historyBars.removeValue(forKey: victim)
    }
    historyBars[symbol] = Array(bars.suffix(245))
  }

  /// 已退订报价不继续冒充实时；只清数字，不碰收藏/分类/顺序。
  func retainQuotes(for symbols: Set<String>) {
    guard tickers.keys.contains(where: { !symbols.contains($0) }) else { return }
    tickers = tickers.filter { symbols.contains($0.key) }
    if sectionsActive { rebuild() }
  }

  func clearQuotes() {
    tickers.removeAll(keepingCapacity: true)
    rebuild()
  }

  func updateQuotes(_ batch: [Ticker]) {
    let changed = batch.filter { tickers[$0.symbol] != $0 }
    guard !changed.isEmpty else { return }
    apply(changed)
    guard sectionsActive else { return }
    // Keep rows under the user's finger stable; rebuild/sort only on navigation or filtering.
    let keys = Set(changed.map { $0.symbol.uppercased() })
    var updated = sections
    for section in updated.indices {
      for row in updated[section].rows.indices where keys.contains(updated[section].rows[row].id) {
        updated[section].rows[row].ticker = tickers[updated[section].rows[row].id]
      }
    }
    sections = updated
  }

  func ticker(for symbol: String) -> Ticker? { tickers[SymbolPrefs.key(symbol)] }

  // ---------------------------------------------------------------- 自选

  func isFavorite(_ symbol: String) -> Bool { prefs.isFavorite(symbol) }

  /// 星星：一点加、再点移除（§10.5）。
  @discardableResult
  func toggleFavorite(_ symbol: String, info: SymbolInfo? = nil) -> Bool {
    if prefs.isFavorite(symbol) { prefs.removeFavorite(symbol); commit(); return false }
    addFavorite(symbol, info: info)
    return true
  }

  func addFavorite(_ symbol: String, info: SymbolInfo? = nil) {
    guard !prefs.isFavorite(symbol) else { return }
    let key = SymbolPrefs.key(symbol)
    guard !key.isEmpty else { return }
    prefs.addFavorite(key)
    let name = FavoriteCategory.name(symbol: key, info: info ?? self.info(for: key))
    let group = prefs.createGroup(name)
    prefs.assign(key, to: group)
    commit()
  }

  private func classifyUnassigned() {
    for symbol in prefs.favorites where prefs.groupForSymbol[symbol] == nil {
      let name = FavoriteCategory.name(symbol: symbol, info: self.info(for: symbol))
      let group = prefs.createGroup(name)
      prefs.assign(symbol, to: group)
    }
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

  @discardableResult
  func createGroup(_ name: String) -> String? {
    let id = prefs.createGroup(name); prefs.classifyUnassigned(); commit(); return id
  }
  func selectGroup(_ id: String) { pickedGroupThisRun = true; prefs.selectGroup(id); commit() }

  /// 这一次使用里用户自己定过看哪一类没有。
  ///
  /// 新装机上「第一次添加品种」和「自选表第一次非空」是同一件事，宿主的冷启动预热
  /// 正好挂在后者上——不挡一下的话，刚落进新分类的品种会被那次重置弹回第一个分类，
  /// 用户点了添加却看见一张空列表。
  private var pickedGroupThisRun = false

  /// 冷启动回到第一个分类。
  ///
  /// 分组的选中在同一次使用里要记住（来回切别跳回去），但下一次开 app 该从头看起，
  /// 这和 AICoin 一致。只改内存里这一份、不落盘也不同步——用户这一次自己切过才算数。
  func resetSelectedGroup() {
    guard !pickedGroupThisRun, prefs.selectedGroupID != nil else { return }
    prefs.selectedGroupID = nil
    rebuild()
  }
  func setPinned(_ symbol: String, _ on: Bool) { prefs.setPinned(symbol, on); commit() }
  func renameGroup(_ id: String, name: String) { prefs.renameGroup(id, name: name); commit() }
  func deleteGroup(_ id: String) { prefs.deleteGroup(id); commit() }
  func assign(_ symbol: String, to group: String?) { prefs.assign(symbol, to: group); commit() }
  func moveVisible(_ visible: [String], from source: IndexSet, to destination: Int) {
    prefs.moveVisible(visible, from: source, to: destination); commit()
  }

  func moveInGroup(_ group: String?, from source: IndexSet, to destination: Int) {
    prefs.moveInGroup(group, from: source, to: destination); commit()
  }

  // ---------------------------------------------------------------- 最近

  /// 点一行：记进最近、落盘、通知宿主。
  func pick(_ info: SymbolInfo) {
    prefs.visit(info.symbol)
    commit()
    onPick?(info)
  }

  func pick(symbol: String) {
    guard let info = info(for: SymbolPrefs.key(symbol)) else { return }
    pick(info)
  }

  // ---------------------------------------------------------------- 内务

  private func commit() {
    store.save(prefs)
    onPrefsChange?(prefs)
    rebuild()
  }

  func useStorage(_ store: SymbolPrefsStore, prefs: SymbolPrefs) {
    self.store = store; self.prefs = prefs; query = ""; rebuild()
  }
  func applySynced(_ value: SymbolPrefs) {
    guard value != prefs else { return }
    prefs = value; store.save(value); rebuild()
  }

  private func rebuildFilter() {
    let present = Set(catalog.map(MarketSector.market))
    markets = MarketSector.order.filter { present.contains($0) }
    let base = catalog.filter { marketFilter == "all" || MarketSector.market($0) == marketFilter }
    sectors = Array(Set(base.flatMap(MarketSector.tags))).sorted()
    filteredCatalog = base.filter { sectorFilter == nil || MarketSector.tags($0).contains(sectorFilter!) }
    rebuild()
  }

  private func rebuild() {
    sections = SymbolSections.build(catalog: filteredCatalog, tickers: tickers, prefs: prefs, query: query)
  }
}
