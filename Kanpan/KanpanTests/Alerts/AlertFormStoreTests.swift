import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 2026-09-25 从图上加提醒：新建带条件 / Webhook、编辑（改价重新布防）、
/// Webhook 只在本机判响时由本机发，以及 v2 创建页的记录行文字与排序。
/// v2 起表单不再交备注与推送内容（落账时两样都是 nil），存储层照旧认这两个字段。
@Suite("提醒 · 新建与编辑")
@MainActor
struct AlertFormStoreTests {
  private func fresh() -> AlertStore {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("alerts-form-\(UUID().uuidString).json")
    return AlertStore(store: AlertFileStore(url: url))
  }

  private func quote(_ price: Double? = 84_500) -> PriceAlertQuote {
    PriceAlertQuote(symbol: "binance/usd_m/BTCUSDT", price: price, decimals: 1)
  }

  @Test("新建时条件、Webhook、推送内容、备注都落账")
  func addCarriesTheNewFields() throws {
    let store = fresh()
    let alert = try #require(store.addPrice(
      symbol: "BTCUSDT", target: 84_662.2, current: 84_500, label: "84,662.2", condition: .close,
      webhook: "  https://example.com/hook ", webhookText: "{品种} {价格}", note: "前高", now: 10))
    #expect(alert.condition == .close)
    #expect(alert.webhook == "https://example.com/hook")
    #expect(alert.webhookText == "{品种} {价格}")
    #expect(alert.note == "前高")
    #expect(alert.once)
    #expect(alert.title == "BTC 涨到 84,662.2")
  }

  @Test("不合法的地址、出厂模板、空备注都不存")
  func junkIsDropped() throws {
    let store = fresh()
    let alert = try #require(store.addPrice(
      symbol: "BTCUSDT", target: 80_000, current: 84_500, label: "80,000.0",
      webhook: "example.com", webhookText: AlertMessage.defaultTemplate, note: "   "))
    #expect(alert.webhook == nil)
    #expect(alert.webhookText == nil)
    #expect(alert.note == nil)
    #expect(alert.title == "BTC 跌到 80,000.0")
  }

  @Test("编辑只改设置时布防不动")
  func editKeepsArmingWhenPriceIsTheSame() throws {
    let store = fresh()
    let alert = try #require(store.addPrice(symbol: "BTCUSDT", target: 90_000, current: 84_500,
                                            label: "90,000.0", now: 10))
    let edited = try #require(store.update(id: alert.id, target: 90_000, current: 84_600, label: "90,000.0",
                                           condition: .close, webhook: "https://a.b/c", webhookText: nil,
                                           note: "改了", now: 99))
    #expect(edited.armedAt == 10)
    #expect(edited.condition == .close)
    #expect(edited.webhook == "https://a.b/c")
    #expect(edited.note == "改了")
    #expect(store.all.count == 1)
  }

  @Test("编辑改了价：重挂线、重写标题、从现在重新布防")
  func editingThePriceRearms() throws {
    let store = fresh()
    let alert = try #require(store.addPrice(symbol: "BTCUSDT", target: 90_000, current: 84_500,
                                            label: "90,000.0", now: 10))
    _ = store.markFired(id: alert.id, at: 20, price: 90_001)
    let edited = try #require(store.update(id: alert.id, target: 80_000, current: 84_500, label: "80,000.0",
                                           condition: .touch, webhook: nil, webhookText: nil, note: nil, now: 30))
    #expect(edited.status == .active)
    #expect(edited.armedAt == 30)
    #expect(edited.firedAt == nil)
    #expect(edited.firedPrice == nil)
    #expect(edited.targetPrice == 80_000)
    #expect(edited.title == "BTC 跌到 80,000.0")
    #expect(edited.id == alert.id)
  }

  @Test("编辑只认价格提醒")
  func editRefusesLineAlerts() {
    let store = fresh()
    let line = store.add(drawing: Drawing(id: "d1", kind: .hline, points: [DrawPoint(t: 1_000, p: 100)]),
                         symbol: "BTCUSDT", now: 5)
    #expect(line != nil)
    #expect(store.update(id: line!.id, target: 120, current: 100, label: "120", condition: .touch,
                         webhook: nil, webhookText: nil, note: "x") == nil)
  }

  @Test("表单落账：新建与编辑走同一个口，备注与推送内容一律不写")
  func commitCreatesThenEdits() throws {
    let store = fresh()
    let draft = AlertDraft(quote: quote(), target: 84_662.2, condition: .touch,
                           webhook: "https://example.com/hook")
    let created = try #require(store.commit(draft))
    #expect(created.title == "BTC 涨到 84,662.2")
    #expect(created.note == nil)
    #expect(created.webhookText == nil)
    #expect(created.webhook == "https://example.com/hook")
    var next = draft
    next.target = 83_000
    next.webhook = nil
    let edited = try #require(store.commit(next, editing: created.id))
    #expect(edited.id == created.id)
    #expect(edited.title == "BTC 跌到 83,000.0")
    #expect(edited.webhook == nil)
    #expect(store.all.count == 1)
  }

  @Test("本机判响的才算本机发 Webhook；同步下来的已触发不算")
  func localFiresGateTheWebhook() throws {
    let store = fresh()
    let alert = try #require(store.addPrice(symbol: "BTCUSDT", target: 90_000, current: 84_500,
                                            label: "90,000.0", webhook: "https://a.b/c", now: 1))
    let fired = try #require(store.markFired(id: alert.id, at: 50, price: 90_001))
    #expect(store.firedLocally(fired))
    // 服务端判响、同步换下来的那种：firedAt 不是本机记的那一刻。
    var synced = fired
    synced.firedAt = 60
    #expect(!store.firedLocally(synced))
    // 没响过的更不算。
    #expect(!store.firedLocally(alert))
  }

  @Test("通知正文只写现价，不再接备注")
  func notificationBody() throws {
    var alert = KanpanCore.Alert.price(symbol: "BTCUSDT", target: 84_662.2, current: 84_500,
                                       label: "84,662.2", now: 1, note: "前高")
    #expect(AlertNotifications.body(for: alert, decimals: 1) == nil)
    alert.firedPrice = 84_670.5
    #expect(AlertNotifications.body(for: alert, decimals: 1) == "现价 84,670.5")
    alert.note = nil
    #expect(AlertNotifications.body(for: alert, decimals: 1) == "现价 84,670.5")
  }

  @Test("十字线药丸的字固定是「创建提醒」，不报价")
  func crosshairChipTitle() {
    #expect(CrosshairActionBar.title == "创建提醒")
  }

  @Test("Webhook 测试的提示：成功只说已发出")
  func webhookToast() {
    #expect(AlertWebhook.Outcome.status(200).toast == "已发出")
    #expect(AlertWebhook.Outcome.status(500).toast == "发送失败 · 500")
    #expect(AlertWebhook.Outcome.failed("超时").toast == "发送失败 · 超时")
  }

  @Test("记录行：创建页的标题不带品种名，总表带")
  func recordTitles() throws {
    let price = KanpanCore.Alert.price(symbol: "BTCUSDT", target: 79_916.2, current: 84_500,
                                       label: "79916.2", now: 1)
    #expect(AlertRecordText.title(price, withSymbol: false) == "跌到 79,916.2")
    #expect(AlertRecordText.title(price, withSymbol: true) == "BTC 跌到 79,916.2")
    let store = fresh()
    let line = try #require(store.add(drawing: Drawing(id: "d1", kind: .hline, points: [DrawPoint(t: 1_000, p: 100)]),
                                      symbol: "BTCUSDT", now: 5))
    #expect(AlertRecordText.title(line, withSymbol: true).hasPrefix("BTC · "))
    #expect(AlertRecordText.title(line, withSymbol: false).hasPrefix("触到你画的"))
  }

  @Test("记录行灰字：生效中写条件，已触发带时间与现价")
  func recordMeta() {
    var alert = KanpanCore.Alert.price(symbol: "BTCUSDT", target: 90_000, current: 84_500,
                                       label: "90,000.0", now: 1, condition: .close)
    #expect(AlertRecordText.meta(alert, zone: .fixed(0), decimals: 1, conditionInline: true) == "收盘穿过")
    alert.condition = .touch
    #expect(AlertRecordText.meta(alert, zone: .fixed(0), decimals: 1, conditionInline: true) == "价格达到")
    alert.status = .fired
    alert.firedAt = 1_758_732_240_000   // 2025-09-24 16:44 UTC
    alert.firedPrice = 84_670.5
    #expect(AlertRecordText.meta(alert, zone: .fixed(0), decimals: 1, conditionInline: true)
            == "已触发 · 9/24 16:44 · 现价 84,670.5")
  }

  @Test("创建页「当前提醒」只列这一只还没触发的，按新建倒序；已触发、复盘到点不列")
  func recordOrder() throws {
    let store = fresh()
    let a = try #require(store.addPrice(symbol: "BTCUSDT", target: 90_000, current: 84_500, label: "a", now: 1))
    let b = try #require(store.addPrice(symbol: "BTCUSDT", target: 91_000, current: 84_500, label: "b", now: 2))
    let c = try #require(store.addPrice(symbol: "BTCUSDT", target: 92_000, current: 84_500, label: "c", now: 3))
    let line = try #require(store.add(drawing: Drawing(id: "d1", kind: .hline, points: [DrawPoint(t: 1_000, p: 100)]),
                                      symbol: "BTCUSDT", now: 4))
    _ = try #require(store.addPrice(symbol: "ETHUSDT", target: 5_000, current: 4_000, label: "e", now: 5))
    _ = store.markFired(id: c.id, at: 10, price: 92_001)
    let ids = AlertRecordText.records(store.all, symbol: "binance/usd_m/BTCUSDT").map(\.id)
    #expect(ids == [line.id, b.id, a.id])
  }

  @Test("全部预警：价格、画线两段按品种分，复盘到点有才单列；已触发的不列")
  func sections() throws {
    let store = fresh()
    let btc1 = try #require(store.addPrice(symbol: "BTCUSDT", target: 90_000, current: 84_500, label: "a", now: 1))
    let eth = try #require(store.addPrice(symbol: "ETHUSDT", target: 5_000, current: 4_000, label: "e", now: 2))
    let btc2 = try #require(store.addPrice(symbol: "BTCUSDT", target: 91_000, current: 84_500, label: "b", now: 3))
    let fired = try #require(store.addPrice(symbol: "BTCUSDT", target: 92_000, current: 84_500, label: "c", now: 4))
    _ = store.markFired(id: fired.id, at: 10, price: 92_001)
    let line = try #require(store.add(drawing: Drawing(id: "d1", kind: .hline, points: [DrawPoint(t: 1_000, p: 100)]),
                                      symbol: "ETHUSDT", now: 5))
    var sections = AlertRecordText.sections(store.all)
    #expect(sections.map(\.kind) == [.price, .drawing])
    #expect(sections.map(\.title) == ["价格提醒 3", "画线提醒 1"])
    // 品种按各自最新那条倒序：BTC（3）在 ETH（2）前面；组里按新建倒序。
    #expect(sections[0].groups.map(\.symbol) == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(sections[0].groups[0].alerts.map(\.id) == [btc2.id, btc1.id])
    #expect(sections[0].groups[1].alerts.map(\.id) == [eth.id])
    #expect(sections[1].groups.map { $0.alerts.map(\.id) } == [[line.id]])

    var due = KanpanCore.Alert(id: "r1", kind: .reviewDue, symbol: "BTCUSDT", armedAt: 1, dueAt: 2,
                               title: "BTC 到点了", created: 1)
    due.status = .fired
    store.settleReviewDue(ReviewDueAlerts.Plan(upsert: [due], remove: []))
    sections = AlertRecordText.sections(store.all)
    #expect(sections.map(\.title) == ["价格提醒 3", "画线提醒 1", "复盘到点 1"])
    #expect(AlertRecordText.sections([]).isEmpty)
  }

  @Test("段头品种名：和品种卡同一个写法")
  func pairName() {
    #expect(AlertRecordText.pairName("binance/usd_m/BTCUSDT") == "BTC/USDT")
    #expect(AlertRecordText.pairName("coinbase/spot/BTC-USD") == "BTC/USD")
  }

  @Test("品种卡第二行：交易所 · 产品")
  func venueLine() {
    #expect(AlertRecordText.venueLine("binance/usd_m/BTCUSDT") == "币安 · USDT 永续")
    #expect(AlertRecordText.venueLine("coinbase/spot/BTC-USD") == "Coinbase · 现货")
    #expect(AlertRecordText.venueLine("BTCUSDT") == "币安 · USDT 永续")
  }
}
