import Foundation
import KanpanCore
import Testing
@testable import KanpanAlerts

/// P3.1 补进提醒系统的三样：裸价格提醒、复盘到点、自选五分钟波动。
///
/// 判定规则本身在 `KanpanCore`（`AlertTests` / `WatchMoveTests`）里量过；这里量的是
/// 接线——建得出来、前台判得到、跟着记录对账、跟着开关与自选走。
@Suite("P3.1 提醒三种")
@MainActor
struct P31AlertKindsTests {
  private let m0: Int64 = 1_758_000_000_000
  private func minute(_ n: Int64) -> Int64 { m0 + n * 60_000 }

  private func fresh() -> AlertStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("alerts-\(UUID().uuidString).json")
    return AlertStore(store: AlertFileStore(url: url))
  }

  // ---------------------------------------------------------------- 价格提醒

  @Test("新建价格提醒：方向按现价定，同一个价不建第二条")
  func addingAPriceAlert() throws {
    let store = fresh()
    let up = try #require(store.addPrice(symbol: "BTCUSDT", target: 70_000, current: 65_000, label: "70,000", now: Double(m0)))
    #expect(up.kind == .price)
    #expect(up.title == "BTC 涨到 70,000")
    #expect(up.targetPrice == 70_000)
    #expect(up.drawingID == nil)
    let again = store.addPrice(symbol: "BTCUSDT", target: 70_000, current: 66_000, label: "70,000", now: Double(m0))
    #expect(again?.id == up.id)
    #expect(up.symbol == "binance/usd_m/BTCUSDT")
    for spelling in ["binance/usd_m/BTCUSDT", "BINANCE/USD_M/BTCUSDT"] {
      #expect(store.addPrice(symbol: spelling, target: 70_000, current: 66_000, label: "70,000")?.id == up.id,
              "\(spelling) 和裸代号是同一只")
    }
    let down = try #require(store.addPrice(symbol: "BTCUSDT", target: 60_000, current: 65_000, label: "60,000", now: Double(m0)))
    #expect(down.title == "BTC 跌到 60,000")
    #expect(store.all.count == 2)
    #expect(store.addPrice(symbol: "BTCUSDT", target: 0, current: 1, label: "0") == nil)
  }

  @Test("价格提醒前台照样判：挂上就盯这只，走到那个价就响")
  func aPriceAlertFiresInTheForeground() throws {
    let store = fresh()
    let alert = try #require(store.addPrice(symbol: "ETHUSDT", target: 3_000, current: 2_900, label: "3,000", now: Double(m0)))
    let engine = AlertEngine()
    engine.attach(store)
    #expect(engine.watched == ["binance/usd_m/ETHUSDT"], "盯的是完整品种 key，和报价簿同一口径")
    engine.observe(symbol: "ETHUSDT", price: 2_990, timeMs: minute(0) + 1_000)
    #expect(store.alert(id: alert.id)?.status == .active)
    engine.observe(symbol: "ETHUSDT", price: 3_001, timeMs: minute(0) + 2_000)
    #expect(store.alert(id: alert.id)?.status == .fired)
    #expect(store.alert(id: alert.id)?.firedPrice == 3_001)
  }

  // ---------------------------------------------------------------- 复盘到点

  private func item(_ id: String = "9F1E", due: Double, waiting: Bool = true, eligible: Bool = true,
                    symbol: String = "BTCUSDT") -> ReviewDueAlerts.Item {
    .init(id: id, symbol: symbol, dueAt: due, short: "BTC", waiting: waiting, eligible: eligible)
  }

  @Test("到点提醒：记录的品种不管写成裸代号、规范键还是大写规范键，对账都是同一只，不来回改")
  func dueAlertSymbolSpellingsAreOneKey() throws {
    let now = Double(m0)
    let due = now + 3_600_000
    let created = try #require(ReviewDueAlerts.plan(items: [item(due: due)], existing: [], now: now).upsert.first)
    #expect(created.symbol == "binance/usd_m/BTCUSDT")
    for spelling in ["BTCUSDT", "binance/usd_m/BTCUSDT", "BINANCE/USD_M/BTCUSDT"] {
      let plan = ReviewDueAlerts.plan(items: [item(due: due, symbol: spelling)], existing: [created], now: now)
      #expect(plan.isEmpty, "\(spelling) 不该让同一条提醒被改写")
    }
  }

  @Test("记一笔等答案的：建一条到点提醒，id 由记录定死")
  func aWaitingRecordBecomesADueAlert() throws {
    let now = Double(m0)
    let plan = ReviewDueAlerts.plan(items: [item(due: now + 3_600_000)], existing: [], now: now)
    let alert = try #require(plan.upsert.first)
    #expect(alert.id == "r9F1E")
    #expect(alert.kind == .reviewDue)
    #expect(alert.lines.isEmpty)
    #expect(alert.dueAt == now + 3_600_000)
    #expect(alert.reviewID == "9F1E")
    #expect(alert.title == "BTC 到点了")
    let store = fresh()
    store.settleReviewDue(plan)
    #expect(store.alert(id: "r9F1E") != nil)
    // 同一份记录再对一遍：没有要做的账。
    #expect(ReviewDueAlerts.plan(items: [item(due: now + 3_600_000)], existing: store.all, now: now).isEmpty)
  }

  @Test("判完、作废、别的市场的记录不建；已经建了的跟着删")
  func settledRecordsDropTheirAlert() {
    let now = Double(m0)
    #expect(ReviewDueAlerts.plan(items: [item(due: now + 1, waiting: false)], existing: [], now: now).isEmpty)
    #expect(ReviewDueAlerts.plan(items: [item(due: now + 1, eligible: false)], existing: [], now: now).isEmpty)
    let store = fresh()
    store.settleReviewDue(ReviewDueAlerts.plan(items: [item(due: now + 60_000)], existing: [], now: now))
    let plan = ReviewDueAlerts.plan(items: [item(due: now + 60_000, waiting: false)], existing: store.all, now: now)
    #expect(plan.remove == ["r9F1E"])
    store.settleReviewDue(plan)
    #expect(store.all.isEmpty)
  }

  @Test("到点了前台判成已触发、不带价；响过一天自动清掉")
  func dueAlertsFireByTimeAndAreCleanedUp() throws {
    let now = Double(m0)
    let store = fresh()
    store.settleReviewDue(ReviewDueAlerts.plan(items: [item(due: now + 60_000)], existing: [], now: now))
    let engine = AlertEngine()
    engine.attach(store)
    #expect(engine.watched.isEmpty, "到点提醒不看价，不去订阅行情")
    engine.settleDue(now: now + 30_000)
    #expect(store.alert(id: "r9F1E")?.status == .active)
    engine.settleDue(now: now + 60_000)
    let fired = try #require(store.alert(id: "r9F1E"))
    #expect(fired.status == .fired)
    #expect(fired.firedPrice == nil)
    // 响过不到一天：还在总表「已触发」里。
    #expect(ReviewDueAlerts.plan(items: [item(due: now + 60_000)], existing: store.all, now: now + 3_600_000).isEmpty)
    // 过了一天：清掉，而且不再补建。
    let later = now + 60_000 + ReviewDueAlerts.keepAfterDue + 1
    let plan = ReviewDueAlerts.plan(items: [item(due: now + 60_000)], existing: store.all, now: later)
    #expect(plan.remove == ["r9F1E"])
    store.settleReviewDue(plan)
    #expect(ReviewDueAlerts.plan(items: [item(due: now + 60_000)], existing: store.all, now: later).isEmpty)
  }

  @Test("到期被改到以后：按新时刻重新上膛")
  func movingTheDueTimeRearms() throws {
    let now = Double(m0)
    let store = fresh()
    store.settleReviewDue(ReviewDueAlerts.plan(items: [item(due: now)], existing: [], now: now))
    store.markFired(id: "r9F1E", at: now, price: nil)
    let plan = ReviewDueAlerts.plan(items: [item(due: now + 7_200_000)], existing: store.all, now: now + 1_000)
    let next = try #require(plan.upsert.first)
    #expect(next.status == .active)
    #expect(next.firedAt == nil)
    #expect(next.dueAt == now + 7_200_000)
  }

  @Test("复盘列表一时是空的（换号、刚启动）不删；记录不见了一天以后才清")
  func aTransientlyEmptyListDoesNotChurn() {
    let now = Double(m0)
    let store = fresh()
    store.settleReviewDue(ReviewDueAlerts.plan(items: [item(due: now + 60_000)], existing: [], now: now))
    #expect(ReviewDueAlerts.plan(items: [], existing: store.all, now: now).isEmpty)
    let later = now + 60_000 + ReviewDueAlerts.keepAfterDue + 1
    #expect(ReviewDueAlerts.plan(items: [], existing: store.all, now: later).remove == ["r9F1E"])
  }

  @Test("前台不在就不判到点：那一段归服务端和本机那条日历通知")
  func dueIsNotJudgedInTheBackground() {
    let now = Double(m0)
    let store = fresh()
    store.settleReviewDue(ReviewDueAlerts.plan(items: [item(due: now)], existing: [], now: now - 1))
    let engine = AlertEngine()
    engine.attach(store)
    engine.setForeground(false)
    engine.settleDue(now: now + 1)
    #expect(store.alert(id: "r9F1E")?.status == .active)
  }

  // ---------------------------------------------------------------- 自选波动

  private func monitor(favorites: [String] = ["BTCUSDT"], threshold: Double = 1.5) -> (WatchMoveMonitor, Box) {
    let m = WatchMoveMonitor()
    let box = Box()
    m.onEvent = { box.events.append($0) }
    m.setFavorites(favorites)
    m.configure(enabled: true, threshold: threshold)
    return (m, box)
  }

  final class Box { var events: [WatchMove.Event] = [] }

  private func warm(_ m: WatchMoveMonitor, _ symbol: String = "BTCUSDT") {
    for n in Int64(0)..<5 { m.observe(symbol: symbol, price: 100, timeMs: minute(n) + 10_000) }
  }

  @Test("自选里的一只五分钟涨过幅度：响一次；跌过去也响")
  func aFavoriteMovingFires() {
    let (m, box) = monitor()
    warm(m)
    m.observe(symbol: "BTCUSDT", price: 101.6, timeMs: minute(5) + 1_000)
    #expect(box.events.map(\.direction) == [.up])
    m.observe(symbol: "BTCUSDT", price: 101.9, timeMs: minute(5) + 2_000)
    #expect(box.events.count == 1, "同窗口同方向只响一次")
    m.observe(symbol: "BTCUSDT", price: 98.2, timeMs: minute(5) + 3_000)
    #expect(box.events.map(\.direction) == [.up, .down])
  }

  @Test("五分钟前那一根缺着（那一分钟一口价都没有）不判：缺口不当零波动")
  func aGapIsNotJudged() {
    let (m, box) = monitor()
    m.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(0) + 10_000)
    // 第 1～6 分钟一口价都没有；第 7 分钟要比的是第 2 分钟那一根——缺着。
    m.observe(symbol: "BTCUSDT", price: 120, timeMs: minute(7) + 10_000)
    m.observe(symbol: "BTCUSDT", price: 121, timeMs: minute(7) + 20_000)
    #expect(box.events.isEmpty)
    // 缺口不把「回到阈值以内」记上：第 8 分钟比第 3 分钟，还是缺着，照样不响也不重置。
    m.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(8) + 10_000)
    #expect(box.events.isEmpty)
  }

  @Test("不在自选里的不盯；拿出自选之后不再响")
  func onlyFavoritesAreWatched() {
    let (m, box) = monitor(favorites: ["BTCUSDT"])
    warm(m, "ETHUSDT")
    m.observe(symbol: "ETHUSDT", price: 110, timeMs: minute(5) + 1_000)
    #expect(box.events.isEmpty)
    warm(m)
    m.setFavorites(["ETHUSDT"])
    m.observe(symbol: "BTCUSDT", price: 110, timeMs: minute(5) + 1_000)
    #expect(box.events.isEmpty)
  }

  @Test("自选存完整品种 key、行情喂裸代号：照样对得上，标题只念代号")
  func canonicalFavoritesMatchBareTickers() {
    let (m, box) = monitor(favorites: ["binance/usd_m/BTCUSDT"])
    warm(m)
    m.observe(symbol: "BTCUSDT", price: 101.6, timeMs: minute(5) + 1_000)
    #expect(box.events.map(\.direction) == [.up])
    #expect(WatchMove.title(for: box.events[0]).hasPrefix("BTC "))
    let (bare, bareBox) = monitor(favorites: ["BTCUSDT"])
    warm(bare, "binance/usd_m/BTCUSDT")
    bare.observe(symbol: "binance/usd_m/BTCUSDT", price: 98.2, timeMs: minute(5) + 1_000)
    #expect(bareBox.events.map(\.direction) == [.down])
  }

  @Test("自选、喂价用哪种写法都算同一只：裸代号 / 规范键 / 大写规范键")
  func symbolSpellingsMatch() {
    for favorite in ["BTCUSDT", "binance/usd_m/BTCUSDT", "BINANCE/USD_M/BTCUSDT"] {
      for fed in ["BTCUSDT", "binance/usd_m/BTCUSDT", "BINANCE/USD_M/BTCUSDT"] {
        let (m, box) = monitor(favorites: [favorite])
        #expect(m.favorites == ["binance/usd_m/BTCUSDT"])
        warm(m, fed)
        m.observe(symbol: fed, price: 101.6, timeMs: minute(5) + 1_000)
        #expect(box.events.map(\.symbol) == ["binance/usd_m/BTCUSDT"], "自选 \(favorite) / 喂价 \(fed)")
      }
    }
  }

  // `WatchMoveMonitor.injectTestMove` 是 UI 用例的注入口，只在 DEBUG 里有；Release 下这一条不编。
  #if DEBUG
  @Test("UI 用例的注入写裸代号，自选是规范键：照样响（以前两边对不上，一声不响）")
  func testInjectionMatchesCanonicalFavorites() {
    let (m, box) = monitor(favorites: ["binance/usd_m/BTCUSDT"])
    m.injectTestMove(symbol: "BTCUSDT")
    #expect(box.events.map(\.direction) == [.up])
  }
  #endif

  @Test("改自选时留下的那只闸还在：同窗口不再响")
  func changingFavoritesKeepsTheRemainingGate() {
    let (m, box) = monitor(favorites: ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    warm(m, "binance/usd_m/BTCUSDT")
    m.observe(symbol: "binance/usd_m/BTCUSDT", price: 101.6, timeMs: minute(5) + 1_000)
    #expect(box.events.count == 1)
    m.setFavorites(["binance/usd_m/BTCUSDT"])
    m.observe(symbol: "binance/usd_m/BTCUSDT", price: 101.8, timeMs: minute(5) + 2_000)
    #expect(box.events.count == 1, "拿掉 ETH 不能把 BTC 的闸一起清掉")
  }

  @Test("关掉开关就停；再打开从缺口重新开始")
  func switchingOffStops() {
    let (m, box) = monitor()
    warm(m)
    m.configure(enabled: false, threshold: 1.5)
    m.observe(symbol: "BTCUSDT", price: 110, timeMs: minute(5) + 1_000)
    #expect(box.events.isEmpty)
    m.configure(enabled: true, threshold: 1.5)
    m.observe(symbol: "BTCUSDT", price: 110, timeMs: minute(5) + 2_000)
    #expect(box.events.isEmpty, "关着那段的价不算数")
  }

  @Test("幅度按设置：3% 时 2% 不响")
  func thresholdFollowsTheSetting() {
    let (m, box) = monitor(threshold: 3)
    warm(m)
    m.observe(symbol: "BTCUSDT", price: 102, timeMs: minute(5) + 1_000)
    #expect(box.events.isEmpty)
    m.observe(symbol: "BTCUSDT", price: 103.1, timeMs: minute(5) + 2_000)
    #expect(box.events.count == 1)
  }

  @Test("切后台断过：回来不拿断口两侧的价比")
  func backgroundBreaksTheSeries() {
    let (m, box) = monitor()
    warm(m)
    m.setForeground(false)
    m.observe(symbol: "BTCUSDT", price: 110, timeMs: minute(5) + 1_000)
    m.setForeground(true)
    m.observe(symbol: "BTCUSDT", price: 110, timeMs: minute(5) + 2_000)
    #expect(box.events.isEmpty)
  }
}
