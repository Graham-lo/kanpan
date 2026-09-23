import Foundation
import Testing
import KanpanCore
import KanpanNetwork
@testable import KanpanSector

// 板块页取数的寿命规则（审查 A-04）。这一路上所有的错都长得一样：屏上有数、列表也在动，
// 只是那些数属于另一条线路或者属于十分钟以前。全离线，不碰网络。

private func ticker(_ symbol: String, pct: Double, volume: Double = 1_000_000,
                    last: Double = 100) -> Ticker {
  Ticker(symbol: symbol, last: last, changePercent: pct, high: last, low: last,
         quoteVolume: volume, open24h: last, timeMs: 1_700_000_000_000)
}

/// 记调用顺序。`fetchTickers` / `resetCooldowns` 是 `@Sendable` 闭包，捡不了外面的
/// 可变局部量，所以拿一个自己上锁的盒子接着。
private final class Calls: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String] = []
  func note(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
  var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

@MainActor
@Suite("A-T12 / B-T21 板块行情不许过期还摆在屏上")
struct SectorFeedTests {

  private func feed(_ tickers: [Ticker]) -> SectorFeed {
    let feed = SectorFeed()
    feed.fetchTickers = { _ in tickers }
    return feed
  }

  // ---------------------------------------------------------------- A-T12

  @Test("换线路把手里那份行情清空")
  func routeSwitchClearsQuotes() async {
    let feed = feed([ticker("BTCUSDT", pct: 1.5)])
    feed.setVisible(true)
    await settle(feed)
    #expect(feed.quotes["BTC"]?.pct == 1.5)

    // 换一家交易所。两家的 24h 口径和品种集合都不一样，上一家报的一条都不能留。
    feed.configure(endpoints: .default, policy: .gateway)
    #expect(feed.quotes.isEmpty)
    #expect(feed.lastUpdate == nil)
  }

  @Test("线路没变就不白清一次")
  func sameRouteKeepsQuotes() async {
    let feed = feed([ticker("BTCUSDT", pct: 1.5)])
    feed.setVisible(true)
    await settle(feed)
    feed.configure(endpoints: .default, policy: .direct)
    #expect(feed.quotes["BTC"]?.pct == 1.5)
  }

  // ---------------------------------------------------------------- B-T21

  @Test("连着取不到、手里那份也过了寿命，就清空给空态")
  func repeatedFailuresDropStaleQuotes() async {
    let feed = feed([ticker("BTCUSDT", pct: 1.5)])
    feed.setVisible(true)
    await settle(feed)
    feed.setVisible(false)                      // 停掉轮询，下面自己记账
    let got = feed.lastUpdate!

    // 一两趟失败不动屏：退避是 2→4 秒，那时候屏上这份还很新。
    feed.noteFailure(now: got.addingTimeInterval(2))
    feed.noteFailure(now: got.addingTimeInterval(6))
    #expect(feed.quotes["BTC"]?.pct == 1.5)

    // 第三趟，而且屏上这份已经一分多钟没换过了：不能再摆出实时的样子。
    feed.noteFailure(now: got.addingTimeInterval(61))
    #expect(feed.quotes.isEmpty)
    #expect(feed.lastUpdate == nil)
  }

  @Test("连着失败但屏上那份还新鲜，就先留着")
  func freshQuotesSurviveAShortOutage() async {
    let feed = feed([ticker("BTCUSDT", pct: 1.5)])
    feed.setVisible(true)
    await settle(feed)
    feed.setVisible(false)
    let got = feed.lastUpdate!
    for i in 1...5 { feed.noteFailure(now: got.addingTimeInterval(Double(i))) }
    #expect(feed.quotes["BTC"]?.pct == 1.5)
  }

  @Test("取到一趟就把失败记账清零")
  func successResetsTheCounter() async {
    let feed = feed([ticker("BTCUSDT", pct: 1.5)])
    feed.setVisible(true)
    await settle(feed)
    feed.setVisible(false)
    let got = feed.lastUpdate!
    feed.noteFailure(now: got.addingTimeInterval(1))
    feed.noteFailure(now: got.addingTimeInterval(2))
    feed.noteSuccess()
    // 记账清零之后又失败一趟：离「连着三趟」还差两趟，屏上那份留着。
    feed.noteFailure(now: got.addingTimeInterval(120))
    #expect(feed.quotes["BTC"]?.pct == 1.5)
  }

  @Test("一趟都没取到过就直接是空的")
  func neverLoadedDropsImmediately() {
    let feed = SectorFeed()
    for _ in 1...SectorFeed.failuresBeforeDropping { feed.noteFailure() }
    #expect(feed.quotes.isEmpty)
  }

  @Test("丢弃规则本身")
  func dropRule() {
    #expect(!SectorFeed.shouldDrop(failures: 2, age: 999))
    #expect(!SectorFeed.shouldDrop(failures: 3, age: 10))
    #expect(SectorFeed.shouldDrop(failures: 3, age: SectorFeed.dropAfterSeconds))
    #expect(SectorFeed.shouldDrop(failures: 3, age: nil))
  }

  // ---------------------------------------------------------------- 空态的判据

  @Test("第一趟还没回来时不算空态")
  func loadingIsNotEmptiness() async {
    let feed = SectorFeed()
    feed.fetchTickers = { _ in [ticker("BTCUSDT", pct: 1)] }
    // 一趟都还没问过：屏上没有板块，但也不是「暂无行情」——那句会在首屏闪一下。
    #expect(feed.quotes.isEmpty)
    #expect(!feed.showsEmptyState)

    feed.setVisible(true)
    await settle(feed)
    feed.setVisible(false)
    #expect(!feed.showsEmptyState, "有板块了自然不是空态")
  }

  @Test("问过了却什么都没有，才是空态")
  func emptinessNeedsAnAttempt() async {
    let feed = SectorFeed()
    feed.fetchTickers = { _ in throw URLError(.timedOut) }
    feed.setVisible(true)
    for _ in 0..<50 where !feed.showsEmptyState { await Task.yield() }
    feed.setVisible(false)
    #expect(feed.showsEmptyState)

    // 换线路等于换了一家交易所：之前问过什么都不作数，回到「还没问过」。
    feed.configure(endpoints: .default, policy: .gateway)
    #expect(feed.quotes.isEmpty)
    #expect(!feed.showsEmptyState)
  }

  @Test("空态这条规则本身")
  func emptyStateRule() {
    #expect(!SectorFeed.showsEmptyState(hasQuotes: false, attempted: false))
    #expect(SectorFeed.showsEmptyState(hasQuotes: false, attempted: true))
    #expect(!SectorFeed.showsEmptyState(hasQuotes: true, attempted: true))
    #expect(!SectorFeed.showsEmptyState(hasQuotes: true, attempted: false))
  }

  @Test("连着失败清掉屏上那份之后，空态要立起来")
  func droppingStaleQuotesLeavesTheEmptyState() async {
    let feed = feed([ticker("BTCUSDT", pct: 1.5)])
    feed.setVisible(true)
    await settle(feed)
    feed.setVisible(false)
    let got = feed.lastUpdate!
    for i in 1...SectorFeed.failuresBeforeDropping {
      feed.noteFailure(now: got.addingTimeInterval(Double(i) * 61))
    }
    #expect(feed.quotes.isEmpty)
    #expect(feed.showsEmptyState)
  }

  // ---------------------------------------------------------------- 重试

  @Test("重试先清线路冷却，再发第一趟请求")
  func retryClearsCooldownsBeforeFetching() async {
    let calls = Calls()
    let feed = SectorFeed()
    feed.resetCooldowns = { _ in calls.note("reset") }
    feed.fetchTickers = { _ in
      calls.note("fetch")
      throw URLError(.timedOut)
    }
    feed.setVisible(true)
    for _ in 0..<50 where calls.all.isEmpty { await Task.yield() }
    #expect(calls.all == ["fetch"], "进页那一趟不清冷却")

    feed.retry()
    for _ in 0..<50 where calls.all.count < 3 { await Task.yield() }
    feed.setVisible(false)
    // 顺序是确定的：清冷却排在重试那一趟请求前面。不清就发出去的话，
    // 这一趟只会被上一轮失败留下的冷却挡回来，用户按了等于没按。
    #expect(calls.all.prefix(3) == ["fetch", "reset", "fetch"])
  }

  @Test("空态上点一下就再取一趟")
  func retryRefetches() async {
    let feed = SectorFeed()
    feed.fetchTickers = { _ in throw URLError(.timedOut) }
    feed.setVisible(true)
    await settle(feed)
    #expect(feed.quotes.isEmpty)

    // 「点此重试」：不等退避，立刻重开一轮，这一趟通了。
    feed.fetchTickers = { _ in [ticker("ETHUSDT", pct: -2)] }
    feed.retry()
    await settle(feed)
    #expect(feed.quotes["ETH"]?.pct == -2)
    feed.setVisible(false)
  }

  // ---------------------------------------------------------------- B-07 的料

  @Test("品种表给的小数位按 base 查得到")
  func decimalsComeFromTheCatalog() {
    let feed = SectorFeed()
    feed.setCatalog([
      SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1),
      SymbolInfo(symbol: "SNDKUSDT", base: "SNDK", pricePrecision: 5, tickSize: 0.01),
      SymbolInfo(symbol: "PEPEUSDT", base: "PEPE", pricePrecision: 8, tickSize: 0.00000001),
    ])
    #expect(feed.priceDecimals(forBase: "BTC") == 1)
    #expect(feed.priceDecimals(forBase: "SNDK") == 2)
    #expect(feed.priceDecimals(forBase: "pepe") == 8)
    #expect(feed.priceDecimals(forBase: "NOPE") == nil)
  }

  // ---------------------------------------------------------------- 复核项 1：缺成交额

  @Test("成交额拿不到就是没有，不编成 0")
  func missingVolumeStaysMissing() async {
    let feed = feed([ticker("BTCUSDT", pct: 1.5, volume: .nan),
                     ticker("ETHUSDT", pct: -2, volume: .infinity),
                     ticker("SOLUSDT", pct: 3, volume: 4_200)])
    feed.setVisible(true)
    await settle(feed)
    feed.setVisible(false)
    // 三条行情都在（成交额缺不影响这个品种上不上场），只是缺的那两条还是非数。
    #expect(feed.quotes.count == 3)
    #expect(feed.quotes["BTC"]?.quoteVolume.isFinite == false)
    #expect(feed.quotes["BTC"]?.quoteVolume != 0, "编成 0 会冒充一个真实的零成交")
    #expect(feed.quotes["ETH"]?.quoteVolume.isFinite == false)
    #expect(feed.quotes["SOL"]?.quoteVolume == 4_200)

    // 一路带到列表上：那条「—」分支得真的走得到。
    let rows = SectorSymbolRow.build(members: ["BTC", "SOL"], quotes: feed.quotes,
                                     symbolForBase: { $0 + "USDT" }, sort: .volume)
    #expect(rows.map(\.base) == ["SOL", "BTC"])
    #expect(rows[0].volumeText == "4.20K")
    #expect(rows[1].volumeText == "—")
  }

  @Test("同一个 base 两张合约，有成交额的那张一定顶掉没有的")
  func realVolumeBeatsAMissingOne() async {
    // USDT 那张先到且没有成交额；同一档的 USDC 那张有——不许「谁先到算谁」。
    let feed = feed([ticker("BTCUSDT", pct: 1, volume: .nan, last: 10),
                     ticker("BTCUSDC", pct: 2, volume: 5_000, last: 11)])
    feed.setCatalog([
      SymbolInfo(symbol: "BTCUSDT", base: "BTC", quote: "USDT", pricePrecision: 2, tickSize: 0.01),
      SymbolInfo(symbol: "BTCUSDC", base: "BTC", quote: "USDT", pricePrecision: 2, tickSize: 0.01),
    ])
    feed.setVisible(true)
    await settle(feed)
    feed.setVisible(false)
    #expect(feed.quotes["BTC"]?.quoteVolume == 5_000)
    #expect(feed.quotes["BTC"]?.pct == 2)
  }

  /// 轮询是异步的，让它跑完一趟。`SectorFeed` 的循环第一件事就是取数，
  /// 假的取数不做 IO，让出几次执行权就到了。
  // ------------------------------------------------------------ 落盘恢复（Lane D3）

  @Test("冷启动第一次 configure 就把盘上那份读回来，但不算「问过了」")
  func firstConfigureRestoresCache() async {
    let feed = SectorFeed()
    let saved = Calls()
    feed.cache = .init(load: { partition in partition == nil ? [ticker("BTCUSDT", pct: 2.5)] : [] },
                       save: { partition, _ in saved.note(partition ?? "root") })
    let got = Calls()
    feed.onTickers = { tickers, upstream in got.note("\(upstream):\(tickers.count)") }
    // 和默认线路一样也要读：从前这一下直接 return，盘上那份没人读。
    feed.configure(endpoints: .default, policy: .direct)
    for _ in 0..<200 where feed.quotes.isEmpty { await Task.yield(); try? await Task.sleep(for: .milliseconds(5)) }
    #expect(feed.quotes["BTC"]?.pct == 2.5)
    #expect(got.all == ["binance:1"])
    #expect(!feed.showsEmptyState)
    // 年龄按交易所时钟算：寿命判定照样能把这份旧的清掉。
    #expect(feed.lastUpdate == Date(timeIntervalSince1970: 1_700_000_000))
    feed.noteFailure(); feed.noteFailure(); feed.noteFailure()
    #expect(feed.quotes.isEmpty)
    #expect(saved.all.isEmpty, "只读不写：恢复出来的那份不必再写回去")
  }

  @Test("已经取到新的，晚到的旧盘作废；换了源，上一家的盘也作废")
  func restoredCacheNeverOverridesFreshOrOtherSource() async {
    let feed = feed([ticker("BTCUSDT", pct: 1.5)])
    feed.setVisible(true)
    await settle(feed)
    feed.setVisible(false)
    feed.applyRestored([ticker("BTCUSDT", pct: 9)], upstream: feed.upstream, generation: 0)
    #expect(feed.quotes["BTC"]?.pct == 1.5)

    let other = SectorFeed()
    other.applyRestored([ticker("BTCUSDT", pct: 9)], upstream: "okx", generation: 0)
    #expect(other.quotes.isEmpty)
  }

  @Test("取回来就整份落一次盘，之后按节流写，不趟趟写")
  func pullSavesThrottled() async {
    let feed = feed([ticker("BTCUSDT", pct: 1.5), ticker("ETHUSDT", pct: -1)])
    let saved = Calls()
    feed.cache = .init(load: { _ in [] }, save: { partition, tickers in saved.note("\(partition ?? "root"):\(tickers.count)") })
    feed.setVisible(true)
    await settle(feed)
    feed.setVisible(false)
    for _ in 0..<200 where saved.all.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
    #expect(saved.all == ["root:2"])
  }

  private func settle(_ feed: SectorFeed) async {
    for _ in 0..<50 {
      await Task.yield()
      if feed.lastUpdate != nil { return }
    }
  }
}
