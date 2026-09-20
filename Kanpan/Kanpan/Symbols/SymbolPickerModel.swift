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

  /// 这个代号在目录里是什么情况（审查复核项 4）。
  ///
  /// 自选页所有「还有没有实时价」的判断都走这一个口子：目录里有它就按它那一档状态，
  /// 目录到了却没有它就是「未知」（灰着、派生值留空，但照旧留在表里、不划掉、不删），
  /// 目录还没到就先按正常渲染——那口价是刚从交易所来的，不能因为目录慢就冤枉它。
  func listing(of symbol: String) -> SymbolListing {
    .of(info(for: symbol), catalogLoaded: !catalog.isEmpty)
  }
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
  /// 自选页此刻停在哪个分类。
  ///
  /// 真身在 `Prefs.favoritesGroup`（设置包里，跟着账号走），这个包看不见那边，
  /// 所以由宿主灌一个读法进来（接线在 `AppAccountBridge.init`）。没接线时按
  /// 「还没挑过」办——`SymbolPrefs.group(_:)` 退回第一个分类，和搬家之前
  /// `selectedGroupID` 是 nil 那一路一模一样。
  @ObservationIgnored var selectedGroupSource: (() -> String?)?
  /// 加自选 / 新建分类 / 删分类时，落单的成员该进哪一类。
  private var currentGroup: String? { prefs.group(selectedGroupSource?()) }
  private let feed: SymbolTickerFeed?
  /// 品种表的来源，宿主用 `KanpanData.SymbolCatalog` 填。
  private var catalogLoader: (@Sendable () async -> [SymbolInfo])?
  /// 用户在搜索框里点名了一个**这份表里没有**的代号时问一次目录（审查 B-06）。
  ///
  /// 「刚上市的新合约」和「根本不存在的代号」在界面上是同一句「没有这个品种」，
  /// 而前者其实只是本机这份目录还没到期。TTL 是 24 小时，不该让人等一天。
  /// 返回新的一整张表（`nil` = 没查到 / 还在去抖期里）。去抖（5 分钟）与 TTL 都在
  /// `SymbolCatalog.lookup` 那一层，这儿只负责把「他确实在找这个」传过去。
  @ObservationIgnored var onMissingSymbol: ((String) async -> [SymbolInfo]?)?
  /// 已经为哪些词问过了。同一个词只问一次，免得每敲一个字母都发一趟。
  @ObservationIgnored private var asked: Set<String> = []
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
    // 目录到了才知道一个代号到底是什么东西（`underlyingType`）——而分类名正是从这儿来的。
    //
    // 建这个模型的时候手里没有目录（`MainScreen` 那一处 `catalog` 是空的），初始化里
    // 那一趟 `classifyUnassigned()` 因此一个都认不出来，只能原样放着；账号同步拉回来的
    // 那份自选也一样，字段里根本不带分类。两种情形下「知道是什么却没分类」的自选会一直
    // 挂在没有分类那一格上，一旦有了别的分类就从分类页上消失（`favorites(in:)` 按
    // 分类过滤）。目录一到就补一趟，它们才归得了队。
    //
    // 真改了东西才 `commit()`：绝大多数进页这儿一条都不动，不该为此重编一遍整份自选。
    if classifyUnassigned() { commit() }
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
    prefs.addFavorite(key, in: currentGroup)
    let facts = info ?? self.info(for: key)
    // 目录里还没有这一行、或者它没带 `underlyingType`：我们就是**不知道**它是什么
    // （审查 B-04），那就不给它编一个分类名。它刚才已经落进用户此刻站着的那一类
    // （`addFavorite(_:in:)`），一个分类都还没有时落在「没有分类」那格——而那一格
    // 正是此时自选页显示的东西，所以两种情形下这一行都看得见。等目录到了他自己
    // 一拖就归好类，比现在按代号猜一个「加密」强。
    guard FavoriteCategory.knows(symbol: key, info: facts) else { commit(); return }
    let group = prefs.createGroup(FavoriteCategory.name(symbol: key, info: facts))
    prefs.assign(key, to: group)
    commit()
  }

  /// 给还没分类的自选补一个分类。返回是否真改了东西——调用方据此决定要不要回写。
  @discardableResult
  private func classifyUnassigned() -> Bool {
    var changed = false
    for symbol in prefs.favorites where prefs.groupForSymbol[symbol] == nil {
      let facts = self.info(for: symbol)
      // 不知道它是什么就不编分类（审查 B-04）。已经有分类在时把它归到他此刻看的
      // 那一类——未归类的自选在分类页上根本看不见，宁可放错一格也不能让它消失；
      // 一个分类都没有就原样留着，那一格本身就是页面此刻显示的东西。
      guard FavoriteCategory.knows(symbol: symbol, info: facts) else {
        if let group = currentGroup { prefs.assign(symbol, to: group); changed = true }
        continue
      }
      let group = prefs.createGroup(FavoriteCategory.name(symbol: symbol, info: facts))
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
    let id = prefs.createGroup(name); prefs.classifyUnassigned(into: currentGroup); commit(); return id
  }
  // 「切到哪一类看」原来是这儿的 `selectGroup(_:)`，改的是 `SymbolPrefs.selectedGroupID`。
  //
  // **2026-09-19 那个字段搬去了 `Prefs.favoritesGroup`**：他停在哪一类是「把自选页摆成
  // 什么样」，和自选表按什么排、板块看今日还是 5 日是同一等级的东西，该跟着体验类设置
  // 一起走；留在自选档案里它只能跟着这台机器。切换现在由 `FavoritesView` 直接写
  // `PrefsStore`（和那一页上 `favoritesSort` / `favoritesExpanded` 走同一条路），
  // 这一层只负责在需要「此刻是哪一类」时通过 `selectedGroupSource` 问一声。
  //
  // 更早还有一个 `pickedGroupThisRun` 记号配 `resetSelectedGroup()`，执行「冷启动回到
  // 第一个分类」，2026-09-19 一并删掉：上次停在哪一类是他的习惯，冷启动照样要还给他。
  func setPinned(_ symbol: String, _ on: Bool) { prefs.setPinned(symbol, on); commit() }
  func renameGroup(_ id: String, name: String) { prefs.renameGroup(id, name: name); commit() }
  func deleteGroup(_ id: String) { prefs.deleteGroup(id, selected: currentGroup); commit() }
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
    // 成交额拿不到、或者拿回来是 NaN / 负数时按「没有」办，一律沉到同档的最后，
    // 彼此之间保交易所原序（审查 B.5）。原来写的是 `?? 0` 而且不过滤非有限值：
    // `nil` 和 0 被压成同一件事、NaN 参与比较还会毁掉排序的传递性——同一个词
    // 敲两遍能得到两个顺序。这儿不做「假的排序」，只做「没有就排后面」。
    func volume(_ info: SymbolInfo) -> Double? {
      guard let value = tickers[info.symbol.uppercased()]?.quoteVolume,
            value.isFinite, value >= 0 else { return nil }
      return value
    }
    return SymbolQuery.match(catalog, query: q)
      .enumerated()
      .sorted { a, b in
        if a.element.tier != b.element.tier { return a.element.tier < b.element.tier }
        // 已停牌 / 还没开盘的排在同档后面，但照旧列出来（审查 B-06）。
        let aStale = !a.element.info.status.hasLivePrice, bStale = !b.element.info.status.hasLivePrice
        if aStale != bStale { return bStale }
        switch (volume(a.element.info), volume(b.element.info)) {
        case let (x?, y?) where x != y: return x > y
        case (nil, .some): return false            // 没有成交额的排在有的后面
        case (.some, nil): return true
        default: return a.offset < b.offset        // 同额、或都没有：保原序
        }
      }
      .prefix(limit)
      .map { $0.element.info.symbol.uppercased() }
  }

  /// 交易所不认这个代号了：在本地这份品种表里把它标成下架，**不删**，
  /// 索引和分区跟着重算一遍（审查 B-06）。自选表一个字都不动。
  ///
  /// 权威那份在 `SymbolCatalog`（磁盘也会跟着改），这儿改的是这一页手里的副本，
  /// 免得用户要等下一次目录刷新才看到一致的样子。
  func markDelisted(_ symbol: String) {
    let key = SymbolPrefs.key(symbol)
    var next = catalog
    if let i = next.firstIndex(where: { $0.symbol.uppercased() == key }) {
      guard next[i].status != .delisted else { return }
      next[i].status = .delisted
    } else {
      // 目录里连这个代号都没有：那就补一行占位记着「交易所说它没了」（审查复核项 4）。
      // 不补的话这一行只会一直是「未知」，而「未知」和「下架」是两件事——
      // 前者是我们不知道，后者是交易所明确拒了这个代号。
      next.append(.placeholder(symbol: key, status: .delisted))
    }
    setCatalog(next)
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
    // `catalogKeys` 给的是**没筛过**的那份目录：被药丸筛掉的自选照旧不列，
    // 目录里根本没有的那个代号才算「未知」（审查复核项 4）。
    sections = SymbolSections.build(catalog: filteredCatalog, tickers: tickers, prefs: prefs,
                                    query: query, catalogKeys: Set(index.keys))
    lookUpMissingSymbolIfNeeded()
  }

  /// 搜了一个词、一条都没命中，而这个词看着就是个合约代号：问一次目录（审查 B-06）。
  ///
  /// 只在「零命中」这一种情形下问，所以它天然是「用户明确点名」的信号；
  /// 打到一半的前缀（`BT`）不算，长度不够 3 或者带非字母数字的字符一律不问。
  private func lookUpMissingSymbolIfNeeded() {
    guard let onMissingSymbol, let section = sections.first, section.kind == .search,
          section.rows.isEmpty else { return }
    let want = SymbolQuery.normalize(query).uppercased()
    guard want.count >= 3, want.allSatisfy({ $0.isLetter || $0.isNumber }),
          !asked.contains(want), index[want] == nil else { return }
    asked.insert(want)
    Task { [weak self] in
      guard let list = await onMissingSymbol(want), !list.isEmpty else { return }
      self?.setCatalog(list)
    }
  }
}
