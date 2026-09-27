import Foundation
import Testing
import KanpanCore
@testable import Kanpan

@Suite("主力订单流 · 设置")
struct OrderFlowPrefsTests {
  @Test("出厂：没有改过的币（显示开关 2026-09-28 收掉，图上走 ChartState 的出厂值 .all）")
  func defaults() {
    let prefs = Prefs.defaults
    #expect(prefs.orderFlowOverrides.isEmpty)
  }

  @Test("改过的门槛落盘再读回一字不差")
  func roundTrip() {
    var prefs = Prefs.defaults
    prefs.setOrderFlowOverride(OrderFlowOverride(spot: 2_000_000, step: 50), for: "BTC")
    prefs.setOrderFlowOverride(OrderFlowOverride(usdtPerp: 1_500_000), for: "TSLA")
    let back = PrefsCodec.decode(PrefsCodec.encode(prefs))
    #expect(back.orderFlowOverrides == prefs.orderFlowOverrides)
  }

  @Test("老存档里的显示开关（四个新键、六合四之前的旧键）读时忽略，也不再写")
  func retiredDisplaySwitchesAreIgnored() {
    let old = PrefsCodec.decode(Data(#"{"v":2,"orderFlow":true,"orderFlowSpot":false,"orderFlowShowCancelled":false,"orderFlowFilledBid":false,"orderFlowCancelledAsk":false}"#.utf8))
    #expect(old.orderFlow)
    let fresh = String(decoding: PrefsCodec.encode(old), as: UTF8.self)
    for key in ["orderFlowSpot", "orderFlowContract", "orderFlowShowFilled", "orderFlowShowCancelled",
                "orderFlowFilledBid", "orderFlowCancelledAsk"] {
      #expect(!fresh.contains(key), "\(key) 不该再写进档里")
    }
  }

  @Test("越界的项丢掉，一项不剩等于恢复默认；认不出的 base 不收")
  func normalization() {
    var prefs = Prefs.defaults
    prefs.setOrderFlowOverride(OrderFlowOverride(spot: 10, usdtPerp: 3_000_000), for: "ETH")
    #expect(prefs.orderFlowOverrides["ETH"] == OrderFlowOverride(usdtPerp: 3_000_000))
    prefs.setOrderFlowOverride(OrderFlowOverride(spot: 10), for: "ETH")
    #expect(prefs.orderFlowOverrides["ETH"] == nil)
    prefs.setOrderFlowOverride(OrderFlowOverride(spot: 2_000_000), for: "btc")
    prefs.setOrderFlowOverride(OrderFlowOverride(spot: 2_000_000), for: "BTC-USDT")
    #expect(prefs.orderFlowOverrides.isEmpty)
    prefs.setOrderFlowOverride(OrderFlowOverride(spot: 2_000_000), for: "SOL")
    prefs.setOrderFlowOverride(nil, for: "SOL")
    #expect(prefs.orderFlowOverrides.isEmpty)
  }

  @Test("最多记 200 只；已经在表里的照样能改")
  func cap() {
    var prefs = Prefs.defaults
    for i in 0..<Prefs.maxOrderFlowOverrides { prefs.setOrderFlowOverride(OrderFlowOverride(spot: 2_000_000), for: "C\(i)") }
    prefs.setOrderFlowOverride(OrderFlowOverride(spot: 2_000_000), for: "EXTRA")
    #expect(prefs.orderFlowOverrides.count == Prefs.maxOrderFlowOverrides && prefs.orderFlowOverrides["EXTRA"] == nil)
    prefs.setOrderFlowOverride(OrderFlowOverride(spot: 3_000_000), for: "C0")
    #expect(prefs.orderFlowOverrides["C0"]?.spot == 3_000_000)
  }

  @Test("坏档：一只坏的不拖垮整张表，越界项丢")
  func tolerantDecode() throws {
    let json = """
    {"v":2,"orderFlowOverrides":{"BTC":{"spot":2000000,"step":0},"eth":{"spot":2000000},"SOL":{"spot":1},
     "XAU":{"usdtPerp":3000000}},"orderFlowSpot":false,"orderFlowContract":"no"}
    """
    let prefs = PrefsCodec.decode(Data(json.utf8))
    #expect(prefs.orderFlowOverrides == ["BTC": OrderFlowOverride(spot: 2_000_000), "XAU": OrderFlowOverride(usdtPerp: 3_000_000)])
    // 整张表不是对象（坏档）→ 退空表，别的字段照读。
    let bad = PrefsCodec.decode(Data(#"{"v":2,"orderFlowOverrides":[1,2],"orderFlow":true}"#.utf8))
    #expect(bad.orderFlowOverrides.isEmpty && bad.orderFlow)
  }

  @Test("门槛跟着人走（随账号同步）；显示开关已收掉")
  func synced() {
    #expect(PrefsFieldPlan.table["orderFlowOverrides"] == .synced)
    #expect(Prefs.syncedFieldNames.contains("orderFlowOverrides"))
    for retired in ["orderFlowFilledBid", "orderFlowFilledAsk", "orderFlowCancelledBid", "orderFlowCancelledAsk",
                    "orderFlowSpot", "orderFlowContract", "orderFlowShowFilled", "orderFlowShowCancelled"] {
      #expect(PrefsFieldPlan.table[retired] == nil && !Prefs.syncedFieldNames.contains(retired), "\(retired)")
    }
  }

  // MARK: 面板保存（审查 30）

  /// 行情流按成交额分到最高档的那份默认：合约 500 万、现货 100 万（app 自己查表不知道成交额，只落到第三档）。
  private static let btcTop = OrderFlowThresholds(spot: 1_000_000, usdtPerp: 5_000_000, coinPerp: 5_000_000,
                                                  delivery: 5_000_000, step: 100)

  @Test("保存：只改打过的格，和行情流给的默认一样的格拿掉")
  func overrideStripsCellsEqualToFeedDefaults() {
    let existing = OrderFlowOverride(spot: 2_000_000, coinPerp: 7_000_000)
    let next = OrderFlowEditor.override(defaults: Self.btcTop, existing: existing,
                                        edited: [.threshold(.usdtPerp): 8_000_000, .threshold(.spot): 1_000_000,
                                                 .step: 100])
    #expect(next == OrderFlowOverride(usdtPerp: 8_000_000, coinPerp: 7_000_000))
  }

  @Test("保存：行情流的默认还没来就一格不拿掉——打了什么存什么，不拿查表那份第三档去比")
  func overrideKeepsEverythingBeforeFeedDefaultsArrive() {
    let next = OrderFlowEditor.override(defaults: nil, existing: nil,
                                        edited: [.threshold(.usdtPerp): 5_000_000, .step: 100])
    #expect(next == OrderFlowOverride(usdtPerp: 5_000_000, step: 100))
  }

  @Test("保存：恢复默认（不带原来那份）后什么都没打就是空，整只从改动表里拿掉")
  func overrideAfterResetIsEmpty() {
    var prefs = Prefs.defaults
    prefs.setOrderFlowOverride(OrderFlowOverride(spot: 2_000_000), for: "DOGE")
    let next = OrderFlowEditor.override(defaults: Self.btcTop, existing: nil, edited: [:])
    #expect(next.isEmpty)
    prefs.setOrderFlowOverride(next, for: "DOGE")
    #expect(prefs.orderFlowOverrides["DOGE"] == nil)
  }

  @Test("保存：默认表里没有步长（按收盘推）时打的步长照存")
  func overrideStoresStepWhenDefaultIsAutomatic() {
    var auto = Self.btcTop; auto.step = nil
    let next = OrderFlowEditor.override(defaults: auto, existing: nil, edited: [.step: 0.0002])
    #expect(next == OrderFlowOverride(step: 0.0002))
  }
}
