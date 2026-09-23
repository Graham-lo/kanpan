import Foundation
import KanpanCore
import KanpanNetwork

// ============================================================ 什么时候给默认自选
//
// 该给哪几条在 `DefaultFavorites`（纯的，有单测）。这一层只管**什么时候给**，
// 因为那要碰三样纯逻辑碰不着的东西：目录什么时候到、成交额榜要联网取、
// 以及「给过没有」这个记号得落在本机。
//
// 一条一条说清楚（方案第 3 节第四件）：
//
// · **只给真正空手的人**：没有账号（访客档案）、一条自选都没有。登录过的人手上
//   那张表是他自己的，一个字都不许加。冷启动那 900 毫秒里挂着的是访客空档案
//   （`AppAccountBridge` 先装访客、`account.restore()` 回来再换成账号那份），
//   所以真要落笔之前还得再问一次「现在还是刚才那份档案吗」——代次对不上就作废。
// · **只给一次**。记号记在本机 `UserDefaults` 里，不进档案、不随账号同步：
//   用户把这几条删掉之后，换一台设备登同一个账号也不该把它们送回来，
//   而「这台机器我已经招呼过了」本来就是这台机器自己的事。
// · **拿不到成交额榜也要给**。联网取榜失败（第一次开机常常还没连上）时退回
//   BTC / ETH / SOL 三条锚——三条总比一页空白强，剩下的他自己搜。
//
// 「冷启动有收藏就进自选页」那条规则不动：这几条落盘之后回一句
// `AppAccountBridge.onProfileReady`，宿主按它自己那套重新兑现落地页，
// 于是第一次开 app 的人正好停在一页有东西的自选上。

@MainActor enum DefaultFavoritesSeeder {
  /// 本机记号。名字里带 v1，将来真要重新招呼一轮（比如默认名单换了口径）时
  /// 换一个键就行，不必去猜老键上那个 true 当初是什么意思。
  static let markKey = "kanpan.defaultFavorites.seeded.v1"

  /// 正在跑的那一趟。一次开机只跑一趟。
  private static var running = false

  /// 记号落在哪儿。测试里换一个空的 `UserDefaults` 就不会碰到真机上的。
  static var defaults: UserDefaults = .standard

  /// 取全市场 24h 成交额。测试里换成假的。
  static var loadTickers: @Sendable () async -> [Ticker] = {
    // 按这台设备选的线路取默认交易所的全市场榜。线路只记在本机（`MarketRoutePolicyStore`），
    // 冷启动这一刻已经读得到，不必等账号档案；选了网关的人不能在这里偷偷直连交易所（审查 14）。
    let rest = RouteResolver.current.provider(venue: VenueRegistry.default.id)
    // 两趟：第一次开机时网络常常刚刚才通。两趟都不成就按没有榜处理。
    for attempt in 0..<2 {
      if let tickers = try? await rest.tickers24h(timeout: 8), !tickers.isEmpty { return tickers }
      if attempt == 0 { try? await Task.sleep(for: .seconds(2)) }
    }
    return []
  }

  /// 档案刚装进来，看看这台机器要不要招呼一下。
  ///
  /// - Parameters:
  ///   - symbols: 自选表。
  ///   - isGuest: 这份档案是不是访客的（没有账号）。
  ///   - stillCurrent: 落笔前再问一次「还是刚才那份档案吗」。
  ///   - done: 真的加进去了才响，宿主据此重新兑现落地页。
  static func consider(symbols: SymbolPickerModel, isGuest: Bool,
                       stillCurrent: @escaping @MainActor () -> Bool,
                       done: @escaping @MainActor () -> Void) {
    // UI 测试自己灌自选（`SymbolPrefs.testSeed`），别和它抢。这一句只在 DEBUG 下编：
    // Release 里没有测试档案，也就没有要让路的对象（审查 C.10-1）。
    #if DEBUG
    guard ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] != "1" else { return }
    #endif
    guard !defaults.bool(forKey: markKey) else { return }
    guard isGuest else { return }
    // 手上已经有自选：这台机器不是新的（老用户升级上来的那批），记上记号，
    // 以后连想都不用再想。
    guard symbols.prefs.favorites.isEmpty else { remember(); return }
    guard !running else { return }
    running = true
    Task {
      await run(symbols: symbols, stillCurrent: stillCurrent, done: done)
      running = false
    }
  }

  /// 测试用：把「这一趟在跑」的记号清掉。
  static func reset() { running = false }

  private static func run(symbols: SymbolPickerModel,
                          stillCurrent: @MainActor () -> Bool,
                          done: @MainActor () -> Void) async {
    guard let catalog = await waitForCatalog(symbols) else { return }
    let tickers = await loadTickers()
    // 取榜那几秒里可能已经换了档案（账号回来了）、或者用户自己抢先加了一条。
    guard stillCurrent(), symbols.prefs.favorites.isEmpty else { return }
    let picks = DefaultFavorites.pick(catalog: catalog, tickers: tickers)
    guard !symbols.seedFavorites(picks).isEmpty else { return }
    remember()
    done()
  }

  /// 等目录。冷启动时它可能是从缓存里秒回，也可能要走一趟网络。
  /// 等不到就这一趟作罢——记号没落，下次开机再说。
  private static func waitForCatalog(_ symbols: SymbolPickerModel) async -> [SymbolInfo]? {
    for _ in 0..<60 {
      if !symbols.catalog.isEmpty { return symbols.catalog }
      try? await Task.sleep(for: .milliseconds(250))
    }
    return nil
  }

  private static func remember() { defaults.set(true, forKey: markKey) }
}
