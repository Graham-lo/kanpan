import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 2026-09-25 从图上加提醒：新建带条件 / Webhook / 备注、编辑（改价重新布防）、
/// 「最近用过」、以及 Webhook 只在本机判响时由本机发。
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

  @Test("表单落账：新建与编辑走同一个口")
  func commitCreatesThenEdits() throws {
    let store = fresh()
    let draft = AlertDraft(quote: quote(), target: 84_662.2, condition: .touch,
                           webhook: "https://example.com/hook", webhookText: nil, note: "n")
    let created = try #require(store.commit(draft))
    #expect(created.title == "BTC 涨到 84,662.2")
    var next = draft
    next.target = 83_000
    next.note = nil
    let edited = try #require(store.commit(next, editing: created.id))
    #expect(edited.id == created.id)
    #expect(edited.title == "BTC 跌到 83,000.0")
    #expect(edited.note == nil)
    #expect(store.all.count == 1)
  }

  @Test("最近用过的地址：去重、新的在前、最多三个")
  func recentWebhooks() {
    let store = fresh()
    let urls = ["https://a.com/1", "https://b.com/2", "https://a.com/1", "https://c.com/3", "https://d.com/4"]
    for (i, url) in urls.enumerated() {
      store.addPrice(symbol: "BTCUSDT", target: Double(90_000 + i), current: 84_500, label: "x",
                     webhook: url, now: Double(i))
    }
    #expect(store.recentWebhooks == ["https://d.com/4", "https://c.com/3", "https://a.com/1"])
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

  @Test("通知正文：现价 · 备注")
  func notificationBody() throws {
    var alert = KanpanCore.Alert.price(symbol: "BTCUSDT", target: 84_662.2, current: 84_500,
                                       label: "84,662.2", now: 1, note: "前高")
    #expect(AlertNotifications.body(for: alert, decimals: 1) == "前高")
    alert.firedPrice = 84_670.5
    #expect(AlertNotifications.body(for: alert, decimals: 1) == "现价 84,670.5 · 前高")
    alert.note = nil
    #expect(AlertNotifications.body(for: alert, decimals: 1) == "现价 84,670.5")
  }

  @Test("十字线药丸的字：比现价高是涨到、低是跌到、没现价写在")
  func crosshairChipTitle() {
    #expect(CrosshairActionBar.title(price: 84_535.5, live: 84_000, decimals: 1) == "涨到 84,535.5 提醒我")
    #expect(CrosshairActionBar.title(price: 83_000, live: 84_000, decimals: 1) == "跌到 83,000.0 提醒我")
    #expect(CrosshairActionBar.title(price: 83_000, live: nil, decimals: 1) == "在 83,000.0 提醒我")
  }
}
