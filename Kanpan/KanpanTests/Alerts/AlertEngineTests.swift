import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 前台的到价判定：一口一口的价折成 1 分钟桶，再交给 `AlertEvaluator` 判。
///
/// 这一摞用例量的是**折桶**和**接线**那一半（判定规则本身在
/// `KanpanCore/Tests/.../AlertTests.swift` 里量过了）：
/// 桶什么时候换、换的时候谁先判、`previousClose` 什么时候不敢用、
/// 断过一次之后链子怎么断、以及响完之后再来价会不会响第二次。
///
/// 时间一律给死（`observe` 收交易所时刻），不看本机的钟。
@Suite("提醒前台判定")
@MainActor
struct AlertEngineTests {
  /// 一个能被 60_000 整除的整分钟，省得桶的开盘时刻要在脑子里算。
  private let m0: Int64 = 1_758_000_000_000
  private func minute(_ n: Int64) -> Int64 { m0 + n * 60_000 }

  private func fresh() -> AlertStore {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("alerts-\(UUID().uuidString).json")
    return AlertStore(store: AlertFileStore(url: url))
  }

  private func hline(_ id: String, p: Double) -> Drawing {
    Drawing(id: id, kind: .hline, points: [DrawPoint(t: Double(m0), p: p)])
  }

  /// 装好一条挂在 `symbol` 上的水平线提醒，`armedAt` 默认就是 `m0`。
  @discardableResult
  private func arm(_ store: AlertStore, symbol: String = "BTCUSDT", price: Double = 100,
                   condition: Alert.Condition = .touch, armedAt: Int64? = nil,
                   id: String = "d1") -> Alert {
    let alert = store.add(drawing: hline(id, p: price), symbol: symbol,
                          now: Double(armedAt ?? m0))!
    if condition != .touch { store.setCondition(condition, id: alert.id) }
    return store.alert(id: alert.id)!
  }

  // ---------------------------------------------------------------- 触碰

  @Test("盘中碰到就响，记的是现价不是线价")
  func touchFiresOnTheLiveBucket() {
    let store = fresh()
    let alert = arm(store, price: 100)
    let engine = AlertEngine()
    engine.attach(store)

    engine.observe(symbol: "BTCUSDT", price: 99, timeMs: minute(0) + 1_000)
    #expect(store.alert(id: alert.id)?.status == .active)

    engine.observe(symbol: "BTCUSDT", price: 100.5, timeMs: minute(0) + 2_000)
    let after = store.alert(id: alert.id)
    #expect(after?.status == .fired)
    // 线价是 100，但通知正文那句「现价 X」说的是手上这一口。和服务端
    // `fire(…, candle.close, …)` 一致。
    #expect(after?.firedPrice == 100.5)
    #expect((after?.firedAt ?? 0) > 0)
  }

  @Test("没盯的品种一口价都不看")
  func unwatchedSymbolsAreIgnored() {
    let store = fresh()
    let alert = arm(store, symbol: "BTCUSDT", price: 100)
    let engine = AlertEngine()
    engine.attach(store)
    engine.observe(symbol: "ETHUSDT", price: 100, timeMs: minute(0) + 1_000)
    #expect(engine.bucketState("ETHUSDT") == nil)
    #expect(store.alert(id: alert.id)?.status == .active)
  }

  @Test("代号大小写不影响对上号")
  func symbolMatchingIsCaseInsensitive() {
    let store = fresh()
    let alert = arm(store, symbol: "ethusdt", price: 100)
    let engine = AlertEngine()
    engine.attach(store)
    #expect(engine.watched == ["binance/usd_m/ETHUSDT"])
    engine.observe(symbol: "EthUsdt", price: 100, timeMs: minute(0) + 1_000)
    #expect(store.alert(id: alert.id)?.status == .fired)
  }

  @Test("报价簿那一批也能喂进来")
  func tickerBatchFeedsTheSameJudgement() {
    let store = fresh()
    let alert = arm(store, price: 100)
    let engine = AlertEngine()
    engine.attach(store)
    let ticker = Ticker(symbol: "BTCUSDT", last: 100, changePercent: 0, high: 0, low: 0,
                        quoteVolume: 0, timeMs: minute(0) + 1_000)
    let other = Ticker(symbol: "SOLUSDT", last: 100, changePercent: 0, high: 0, low: 0,
                       quoteVolume: 0, timeMs: minute(0) + 1_000)
    engine.observe([other, ticker])
    #expect(store.alert(id: alert.id)?.status == .fired)
  }

  // ---------------------------------------------------------------- 收盘穿过

  @Test("收盘穿过：盘中不判，第一根也不判，第二根收了才响")
  func closeNeedsAClosedBarAndAPreviousClose() {
    let store = fresh()
    let alert = arm(store, price: 100, condition: .close)
    let engine = AlertEngine()
    engine.attach(store)

    // 第一根：桶刚开，没有「上一根的收盘」。
    engine.observe(symbol: "BTCUSDT", price: 99, timeMs: minute(0) + 1_000)
    #expect(engine.bucketState("BTCUSDT")?.previousClose == nil)
    #expect(store.alert(id: alert.id)?.status == .active)

    // 换桶 ⇒ 第一根收了，但它的 previousClose 是 nil，不判。第二根开着，盘中不判。
    engine.observe(symbol: "BTCUSDT", price: 101, timeMs: minute(1) + 1_000)
    #expect(store.alert(id: alert.id)?.status == .active)
    #expect(engine.bucketState("BTCUSDT")?.previousClose == 99)

    // 再换桶 ⇒ 第二根收了：99 → 101 穿过 100。
    engine.observe(symbol: "BTCUSDT", price: 102, timeMs: minute(2) + 1_000)
    let after = store.alert(id: alert.id)
    #expect(after?.status == .fired)
    // 记的是**收了的那一根**的收盘价，不是刚到的这一口。
    #expect(after?.firedPrice == 101)
  }

  @Test("收盘没穿过就不响：影线扫到了也不算")
  func closeIgnoresWicks() {
    let store = fresh()
    let alert = arm(store, price: 100, condition: .close)
    let engine = AlertEngine()
    engine.attach(store)
    engine.observe(symbol: "BTCUSDT", price: 98, timeMs: minute(0) + 1_000)
    // 第二根盘中一度冲到 105，收回 99：`.touch` 会响，`.close` 不该响。
    engine.observe(symbol: "BTCUSDT", price: 105, timeMs: minute(1) + 1_000)
    engine.observe(symbol: "BTCUSDT", price: 99, timeMs: minute(1) + 30_000)
    engine.observe(symbol: "BTCUSDT", price: 99, timeMs: minute(2) + 1_000)
    #expect(store.alert(id: alert.id)?.status == .active)
  }

  @Test("中间断得太久就不敢拿那口价当上一根收盘")
  func staleGapDropsPreviousClose() {
    let store = fresh()
    arm(store, price: 100, condition: .close)
    let engine = AlertEngine()
    engine.attach(store)

    engine.observe(symbol: "BTCUSDT", price: 99, timeMs: minute(0) + 1_000)
    // 正好隔 5 个桶：还认。
    engine.observe(symbol: "BTCUSDT", price: 99.5, timeMs: minute(5) + 1_000)
    #expect(engine.bucketState("BTCUSDT")?.previousClose == 99)

    // 再隔 6 个桶：这条流多半是断过，previousClose 清掉。
    engine.observe(symbol: "BTCUSDT", price: 101, timeMs: minute(11) + 1_000)
    #expect(engine.bucketState("BTCUSDT")?.previousClose == nil)
  }

  // ---------------------------------------------------------------- 上膛时刻

  @Test("刚挪好的线不会被它开盘那一分钟当场判成已触发")
  func armedAtSuppressesTheBucketItWasArmedIn() {
    let store = fresh()
    // 在第 0 分钟的正中间上膛。
    let alert = arm(store, price: 100, armedAt: minute(0) + 30_000)
    let engine = AlertEngine()
    engine.attach(store)

    // 这一口落在第 0 分钟那个桶里，桶的开盘时刻比 armedAt 早 ⇒ 不判。
    engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(0) + 40_000)
    #expect(store.alert(id: alert.id)?.status == .active)

    // 下一个桶的开盘时刻已经在 armedAt 之后。
    engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(1) + 1_000)
    #expect(store.alert(id: alert.id)?.status == .fired)
  }

  // ---------------------------------------------------------------- 桶本身

  @Test("比手上这桶还早的一口价一概不要")
  func outOfOrderTicksAreDropped() {
    let store = fresh()
    let alert = arm(store, price: 100)
    let engine = AlertEngine()
    engine.attach(store)

    engine.observe(symbol: "BTCUSDT", price: 105, timeMs: minute(2) + 1_000)
    // 迟到的那一口如果被并进来，[95, 105] 就会夹住 100，响一条假的。
    engine.observe(symbol: "BTCUSDT", price: 95, timeMs: minute(1) + 1_000)
    #expect(store.alert(id: alert.id)?.status == .active)
    let bucket = engine.bucketState("BTCUSDT")
    #expect(bucket?.openTime == minute(2))
    #expect(bucket?.high == 105)
    #expect(bucket?.low == 105)
  }

  @Test("同一桶里高低会长开")
  func bucketWidens() {
    let store = fresh()
    arm(store, price: 1_000) // 够远，不会响
    let engine = AlertEngine()
    engine.attach(store)
    engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(0) + 1_000)
    engine.observe(symbol: "BTCUSDT", price: 108, timeMs: minute(0) + 2_000)
    engine.observe(symbol: "BTCUSDT", price: 95, timeMs: minute(0) + 3_000)
    engine.observe(symbol: "BTCUSDT", price: 101, timeMs: minute(0) + 4_000)
    let bucket = engine.bucketState("BTCUSDT")
    #expect(bucket?.openTime == minute(0))
    #expect(bucket?.high == 108)
    #expect(bucket?.low == 95)
    #expect(bucket?.close == 101)
  }

  @Test("不是数的价、零价、负价都挡在外面")
  func junkPricesAreRefused() {
    let store = fresh()
    arm(store, price: 100)
    let engine = AlertEngine()
    engine.attach(store)
    engine.observe(symbol: "BTCUSDT", price: .nan, timeMs: minute(0) + 1_000)
    engine.observe(symbol: "BTCUSDT", price: 0, timeMs: minute(0) + 1_000)
    engine.observe(symbol: "BTCUSDT", price: -3, timeMs: minute(0) + 1_000)
    #expect(engine.bucketState("BTCUSDT") == nil)
  }

  // ---------------------------------------------------------------- 前后台

  @Test("切后台把桶丢掉：回来那一下不拿断了的链子算穿越")
  func leavingForegroundClearsBuckets() {
    let store = fresh()
    let alert = arm(store, price: 100)
    let engine = AlertEngine()
    engine.attach(store)

    engine.observe(symbol: "BTCUSDT", price: 99, timeMs: minute(0) + 1_000)
    engine.setForeground(false)
    // 后台里来的价一口都不看。
    engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(0) + 2_000)
    #expect(store.alert(id: alert.id)?.status == .active)
    #expect(engine.bucketState("BTCUSDT") == nil)

    engine.setForeground(true)
    // 回来重开一桶：只有这一口，99 那一口不在里面了，夹不住 100。
    engine.observe(symbol: "BTCUSDT", price: 100.5, timeMs: minute(0) + 3_000)
    #expect(store.alert(id: alert.id)?.status == .active)
    #expect(engine.bucketState("BTCUSDT")?.previousClose == nil)
    #expect(engine.bucketState("BTCUSDT")?.low == 100.5)
  }

  // ---------------------------------------------------------------- 只响一次

  @Test("响完再来价不会响第二次，触发记录也不会被改写")
  func firedAlertsDoNotFireAgain() {
    let store = fresh()
    let alert = arm(store, price: 100)
    let engine = AlertEngine()
    engine.attach(store)

    engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(0) + 1_000)
    let first = store.alert(id: alert.id)
    #expect(first?.status == .fired)
    #expect(first?.firedPrice == 100)

    // 后面这几口照样撞在线上（桶里还在、下一分钟又撞一次），一次都不该再记。
    engine.observe(symbol: "BTCUSDT", price: 100.5, timeMs: minute(0) + 2_000)
    engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(1) + 1_000)
    let again = store.alert(id: alert.id)
    #expect(again?.firedPrice == first?.firedPrice)
    #expect(again?.firedAt == first?.firedAt)
  }

  @Test("价格提醒改了价就重新布防，新价照样能响")
  func editedPriceAlertsCanFireAgain() {
    let store = fresh()
    let alert = store.addPrice(symbol: "BTCUSDT", target: 100, current: 90, label: "100",
                               now: Double(minute(0)))!
    let engine = AlertEngine()
    engine.attach(store)
    engine.observe(symbol: "BTCUSDT", price: 99, timeMs: minute(1) + 1_000)
    engine.observe(symbol: "BTCUSDT", price: 101, timeMs: minute(1) + 2_000)
    #expect(store.alert(id: alert.id)?.status == .fired)

    store.update(id: alert.id, target: 120, current: 101, label: "120", condition: .touch,
                 webhook: nil, webhookText: nil, note: nil, now: Double(minute(2)))
    #expect(store.alert(id: alert.id)?.status == .active)
    engine.observe(symbol: "BTCUSDT", price: 119, timeMs: minute(3) + 1_000)
    engine.observe(symbol: "BTCUSDT", price: 121, timeMs: minute(3) + 2_000)
    #expect(store.alert(id: alert.id)?.status == .fired)
  }

  // ---------------------------------------------------------------- 盯谁

  @Test("装上那一刻就把要盯的品种报给报价簿")
  func attachPublishesTheWatchlist() {
    let store = fresh()
    arm(store, symbol: "BTCUSDT", price: 100, id: "d1")
    arm(store, symbol: "ethusdt", price: 200, id: "d2")
    let engine = AlertEngine()
    var reported: [Set<String>] = []
    engine.onWatchlist = { reported.append($0) }
    engine.attach(store)
    #expect(engine.watched == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(reported == [["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"]])

    // 换号那一拍报价簿会把钉进去的那批清空，所以要能无条件再交一次。
    engine.republishWatchlist()
    #expect(reported == [["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"], ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"]])
  }

  @Test("已触发、已暂停、没线的那些不占订阅名额")
  func onlyLiveDrawingAlertsAreWatched() {
    let store = fresh()
    let live = Alert(symbol: "BTCUSDT", drawingID: "d1",
                     lines: [AlertLine(points: [DrawPoint(t: Double(m0), p: 100)],
                                       extendLeft: true, extendRight: true)],
                     armedAt: Double(m0), title: "在等", created: Double(m0))
    var fired = live; fired.id = "a2"; fired.symbol = "ETHUSDT"; fired.status = .fired
    var paused = live; paused.id = "a3"; paused.symbol = "SOLUSDT"; paused.status = .paused
    var bare = live; bare.id = "a4"; bare.symbol = "XRPUSDT"; bare.lines = []
    var due = live; due.id = "a5"; due.symbol = "DOGEUSDT"; due.kind = .reviewDue
    store.publishSynced(AlertArchive(alerts: [live, fired, paused, bare, due]))

    let engine = AlertEngine()
    engine.attach(store)
    #expect(engine.watched == ["binance/usd_m/BTCUSDT"])

    // 暂停的那条即使价撞上来也不响（`AlertEvaluator.hit` 第一道闸）。
    engine.observe(symbol: "SOLUSDT", price: 100, timeMs: minute(0) + 1_000)
    #expect(store.alert(id: "a3")?.status == .paused)
  }

  @Test("一个品种上两条，只响撞上的那条")
  func onlyTheHitAlertFires() {
    let store = fresh()
    let near = arm(store, price: 100, id: "d1")
    let far = arm(store, price: 500, id: "d2")
    let engine = AlertEngine()
    engine.attach(store)
    engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(0) + 1_000)
    #expect(store.alert(id: near.id)?.status == .fired)
    #expect(store.alert(id: far.id)?.status == .active)
  }

  @Test("响一条就走一次落盘 + 记账那一个出口")
  func firingGoesThroughTheStoreWriteExit() {
    let store = fresh()
    let alert = arm(store, price: 100)
    var booked: [Int] = []
    store.onChange = { booked.append($0.alerts.filter { $0.status == .fired }.count) }
    let engine = AlertEngine()
    engine.attach(store)
    engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(0) + 1_000)
    // `onChange` 是账号桥记账 + 同步那一条线；走了它才说明这一版会被推上去。
    #expect(booked == [1])
    #expect(store.alert(id: alert.id)?.status == .fired)
  }
}
