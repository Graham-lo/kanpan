import Foundation
import Testing
@testable import KanpanCore

/// 条件提醒（`docs/条件提醒-协议-2026-09-27.md`）：rule 的线上形状、文案与四种判法。
@Suite("条件提醒")
struct ConditionAlertTests {
  static let t0: Double = 1_790_517_600_000

  private func roundTrip(_ alert: Alert) throws -> Alert {
    try JSONDecoder().decode(Alert.self, from: JSONEncoder().encode(alert))
  }

  private func json(_ alert: Alert) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(alert)) as? [String: Any])
  }

  // ------------------------------------------------------------------ 形状

  @Test("四种 rule 往返：比例与金额是十进制字符串，length 是整数")
  func rulesRoundTrip() throws {
    let rules: [AlertRule] = [
      .funding(side: .above, rate: "0.0005"), .funding(side: .below, rate: "-0.0001"),
      .openInterestChange(threshold: "0.05"),
      .maCross(interval: "4h", length: 20, side: .above), .maCross(interval: "1m", length: 5, side: .below),
      .orderflowWall(threshold: "5000000"),
    ]
    for rule in rules {
      let a = Alert.condition(symbol: "BTCUSDT", rule: rule, now: Self.t0)
      #expect(try roundTrip(a) == a)
      let body = try json(a)
      #expect(body["kind"] as? String == "condition")
      #expect(body["condition"] as? String == "touch")
      #expect((body["lines"] as? [Any])?.isEmpty == true)
      #expect(body["market"] as? String == "binance/usd_m")
      #expect(body["drawingID"] is NSNull && body["dueAt"] is NSNull && body["reviewID"] is NSNull)
      #expect(body["once"] as? Bool == true)
    }
    let ma = try json(Alert.condition(symbol: "BTCUSDT", rule: .maCross(interval: "4h", length: 20, side: .above), now: Self.t0))
    let rule = try #require(ma["rule"] as? [String: Any])
    #expect(rule["length"] as? Int == 20)
    #expect(rule["interval"] as? String == "4h" && rule["side"] as? String == "above" && rule["type"] as? String == "maCross")
    let wall = try json(Alert.condition(symbol: "BTCUSDT", rule: .orderflowWall(threshold: "5000000"), now: Self.t0))
    #expect((wall["rule"] as? [String: Any])?["threshold"] as? String == "5000000")
  }

  @Test("认不得的条件、字段不合规的已知条件：整份原样写回，不丢")
  func unknownRulesSurvive() throws {
    let raw = #"{"kind":"condition","symbol":"BTCUSDT","market":"binance/usd_m","rule":{"type":"liquidation","distance":"0.05","nested":{"a":[1,2.5,true,null]}},"condition":"touch","lines":[],"armedAt":1,"once":true,"status":"active","title":"x","created":1}"#
    let a = try JSONDecoder().decode(Alert.self, from: Data(raw.utf8))
    #expect(a.kind == .condition)
    #expect(a.rule?.isKnown == false)
    #expect(a.rule?.type == "liquidation")
    let back = try json(a)
    let rule = try #require(back["rule"] as? [String: Any])
    #expect(rule["distance"] as? String == "0.05")
    #expect(((rule["nested"] as? [String: Any])?["a"] as? [Any])?.count == 4)
    // 已知 type、越界的 rate：不认成 funding，也不丢。
    let bad = #"{"kind":"condition","symbol":"BTCUSDT","rule":{"type":"funding","side":"above","rate":"0.5"},"armedAt":1,"title":"x","created":1}"#
    let b = try JSONDecoder().decode(Alert.self, from: Data(bad.utf8))
    #expect(b.rule?.isKnown == false)
    #expect((try json(b)["rule"] as? [String: Any])?["rate"] as? String == "0.5")
  }

  @Test("老形状不变：价格 / 画线提醒 rule 为 null，缺键的老存档照读；有 rule 的一律是 condition")
  func oldShapes() throws {
    let price = Alert.price(symbol: "BTCUSDT", target: 100, current: 90, label: "100", now: Self.t0)
    #expect(price.rule == nil)
    #expect(try json(price)["rule"] is NSNull)
    #expect(try roundTrip(price) == price)
    let old = #"{"kind":"price","symbol":"BTCUSDT","market":"binance/usd_m","lines":[{"points":[{"t":1,"p":100}],"extendLeft":true,"extendRight":true}],"condition":"close","armedAt":1,"once":true,"status":"active","title":"BTC 涨到 100","created":1}"#
    let a = try JSONDecoder().decode(Alert.self, from: Data(old.utf8))
    #expect(a.kind == .price && a.rule == nil && a.condition == .close && a.targetPrice == 100)
    // 老客户端把条件提醒回写成 drawing：body 里有 rule，读回来还是 condition（协议第 5 节）。
    let downgraded = #"{"kind":"drawing","symbol":"BTCUSDT","rule":{"type":"orderflowWall","threshold":"1000000"},"armedAt":1,"title":"x","created":1}"#
    let c = try JSONDecoder().decode(Alert.self, from: Data(downgraded.utf8))
    #expect(c.kind == .condition && c.rule == .orderflowWall(threshold: "1000000"))
    // 将来的 kind（认不得）+ 没有 rule：退回 drawing，和从前一样。
    let future = #"{"kind":"someday","symbol":"BTCUSDT","armedAt":1,"title":"x","created":1}"#
    #expect(try JSONDecoder().decode(Alert.self, from: Data(future.utf8)).kind == .drawing)
  }

  @Test("十进制字符串：规范写法才收；Decimal 写回不带科学计数法")
  func decimals() {
    #expect(AlertRule.decimal("0.0005") == Decimal(string: "0.0005"))
    #expect(AlertRule.decimal("-0.0001") != nil)
    #expect(AlertRule.decimal("5e-4") == nil)
    #expect(AlertRule.decimal("+1") == nil)
    #expect(AlertRule.decimal("1,000") == nil)
    #expect(AlertRule.decimal(".5") == nil)
    #expect(AlertRule.decimal("5.") == nil)
    #expect(AlertRule.text(Decimal(string: "0.00050")!) == "0.0005")
    #expect(AlertRule.text(Decimal(5_000_000)) == "5000000")
    #expect(AlertRule.parseAmount("5M") == Decimal(5_000_000))
    #expect(AlertRule.parseAmount("1.5m") == Decimal(1_500_000))
    #expect(AlertRule.parseAmount("800K") == Decimal(800_000))
    #expect(AlertRule.parseAmount("2,000,000") == Decimal(2_000_000))
    #expect(AlertRule.parseAmount("abc") == nil)
    #expect(AlertRule.parseAmount("-1M") == nil)
  }

  @Test("回填输入框的金额一位不舍，读回去一分不差（深度审查 E-4）")
  func editableAmountRoundTrips() {
    #expect(AlertRule.editableAmount(Decimal(1_250_000)) == "1.25M")
    #expect(AlertRule.editableAmount(Decimal(1_234_567)) == "1.234567M")
    #expect(AlertRule.editableAmount(Decimal(5_000_000)) == "5M")
    #expect(AlertRule.editableAmount(Decimal(800_000)) == "800K")
    #expect(AlertRule.editableAmount(1_250_000.0) == "1.25M")
    for v in [Decimal(1_250_000), Decimal(1_234_567), Decimal(10_000), Decimal(string: "2500000000.5")!, Decimal(3_100_000_000_000)] {
      #expect(AlertRule.parseAmount(AlertRule.editableAmount(v)) == v)
    }
    // 给人看的 `units` 不变（和服务端 `conditions::units` 一字不差）。
    #expect(AlertRule.units(1_250_000) == "1.2M")
  }


  // ------------------------------------------------------------------ 文案

  @Test("标题与服务端默认标题同一句；列表行是短句")
  func phrases() {
    let cases: [(AlertRule, String, String)] = [
      (.funding(side: .above, rate: "0.0005"), "BTC 资金费率高于 0.05%", "费率高于 0.05%"),
      (.funding(side: .below, rate: "-0.0001"), "BTC 资金费率低于 -0.01%", "费率低于 -0.01%"),
      (.openInterestChange(threshold: "0.03"), "BTC 1 小时持仓量变化超过 3%", "1 小时持仓量变化超过 3%"),
      (.maCross(interval: "1h", length: 20, side: .above), "BTC 1h 收盘站上 MA20", "1h 收盘站上 MA 20"),
      (.maCross(interval: "4h", length: 60, side: .below), "BTC 4h 收盘跌破 MA60", "4h 收盘跌破 MA 60"),
      (.orderflowWall(threshold: "5000000"), "BTC 出现 5M 以上的大单墙", "出现超过 5M 的挂单墙"),
      (.orderflowWall(threshold: "12400000"), "BTC 出现 12.4M 以上的大单墙", "出现超过 12.4M 的挂单墙"),
    ]
    for (rule, title, row) in cases {
      #expect(Alert.condition(symbol: "BTCUSDT", rule: rule, now: 0).title == title)
      #expect(rule.rowText == row)
    }
    #expect(AlertRule.money(84_210.6) == "84,211")
    #expect(AlertRule.money(1.23456) == "1.23")
    #expect(AlertRule.money(0.012345) == "0.0123")
    #expect(AlertRule.signedPercent(Decimal(string: "0.0621")!, dp: 2) == "+6.21%")
    #expect(AlertRule.signedPercent(Decimal(string: "-0.035")!, dp: 2) == "-3.5%")
  }

  // ------------------------------------------------------------------ 判法

  @Test("费率：结算前 15 分钟窗口内按预测费率判，正文带分钟数")
  func funding() throws {
    let next = Self.t0 + 8 * 3_600_000
    #expect(!ConditionJudge.inFundingWindow(now: next - 16 * 60_000, nextFunding: next, armedAt: Self.t0))
    #expect(ConditionJudge.inFundingWindow(now: next - 14 * 60_000 - 1, nextFunding: next, armedAt: Self.t0))
    #expect(!ConditionJudge.inFundingWindow(now: next, nextFunding: next, armedAt: Self.t0))
    #expect(!ConditionJudge.inFundingWindow(now: next - 60_000, nextFunding: next, armedAt: next - 30_000))
    let now = next - 13 * 60_000 - 30_000
    let hit = try #require(ConditionJudge.funding(side: .above, rate: "0.0005", predicted: Decimal(string: "0.000612")!,
                                                  mark: 84_671.2, nextFunding: next, now: now))
    #expect(hit.detail == "预测费率 0.0612% · 14 分钟后结算")
    #expect(hit.price == 84_671.2)
    #expect(hit.value.object?["rate"]?.string == "0.000612")
    #expect(ConditionJudge.funding(side: .above, rate: "0.0005", predicted: Decimal(string: "0.0004")!,
                                   mark: 1, nextFunding: next, now: now) == nil)
    #expect(ConditionJudge.funding(side: .below, rate: "0", predicted: Decimal(string: "-0.0001")!,
                                   mark: 1, nextFunding: next, now: now) != nil)
  }

  @Test("持仓量：最新点与恰好 1 小时前那点比绝对值；缺那一点或没武装不判")
  func openInterest() throws {
    let h = ConditionJudge.oiSpanMs, step = ConditionJudge.oiPeriodMs
    var points = (0...12).map { ConditionJudge.OIPoint(at: Self.t0 + Double($0) * step, amount: 100) }
    points[12].amount = 106.21
    let hit = try #require(ConditionJudge.openInterest(threshold: "0.05", points: points, armedAt: Self.t0,
                                                       price: 84_671, now: Self.t0 + h + 30_000))
    #expect(hit.detail == "1 小时持仓量 +6.21% · 现价 84,671")
    #expect(hit.value.object?["from"]?.string == "100")
    // 跌也算。
    points[12].amount = 94
    #expect(ConditionJudge.openInterest(threshold: "0.05", points: points, armedAt: Self.t0, price: 1, now: 0)?
      .detail.hasPrefix("1 小时持仓量 -6%") == true)
    // 没到阈值。
    points[12].amount = 103
    #expect(ConditionJudge.openInterest(threshold: "0.05", points: points, armedAt: Self.t0, price: 1, now: 0) == nil)
    // 武装在最新点之后。
    points[12].amount = 110
    #expect(ConditionJudge.openInterest(threshold: "0.05", points: points, armedAt: Self.t0 + h + 1, price: 1, now: 0) == nil)
    // 缺 1 小时前那一点。
    #expect(ConditionJudge.openInterest(threshold: "0.05", points: Array(points.dropFirst()), armedAt: Self.t0, price: 1, now: 0) == nil)
  }

  @Test("均线：边沿穿过才响，要 N+1 根，只判收盘晚于武装的")
  func maCross() throws {
    let step = 60_000.0
    func bars(_ closes: [Double]) -> [ConditionJudge.ClosedBar] {
      closes.enumerated().map { i, c in
        ConditionJudge.ClosedBar(openTime: Self.t0 + Double(i) * step, close: c, closeTime: Self.t0 + Double(i + 1) * step)
      }
    }
    // MA3：前一根 90 在 MA(100,100,90)=96.67 下面，这一根 110 在 MA(100,90,110)=100 上面。
    let up = bars([100, 100, 100, 90, 110])
    let hit = try #require(ConditionJudge.maCross(length: 3, side: .above, bars: up, armedAt: Self.t0, now: 0))
    #expect(hit.detail == "收盘 110.00 · MA3 100.00")
    #expect(hit.price == 110)
    #expect(ConditionJudge.maCross(length: 3, side: .below, bars: up, armedAt: Self.t0, now: 0) == nil)
    // 已经在上面：不是边沿。
    #expect(ConditionJudge.maCross(length: 3, side: .above, bars: bars([100, 100, 100, 110, 120]), armedAt: Self.t0, now: 0) == nil)
    // 根数不够 N+1。
    #expect(ConditionJudge.maCross(length: 5, side: .above, bars: up, armedAt: Self.t0, now: 0) == nil)
    // 最后一根收盘不晚于武装。
    #expect(ConditionJudge.maCross(length: 3, side: .above, bars: up, armedAt: up.last!.closeTime, now: 0) == nil)
    // 下穿。
    #expect(ConditionJudge.maCross(length: 3, side: .below, bars: bars([100, 100, 100, 110, 90]), armedAt: Self.t0, now: 0) != nil)
  }

  @Test("大单：只认新墙——武装后出现的、或武装时还没到门槛后来长过去的；老墙不响")
  func walls() throws {
    let armed = Self.t0
    let old = ConditionJudge.Wall(key: "old", exchange: "币安", product: "usdtPerp", side: "bid", price: 84_000,
                                  notional: 12_400_000, firstSeen: armed - 60_000)
    let small = ConditionJudge.Wall(key: "grow", exchange: "OKX", product: "spot", side: "ask", price: 85_000,
                                    notional: 800_000, firstSeen: armed - 60_000)
    let baseline = ConditionJudge.wallBaseline(walls: [old, small], threshold: 1_000_000, armedAt: armed)
    #expect(baseline == ["old"])
    #expect(ConditionJudge.wall(threshold: 1_000_000, walls: [old, small], baseline: baseline, armedAt: armed, now: 0) == nil)
    var grown = small; grown.notional = 5_600_000
    let hit = try #require(ConditionJudge.wall(threshold: 1_000_000, walls: [old, grown], baseline: baseline, armedAt: armed, now: 0))
    #expect(hit.detail == "OKX 现货 卖墙 5.6M @ 85,000")
    let fresh = ConditionJudge.Wall(key: "new", exchange: "币安", product: "usdtPerp", side: "bid", price: 84_000,
                                    notional: 12_400_000, firstSeen: armed + 1)
    #expect(ConditionJudge.wall(threshold: 1_000_000, walls: [old, fresh], baseline: baseline, armedAt: armed, now: 0)?
      .detail == "币安 U 本位 买墙 12.4M @ 84,000")
  }
}
