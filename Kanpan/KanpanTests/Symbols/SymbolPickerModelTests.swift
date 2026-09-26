import Foundation
import Observation
import Testing
import KanpanCore

@testable import Kanpan

/// 整页的行为：搜索联动、星星、最近、报价灌入、落盘。全程无网络。
@Suite("品种页")
@MainActor
struct SymbolPickerModelTests {

  private func make(prefs: SymbolPrefs = SymbolPrefs(),
                    tickers: [Ticker] = SymbolFixtures.tickers)
    -> (SymbolPickerModel, MemoryPrefsStorage) {
    let storage = MemoryPrefsStorage()
    let store = SymbolPrefsStore(storage: storage, key: "t")
    store.save(prefs)
    let m = SymbolPickerModel(catalog: SymbolFixtures.catalog,
                              tickers: tickers,
                              store: store)
    return (m, storage)
  }

  @Test("重新连接清除报价而不改自选存档")
  func reconnectClearsQuotesOnly() {
    let (m, storage) = make(prefs: SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"]))
    #expect(!m.tickers.isEmpty)
    m.clearQuotes()
    #expect(m.tickers.isEmpty)
    #expect(m.prefs.favorites == ["binance/usd_m/BTCUSDT"])
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().favorites == ["binance/usd_m/BTCUSDT"])
  }

  @Test("离开订阅范围只移除旧报价，收藏与仍订阅报价保持")
  func unsubscribeDropsStaleQuotes() throws {
    let (m, storage) = make(prefs: SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"]))
    let btc = try #require(m.ticker(for: "binance/usd_m/BTCUSDT"))
    m.retainQuotes(for: ["binance/usd_m/BTCUSDT"])
    #expect(m.tickers.count == 1 && m.ticker(for: "binance/usd_m/BTCUSDT") == btc)
    #expect(m.ticker(for: "binance/usd_m/ETHUSDT") == nil)
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
  }

  @Test("隐藏搜索表不随报价重建，打开时追上最新")
  func hiddenSectionsCatchUpOnPresentation() throws {
    let (m, _) = make()
    let original = m.sections
    m.setSectionsActive(false)
    var ticker = try #require(m.ticker(for: "binance/usd_m/BTCUSDT"))
    ticker.last += 100
    m.updateQuotes([ticker])
    #expect(m.ticker(for: "binance/usd_m/BTCUSDT")?.last == ticker.last)
    #expect(m.sections == original)
    m.setSectionsActive(true)
    #expect(m.sections != original)
  }

  @Test("报价变化只刷新数字，不在手指下自动重排")
  func quotesKeepRowPositionsStable() throws {
    let (model, _) = make()
    let order = model.sections.flatMap(\.rows).map(\.id)
    var quote = try #require(model.ticker(for: "binance/usd_m/BTCUSDT"))
    quote.last += 1; quote.quoteVolume = 0
    model.updateQuotes([quote])
    #expect(model.sections.flatMap(\.rows).map(\.id) == order)
    #expect(model.sections.flatMap(\.rows).first { $0.id == "binance/usd_m/BTCUSDT" }?.ticker?.last == quote.last)
  }

  @Test("开页就把存档读回来")
  func loadsPrefsOnInit() {
    let (m, _) = make(prefs: SymbolPrefs(favorites: ["binance/usd_m/ETHUSDT"], recents: ["binance/usd_m/SOLUSDT"]))
    #expect(m.prefs.favorites == ["binance/usd_m/ETHUSDT"])
    #expect(m.sections.map(\.kind) == [.favorites, .recents, .all])
  }

  @Test("改搜索词，停手落定后分区跟着变；清空当场回来")
  func queryRebuilds() async {
    let (m, _) = make(prefs: SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"]))
    #expect(m.sections.count == 2)
    m.query = "eth"
    await m.settleSearch()
    #expect(m.sections.count == 1)
    #expect(m.sections[0].rows.map(\.id) == ["binance/usd_m/ETHUSDT", "binance/usd_m/ETHFIUSDT", "binance/usd_m/ETHWUSDT"])
    m.query = "zzz"
    await m.settleSearch()
    #expect(m.isEmpty)
    m.query = ""
    #expect(m.sections.count == 2)
    #expect(!m.isEmpty)
  }

  @Test("点星星：加 → 落盘 → 分区里冒出自选组；再点一次全撤回")
  func toggleFavoritePersists() {
    let (m, storage) = make()
    #expect(m.sections.map(\.kind) == [.all])

    #expect(m.toggleFavorite("binance/usd_m/SOLUSDT") == true)
    #expect(m.isFavorite("binance/usd_m/SOLUSDT"))
    #expect(m.sections.first?.kind == .favorites)
    #expect(m.sections.first?.rows.map(\.id) == ["binance/usd_m/SOLUSDT"])

    // 真落盘了：另开一个 model 读同一份存档
    let reopened = SymbolPickerModel(catalog: SymbolFixtures.catalog,
                                     store: SymbolPrefsStore(storage: storage, key: "t"))
    #expect(reopened.prefs.favorites == ["binance/usd_m/SOLUSDT"])

    #expect(m.toggleFavorite("binance/usd_m/SOLUSDT") == false)
    #expect(m.sections.map(\.kind) == [.all])
  }

  @Test("左滑删除按分区内下标删对人")
  func removeFavoritesByOffsets() {
    let (m, _) = make(prefs: SymbolPrefs(favorites: ["binance/usd_m/A1USDT", "binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"]))
    m.removeFavorites(at: IndexSet(integer: 1))
    #expect(m.prefs.favorites == ["binance/usd_m/A1USDT", "binance/usd_m/ETHUSDT"])
    m.removeFavorites(at: IndexSet([0, 1]))
    #expect(m.prefs.favorites.isEmpty)
    // 越界不崩
    m.removeFavorites(at: IndexSet(integer: 9))
    #expect(m.prefs.favorites.isEmpty)
  }

  @Test("拖排序后落盘，顺序就是自选分区的顺序")
  func reorderPersists() {
    let (m, storage) = make(prefs: SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT"]))
    m.moveFavorite("binance/usd_m/SOLUSDT", onto: "binance/usd_m/BTCUSDT")
    #expect(m.prefs.favorites == ["binance/usd_m/SOLUSDT", "binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(m.sections.first?.rows.map(\.id) == ["binance/usd_m/SOLUSDT", "binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().favorites
      == ["binance/usd_m/SOLUSDT", "binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])

    m.moveFavorites(from: IndexSet(integer: 0), to: 3)
    #expect(m.prefs.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT"])
  }

  @Test("点一行：记进最近、落盘、回调宿主（A5.9）")
  func pickRecordsRecent() {
    let (m, storage) = make()
    var picked: [String] = []
    m.onPick = { picked.append($0.symbol) }

    m.pick(symbol: "binance/usd_m/SOLUSDT")
    m.pick(symbol: "binance/usd_m/BTCUSDT")
    #expect(picked == ["binance/usd_m/SOLUSDT", "binance/usd_m/BTCUSDT"])
    #expect(m.prefs.recents == ["binance/usd_m/BTCUSDT", "binance/usd_m/SOLUSDT"])
    #expect(m.sections.first?.kind == .recents)
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().recents == ["binance/usd_m/BTCUSDT", "binance/usd_m/SOLUSDT"])

    // 品种表里没有的，不回调也不记
    m.pick(symbol: "binance/usd_m/NOPEUSDT")
    #expect(picked.count == 2)
    #expect(m.prefs.recents.count == 2)
  }

  @Test("最近最多 10 个，第 11 次打开挤掉最旧的")
  func recentCap() {
    let catalog = (1 ... 12).map {
      SymbolInfo(symbol: "S\($0)USDT", base: "S\($0)", pricePrecision: 2, tickSize: 0.01)
    }
    let m = SymbolPickerModel(catalog: catalog,
                              store: SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "t"))
    for s in catalog { m.pick(s) }
    #expect(m.prefs.recents.count == 10)
    #expect(m.prefs.recents.first == "binance/usd_m/S12USDT")
    #expect(m.sections.first { $0.kind == .recents }?.rows.count == 10)
  }

  // ---------------------------------------------------------------- 行情流

  @Test("宿主灌入新价，行上的数跟着跳")
  func tickerUpdatesRows() {
    let (m, _) = make(tickers: [])
    #expect(m.sections[0].rows.first { $0.id == "binance/usd_m/BTCUSDT" }?.priceText == "—")
    m.updateQuotes([Ticker(symbol: "binance/usd_m/BTCUSDT", last: 77_123.4, changePercent: -2.5,
                          high: 78_000, low: 76_000, quoteVolume: 1e9)])
    let btc = m.sections[0].rows.first { $0.id == "binance/usd_m/BTCUSDT" }
    #expect(btc?.priceText == "77,123.4")
    #expect(btc?.changeText == "\u{2212}2.50%")
    #expect(btc?.isUp == false)
  }

  @Test("品种表可以后到（异步拉回来再灌）")
  func lateCatalog() async {
    let m = SymbolPickerModel(catalog: [],
                              store: SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "t"),
                              catalogLoader: { SymbolFixtures.catalog })
    #expect(m.isEmpty)
    #expect(m.countText == "0 个永续合约")

    await m.appear()
    #expect(!m.isEmpty)
    #expect(m.countText == "\(SymbolFixtures.catalog.count) 个永续合约")
    #expect(m.sections.first { $0.kind == .all }?.rows.isEmpty == false)
  }

  /// 数一数到底写了几次盘。「同样的字节写回去」在文件上看不出来，但那一次编码
  /// 加一次 `UserDefaults` 写是实打实花在冷启动主线程上的。
  private final class CountingStorage: SymbolPrefsStorage {
    private let inner = MemoryPrefsStorage()
    private let lock = NSLock()
    private var count = 0
    var writes: Int { lock.lock(); defer { lock.unlock() }; return count }
    var raw: [String: Data] { inner.raw }
    func symbolPrefsData(forKey key: String) -> Data? { inner.symbolPrefsData(forKey: key) }
    func setSymbolPrefsData(_ data: Data?, forKey key: String) {
      lock.lock(); count += 1; lock.unlock()
      inner.setSymbolPrefsData(data, forKey: key)
    }
  }

  @Test("存档已经齐整时，开页一次盘都不写")
  func openingACleanArchiveWritesNothing() throws {
    var prefs = SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    for symbol in prefs.favorites {
      let group = prefs.createGroup(FavoriteCategory.name(symbol: symbol, info: SymbolFixtures.info(symbol)))
      prefs.assign(symbol, to: group)
    }
    let storage = CountingStorage()
    let store = SymbolPrefsStore(storage: storage, key: "t")
    store.save(prefs)
    let before = try #require(storage.raw["t"])
    let writesBeforeOpening = storage.writes

    let m = SymbolPickerModel(catalog: SymbolFixtures.catalog, tickers: SymbolFixtures.tickers, store: store)
    #expect(storage.writes == writesBeforeOpening)
    #expect(storage.raw["t"] == before)
    #expect(m.prefs.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
  }

  @Test("还没分类的自选照样补齐并落盘")
  func openingStillClassifiesAndSavesUnassignedFavorites() throws {
    let storage = CountingStorage()
    let store = SymbolPrefsStore(storage: storage, key: "t")
    store.save(SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"]))
    let writesBeforeOpening = storage.writes

    let m = SymbolPickerModel(catalog: SymbolFixtures.catalog, store: store)
    #expect(storage.writes == writesBeforeOpening + 1)
    #expect(m.prefs.groupForSymbol["binance/usd_m/BTCUSDT"] != nil)
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().groupForSymbol["binance/usd_m/BTCUSDT"] != nil)
  }

  @Test("目录晚一步才到，那时候才补分类")
  func classifyingWaitsForTheCatalogToArrive() throws {
    // 宿主建这个模型的时候手里没有品种表（`MainScreen` 那一处 `catalog` 是空的），
    // 品种表要么等 `setLoader`、要么等进页 `appear()` 才到。那一趟 init 里
    // 一个代号都认不出是什么（分类名来自 `underlyingType`），所以只能原样放着——
    // 账号同步拉回来的那份自选同理，字段里根本不带分类。
    let storage = CountingStorage()
    let store = SymbolPrefsStore(storage: storage, key: "t")
    store.save(SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"]))
    let writesBeforeOpening = storage.writes

    let m = SymbolPickerModel(store: store)   // 目录还没到
    #expect(storage.writes == writesBeforeOpening)
    #expect(m.prefs.groupForSymbol["binance/usd_m/BTCUSDT"] == nil)
    #expect(m.prefs.groups.isEmpty)

    // 目录到了：这时候才知道它们是什么，补一趟分类并落盘。
    // 不补的话，「知道是什么却没分类」的自选会一直挂在没有分类那一格上，
    // 一旦有了别的分类就从分类页上消失（`SymbolPrefs.favorites(in:)` 按分类过滤）。
    m.setCatalog(SymbolFixtures.catalog)
    #expect(m.prefs.groupForSymbol["binance/usd_m/BTCUSDT"] != nil)
    #expect(m.prefs.groupForSymbol["binance/usd_m/ETHUSDT"] != nil)
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().groupForSymbol["binance/usd_m/BTCUSDT"] != nil)

    // 已经齐整了就别再写：自选页每进一次都会灌一趟目录。
    let writesAfter = storage.writes
    m.setCatalog(SymbolFixtures.catalog)
    #expect(storage.writes == writesAfter)
  }

  @Test("这一批行情一行都没落在表里，就不碰 sections")
  func quotesOutsideTheTableLeaveSectionsAlone() throws {
    final class Flag: @unchecked Sendable { var hit = false }
    let (m, _) = make()
    let touched = Flag()
    withObservationTracking { _ = m.sections } onChange: { touched.hit = true }

    m.updateQuotes([Ticker(symbol: "binance/usd_m/ZZZUSDT", last: 1, changePercent: 0,
                           high: 1, low: 1, quoteVolume: 0)])
    #expect(!touched.hit)
    // 但报价本身照收：下次这一行真的出现在表里时，数字已经在手上了。
    #expect(m.ticker(for: "binance/usd_m/ZZZUSDT")?.last == 1)

    var btc = try #require(m.ticker(for: "binance/usd_m/BTCUSDT"))
    btc.last += 1
    m.updateQuotes([btc])
    #expect(touched.hit)
    #expect(m.sections.flatMap(\.rows).first { $0.id == "binance/usd_m/BTCUSDT" }?.ticker?.last == btc.last)
  }

  @Test("删自选后换了账号，提示条上的撤销不能把上一个人的自选写进新档案")
  func undoDoesNotCrossAProfileSwitch() throws {
    let (m, _) = make(prefs: SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"]))
    let snapshot = try #require(m.favoriteSnapshot("binance/usd_m/ETHUSDT"))
    m.removeFavorite("binance/usd_m/ETHUSDT")
    let undo = m.undoable { m.restoreFavorites([snapshot]) }

    let other = MemoryPrefsStorage()
    let otherStore = SymbolPrefsStore(storage: other, key: "t")
    m.useStorage(otherStore, prefs: SymbolPrefs(favorites: ["binance/usd_m/SOLUSDT"]))
    undo()
    #expect(m.prefs.favorites == ["binance/usd_m/SOLUSDT"])
    #expect(!otherStore.load().favorites.contains("binance/usd_m/ETHUSDT"))
  }

  @Test("没换档案时撤销照常放回原位")
  func undoWorksWithinTheSameProfile() throws {
    let (m, _) = make(prefs: SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"]))
    let snapshot = try #require(m.favoriteSnapshot("binance/usd_m/BTCUSDT"))
    m.removeFavorite("binance/usd_m/BTCUSDT")
    m.undoable { m.restoreFavorites([snapshot]) }()
    #expect(m.prefs.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
  }
}
