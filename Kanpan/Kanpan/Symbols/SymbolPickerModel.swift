import Foundation
import Observation
import KanpanCore

// ============================================================ 品种页的状态
//
// 一个自包含的 ViewModel：品种表 + 行情 + 自选/最近 + 搜索词 → 分区列表。
// 不认识网络，也不认识 KanpanData——品种表和行情都是灌进来的，
// 宿主通过 QuoteBook 灌入行情，模型只维护展示与个人选品状态。

/// 一只品种此刻摆在行上的那口报价与那段分钟线——自选表**按行订阅**用的格子。
///
/// 自选页原来每一行都在整页 body 里读 `tickers` / `historyBars`：任何一只跳一下，
/// 整页 body 连同每一行一起重算（整机压测 2026-09-26：300 只自选、一批报价只变三五只，
/// 也是 300 行全算一遍）。现在行里跟着行情跳的那一截自己读自己这一格，
/// 一批报价只叫醒价真变了的那几行，整页 body 不动。
///
/// `ticker` 的口径和 `SymbolPickerModel.ticker(for:)` 一字不差：真价优先，没有就是种子。
@MainActor
@Observable
final class QuoteCell {
  fileprivate(set) var ticker: Ticker?
  fileprivate(set) var bars: [Bar]?
  fileprivate init(ticker: Ticker?, bars: [Bar]?) {
    self.ticker = ticker
    self.bars = bars
  }
}

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
  func info(for symbol: String) -> SymbolInfo? { index[InstrumentID.canonical(symbol)] }

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
    index = Dictionary(catalog.map { (InstrumentID.canonical($0.symbol), $0) }, uniquingKeysWith: { a, _ in a })
  }
  /// symbol（大写）→ 24h 行情。
  ///
  /// **不参与观察**（整机压测 2026-09-26）：谁在 body 里读它，谁就登记在整张表上，
  /// 自选里任何一只跳一下都要跟着重算。要跟着某一只跳的读 `quoteCell(_:)`，
  /// 要知道「整张表动过了」的读 `quoteRevision`，要知道「空不空」的读 `hasQuotes`。
  @ObservationIgnored private(set) var tickers: [String: Ticker] = [:]
  /// 报价表里有没有东西。只在「空 ↔ 不空」翻的那一下才写，自选页拿它代替
  /// `tickers.isEmpty`——后者一读就把整页登记到整张报价表上，每批报价都得重跑。
  private(set) var hasQuotes = false
  /// 按行订阅的格子（见 `QuoteCell`）。只有露过面的行才有，不观察——格子自己是被观察的。
  @ObservationIgnored private var cells: [String: QuoteCell] = [:]
  /// 报价表或品种表每变一次就加一。自选页拿它当排序缓存的键（审查 C3）：
  /// 版本没动，排好的那份顺序就还作数，不必每求值一次 body 就把整张表重排一遍。
  /// 品种表也算在里面，因为「有没有实时价」（`listing(of:)`）决定一行沉不沉底。
  private(set) var quoteRevision: UInt64 = 0
  /// 同 `tickers`，不参与观察；行上的迷你走势读 `quoteCell(_:).bars`。
  @ObservationIgnored private(set) var historyBars: [String: [Bar]] = [:]
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

  private var store: SymbolPrefsStore
  @ObservationIgnored var onPrefsChange: ((SymbolPrefs) -> Void)?
  /// `symbols.json` 那次写什么时候真的发生。答 `true` = 这次落盘被接管了，
  /// 这儿就别自己写；答 `false` / 没接线 = 就地同步写（没登录、单测、访客都是这条）。
  ///
  /// 接管它的是账号桥：它把这次写排到「同步存档这一版已经落盘」之后
  /// （`SyncStore.afterArchiveWritten`）。理由见 `commit()`——自选这一档从前是
  /// **正式文件先写、存档后写**，正好是启动前向对账补不回来的那一侧。
  @ObservationIgnored var persistence: ((SymbolPrefs) -> Bool)?
  /// 自选页此刻停在哪个分类。
  ///
  /// 真身在 `Prefs.favoritesGroup`（设置包里，跟着账号走），这个包看不见那边，
  /// 所以由宿主灌一个读法进来（接线在 `AppAccountBridge.init`）。没接线时按
  /// 「还没挑过」办——`SymbolPrefs.group(_:)` 退回第一个分类，和搬家之前
  /// `selectedGroupID` 是 nil 那一路一模一样。
  @ObservationIgnored var selectedGroupSource: (() -> String?)?
  /// 加自选 / 新建分类 / 删分类时，落单的成员该进哪一类。
  private var currentGroup: String? { prefs.group(selectedGroupSource?()) }
  /// 品种表的来源，宿主用 `KanpanData.SymbolCatalog` 填。
  private var catalogLoader: (@Sendable () async -> [SymbolInfo])?
  /// 用户在搜索框里点名了一个**这份表里没有**的代号时问一次目录（审查 B-06）。
  ///
  /// 「刚上市的新合约」和「根本不存在的代号」在界面上是同一句「没有这个品种」，
  /// 而前者其实只是本机这份目录还没到期。TTL 是 24 小时，不该让人等一天。
  /// 返回新的一整张表（`nil` = 没查到 / 还在去抖期里）。去抖（5 分钟）与 TTL 都在
  /// `SymbolCatalog.lookup` 那一层，这儿只负责把「他确实在找这个」传过去。
  @ObservationIgnored var onMissingSymbol: ((String) async -> [SymbolInfo]?)?
  /// 全市场 24h 种子（报价簿那份，见 `QuoteBook.seed`）。一行刚露面、自己的报价还没到时
  /// 先拿它垫：从前要等 `onAppear` → 报价簿 → 回调这一跳，搜索结果会先出一帧「—」。
  /// 不观察——种子变了不必重画谁，真值一到照常盖掉它。
  @ObservationIgnored var seedTickers: (() -> [String: Ticker])?
  /// 已经为哪些词问过了。同一个词只问一次，免得每敲一个字母都发一趟。
  @ObservationIgnored private var asked: Set<String> = []
  private var sectionsActive = true

  /// 自选直接读取报价字典，隐藏的全市场搜索表不必随每笔价格重建。
  func setSectionsActive(_ active: Bool) {
    sectionsActive = active
    if active { rebuild() }
  }

  /// 品种键 → 它所在交易所在自选页上的那一类（nil = 默认交易所，按资产类型分）。
  /// 交易所清单在网络层的注册表里，这个包看不见，由宿主注进来。
  private let venueCategory: @Sendable (String) -> String?
  /// 交易所那一类排在哪一类后面（交接 §2：「美股」之后）。
  static let venueCategoryAnchor = "美股"

  init(catalog: [SymbolInfo] = [],
       tickers: [Ticker] = [],
       store: SymbolPrefsStore,
       catalogLoader: (@Sendable () async -> [SymbolInfo])? = nil,
       venueCategory: @escaping @Sendable (String) -> String? = { _ in nil }) {
    self.catalog = catalog
    self.filteredCatalog = catalog
    self.store = store
    self.catalogLoader = catalogLoader
    self.venueCategory = venueCategory
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

  /// 进页补品种表；报价订阅由宿主的 QuoteBook 管理。
  func appear() async {
    if let catalogLoader {
      let list = await catalogLoader()
      setCatalog(list)
    }
  }

  // ---------------------------------------------------------------- 灌数据

  func setCatalog(_ list: [SymbolInfo]) {
    catalog = list
    quoteRevision &+= 1
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
    quoteRevision &+= 1
    for t in batch {
      let symbol = InstrumentID.canonical(t.symbol)
      tickers[symbol] = t
      if let cell = cells[symbol], cell.ticker != t { cell.ticker = t }
    }
    noteQuotesPresence()
  }

  /// 这一只的格子。行第一次露面时现建，建的时候按 `ticker(for:)` 与手上的分钟线填好。
  func quoteCell(_ symbol: String) -> QuoteCell {
    let key = SymbolPrefs.key(symbol)
    if let cell = cells[key] { return cell }
    let cell = QuoteCell(ticker: ticker(for: key), bars: historyBars[key])
    cells[key] = cell
    return cell
  }

  /// 报价表整体换过一轮（退订、清空）之后，格子按 `ticker(for:)` 的口径重新对一遍：
  /// 真价没了就退回种子，种子也没有就是 nil。只写真变了的格子。
  private func resyncCells() {
    guard !cells.isEmpty else { return }
    let seeds = seedTickers?() ?? [:]
    for (key, cell) in cells {
      let now = tickers[key] ?? seeds[key]
      if cell.ticker != now { cell.ticker = now }
    }
  }

  private func noteQuotesPresence() {
    let has = !tickers.isEmpty
    if has != hasQuotes { hasQuotes = has }
  }

  /// 自选行尾的迷你走势线和长按预览卡上 1 小时 / 4 小时涨跌用的分钟线。一份 245 根约 8 KB，
  /// 三十几份也就几百 KB——按「机器资源可以大方用」的口径，翻一整张自选表
  /// 也不用互相挤掉。
  static let historyCapacity = 40

  func setHistory(_ symbol: String, _ bars: [Bar]) {
    if historyBars[symbol] == nil, historyBars.count >= Self.historyCapacity,
       let victim = historyBars.keys.sorted().first {
      historyBars.removeValue(forKey: victim)
      cells[victim]?.bars = nil
    }
    let kept = Array(bars.suffix(245))
    historyBars[symbol] = kept
    cells[symbol]?.bars = kept
  }

  /// 已退订报价不继续冒充实时；只清数字，不碰收藏/分类/顺序。
  func retainQuotes(for symbols: Set<String>) {
    guard tickers.keys.contains(where: { !symbols.contains($0) }) else { return }
    tickers = tickers.filter { symbols.contains($0.key) }
    quoteRevision &+= 1
    noteQuotesPresence()
    resyncCells()
    if sectionsActive { rebuild() }
  }

  func clearQuotes() {
    tickers.removeAll(keepingCapacity: true)
    quoteRevision &+= 1
    noteQuotesPresence()
    resyncCells()
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
    let keys = Set(changed.map { InstrumentID.canonical($0.symbol) })
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

  func ticker(for symbol: String) -> Ticker? {
    let key = SymbolPrefs.key(symbol)
    return tickers[key] ?? seedTickers?()[key]
  }

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
    // 别家交易所的品种固定进它自己那一类（交接 §2 拍板：分类条上「美股」之后的那一格），
    // 不跟着他此刻站着的那一类走——两家所的 BTC 混在一类里，一眼分不出是哪家的报价。
    if assignVenueCategory(key) { commit(); return }
    // 已经落进一类了就到此为止——那一类就是**他此刻站着的那一类**
    // （`currentGroup`；停在「全部」时是默认的第一类）。用户 2026-09-20 定的：
    // 从某一类里点搜索加进来的品种要留在那一类，不再问他归哪儿，也不再按
    // 资产类型把它挪走。以前这里无论如何都要 `createGroup(加密/美股…)` 再
    // `assign` 一次，结果是在「短线」里加 BTC，一松手它自己跳去「加密」。
    guard prefs.groupForSymbol[key] == nil else { commit(); return }
    // 一个分类都还没有（新用户）才走到这儿：按资产类型开第一类。
    let facts = info ?? self.info(for: key)
    // 目录里还没有这一行、或者它没带 `underlyingType`：我们就是**不知道**它是什么
    // （审查 B-04），那就不给它编一个分类名。它此刻落在「没有分类」那格——而那一格
    // 正是此时自选页显示的东西，所以这一行照样看得见。等目录到了他自己
    // 一拖就归好类，比现在按代号猜一个「加密」强。
    guard FavoriteCategory.knows(symbol: key, info: facts) else { commit(); return }
    let group = prefs.createGroup(FavoriteCategory.name(symbol: key, info: facts))
    prefs.assign(key, to: group)
    commit()
  }

  /// 第一次启动时一次落一整批默认自选（`DefaultFavorites`，方案第 3 节第四件）。
  ///
  /// 不复用 `addFavorite` 逐条加是因为那样是八次落盘、八条同步操作、八次重排，
  /// 而这八条在用户眼里是**同一件事**（他打开 app 就看见一页自选）。
  ///
  /// 只在这台机器上一条自选都没有时算数——手上已经有东西了就什么都不做，
  /// 谁的表都不许被默认值挤。返回真正加进去的那几条。
  @discardableResult
  func seedFavorites(_ list: [String]) -> [String] {
    guard prefs.favorites.isEmpty, !list.isEmpty else { return [] }
    for symbol in list { prefs.addFavorite(symbol, in: currentGroup) }
    let added = prefs.favorites
    guard !added.isEmpty else { return [] }
    // 新机器上一个分类都没有：按第一条的资产类型开一类，剩下的跟着进去
    // （默认那几条全是币，所以就是「加密」那一类）。
    if prefs.groups.isEmpty {
      let facts = info(for: added[0])
      if FavoriteCategory.knows(symbol: added[0], info: facts),
         let group = prefs.createGroup(FavoriteCategory.name(symbol: added[0], info: facts)) {
        for symbol in added { prefs.assign(symbol, to: group) }
      }
    }
    commit()
    return added
  }

  /// 给还没分类的自选补一个分类。返回是否真改了东西——调用方据此决定要不要回写。
  @discardableResult
  private func classifyUnassigned() -> Bool {
    var changed = false
    for symbol in prefs.favorites where prefs.groupForSymbol[symbol] == nil {
      if assignVenueCategory(symbol) { changed = true; continue }
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

  /// 这一只属于有自己分类的交易所：把它归进那一类（没有就在「美股」之后开一类）。
  /// 返回是否归了——默认交易所的品种返回 false，照原来的规则走。
  private func assignVenueCategory(_ symbol: String) -> Bool {
    guard let name = venueCategory(symbol),
          let group = prefs.createGroup(name, after: Self.venueCategoryAnchor) else { return false }
    prefs.assign(symbol, to: group)
    return true
  }

  func removeFavorite(_ symbol: String) {
    prefs.removeFavorite(symbol)
    commit()
  }

  /// 移除之前替调用方拍一张快照（撤销要用）。
  func favoriteSnapshot(_ symbol: String) -> FavoriteSnapshot? { prefs.snapshot(of: symbol) }

  /// 现在挂着的是第几份档案。`useStorage(_:prefs:)`（登录、退登、换账号）每换一次加一。
  @ObservationIgnored private(set) var profileEpoch = 0

  /// 把一个撤销动作钉在**此刻这份档案**上：档案换过之后再点就什么都不做。
  ///
  /// 「已移除 · 撤销」那条提示条要留五秒，动作存在全 app 那唯一一条提示里
  /// （`ToastCenter`），不跟着自选页走。这五秒里换了账号（会话被顶掉、退登、登录），
  /// 快照里的是上一个人的自选——照旧 `restoreFavorites` 就会把它们写进新账号的档案、
  /// 再推上他的云端。
  func undoable(_ action: @escaping () -> Void) -> () -> Void {
    let epoch = profileEpoch
    return { [weak self] in
      guard let self, self.profileEpoch == epoch else { return }
      action()
    }
  }

  /// 撤销「移除自选」：照快照放回原来的位置和分类。
  ///
  /// 走的是和别处一模一样的 `commit()`——落盘、推同步、重挂行情订阅一样不少，
  /// 不走 `applySynced` 那条「只存不推」的近路，否则这一下在别的设备上等于没发生。
  func restoreFavorites(_ items: [FavoriteSnapshot]) {
    guard !items.isEmpty else { return }
    prefs.restore(items, fallback: currentGroup)
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

  /// 按名字开一类（已有同名的就用那一类）。界面上 2026-09-24 起没有「新建分类」了——
  /// 分类只由加自选时按资产类型自动开（`addFavorite`）；这一层留着它，是因为老账号里
  /// 仍躺着他当年自己建的分类，测试要拼出这种存档。
  @discardableResult
  func createGroup(_ name: String) -> String? {
    let id = prefs.createGroup(name); prefs.classifyUnassigned(into: currentGroup); commit(); return id
  }
  // 「切到哪一类看」原来是这儿的 `selectGroup(_:)`，改的是 `SymbolPrefs.selectedGroupID`。
  //
  // **2026-09-19 那个字段搬去了 `Prefs.favoritesGroup`**：他停在哪一类是「把自选页摆成
  // 什么样」，和自选表按什么排、板块看今日还是 5 日是同一等级的东西，该跟着体验类设置
  // 一起走；留在自选档案里它只能跟着这台机器。切换现在由 `FavoritesView` 直接写
  // `PrefsStore`（和那一页上 `favoritesSort` / `favoritesSparkline` 走同一条路），
  // 这一层只负责在需要「此刻是哪一类」时通过 `selectedGroupSource` 问一声。
  //
  // 更早还有一个 `pickedGroupThisRun` 记号配 `resetSelectedGroup()`，执行「冷启动回到
  // 第一个分类」，2026-09-19 一并删掉：上次停在哪一类是他的习惯，冷启动照样要还给他。
  func deleteGroup(_ id: String) { prefs.deleteGroup(id, selected: currentGroup); commit() }
  func assign(_ symbol: String, to group: String?) { prefs.assign(symbol, to: group); commit() }
  /// 「移到分类」挑了一格：已经开着的就直接用，还没开的预设分类（`FavoriteCategory.presets`）
  /// 当场开出来。开类和移过去是同一次落盘、同一条同步。返回那一类的 id。
  @discardableResult
  func assign(_ symbols: [String], toCategory name: String) -> String? {
    guard let group = prefs.createGroup(name) else { return nil }
    symbols.forEach { prefs.assign($0, to: group) }
    commit()
    return group
  }
  /// 「移到分类」列出来的那几格：已有的分类照原顺序，后面接还没开的预设分类。
  var moveTargets: [String] {
    let names = prefs.groups.map(\.name)
    return names + FavoriteCategory.presets.filter { !names.contains($0) }
  }
  func moveVisible(_ visible: [String], from source: IndexSet, to destination: Int) {
    prefs.moveVisible(visible, from: source, to: destination); commit()
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
    // 走同一条落盘路（见 `save(_:)`）：这份分数表和自选住在同一个文件里，
    // 一条就地写、一条排队写的话，队列上那笔会把它盖回去。
    save(prefs)
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
      .map { (InstrumentID.canonical($0.symbol), tickers[InstrumentID.canonical($0.symbol)]?.quoteVolume ?? 0) }
      .filter { $0.1.isFinite }
      .sorted { $0.1 > $1.1 }
    for (symbol, _) in hot where seen.insert(symbol).inserted {
      out.append(symbol); if out.count == limit { return out }
    }
    return out
  }

  /// 搜索页「热门」那一组的代号（`SymbolSections.hot`）。行情取实时 + 全市场种子合起来的那份，
  /// 和搜索结果排序用的是同一份（见 `rebuild()`）。
  func hotSymbols(limit: Int = SymbolSections.hotLimit) -> [String] {
    var shown = tickers
    if let seeds = seedTickers?(), !seeds.isEmpty { shown.merge(seeds) { live, _ in live } }
    return SymbolSections.hot(catalog: catalog, tickers: shown, limit: limit)
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
      guard let value = tickers[InstrumentID.canonical(info.symbol)]?.quoteVolume,
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
      .map { InstrumentID.canonical($0.element.info.symbol) }
  }

  /// 交易所不认这个代号了：在本地这份品种表里把它标成下架，**不删**，
  /// 索引和分区跟着重算一遍（审查 B-06）。自选表一个字都不动。
  ///
  /// 权威那份在 `SymbolCatalog`（磁盘也会跟着改），这儿改的是这一页手里的副本，
  /// 免得用户要等下一次目录刷新才看到一致的样子。
  func markDelisted(_ symbol: String) {
    let key = SymbolPrefs.key(symbol)
    var next = catalog
    if let i = next.firstIndex(where: { InstrumentID.canonical($0.symbol) == key }) {
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

  /// 自选改完之后的那一下：**先记账，再落盘**。
  ///
  /// 顺序 2026-09-22 掉了个个儿，和画线 / 提醒对齐（`DrawingController.write()`）。
  /// 从前是 `store.save(prefs)` 在前、`onPrefsChange` 在后，也就是
  /// 「正式文件先落、同步存档后落」——那正是启动前向对账**补不回来**的那一侧：
  /// 两次写之间进程没了，盘上是「新 symbols.json + 旧存档」，存档里既没有新值
  /// 也没有待发操作。举个真会发生的例子：用户删掉一条自选，崩在这个窗口里，
  /// 重开之后 `applyPending()` 拿 `archive.local` 重建自选（那儿还留着这条），
  /// **删掉的自选自己回来了**，而且全程没有任何痕迹。
  ///
  /// 现在两件事都在这一句里当场发起，谁先谁后由写盘队列（串行 FIFO）定：
  /// `onPrefsChange` 把存档排进去，`save` 把 `symbols.json` 排在它后面。
  /// 崩在中间只会剩「新存档 + 旧 symbols.json」，那一侧存档里有值有操作，
  /// 冷启动 `AppAccountBridge.prepare` 会把它向前补进 `symbols.json`。
  private func commit() {
    onPrefsChange?(prefs)
    save(prefs)
    // 桌面长按图标那几格摆的是「最近看过」，它就在 `prefs` 里，所以每次存档
    // 顺手让它跟上。没变就不会真去写系统那张表（`HomeShortcuts.refresh`）。
    HomeShortcuts.refresh(recents: prefs.recents)
    rebuild()
  }
  /// 落 `symbols.json`。接了线就交给 `persistence` 去排队，没接线就地写。
  ///
  /// **用户改出来的每一次写都要走这儿**（`commit()` 与 `noteDwell(_:)`），否则两条路
  /// 一条排队、一条就地，队列上那笔落在后面就会把刚写下去的盖回旧的。
  ///
  /// 另外两处直接 `store.save` 不走这儿，都是故意的：`init` 里那次补分类发生在
  /// 账号桥接线（`persistence`）之前，那会儿还没有存档可排；`applySynced(_:)` 在
  /// `applyPending` 的发布段里，那一段动手前刚 `flushNow()` 过、期间又有 `gate`
  /// 挡着不产生新的记账，队列是空的。
  private func save(_ value: SymbolPrefs) {
    guard persistence?(value) != true else { return }
    store.save(value)
  }

  func useStorage(_ store: SymbolPrefsStore, prefs: SymbolPrefs) {
    self.store = store; self.prefs = prefs; query = ""
    profileEpoch += 1
    // 换了档案（登录 / 退登）就是换了一份「最近看过」，桌面那几格要跟着换人。
    HomeShortcuts.refresh(recents: prefs.recents)
    rebuild()
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
    var shown = tickers
    if let seeds = seedTickers?(), !seeds.isEmpty { shown.merge(seeds) { live, _ in live } }
    sections = SymbolSections.build(catalog: filteredCatalog, tickers: shown, prefs: prefs,
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
    // 只有「看着就像个合约代号」的词才去问：中文（粘进来的「比特币」）和带
    // 分隔符的写法都不是代号，问了也是白问一趟。`isLetter` 对汉字是 true，
    // 所以这儿必须连 `isASCII` 一起要。
    guard want.count >= 3, want.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
          !asked.contains(want), index[InstrumentID.canonical(want)] == nil else { return }
    asked.insert(want)
    Task { [weak self] in
      guard let list = await onMissingSymbol(want), !list.isEmpty else { return }
      self?.setCatalog(list)
    }
  }
}
