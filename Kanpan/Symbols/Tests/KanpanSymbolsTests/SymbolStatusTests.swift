import Foundation
import Testing
import KanpanCore

@testable import KanpanSymbols

/// B-T14 / B-T15 / B-T16 / B-T22：一个品种「还能不能交易」这件事，
/// 在自选、搜索、全部合约三处必须是**同一个判据**（`SymbolInfo.status`），
/// 而且不许把「下架」办成「消失」。
///
/// 全程离线：品种表和行情都是手摆的。
@Suite("B-06 挂牌状态 · 三处一致")
@MainActor
struct SymbolStatusTests {

  /// 在夹具表里把某个品种改成某一档状态，其余照旧。
  private func catalog(_ changes: [String: SymbolStatus] = [:]) -> [SymbolInfo] {
    SymbolFixtures.catalog.map { info in
      guard let status = changes[info.symbol] else { return info }
      var next = info; next.status = status; return next
    }
  }

  private var tickers: [String: Ticker] {
    Dictionary(SymbolFixtures.tickers.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })
  }

  private func model(_ list: [SymbolInfo], prefs: SymbolPrefs = SymbolPrefs())
    -> SymbolPickerModel {
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "status")
    store.save(prefs)
    return SymbolPickerModel(catalog: list, tickers: SymbolFixtures.tickers, store: store)
  }

  // ------------------------------------------------------------ B-T14

  @Test("自选里那个已下架的照旧在表上：留着身份、留着最后一口价、涨跌幅留空")
  func delistedFavoriteKeepsItsIdentity() {
    let prefs = SymbolPrefs(favorites: ["binance/usd_m/ETHUSDT", "binance/usd_m/BTCUSDT"])
    let sections = SymbolSections.build(catalog: catalog(["binance/usd_m/ETHUSDT": .delisted]),
                                        tickers: tickers, prefs: prefs, query: "")
    let favorites = try! #require(sections.first { $0.kind == .favorites })
    // ① 一行都没少，顺序还是用户自己的顺序。
    #expect(favorites.rows.map(\.id) == ["binance/usd_m/ETHUSDT", "binance/usd_m/BTCUSDT"])
    let eth = try! #require(favorites.rows.first { $0.id == "binance/usd_m/ETHUSDT" })
    // ② 最后那口真价照旧摆着（灰显由视图按 `isStale` 做），
    //    由它算出来的涨跌幅留空——不写 0.00%，也不写任何文字标签。
    #expect(eth.isStale)
    #expect(eth.priceText == "2913.45")
    #expect(eth.changeText == "—")
    // ③ 还在交易的那一行什么都没变。
    let btc = try! #require(favorites.rows.first { $0.id == "binance/usd_m/BTCUSDT" })
    #expect(!btc.isStale)
    #expect(btc.changeText == "+1.24%")
  }

  @Test("「全部合约」只列还能交易的，页头那句小字也只数这些")
  func allContractsListsTradableOnly() {
    let list = catalog(["binance/usd_m/ETHUSDT": .delisted, "binance/usd_m/SOLUSDT": .pending])
    let sections = SymbolSections.build(catalog: list, tickers: tickers,
                                        prefs: SymbolPrefs(), query: "")
    let all = try! #require(sections.first { $0.kind == .all })
    #expect(!all.rows.map(\.id).contains("binance/usd_m/ETHUSDT"))
    #expect(!all.rows.map(\.id).contains("binance/usd_m/SOLUSDT"))
    #expect(all.rows.count == list.count - 2)
    #expect(SymbolSections.countText(list) == "\(list.count - 2) 个永续合约")
  }

  @Test("搜得到那个已下架的自选，只是排在同档的后面")
  func searchStillFindsDelistedRows() {
    // ETHFI / ETHW 跟 ETH 撞前缀，是**同一档**（前缀命中）；ETH 自己是打全了的那一档。
    // 夹具里 ETHFI 的成交额比 ETHW 大一个量级，所以照常应当排在它前面。
    let list = catalog(["binance/usd_m/ETHUSDT": .delisted, "binance/usd_m/ETHFIUSDT": .delisted])
    let sections = SymbolSections.build(catalog: list, tickers: tickers,
                                        prefs: SymbolPrefs(), query: "eth")
    let hits = try! #require(sections.first).rows.map(\.id)
    #expect(hits.contains("binance/usd_m/ETHUSDT"), "搜不到 = 不存在，那就把「下架」办成了「消失」")
    // 档位永远说第一句话：打全了的那个即便已下架也还在最前，下架只在**同档之内**下沉。
    #expect(hits.first == "binance/usd_m/ETHUSDT")
    // 同档里下架的那个沉到后面，哪怕它成交额更大。
    #expect(hits == ["binance/usd_m/ETHUSDT", "binance/usd_m/ETHWUSDT", "binance/usd_m/ETHFIUSDT"])
  }

  @Test("选择器和品种页读的是同一档状态，标下架不删自选")
  func pickerSharesTheSameStatus() {
    let m = model(catalog(), prefs: SymbolPrefs(favorites: ["binance/usd_m/ETHUSDT"]))
    #expect(m.info(for: "binance/usd_m/ETHUSDT")?.status == .tradable)
    m.markDelisted("binance/usd_m/ETHUSDT")
    #expect(m.info(for: "binance/usd_m/ETHUSDT")?.status == .delisted)
    // 自选一个字没动。
    #expect(m.prefs.favorites == ["binance/usd_m/ETHUSDT"])
    // 品种页那一屏立刻一致：全部合约里没有它了，自选里还在。
    #expect(!(m.sections.first { $0.kind == .all }?.rows.map(\.id).contains("binance/usd_m/ETHUSDT") ?? false))
    #expect(m.sections.first { $0.kind == .favorites }?.rows.map(\.id) == ["binance/usd_m/ETHUSDT"])
    // 再标一次是空操作（不许把表重建成别的样子）。
    m.markDelisted("binance/usd_m/ETHUSDT")
    #expect(m.info(for: "binance/usd_m/ETHUSDT")?.status == .delisted)
  }

  @Test("认不出来的交易所状态按「还能交易」办，不把用户的自选打成灰的")
  func unknownExchangeStatusStaysTradable() {
    #expect(SymbolStatus.exchange("TRADING") == .tradable)
    #expect(SymbolStatus.exchange("PENDING_TRADING") == .pending)
    #expect(SymbolStatus.exchange("PRE_TRADING") == .pending)
    #expect(SymbolStatus.exchange("SETTLING") == .delisted)
    #expect(SymbolStatus.exchange("something_new") == .tradable)
    #expect(SymbolStatus.exchange(nil) == .tradable)
    #expect(SymbolStatus.tradable.hasLivePrice)
    #expect(!SymbolStatus.pending.hasLivePrice)
    #expect(!SymbolStatus.delisted.hasLivePrice)
  }

  // ------------------------------------------------------------ 复核项 3

  @Test("停牌是临时的：四档状态里只有它仍按正常行办")
  func haltedIsATemporaryPauseNotADelisting() {
    // 收盘 / 休市 / 集合竞价 / 交易所维护，全是**临时**停牌。
    for raw in ["BREAK", "HALT", "AUCTION_MATCH", "END_OF_DAY", "break", "Halt"] {
      #expect(SymbolStatus.exchange(raw) == .halted, "\(raw) 不该被算成别的档")
    }
    // 真的不会再开的那些才是下架。
    for raw in ["CLOSE", "SETTLING", "PRE_SETTLE", "PRE_DELIVERING", "DELIVERING", "DELIVERED"] {
      #expect(SymbolStatus.exchange(raw) == .delisted, "\(raw) 该算下架")
    }
    #expect(SymbolStatus.allCases.count == 4)
    #expect(SymbolStatus.halted.hasLivePrice)          // 身份与外观一律正常
    #expect(SymbolStatus.halted.isHalted)
    #expect(!SymbolStatus.delisted.isHalted)

    // 美股永续每天收盘都报 BREAK：那一整页不许因此变灰、掉行、少计数。
    let list = catalog(["binance/usd_m/ETHUSDT": .halted])
    let prefs = SymbolPrefs(favorites: ["binance/usd_m/ETHUSDT"])
    let sections = SymbolSections.build(catalog: list, tickers: tickers, prefs: prefs, query: "")
    let favorite = try! #require(sections.first { $0.kind == .favorites }?
      .rows.first { $0.id == "binance/usd_m/ETHUSDT" })
    #expect(!favorite.isStale, "停牌不是「没有实时价」，灰不灰只看价格新不新鲜")
    #expect(favorite.changeText == "\u{2212}0.86%")           // 涨跌幅照常摆
    #expect(favorite.catalogListing == .listed(.halted))
    #expect(!favorite.catalogListing.isDelisted)
    // 「全部合约」里照常有它，页头那句小字也照常数它。
    // （上面那一屏把 ETH 摆进了自选组，「全部」按原型会剔掉露过脸的，所以另起一屏看。）
    let plain = SymbolSections.build(catalog: list, tickers: tickers,
                                     prefs: SymbolPrefs(), query: "")
    let all = try! #require(plain.first { $0.kind == .all })
    #expect(all.rows.map(\.id).contains("binance/usd_m/ETHUSDT"))
    #expect(SymbolSections.countText(list) == "\(list.count) 个永续合约")
    // 搜索里也不下沉（下沉只对真的没有实时价的那些）。
    let hits = SymbolSections.build(catalog: list, tickers: tickers,
                                    prefs: SymbolPrefs(), query: "eth")
      .first?.rows.map(\.id)
    #expect(hits == ["binance/usd_m/ETHUSDT", "binance/usd_m/ETHFIUSDT", "binance/usd_m/ETHWUSDT"])
  }

  // ------------------------------------------------------------ 复核项 4

  @Test("目录里没有这个自选 = 未知：留着、按没有实时价、不划掉、不删")
  func favoritesMissingFromTheCatalogShowAsUnknown() {
    // GONEUSDT 不在目录里，但盘上还留着上次看到的那口价（报价快照）。
    var quotes = tickers
    quotes["binance/usd_m/GONEUSDT"] = Ticker(symbol: "binance/usd_m/GONEUSDT", last: 0.0000004, changePercent: 3.2,
                                high: .nan, low: .nan, quoteVolume: .nan)
    let prefs = SymbolPrefs(favorites: ["binance/usd_m/GONEUSDT", "binance/usd_m/BTCUSDT"])
    let sections = SymbolSections.build(catalog: SymbolFixtures.catalog, tickers: quotes,
                                        prefs: prefs, query: "")
    let favorites = try! #require(sections.first { $0.kind == .favorites })
    // ① 一行都没少，顺序还是用户自己排的顺序（从前它被 compactMap 掉，凭空消失）。
    #expect(favorites.rows.map(\.id) == ["binance/usd_m/GONEUSDT", "binance/usd_m/BTCUSDT"])
    let gone = try! #require(favorites.rows.first { $0.id == "binance/usd_m/GONEUSDT" })
    // ② 「未知」不是「下架」：按没有实时价渲染（灰），但不划掉、不算下架。
    #expect(gone.catalogListing == .unknown)
    #expect(!gone.catalogListing.isDelisted)
    #expect(gone.isStale)
    #expect(gone.changeText == "—")
    // ③ 最后那口真价照旧摆着，而且不许被写成 `0.00`——占位行没有精度，按价自己猜。
    #expect(gone.priceText == fmtPrice(0.0000004, decimals: priceDecimalsFallback(0.0000004)))
    #expect((Double(gone.priceText) ?? 0) > 0)
    #expect(gone.name == "GONE" && gone.info.quote == "USDT")
    // ④ 它不属于「全部合约」，也不进页头计数。
    #expect(!(sections.first { $0.kind == .all }?.rows.map(\.id).contains("binance/usd_m/GONEUSDT") ?? true))
  }

  @Test("目录还没到的时候不算未知：整页自选不许一起变灰")
  func favoritesAreNotGreyedBeforeTheCatalogArrives() {
    let prefs = SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"])
    let sections = SymbolSections.build(catalog: [], tickers: tickers, prefs: prefs, query: "")
    let row = try! #require(sections.first { $0.kind == .favorites }?.rows.first)
    #expect(row.id == "binance/usd_m/BTCUSDT")
    #expect(row.catalogListing == .unloaded)
    #expect(!row.isStale, "冷启动第一帧目录还没到，价是刚拿到的，凭「目录慢」打灰是冤枉它")
    #expect(row.changeText == "+1.24%")
  }

  @Test("被市场药丸筛掉的自选照旧不列，不许当成未知")
  func favoritesFilteredByThePillAreOmittedNotUnknown() {
    // 药丸把目录筛成只剩 BTC；ETH 仍然在完整目录里，只是不属于这颗药丸。
    let full = SymbolFixtures.catalog
    let filtered = full.filter { $0.symbol == "binance/usd_m/BTCUSDT" }
    let prefs = SymbolPrefs(favorites: ["binance/usd_m/ETHUSDT", "binance/usd_m/BTCUSDT"])
    let sections = SymbolSections.build(catalog: filtered, tickers: tickers, prefs: prefs,
                                        query: "",
                                        catalogKeys: Set(full.map(\.symbol)))
    #expect(sections.first { $0.kind == .favorites }?.rows.map(\.id) == ["binance/usd_m/BTCUSDT"])
    // 不给 `catalogKeys`（也就是没有药丸这回事）时，ETH 就成了「目录里没有」。
    let naive = SymbolSections.build(catalog: filtered, tickers: tickers, prefs: prefs, query: "")
    #expect(naive.first { $0.kind == .favorites }?.rows.map(\.id) == ["binance/usd_m/ETHUSDT", "binance/usd_m/BTCUSDT"])
    #expect(naive.first { $0.kind == .favorites }?.rows.first?.catalogListing == .unknown)
  }

  @Test("选择器给出的挂牌口径：三处都问它，同一个代号不会有两种说法")
  func pickerAnswersTheSameListingEverywhere() {
    let m = model(catalog(["binance/usd_m/SOLUSDT": .halted, "binance/usd_m/XRPUSDT": .pending]))
    #expect(m.listing(of: "binance/usd_m/BTCUSDT") == .listed(.tradable))
    #expect(m.listing(of: "binance/usd_m/SOLUSDT") == .listed(.halted))
    #expect(m.listing(of: "binance/usd_m/XRPUSDT") == .listed(.pending))
    // 目录里没有 = 未知（不是下架）。
    #expect(m.listing(of: "binance/usd_m/GONEUSDT") == .unknown)
    #expect(m.listing(of: "binance/usd_m/GONEUSDT").hasLivePrice == false)
    #expect(m.listing(of: "binance/usd_m/GONEUSDT").isDelisted == false)
    // 停牌那一行仍然有实时价可言。
    #expect(m.listing(of: "binance/usd_m/SOLUSDT").hasLivePrice)
    // 明确标过才是下架，而且目录里没有它也记得住（占位行）。
    m.markDelisted("binance/usd_m/GONEUSDT")
    #expect(m.listing(of: "binance/usd_m/GONEUSDT") == .listed(.delisted))
    #expect(m.listing(of: "binance/usd_m/GONEUSDT").isDelisted)
    #expect(m.info(for: "binance/usd_m/GONEUSDT")?.pricePrecision == 0)
    // 目录空着的时候什么都不知道，别装作知道。
    let empty = model([])
    #expect(empty.listing(of: "binance/usd_m/BTCUSDT") == .unloaded)
    #expect(empty.listing(of: "binance/usd_m/BTCUSDT").hasLivePrice)
  }

  // ------------------------------------------------------------ B-T15

  @Test("搜一个表里没有的代号：问一次目录，同一个词只问一次")
  func missingSymbolAsksTheCatalogOnce() async {
    let m = model(catalog())
    let box = Counter()
    m.onMissingSymbol = { symbol in
      await box.note(symbol)
      return SymbolFixtures.catalog + [SymbolInfo(symbol: "binance/usd_m/ASTERUSDT", base: "ASTER",
                                                  pricePrecision: 4, tickSize: 0.0001)]
    }
    m.query = "ASTERUSDT"
    // 第一趟：零命中 → 问目录 → 新表灌回来 → 这一屏立刻有它。
    await waitFor { m.info(for: "binance/usd_m/ASTERUSDT") != nil }
    #expect(await box.asked == ["ASTERUSDT"])
    #expect(m.sections.first?.rows.map(\.id) == ["binance/usd_m/ASTERUSDT"])
    // 再搜一遍同一个词：表里已经有了，不再问。
    m.query = ""
    m.query = "ASTERUSDT"
    #expect(await box.asked == ["ASTERUSDT"])
  }

  @Test("打到一半的前缀不算「点名」，不问目录")
  func partialQueriesDoNotAsk() async {
    let m = model(catalog())
    let box = Counter()
    m.onMissingSymbol = { symbol in await box.note(symbol); return nil }
    m.query = "ZZ"           // 太短
    m.query = "ZZ-"          // 带杂字符
    m.query = "BTC"          // 有命中
    // 给异步一点时间，确认确实一趟都没发。
    try? await Task.sleep(nanoseconds: 120_000_000)
    #expect(await box.asked.isEmpty)
  }

  // ------------------------------------------------------------ B-T16

  @Test("四种精度的价：小数位听品种表的，极小的正价不写成 0")
  func priceTextFollowsTheSymbolsPrecision() {
    let rows = SymbolSections.build(catalog: SymbolFixtures.catalog, tickers: tickers,
                                    prefs: SymbolPrefs(), query: "")
      .first { $0.kind == .all }?.rows ?? []
    func text(_ symbol: String) -> String? { rows.first { $0.id == symbol }?.priceText }
    #expect(text("binance/usd_m/BTCUSDT") == "76800.0")           // 1 位
    #expect(text("binance/usd_m/SOLUSDT") == "141.226")           // 3 位
    #expect(text("binance/usd_m/XRPUSDT") == "2.1843")            // 4 位
    #expect(text("binance/usd_m/1000PEPEUSDT") == "0.0074812")    // 7 位
    // 精度写 2 位、价格极小的合成行：绝不能写成 `0.00`。
    let tiny = SymbolInfo(symbol: "binance/usd_m/TINYUSDT", base: "TINY", pricePrecision: 2, tickSize: 0.01)
    let row = SymbolRow(match: SymbolMatch(info: tiny),
                        ticker: Ticker(symbol: "binance/usd_m/TINYUSDT", last: 0.00000004, changePercent: 1,
                                       high: 1, low: 1, quoteVolume: 1))
    #expect(row.priceText != "0.00")
    #expect((Double(row.priceText) ?? 0) > 0)
    // 品种表缺位时那把共用的梯子（和板块页同一把）。
    #expect(priceDecimalsFallback(76_800) == 2)
    #expect(priceDecimalsFallback(2.18) == 4)
    #expect(priceDecimalsFallback(0.162) == 5)
    #expect(priceDecimalsFallback(0.0074) == 7)
    // P4.8 普查：0.01–0.1 与 0.001 以下两段按真实步长各多给一位，不再吃掉有效数字。
    #expect(priceDecimalsFallback(0.016991) == 6)   // COTIUSDT 步长 0.000001
    #expect(priceDecimalsFallback(0.00001234) == 8) // 1000SATSUSDT 步长 0.00000001
  }

  // ------------------------------------------------------------ B-T22

  @Test("同一个词搜三遍：成交额一批批到，档位不乱、没有额的不伪排")
  func searchOrderIsStableWhileVolumesArrive() {
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "order")
    let m = SymbolPickerModel(catalog: SymbolFixtures.catalog, tickers: [], store: store)
    // ① 一条行情都没有：档位说话，同档保交易所原序。
    let first = m.matchingSymbols("eth")
    #expect(first == ["binance/usd_m/ETHUSDT", "binance/usd_m/ETHFIUSDT", "binance/usd_m/ETHWUSDT"])
    // ② 只有一部分有额：有额的排在没额的前面，没额的彼此保原序。
    m.apply([Ticker(symbol: "binance/usd_m/ETHWUSDT", last: 1.88, changePercent: 0, high: 2, low: 1,
                    quoteVolume: 9.9e9)])
    let second = m.matchingSymbols("eth")
    #expect(second.first == "binance/usd_m/ETHUSDT", "打全了的那一档永远在最前，成交额不许越档")
    #expect(second == ["binance/usd_m/ETHUSDT", "binance/usd_m/ETHWUSDT", "binance/usd_m/ETHFIUSDT"])
    // ③ 非法的额（NaN / 负数）按「没有」办，不许拿它排出一个假顺序。
    m.apply([Ticker(symbol: "binance/usd_m/ETHWUSDT", last: 1.88, changePercent: 0, high: 2, low: 1,
                    quoteVolume: .nan),
             Ticker(symbol: "binance/usd_m/ETHFIUSDT", last: 1.2, changePercent: 0, high: 2, low: 1,
                    quoteVolume: -1)])
    #expect(m.matchingSymbols("eth") == first)
    // ④ 同一份数据搜两遍必须一样（排序谓词是严格弱序）。
    #expect(m.matchingSymbols("eth") == m.matchingSymbols("eth"))
  }

  @Test("已下架的排在同档最后，但照旧列在搜索结果里")
  func delistedRowsSinkWithinTheirTier() {
    let store = SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "sink")
    let m = SymbolPickerModel(catalog: catalog(["binance/usd_m/ETHFIUSDT": .delisted]),
                              tickers: SymbolFixtures.tickers, store: store)
    let hits = m.matchingSymbols("eth")
    #expect(hits.contains("binance/usd_m/ETHFIUSDT"), "下架了照旧搜得到")
    // 成交额更大的 ETHFI 下架了，于是沉到同档最后。
    #expect(hits == ["binance/usd_m/ETHUSDT", "binance/usd_m/ETHWUSDT", "binance/usd_m/ETHFIUSDT"])
    // 顶栏搜索走的是这条路，和上面品种页那条（`SymbolSections`）必须同一个次序规则：
    // 打全了的那一档不因为下架而让位。
    let other = SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "sink2")
    let n = SymbolPickerModel(catalog: catalog(["binance/usd_m/ETHUSDT": .delisted]),
                              tickers: SymbolFixtures.tickers, store: other)
    #expect(n.matchingSymbols("eth") == ["binance/usd_m/ETHUSDT", "binance/usd_m/ETHFIUSDT", "binance/usd_m/ETHWUSDT"])
  }
}

/// 记一笔「问过哪些词」。`onMissingSymbol` 在主 actor 上被调，但它是 async 的，
/// 用个 actor 装着最稳。
private actor Counter {
  var asked: [String] = []
  func note(_ symbol: String) { asked.append(symbol) }
}

/// 等一个条件成立（最多 2 秒）。异步只有一跳，但别把用例写成靠运气。
@MainActor
private func waitFor(_ condition: () -> Bool) async {
  for _ in 0..<200 {
    if condition() { return }
    try? await Task.sleep(nanoseconds: 10_000_000)
  }
}
