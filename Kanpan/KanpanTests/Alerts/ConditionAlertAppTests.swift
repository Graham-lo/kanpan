import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 条件提醒客户端（阶段 4b，`docs/条件提醒-协议-2026-09-27.md`）：建 / 去重 / 本机判响、列表行、
/// 品种上新与停牌下架的拉取游标、均线收盘时刻。
@Suite("提醒 · 条件提醒客户端")
@MainActor
struct ConditionAlertAppTests {
  private static let btc = "binance/usd_m/BTCUSDT"

  private func fresh() -> AlertStore {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("alerts-condition-\(UUID().uuidString).json")
    return AlertStore(store: AlertFileStore(url: url))
  }

  @Test("建一条条件提醒：kind=condition、带 rule；同一只品种同一条件不建第二条；非币安 U 本位不建")
  func addDedupesAndGuardsMarket() throws {
    let store = fresh()
    let rule = AlertRule.orderflowWall(threshold: "1000000")
    let a = try #require(store.addCondition(symbol: Self.btc, rule: rule, now: 1_000))
    #expect(a.kind == .condition)
    #expect(a.rule == rule)
    #expect(a.title == KanpanCore.Alert.conditionTitle(symbol: Self.btc, rule: rule))
    #expect(a.title.hasSuffix("出现 1M 以上的大单墙"))
    let again = store.addCondition(symbol: Self.btc, rule: rule, webhook: "https://example.com/h", now: 2_000)
    #expect(again?.id == a.id)
    #expect(store.all.filter { $0.kind == .condition }.count == 1)
    #expect(store.addCondition(symbol: "coinbase/spot/BTC-USD", rule: rule) == nil)
    #expect(store.addCondition(symbol: Self.btc, rule: .unknown(.object(["type": .string("x")]))) == nil)
  }

  @Test("本机判响：先存观测再标已触发；观测只给本机判响的那一次；判过的不再判")
  func localFireKeepsObservation() throws {
    let store = fresh()
    let a = try #require(store.addCondition(symbol: Self.btc, rule: .openInterestChange(threshold: "0.03"), now: 1_000))
    let obs = ConditionObservation(at: 5_000, price: 84_000, detail: "1 小时持仓量 +3.40% · 现价 84,000",
                                   value: .object(["change": .string("0.034")]))
    let fired = try #require(store.markFired(id: a.id, observation: obs))
    #expect(fired.firedAt == 5_000)
    #expect(fired.firedPrice == 84_000)
    #expect(store.observation(for: fired) == obs)
    #expect(store.markFired(id: a.id, observation: obs) == nil, "只响一次")
  }

  @Test("编辑：条件变了改标题并重新布防；只改 Webhook 不动布防")
  func updateRearmsOnlyWhenRuleChanges() throws {
    let store = fresh()
    let a = try #require(store.addCondition(symbol: Self.btc, rule: .funding(side: .above, rate: "0.0005"), now: 1_000))
    let hooked = try #require(store.updateCondition(id: a.id, rule: .funding(side: .above, rate: "0.0005"),
                                                    webhook: "https://example.com/h", now: 2_000))
    #expect(hooked.armedAt == a.armedAt)
    let moved = try #require(store.updateCondition(id: a.id, rule: .funding(side: .below, rate: "-0.0003"),
                                                   webhook: nil, now: 3_000))
    #expect(moved.title.hasSuffix("资金费率低于 -0.03%"))
    #expect(moved.armedAt == 3_000)
  }

  @Test("列表行：短句；条件提醒归在「价格提醒」那一段，不另起第三段")
  func listRowsAndSection() throws {
    let store = fresh()
    try #require(store.addCondition(symbol: Self.btc, rule: .funding(side: .above, rate: "0.0005"), now: 1) != nil)
    try #require(store.addCondition(symbol: Self.btc, rule: .openInterestChange(threshold: "0.03"), now: 2) != nil)
    try #require(store.addCondition(symbol: Self.btc, rule: .maCross(interval: "1h", length: 20, side: .above), now: 3) != nil)
    try #require(store.addCondition(symbol: Self.btc, rule: .orderflowWall(threshold: "5000000"), now: 4) != nil)
    try #require(store.addPrice(symbol: Self.btc, target: 90_000, current: 84_000, label: "90000", now: 5) != nil)
    let titles = Set(store.all.filter { $0.kind == .condition }.map { AlertRecordText.title($0, withSymbol: false) })
    #expect(titles == ["费率高于 0.05%", "1 小时持仓量变化超过 3%", "1h 收盘站上 MA 20", "出现超过 5M 的挂单墙"])
    let sections = AlertRecordText.sections(store.all)
    #expect(sections.map(\.kind) == [.price])
    #expect(sections.first?.count == 5)
    #expect(sections.first?.title == "价格提醒 5")
  }

  @Test("表单输入 → 线上字符串：百分数转比值、金额认 K/M/B；不合规的不收")
  func formTextToWire() {
    #expect(AlertRule.ratio(percent: "0.05") == "0.0005")
    #expect(AlertRule.ratio(percent: "-.03%") == "-0.0003")
    #expect(AlertRule.ratio(percent: "3") == "0.03")
    #expect(AlertRule.ratio(percent: "abc") == nil)
    #expect(AlertRule.amount("1M") == "1000000")
    #expect(AlertRule.amount("2.5m") == "2500000")
    #expect(AlertRule.amount("500K") == "500000")
    #expect(AlertRule.funding(side: .above, rate: "0.5").checked == nil, "费率超过 ±10% 不收")
    #expect(AlertRule.orderflowWall(threshold: "5000").checked == nil, "墙低于 10K 不收")
    #expect(AlertRule.maCross(interval: "1y", length: 20, side: .above).checked == nil, "没有年线")
    #expect(AlertRule.maCross(interval: "1m", length: 5, side: .above).checked != nil)
  }

  @Test("均线收盘时刻：普通周期 = 开盘 + 周期；月线按 UTC 日历加一个月")
  func maCloseTime() {
    #expect(ConditionAlertEngine.closeTime(openTime: 1_790_000_000_000, interval: .h1) == 1_790_003_600_000)
    // 2026-02-01 00:00 UTC → 2026-03-01 00:00 UTC（28 天）
    let feb: Int64 = 1_769_904_000_000
    #expect(ConditionAlertEngine.closeTime(openTime: feb, interval: .mo1) == Double(feb) + 28 * 86_400_000)
  }

  private func notice(_ id: Int64, at: Int64) -> ListingNotices.Notice {
    .init(id: id, venue: "binance", market: "usd_m", symbol: "ABCUSDT", event: "listed", at: at,
          title: "新上线：ABCUSDT", body: "币安合约")
  }

  @Test("品种上新拉取：第一次只出 1 小时内的；之后只出游标以后、24 小时内的；游标只往前挪；一次最多 5 条")
  func listingPlan() {
    let now: Int64 = 1_790_000_000_000
    let hour: Int64 = 3_600_000
    let first = ListingNotices.plan([notice(3, at: now - hour / 2), notice(2, at: now - 2 * hour)], cursor: nil, now: now)
    #expect(first.show.map(\.id) == [3])
    #expect(first.cursor == 3)
    let again = ListingNotices.plan([notice(3, at: now - hour / 2), notice(2, at: now - 2 * hour)], cursor: 3, now: now)
    #expect(again.show.isEmpty, "同一条不出第二次")
    #expect(again.cursor == 3)
    let later = ListingNotices.plan([notice(5, at: now - 3 * hour), notice(4, at: now - 30 * hour), notice(3, at: now)],
                                    cursor: 3, now: now)
    #expect(later.show.map(\.id) == [5])
    #expect(later.cursor == 5)
    let empty = ListingNotices.plan([], cursor: 9, now: now)
    #expect(empty.show.isEmpty && empty.cursor == 9)
    let burst = ListingNotices.plan((10...20).map { notice($0, at: now) }, cursor: 9, now: now)
    #expect(burst.show.map(\.id) == [20, 19, 18, 17, 16])
    #expect(burst.cursor == 20)
  }

  @Test("品种上新拉取的闸按账号分：A 那笔还在路上时 B 照常发；同一账号在路上或刚拉过才挡（E-11）")
  func listingGateIsPerOwner() {
    let a = UUID(), b = UUID()
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    #expect(ListingNotices.begin(owner: a, now: t0))
    #expect(ListingNotices.begin(owner: b, now: t0), "切账号时上一个账号那笔没回来，新账号被挡掉")
    #expect(!ListingNotices.begin(owner: a, now: t0 + 60), "同一账号那笔还在路上")
    ListingNotices.end(owner: a)
    #expect(!ListingNotices.begin(owner: a, now: t0 + 5), "两次太近")
    #expect(ListingNotices.begin(owner: a, now: t0 + ListingNotices.minInterval))
    ListingNotices.end(owner: a); ListingNotices.end(owner: b)
  }

  @Test("品种上新拉取的线上形状：data.notices，deliveryAt 可为 null")
  func listingDecodes() throws {
    let json = #"{"notices":[{"id":42,"venue":"binance","market":"usd_m","symbol":"ABCUSDT","event":"delistScheduled","at":1790517600000,"deliveryAt":1790985600000,"title":"ABCUSDT 将下架","body":"币安合约 · 10月3日 16:00（北京时间）停止交易"},{"id":41,"venue":"coinbase","market":"spot","symbol":"XYZ-USD","event":"listed","at":1790517000000,"deliveryAt":null,"title":"新上线：XYZ-USD","body":"Coinbase 现货"}]}"#
    let page = try JSONDecoder().decode(ListingNotices.Page.self, from: Data(json.utf8))
    #expect(page.notices.map(\.id) == [42, 41])
    #expect(page.notices[1].symbol == "XYZ-USD")
  }
}
