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
       store: SymbolPrefsStore,
       feed: SymbolTickerFeed? = nil,
       catalogLoader: (@Sendable () async -> [SymbolInfo])? = nil) {
    self.catalog = catalog
    self.filteredCatalog = catalog
    self.store = store
    self.feed = feed
    self.catalogLoader = catalogLoader
    reindex()
    self.prefs = store.load()
    // 只有真给未分类的自选补了分类才回写。
    //
    // 原来是无条件 `save`：每次冷启动都要把整份自选编码一遍再塞进 UserDefaults，
    // 而绝大多数启动里这份数据一个字节都没变。`load()` 自己那层清洗（去重、
    // 大写、截断）是幂等的，每次读都会再做一遍，不落盘也丢不了东西。
    if classifyUnassigned() { store.save(self.prefs) }
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
    //
    // 这一批里有几个是盘上真有的行？`onUpdate` 给的是整个 `QuoteBook` 的范围
    // （图上那个品种、别的分组、搜索页点过的），落到当前这张表里常常一行都没有。
    // 先把命中的下标找出来，一个没有就直接回——不然每来一批行情都要把整份
    // `sections`（分区 + 行的值类型数组）复制一遍再整体赋回去，`@Observable`
    // 那边跟着判定「变了」，一整张表重新求值。
    let keys = Set(changed.map { $0.symbol.uppercased() })
    let current = sections  // 只取一次；下面找下标的过程不碰 `@Observable` 的存取。
    var hits: [(section: Int, row: Int)] = []
    for section in current.indices {
      for row in current[section].rows.indices where keys.contains(current[section].rows[row].id) {
        hits.append((section, row))
      }
    }
    guard !hits.isEmpty else { return }
    var updated = current
    for hit in hits { updated[hit.section].rows[hit.row].ticker = tickers[updated[hit.section].rows[hit.row].id] }
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

  /// 给还没分类的自选补一个分类。返回是否真改了东西——调用方据此决定要不要回写。
  @discardableResult
  private func classifyUnassigned() -> Bool {
    var changed = false
    for symbol in prefs.favorites where prefs.groupForSymbol[symbol] == nil {
      let name = FavoriteCategory.name(symbol: symbol, info: self.info(for: symbol))
      let group = prefs.createGroup(name)
      prefs.assign(symbol, to: group)
      if prefs.groupForSymbol[symbol] != nil { changed = true }
    }
    return changed
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
  /// 切到哪一类看。落盘 + 同步，跨启动保留。
  ///
  /// 这儿原来还带一个 `pickedGroupThisRun` 记号，配一个 `resetSelectedGroup()`，
  /// 执行的是「冷启动回到第一个分类」（旧注释：「同一次使用里要记住，下一次开 app
  /// 该从头看起，这和 AICoin 一致」）。**2026-09-19 整套删掉**：按「所有交互状态
  /// 跟着人走，无论怎么切换」，上次停在哪一类是他的习惯，冷启动照样要还给他。
  /// 顺带也修掉了旧实现里一个纯 bug——它只改内存那一份、不 `commit()`，内存和盘上
  /// 从此对不上，还会被账号同步把这份不一致带出去。删掉的调用点在
  /// `MainScreen.primeFavorites()`，那儿留了同一段说明。
  func selectGroup(_ id: String) { prefs.selectGroup(id); commit() }
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

  /// 只记「最近看过」，不走 `onPick`。
  ///
  /// 目录还没载回来时（板块页点一行就可能撞上）拿不到 `SymbolInfo`，换图那条路是
  /// 宿主自己走的，但这一笔「他看过这张图」照样得记下——否则同一个动作在目录加载
  /// 前后结果不一样，冷启动「上次看的那张图」也会落到别的品种上。
  func visit(_ symbol: String) {
    let key = SymbolPrefs.key(symbol)
    guard !key.isEmpty, prefs.recents.first != key else { return }
    prefs.visit(key)
    commit()
  }

  // ---------------------------------------------------------------- 常看

  /// 在某个品种的图上真待了一会儿——记一分。见 `SymbolPrefs.noteDwell(_:)`。
  ///
  /// 只落盘，既不 `rebuild()` 也不走 `onPrefsChange`：这张分数表是**纯本机**的
  /// （服务端那几张表里没有它，`AppAccountBridge` 只负责把它原样带过同步），
  /// 而且不参与任何一张列表的排序，所以重排分区和推同步都是白跑一趟。
  func noteDwell(_ symbol: String) {
    let before = prefs.viewScores
    prefs.noteDwell(symbol)
    guard prefs.viewScores != before else { return }
    store.save(prefs)
  }

  /// 常看的品种，分数从高到低。画线工作台里换品种那一层，没输入时列的就是它。
  ///
  /// 冷启动那几天分数表还是空的，这时回落到「最近」——总比给用户一张白名单强。
  /// 两边都空就给「全部」里成交额最高的几个，**永远不让这一列是空的**：
  /// 那一层除了这一列没有别的内容，空了就成了一张只有搜索框的白板。
  func frequentSymbols(limit: Int = 12) -> [String] {
    var out = prefs.frequent(limit: limit)
    guard out.count < limit else { return out }
    var seen = Set(out)
    for symbol in prefs.recents where seen.insert(symbol).inserted {
      out.append(symbol); if out.count == limit { return out }
    }
    let hot = catalog
      .map { ($0.symbol.uppercased(), tickers[$0.symbol.uppercased()]?.quoteVolume ?? 0) }
      .filter { $0.1.isFinite }
      .sorted { $0.1 > $1.1 }
    for (symbol, _) in hot where seen.insert(symbol).inserted {
      out.append(symbol); if out.count == limit { return out }
    }
    return out
  }

  /// 搜索框里打了字时列的那一列——**只有代号**，没有价格涨跌。
  /// 排序跟品种页一个口径：先最匹配，同档按 24h 成交额降序（见 `SymbolSections.build`）。
  func matchingSymbols(_ query: String, limit: Int = 60) -> [String] {
    let q = SymbolQuery.normalize(query)
    guard !q.isEmpty else { return [] }
    return SymbolQuery.match(catalog, query: q)
      .enumerated()
      .sorted { a, b in
        if a.element.tier != b.element.tier { return a.element.tier < b.element.tier }
        let x = tickers[a.element.info.symbol.uppercased()]?.quoteVolume ?? 0
        let y = tickers[b.element.info.symbol.uppercased()]?.quoteVolume ?? 0
        if x != y { return x > y }
        return a.offset < b.offset
      }
      .prefix(limit)
      .map { $0.element.info.symbol.uppercased() }
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
