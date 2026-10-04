import Foundation

/// 提醒响的时候发给 Webhook 的那句话，以及整份 JSON 身体。
///
/// **纯函数**：不碰网络、不读时钟（时刻由调用方给）。发送在 app 里的 `AlertWebhook`；
/// 服务端 `alerts.rs` 按同一份模板规则渲染一遍（后台时是它发），两边写出来的字要一样，
/// 所以占位符、价格写法、时间写法都钉在这儿，由 `AlertMessageTests` 用契约里那条例子对账。
public enum AlertMessage {
  /// 出厂模板：`BTC 价格达到 84,662.2，现价 84,670.5`。
  public static let defaultTemplate = "{品种} {条件} {目标价}，现价 {价格}"
  /// 条件提醒的出厂模板：`BTC 资金费率高于 0.05%，预测费率 0.0612% · 14 分钟后结算`（协议第 4 节）。
  public static let conditionTemplate = "{品种} {条件}，{数值}"

  /// 表单上那排占位符胶囊的顺序（点一下往模板末尾追加 `{名字}`）。
  public static let placeholders = ["品种", "价格", "目标价", "条件", "时间", "备注"]

  /// 按模板把一句话拼出来。
  ///
  /// - `{品种}`：`Alert.name(of:)`（`BTC`、`BTC/USD`）
  /// - `{代号}`：完整代号（`BTCUSDT`、`BTC-USD`）
  /// - `{价格}`：现价，千分位 + 品种小数位
  /// - `{目标价}`：响的那一刻线上的价（`Alert.target(at:near:)`，斜线、通道取触发时离现价最近那条），写法同上
  /// - `{条件}`：价格达到 / 收盘穿过
  /// - `{时间}`：ISO 8601 UTC，`2026-09-24T16:44:00Z`
  /// - `{备注}`：备注，没有就是空
  /// - `{数值}`：条件提醒触发时的那句观测（`detail`，和推送正文同一句）；价格提醒上是空
  ///
  /// 条件提醒上 `{条件}` 是「资金费率高于 0.05%」（`AlertRule.phrase`）、`{目标价}` 是空、
  /// `{价格}` 按服务端 `alerts::money` 写（它不知道品种小数位）。
  ///
  /// 模板为空（nil 或全是空白）时用出厂模板；认不得的 `{…}` 原样留着。
  ///
  /// **一遍扫完**（和服务端 `render_template` 同一个走法）：从前是按占位符逐个
  /// `replacingOccurrences`，备注里写了「{价格}」、先被换进去的值就会被后面那一轮再换一次
  /// （深度审查 E-5）。现在填进去的值原样落字，不再被扫第二遍。
  public static func render(template: String?, alert: Alert, price: Double, decimals: Int?,
                            at ms: Double, detail: String? = nil) -> String {
    let isCondition = alert.kind == .condition
    let text = Alert.blankIsNil(template) ?? (isCondition ? conditionTemplate : defaultTemplate)
    let target = isCondition ? nil : alert.target(at: ms, near: price)
    let values: [String: String] = [
      "品种": Alert.name(of: alert.symbol),
      "代号": InstrumentID(alert.symbol).symbol,
      "价格": isCondition ? AlertRule.money(price) : groupedPrice(price, decimals: decimals),
      "目标价": target.map { groupedPrice($0, decimals: decimals) } ?? "",
      "条件": isCondition ? (alert.rule?.phrase ?? "") : alert.condition.title,
      "数值": detail ?? "",
      "时间": iso(ms: ms),
      "备注": alert.note ?? "",
    ]
    return fill(text, values)
  }

  /// 模板替换本身：遇到 `{名字}` 查表，查得到就写值、查不到就把 `{` 原样写出去接着往后扫；
  /// 没有配对的 `}` 时余下部分原样留着。和服务端 `alerts::render_template` 一字一字同一个走法。
  static func fill(_ template: String, _ values: [String: String]) -> String {
    var out = ""
    var rest = Substring(template)
    while let open = rest.firstIndex(of: "{") {
      out += rest[..<open]
      let tail = rest[open...]
      guard let close = tail.firstIndex(of: "}") else { rest = tail; break }
      if let value = values[String(tail[tail.index(after: open)..<close])] {
        out += value
        rest = tail[tail.index(after: close)...]
      } else {
        out += "{"
        rest = tail[tail.index(after: open)...]
      }
    }
    out += rest
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
///  "text":"BTC 价格达到 84,662.2，现价 84,670.5"}
/// ```
///
/// 「发一条测试」是同一份，`event` 为 `test`、价格用现价。
///
/// 条件提醒（协议第 4 节）：`condition` 是 `rule.type`、`target` 是 `null`，另多带 `rule` /
/// `detail` / `value` 三个键（价格提醒上不写这三个）。
public struct AlertWebhookPayload: Sendable, Equatable, Encodable {
  public enum Event: String, Sendable, Encodable { case alert, test }

  public var event: Event
  public var alertId: String
  public var symbol: String
  public var market: String
  public var name: String
  public var title: String
  /// 价格提醒：`touch` / `close`；条件提醒：`rule.type`。
  public var condition: String
  public var once: Bool
  /// 条件提醒没有目标价，写 `null`。
  public var target: Double?
  public var price: Double
  public var firedAt: Int64
  public var time: String
  public var note: String
  public var text: String
  public var rule: AlertRule?
  public var detail: String?
  public var value: RuleJSON?

  /// 按一条提醒和这一刻的价拼出来。`at` 是响的那一刻（测试时是现在）。
  /// 条件提醒给 `observation`（触发时观测到的那句与那组数）；测试事件没有观测时 `detail` 写那条条件。
  public init(event: Event, alert: Alert, price: Double, decimals: Int?, at ms: Double,
              observation: ConditionObservation? = nil) {
    self.event = event
    alertId = alert.id
    symbol = InstrumentID(alert.symbol).symbol
    market = alert.market
    name = Alert.name(of: alert.symbol)
    title = alert.title
    once = alert.once
    self.price = price
    firedAt = Int64(ms)
    time = AlertMessage.iso(ms: ms)
    note = alert.note ?? ""
    if alert.kind == .condition {
      condition = alert.rule?.type ?? "condition"
      target = nil
      rule = alert.rule
      detail = observation?.detail ?? ConditionJudge.fallbackDetail(rule: alert.rule, price: price)
      value = observation?.value ?? .object([:])
    } else {
      condition = alert.condition.rawValue
      target = alert.target(at: ms, near: price) ?? price
    }
    text = AlertMessage.render(template: alert.webhookText, alert: alert, price: price,
                               decimals: decimals, at: ms, detail: detail)
  }

  private enum CodingKeys: String, CodingKey {
    case event, alertId, symbol, market, name, title, condition, once, target, price, firedAt, time, note, text
    case rule, detail, value
  }

  /// 价格提醒那十四个键永远写（`target` 为空写 null）；条件提醒的三个键只在条件提醒上写。
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(event, forKey: .event)
    try c.encode(alertId, forKey: .alertId)
    try c.encode(symbol, forKey: .symbol)
    try c.encode(market, forKey: .market)
    try c.encode(name, forKey: .name)
    try c.encode(title, forKey: .title)
    try c.encode(condition, forKey: .condition)
    try c.encode(once, forKey: .once)
    try c.encode(target, forKey: .target)
    try c.encode(price, forKey: .price)
    try c.encode(firedAt, forKey: .firedAt)
    try c.encode(time, forKey: .time)
    try c.encode(note, forKey: .note)
    try c.encode(text, forKey: .text)
    try c.encodeIfPresent(rule, forKey: .rule)
    try c.encodeIfPresent(detail, forKey: .detail)
    try c.encodeIfPresent(value, forKey: .value)
  }

  /// 编成 JSON 字节。键按契约里的顺序排不排无所谓，接收方按名字取。
  public func json() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return try encoder.encode(self)
  }
}
