import Testing
@testable import ReviewUI

/// 回放页头浮盈胶囊：颜色和摆出来的正负号必须是同一个说法。
@MainActor struct TradeReplayCapsuleToneTests {
  @Test func toneFollowsTheRoundedNumber() {
    // 取整后是 0：字写「+0.00%」，颜色也得是中性，不能一个涂涨色一个涂跌色。
    #expect(TradeReplayCapsule.text(-0.00004) == "+0.00%")
    #expect(TradeReplayCapsule.tone(-0.00004) == 0)
    #expect(TradeReplayCapsule.text(0.00004) == "+0.00%")
    #expect(TradeReplayCapsule.tone(0.00004) == 0)
    #expect(TradeReplayCapsule.tone(0) == 0)
    // 摆得出数的照常分涨跌。
    #expect(TradeReplayCapsule.text(0.0123) == "+1.23%")
    #expect(TradeReplayCapsule.tone(0.0123) == 1)
    #expect(TradeReplayCapsule.text(-0.0001) == "-0.01%")
    #expect(TradeReplayCapsule.tone(-0.0001) == -1)
  }
}
