import Foundation

/// 提醒响的时候发给 Webhook 的那句话，以及整份 JSON 身体。
///
/// **纯函数**：不碰网络、不读时钟（时刻由调用方给）。发送在 app 里的 `AlertWebhook`；
/// 服务端 `alerts.rs` 按同一份模板规则渲染一遍（后台时是它发），两边写出来的字要一样，
/// 所以占位符、价格写法、时间写法都钉在这儿，由 `AlertMessageTests` 用契约里那条例子对账。
public enum AlertMessage {
  /// 出厂模板：`BTC 碰到 84,662.2，现价 84,670.5`。
  public static let defaultTemplate = "{品种} {条件} {目标价}，现价 {价格}"

  /// 表单上那排占位符胶囊的顺序（点一下往模板末尾追加 `{名字}`）。
  public static let placeholders = ["品种", "价格", "目标价", "条件", "时间", "备注"]

  /// 按模板把一句话拼出来。
  ///
  /// - `{品种}`：`Alert.name(of:)`（`BTC`、`BTC/USD`）
  /// - `{代号}`：完整代号（`BTCUSDT`、`BTC-USD`）
  /// - `{价格}`：现价，千分位 + 品种小数位
  /// - `{目标价}`：`lines.first.points.first.p`，写法同上
  /// - `{条件}`：碰到 / 收盘穿过
  /// - `{时间}`：ISO 8601 UTC，`2026-09-24T16:44:00Z`
  /// - `{备注}`：备注，没有就是空
  ///
  /// 模板为空（nil 或全是空白）时用出厂模板；认不得的 `{…}` 原样留着。
  public static func render(template: String?, alert: Alert, price: Double, decimals: Int?,
                            at ms: Double) -> String {
    let text = Alert.blankIsNil(template) ?? defaultTemplate
    let target = alert.lines.first?.points.first?.p
    let values: [(String, String)] = [
      ("品种", Alert.name(of: alert.symbol)),
      ("代号", InstrumentID(alert.symbol).symbol),
      ("价格", groupedPrice(price, decimals: decimals)),
      ("目标价", target.map { groupedPrice($0, decimals: decimals) } ?? ""),
      ("条件", alert.condition.title),
      ("时间", iso(ms: ms)),
      ("备注", alert.note ?? ""),
    ]
    var out = text
    for (name, value) in values { out = out.replacingOccurrences(of: "{\(name)}", with: value) }
    return out
  }

  /// 一口价：品种小数位 + 整数部分千分位（`84,662.2`）。小数位问不到按价自己猜。
  public static func groupedPrice(_ value: Double, decimals: Int?) -> String {
    let text = ReviewLabels.price(value, decimals: decimals)
    let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard let head = parts.first else { return text }
    let neg = head.hasPrefix("-")
    let digits = Array(neg ? head.dropFirst() : head)
    guard digits.count > 3, digits.allSatisfy(\.isNumber) else { return text }
    var grouped: [Character] = []
    for (i, d) in digits.enumerated() {
      if i > 0, (digits.count - i) % 3 == 0 { grouped.append(",") }
      grouped.append(d)
    }
    let whole = (neg ? "-" : "") + String(grouped)
    return parts.count > 1 ? whole + "." + parts[1] : whole
  }

  /// `2026-09-24T16:44:00Z`：UTC、到秒、不带毫秒。
  public static func iso(ms: Double) -> String {
    let date = Date(timeIntervalSince1970: (ms / 1000).rounded(.down))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", c.year ?? 1970, c.month ?? 1, c.day ?? 1,
                  c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
  }
}

/// 发给 Webhook 的那份 JSON。字段与服务端一字不差（契约见 2026-09-25 从图上加提醒）：
///
/// ```json
/// {"event":"alert","alertId":"a…","symbol":"BTCUSDT","market":"binance/usd_m","name":"BTC",
///  "title":"BTC 涨到 84,662.2","condition":"touch","once":true,"target":84662.2,
///  "price":84670.5,"firedAt":1758000000000,"time":"2026-09-24T16:44:00Z","note":"",
///  "text":"BTC 碰到 84,662.2，现价 84,670.5"}
/// ```
///
/// 「发一条测试」是同一份，`event` 为 `test`、价格用现价。
public struct AlertWebhookPayload: Sendable, Equatable, Encodable {
  public enum Event: String, Sendable, Encodable { case alert, test }

  public var event: Event
  public var alertId: String
  public var symbol: String
  public var market: String
  public var name: String
  public var title: String
  public var condition: Alert.Condition
  public var once: Bool
  public var target: Double
  public var price: Double
  public var firedAt: Int64
  public var time: String
  public var note: String
  public var text: String

  /// 按一条提醒和这一刻的价拼出来。`at` 是响的那一刻（测试时是现在）。
  public init(event: Event, alert: Alert, price: Double, decimals: Int?, at ms: Double) {
    self.event = event
    alertId = alert.id
    symbol = InstrumentID(alert.symbol).symbol
    market = alert.market
    name = Alert.name(of: alert.symbol)
    title = alert.title
    condition = alert.condition
    once = alert.once
    target = alert.lines.first?.points.first?.p ?? price
    self.price = price
    firedAt = Int64(ms)
    time = AlertMessage.iso(ms: ms)
    note = alert.note ?? ""
    text = AlertMessage.render(template: alert.webhookText, alert: alert, price: price,
                               decimals: decimals, at: ms)
  }

  private enum CodingKeys: String, CodingKey {
    case event, alertId, symbol, market, name, title, condition, once, target, price, firedAt, time, note, text
  }

  /// 编成 JSON 字节。键按契约里的顺序排不排无所谓，接收方按名字取。
  public func json() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return try encoder.encode(self)
  }
}
