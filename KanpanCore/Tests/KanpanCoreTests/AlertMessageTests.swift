import Foundation
import Testing

@testable import KanpanCore

/// 2026-09-25 提醒加的三个可空键（备注、Webhook 地址、推送内容）和 Webhook 那段话的拼法。
/// 字段契约与服务端 `alerts.rs` 一字不差：永远写出、空则 null，缺键读成 nil。
@Suite("提醒 · 备注与 Webhook")
struct AlertMessageTests {
  static let t0: Double = 1_790_000_000_000

  private func btc(note: String? = nil, webhook: String? = nil, text: String? = nil) -> Alert {
    Alert.price(symbol: "binance/usd_m/BTCUSDT", target: 84_662.2, current: 84_500, label: "84,662.2",
                now: Self.t0, webhook: webhook, webhookText: text, note: note)
  }

  private func json(_ alert: Alert) throws -> [String: Any] {
    let data = try JSONEncoder().encode(alert)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test("三个新键永远写出，空的写 null")
  func nullsAreWritten() throws {
    let body = try json(btc())
    for key in ["note", "webhook", "webhookText"] {
      #expect(body.keys.contains(key))
      #expect(body[key] is NSNull)
    }
  }

  @Test("填了的原样往返")
  func roundTrip() throws {
    let a = btc(note: "突破前高", webhook: "https://example.com/hook", text: "{品种} {价格}")
    let back = try JSONDecoder().decode(Alert.self, from: JSONEncoder().encode(a))
    #expect(back == a)
    #expect(back.note == "突破前高")
    #expect(back.webhook == "https://example.com/hook")
    #expect(back.webhookText == "{品种} {价格}")
  }

  @Test("老存档缺这三个键读成 nil；空白串也读成 nil")
  func missingKeysDecodeToNil() throws {
    var body = try json(btc(note: "x", webhook: "https://a.b", text: "t"))
    body.removeValue(forKey: "note")
    body.removeValue(forKey: "webhook")
    body["webhookText"] = "   "
    let data = try JSONSerialization.data(withJSONObject: body)
    let back = try JSONDecoder().decode(Alert.self, from: data)
    #expect(back.note == nil)
    #expect(back.webhook == nil)
    #expect(back.webhookText == nil)
  }

  @Test("备注截到 30 个字")
  func noteClip() {
    let long = String(repeating: "涨", count: 40)
    #expect(Alert.clip(note: long).count == 30)
    #expect(btc(note: long).note?.count == 30)
    #expect(Alert.clip(note: "短") == "短")
  }

  @Test("Webhook 地址：http(s) 开头、不含空白")
  func webhookValidity() {
    #expect(Alert.isValidWebhook("https://example.com/hook"))
    #expect(Alert.isValidWebhook("HTTP://10.0.0.1:8080/x"))
    #expect(Alert.isValidWebhook("  https://example.com  "))
    #expect(!Alert.isValidWebhook("https://"))
    #expect(!Alert.isValidWebhook("ftp://example.com"))
    #expect(!Alert.isValidWebhook("example.com"))
    #expect(!Alert.isValidWebhook("https://exa mple.com"))
    #expect(!Alert.isValidWebhook(""))
  }

  @Test("默认模板按契约那个例子拼出来")
  func defaultTemplate() {
    let text = AlertMessage.render(template: AlertMessage.defaultTemplate, alert: btc(),
                                   price: 84_670.5, decimals: 1, at: Self.t0)
    #expect(text == "BTC 碰到 84,662.2，现价 84,670.5")
    // 空模板回落到默认。
    #expect(AlertMessage.render(template: "  ", alert: btc(), price: 84_670.5, decimals: 1, at: Self.t0) == text)
  }

  @Test("占位符逐个替换，认不得的原样留着")
  func placeholders() {
    let a = btc(note: "看这里")
    let text = AlertMessage.render(template: "{代号}|{目标价}|{条件}|{时间}|{备注}|{别的}", alert: a,
                                   price: 84_670.5, decimals: 1, at: Self.t0)
    #expect(text == "BTCUSDT|84,662.2|碰到|2026-09-21T14:13:20Z|看这里|{别的}")
  }

  @Test("POST 身体：十四个键，测试事件与告警事件同一个形状")
  func payload() throws {
    let a = btc(note: "n", webhook: "https://a.b/c")
    let payload = AlertWebhookPayload(event: .alert, alert: a, price: 84_670.5, decimals: 1, at: Self.t0)
    let body = try #require(try JSONSerialization.jsonObject(with: payload.json()) as? [String: Any])
    #expect(Set(body.keys) == ["event", "alertId", "symbol", "market", "name", "title", "condition", "once",
                               "target", "price", "firedAt", "time", "note", "text"])
    #expect(body["event"] as? String == "alert")
    #expect(body["text"] as? String == "BTC 碰到 84,662.2，现价 84,670.5")
    #expect(body["condition"] as? String == "touch")
    #expect(body["once"] as? Bool == true)
    let test = AlertWebhookPayload(event: .test, alert: a, price: 84_670.5, decimals: 1, at: Self.t0)
    let testBody = try #require(try JSONSerialization.jsonObject(with: test.json()) as? [String: Any])
    #expect(testBody["event"] as? String == "test")
    #expect(Set(testBody.keys) == Set(body.keys))
  }
}
