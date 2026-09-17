import Foundation
import Observation
import Testing
import KanpanCore

@testable import KanpanSymbols

/// 整页的行为：搜索联动、星星、最近、订阅 / 退订、落盘。全程无网络。
@Suite("品种页")
@MainActor
struct SymbolPickerModelTests {

  private func make(prefs: SymbolPrefs = SymbolPrefs(),
                    feed: StaticTickerFeed? = nil,
                    tickers: [Ticker] = SymbolFixtures.tickers)
    -> (SymbolPickerModel, MemoryPrefsStorage) {
    let storage = MemoryPrefsStorage()
    let store = SymbolPrefsStore(storage: storage, key: "t")
    store.save(prefs)
    let m = SymbolPickerModel(catalog: SymbolFixtures.catalog,
                              tickers: tickers,
                              store: store,
                              feed: feed)
    return (m, storage)
  }

  @Test("重新连接清除报价而不改自选存档")
  func reconnectClearsQuotesOnly() {
    let (m, storage) = make(prefs: SymbolPrefs(favorites: ["BTCUSDT"]))
    #expect(!m.tickers.isEmpty)
    m.clearQuotes()
    #expect(m.tickers.isEmpty)
    #expect(m.prefs.favorites == ["BTCUSDT"])
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().favorites == ["BTCUSDT"])
  }

  @Test("离开订阅范围只移除旧报价，收藏与仍订阅报价保持")
  func unsubscribeDropsStaleQuotes() throws {
    let (m, storage) = make(prefs: SymbolPrefs(favorites: ["BTCUSDT", "ETHUSDT"]))
    let btc = try #require(m.ticker(for: "BTCUSDT"))
    m.retainQuotes(for: ["BTCUSDT"])
    #expect(m.tickers.count == 1 && m.ticker(for: "BTCUSDT") == btc)
    #expect(m.ticker(for: "ETHUSDT") == nil)
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().favorites == ["BTCUSDT", "ETHUSDT"])
  }

  @Test("隐藏搜索表不随报价重建，打开时追上最新")
  func hiddenSectionsCatchUpOnPresentation() throws {
    let (m, _) = make()
    let original = m.sections
    m.setSectionsActive(false)
    var ticker = try #require(m.ticker(for: "BTCUSDT"))
    ticker.last += 100
    m.updateQuotes([ticker])
    #expect(m.ticker(for: "BTCUSDT")?.last == ticker.last)
    #expect(m.sections == original)
    m.setSectionsActive(true)
    #expect(m.sections != original)
  }

  @Test("报价变化只刷新数字，不在手指下自动重排")
  func quotesKeepRowPositionsStable() throws {
    let (model, _) = make()
    let order = model.sections.flatMap(\.rows).map(\.id)
    var quote = try #require(model.ticker(for: "BTCUSDT"))
    quote.last += 1; quote.quoteVolume = 0
    model.updateQuotes([quote])
    #expect(model.sections.flatMap(\.rows).map(\.id) == order)
    #expect(model.sections.flatMap(\.rows).first { $0.id == "BTCUSDT" }?.ticker?.last == quote.last)
  }

  @Test("开页就把存档读回来")
  func loadsPrefsOnInit() {
    let (m, _) = make(prefs: SymbolPrefs(favorites: ["ETHUSDT"], recents: ["SOLUSDT"]))
    #expect(m.prefs.favorites == ["ETHUSDT"])
    #expect(m.sections.map(\.kind) == [.favorites, .recents, .all])
  }

  @Test("改搜索词，分区立刻跟着变")
  func queryRebuilds() {
    let (m, _) = make(prefs: SymbolPrefs(favorites: ["BTCUSDT"]))
    #expect(m.sections.count == 2)
    m.query = "eth"
    #expect(m.sections.count == 1)
    #expect(m.sections[0].rows.map(\.id) == ["ETHUSDT", "ETHFIUSDT", "ETHWUSDT"])
    m.query = "zzz"
    #expect(m.isEmpty)
    m.query = ""
    #expect(m.sections.count == 2)
    #expect(!m.isEmpty)
  }

  @Test("点星星：加 → 落盘 → 分区里冒出自选组；再点一次全撤回")
  func toggleFavoritePersists() {
    let (m, storage) = make()
    #expect(m.sections.map(\.kind) == [.all])

    #expect(m.toggleFavorite("SOLUSDT") == true)
    #expect(m.isFavorite("SOLUSDT"))
    #expect(m.sections.first?.kind == .favorites)
    #expect(m.sections.first?.rows.map(\.id) == ["SOLUSDT"])

    // 真落盘了：另开一个 model 读同一份存档
    let reopened = SymbolPickerModel(catalog: SymbolFixtures.catalog,
                                     store: SymbolPrefsStore(storage: storage, key: "t"))
    #expect(reopened.prefs.favorites == ["SOLUSDT"])

    #expect(m.toggleFavorite("SOLUSDT") == false)
    #expect(m.sections.map(\.kind) == [.all])
  }

  @Test("左滑删除按分区内下标删对人")
  func removeFavoritesByOffsets() {
    let (m, _) = make(prefs: SymbolPrefs(favorites: ["A1USDT", "BTCUSDT", "ETHUSDT"]))
    m.removeFavorites(at: IndexSet(integer: 1))
    #expect(m.prefs.favorites == ["A1USDT", "ETHUSDT"])
    m.removeFavorites(at: IndexSet([0, 1]))
    #expect(m.prefs.favorites.isEmpty)
    // 越界不崩
    m.removeFavorites(at: IndexSet(integer: 9))
    #expect(m.prefs.favorites.isEmpty)
  }

  @Test("拖排序后落盘，顺序就是自选分区的顺序")
  func reorderPersists() {
    let (m, storage) = make(prefs: SymbolPrefs(favorites: ["BTCUSDT", "ETHUSDT", "SOLUSDT"]))
    m.moveFavorite("SOLUSDT", onto: "BTCUSDT")
    #expect(m.prefs.favorites == ["SOLUSDT", "BTCUSDT", "ETHUSDT"])
    #expect(m.sections.first?.rows.map(\.id) == ["SOLUSDT", "BTCUSDT", "ETHUSDT"])
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().favorites
      == ["SOLUSDT", "BTCUSDT", "ETHUSDT"])

    m.moveFavorites(from: IndexSet(integer: 0), to: 3)
    #expect(m.prefs.favorites == ["BTCUSDT", "ETHUSDT", "SOLUSDT"])
  }

  @Test("点一行：记进最近、落盘、回调宿主（A5.9）")
  func pickRecordsRecent() {
    let (m, storage) = make()
    var picked: [String] = []
    m.onPick = { picked.append($0.symbol) }

    m.pick(symbol: "SOLUSDT")
    m.pick(symbol: "BTCUSDT")
    #expect(picked == ["SOLUSDT", "BTCUSDT"])
    #expect(m.prefs.recents == ["BTCUSDT", "SOLUSDT"])
    #expect(m.sections.first?.kind == .recents)
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().recents == ["BTCUSDT", "SOLUSDT"])

    // 品种表里没有的，不回调也不记
    m.pick(symbol: "NOPEUSDT")
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
    #expect(m.prefs.recents.first == "S12USDT")
    #expect(m.sections.first { $0.kind == .recents }?.rows.count == 10)
  }

  // ---------------------------------------------------------------- 行情流

  @Test("进页订阅、出页退订，并且都打了日志（A5.7）")
  func subscribeAndUnsubscribe() async {
    let feed = StaticTickerFeed(SymbolFixtures.tickers)
    let (m, _) = make(feed: feed)
    var lines: [String] = []
    m.log = { lines.append($0) }

    await m.appear()
    #expect(feed.startCount == 1)
    #expect(feed.isRunning)
    #expect(lines == ["品种页订阅 !ticker@arr"])

    m.disappear()
    #expect(feed.stopCount == 1)
    #expect(!feed.isRunning)
    #expect(lines == ["品种页订阅 !ticker@arr", "品种页退订 !ticker@arr"])

    // 重复 disappear 不会再退一次
    m.disappear()
    #expect(feed.stopCount == 1)
  }

  @Test("推一批新价，行上的数跟着跳")
  func tickerUpdatesRows() async {
    let feed = StaticTickerFeed([])
    let (m, _) = make(feed: feed, tickers: [])     // 开局没有任何行情
    await m.appear()
    #expect(m.sections[0].rows.first { $0.id == "BTCUSDT" }?.priceText == "—")

    feed.push([Ticker(symbol: "BTCUSDT", last: 77_123.4, changePercent: -2.5,
                      high: 78_000, low: 76_000, quoteVolume: 1e9)])
    let btc = m.sections[0].rows.first { $0.id == "BTCUSDT" }
    #expect(btc?.priceText == "77123.40")
    #expect(btc?.changeText == "-2.50%")
    #expect(btc?.isUp == false)

    // 退订之后再推，进不来了
    m.disappear()
    feed.push([Ticker(symbol: "BTCUSDT", last: 1, changePercent: 0,
                      high: 1, low: 1, quoteVolume: 1)])
    #expect(m.sections[0].rows.first { $0.id == "BTCUSDT" }?.priceText == "77123.40")
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
    var prefs = SymbolPrefs(favorites: ["BTCUSDT", "ETHUSDT"])
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
    #expect(m.prefs.favorites == ["BTCUSDT", "ETHUSDT"])
  }

  @Test("还没分类的自选照样补齐并落盘")
  func openingStillClassifiesAndSavesUnassignedFavorites() throws {
    let storage = CountingStorage()
    let store = SymbolPrefsStore(storage: storage, key: "t")
    store.save(SymbolPrefs(favorites: ["BTCUSDT"]))
    let writesBeforeOpening = storage.writes

    let m = SymbolPickerModel(catalog: SymbolFixtures.catalog, store: store)
    #expect(storage.writes == writesBeforeOpening + 1)
    #expect(m.prefs.groupForSymbol["BTCUSDT"] != nil)
    #expect(SymbolPrefsStore(storage: storage, key: "t").load().groupForSymbol["BTCUSDT"] != nil)
  }

  @Test("这一批行情一行都没落在表里，就不碰 sections")
  func quotesOutsideTheTableLeaveSectionsAlone() throws {
    final class Flag: @unchecked Sendable { var hit = false }
    let (m, _) = make()
    let touched = Flag()
    withObservationTracking { _ = m.sections } onChange: { touched.hit = true }

    m.updateQuotes([Ticker(symbol: "ZZZUSDT", last: 1, changePercent: 0,
                           high: 1, low: 1, quoteVolume: 0)])
    #expect(!touched.hit)
    // 但报价本身照收：下次这一行真的出现在表里时，数字已经在手上了。
    #expect(m.ticker(for: "ZZZUSDT")?.last == 1)

    var btc = try #require(m.ticker(for: "BTCUSDT"))
    btc.last += 1
    m.updateQuotes([btc])
    #expect(touched.hit)
    #expect(m.sections.flatMap(\.rows).first { $0.id == "BTCUSDT" }?.ticker?.last == btc.last)
  }
}
