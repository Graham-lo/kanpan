import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 选中栏上那句「跌到 64,000 叫我」怎么拼。
///
/// 方向按线在现价上面还是下面定；好几条线（通道、矩形、回撤）只报现价两侧最近的那两条；
/// 「还差多少」只在一侧有线时写。
@Suite("画线提醒胶囊的那句话")
struct LineAlertPhraseTests {
  @Test("线在现价下面：跌到")
  func below() {
    let p = LineAlertPhrase(targets: [64_000], current: 65_152, decimals: 0)
    #expect(p.target == "跌到 64,000")
    #expect(p.distance == "还差 1.77%")
  }

  @Test("线在现价上面：涨到")
  func above() {
    let p = LineAlertPhrase(targets: [70_000], current: 65_000, decimals: 1)
    #expect(p.target == "涨到 70,000.0")
    #expect(p.distance == "还差 7.69%")
  }

  @Test("两侧都有线：各报最近的一条，不写还差多少")
  func bothSides() {
    let p = LineAlertPhrase(targets: [60_000, 63_000, 66_000, 70_000], current: 64_000, decimals: 0)
    #expect(p.target == "涨到 66,000 或跌到 63,000")
    #expect(p.distance == nil)
  }

  @Test("还没拿到现价：只说到哪个价")
  func noQuote() {
    #expect(LineAlertPhrase(targets: [64_000], current: nil, decimals: 0).target == "到 64,000")
    #expect(LineAlertPhrase(targets: [1, 2], current: nil, decimals: 0).target == "价格达到这条线")
  }

  @Test("线段此刻不在（已经走完或还没开始）：不报价")
  func outOfSpan() {
    #expect(LineAlertPhrase(targets: [], current: 64_000, decimals: 0).target == "价格达到这条线")
  }

  @Test("已经走完的趋势线段不出胶囊；走完之前就开着的那条照出，好让人关掉（深度审查 E-1）")
  @MainActor
  func spentSegmentHasNoChip() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("alerts-\(UUID().uuidString).json")
    let store = AlertStore(store: AlertFileStore(url: url))
    let model = LineAlertModel()
    model.attach(store)
    let trend = Drawing(id: "t1", kind: .trend, points: [DrawPoint(t: 1_000_000, p: 100), DrawPoint(t: 2_000_000, p: 120)])
    let during = Date(timeIntervalSince1970: 1_500)      // 线段中间：1,500,000 毫秒
    let after = Date(timeIntervalSince1970: 3_000)       // 右锚点之后
    #expect(model.phrase(for: trend, symbol: "BTCUSDT", now: during) != nil)
    #expect(model.phrase(for: trend, symbol: "BTCUSDT", now: after) == nil)
    // 线段还没走完时开的提醒：走完之后胶囊仍在（显示开着），点一下就能关。
    try #require(store.add(drawing: trend, symbol: "BTCUSDT", now: 1_500_000) != nil)
    #expect(model.phrase(for: trend, symbol: "BTCUSDT", now: after) != nil)
    // 画在过去的回撤：价位往右延，任何时候都有胶囊、都报得出价。
    var fib = Drawing(id: "f1", kind: .fibonacci, points: [DrawPoint(t: 1_000_000, p: 200), DrawPoint(t: 2_000_000, p: 100)])
    fib.levels = [0.618]
    let phrase = try #require(model.phrase(for: fib, symbol: "BTCUSDT", now: after))
    #expect(phrase.target.contains("161.8"))
  }

  @Test("总表里线段已走完的那条写「线段已走完」，不再假装生效中")
  func spentAlertSaysSo() {
    let line = AlertLine(points: [DrawPoint(t: 1_000, p: 100), DrawPoint(t: 2_000, p: 120)])
    let alert = KanpanCore.Alert(symbol: "BTCUSDT", drawingID: "t1", lines: [line], armedAt: 1_000,
                                 title: "BTC 触到你画的趋势线", created: 1_000)
    #expect(AlertRecordText.meta(alert, zone: .fixed(0), decimals: 1, conditionInline: true, now: 1_500) == "价格达到")
    #expect(AlertRecordText.meta(alert, zone: .fixed(0), decimals: 1, conditionInline: true, now: 3_000)
            == AlertRecordText.spentNote)
  }

  @Test("小价不插千分位，四位以上才插")
  func grouping() {
    #expect(LineAlertPhrase(targets: [0.5], current: 0.6, decimals: 4).target == "跌到 0.5000")
    #expect(LineAlertPhrase(targets: [1234.5], current: 1300, decimals: 1).target == "跌到 1,234.5")
    #expect(LineAlertPhrase(targets: [987], current: 900, decimals: 0).target == "涨到 987")
  }

  @Test("压在现价上")
  func atPrice() {
    #expect(LineAlertPhrase(targets: [64_000], current: 64_000, decimals: 0).distance == "就在现价")
  }
}
