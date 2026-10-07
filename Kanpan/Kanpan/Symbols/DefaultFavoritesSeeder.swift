import Foundation
import KanpanCore
import KanpanNetwork

// ============================================================ 什么时候给默认自选
//
// 该给哪几条、各归哪一类在 `DefaultFavorites`（纯的，有单测），怎么并进已有的表在
// `SymbolPickerModel.seedFavorites`。这一层只管**什么时候给**，因为那要碰三样纯逻辑
// 碰不着的东西：目录什么时候到、成交额榜要联网取、以及「给过没有」这个记号得落在本机。
//
// 一条一条说清楚（2026-10-07 用户改的口径）：
//
// · **访客和账号一视同仁**。每一份档案装进来都问一次：访客记在 `guest` 名下，账号记在
//   它的用户 id 名下。手上已经有自选也照样给——只补缺的那几条，他自己的一条不动、
//   分类一个不挪（并法见 `seedFavorites`）。
// · **每台设备、每份档案只给一次**。记号记在本机 `UserDefaults` 里（键带档案名），
//   不进档案、不随账号同步：「这台机器上这份档案我已经招呼过了」本来就是这台机器自己的事。
//   名单换了口径就换键（v1 → v2 → v3）：老键直接不认，老用户升级上来会被并一趟新名单
//   （v3：现货排到永续前面，这一趟顺手把挨着的同品种按「现货在前」站好）。
//   跑完了就记，哪怕一条都没加（他手上本来就全有）——那也是招呼过了。
// · **一趟只给最新那份档案**。冷启动先装访客档案顶着，`account.restore()` 回来再换成
//   账号那份；访客那一趟还在等目录 / 取榜时账号档案到了，就当场把访客那趟作废、
//   给账号重开一趟（原来是「正在跑就不再起」，账号那趟在这次开机里就被吞掉了）。
//   每次 await 回来、真要落笔之前都再问一次「被作废了没有、还是刚才那份档案吗」。
// · **拿不到成交额榜也要给**。联网取榜失败（第一次开机常常还没连上）时点名的那几条
//   照给，只是少了成交额前五——剩下的他自己搜。
//
// 「冷启动有收藏就进自选页」那条规则不动：真加了东西之后回一句
// `AppAccountBridge.onProfileReady`，宿主按它自己那套重新兑现落地页，
// 于是第一次开 app 的人正好停在一页有东西的自选上。

@MainActor enum DefaultFavoritesSeeder {
  /// 本机记号的前缀，后面接档案名（`guest` 或账号的用户 id）。名字里带版本号：
  /// 将来真要重新招呼一轮时换一个键就行，不必去猜老键上那个 true 当初是什么意思。
  static let markPrefix = "kanpan.defaultFavorites.seeded.v3."

  /// 访客档案在记号里的名字。
  static let guestProfile = "guest"

  static func markKey(_ profileKey: String) -> String { markPrefix + profileKey }

  /// 正在跑的那一趟。新的档案进来就作废它。
  private static var task: Task<Void, Never>?

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
  ///   - profileKey: 这份档案的名字：访客是 `guestProfile`，账号是它的用户 id。
  ///   - stillCurrent: 落笔前再问一次「还是刚才那份档案吗」。
  ///   - done: 真的加进去了才响，宿主据此重新兑现落地页。
  static func consider(symbols: SymbolPickerModel, profileKey: String,
                       stillCurrent: @escaping @MainActor () -> Bool,
                       done: @escaping @MainActor () -> Void) {
    // 换了档案：上一份档案那一趟不管走到哪儿都作废（它写的是上一个人的表）。
    task?.cancel(); task = nil
    // UI 测试自己灌自选（`SymbolPrefs.testSeed`），别和它抢。这一句只在 DEBUG 下编：
    // Release 里没有测试档案，也就没有要让路的对象（审查 C.10-1）。
    #if DEBUG
    guard ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] != "1" else { return }
    #endif
    let key = markKey(profileKey)
    guard !defaults.bool(forKey: key) else { return }
    task = Task {
      await run(symbols: symbols, markKey: key, stillCurrent: stillCurrent, done: done)
    }
  }

  /// 测试用：作废正在跑的那一趟。
  static func reset() { task?.cancel(); task = nil }

  private static func run(symbols: SymbolPickerModel, markKey: String,
                          stillCurrent: @MainActor () -> Bool,
                          done: @MainActor () -> Void) async {
    guard let catalog = await waitForCatalog(symbols), !Task.isCancelled, stillCurrent() else { return }
    let tickers = await loadTickers()
    // 取榜那几秒里可能已经换了档案（账号回来了、退登了）。
    guard !Task.isCancelled, stillCurrent() else { return }
    let plan = DefaultFavorites.pick(catalog: catalog, tickers: tickers)
    guard !plan.isEmpty else { return }
    let added = symbols.seedFavorites(plan)
    defaults.set(true, forKey: markKey)
    if !added.isEmpty { done() }
  }

  /// 等目录。冷启动时它可能是从缓存里秒回，也可能要走一趟网络。
  /// 等不到就这一趟作罢——记号没落，下次开机再说。
  private static func waitForCatalog(_ symbols: SymbolPickerModel) async -> [SymbolInfo]? {
    for _ in 0..<60 {
      if Task.isCancelled { return nil }
      if !symbols.catalog.isEmpty { return symbols.catalog }
      try? await Task.sleep(for: .milliseconds(250))
    }
    return nil
  }
}
