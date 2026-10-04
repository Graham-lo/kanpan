import Foundation
import Testing
@testable import ReviewUI

/// 交易复盘的金额、百分比：取整成 0 的不带正负号，颜色与正负号同一个说法。
struct TradeLabelsSignTests {
  @Test func roundedToZeroCarriesNoSign() {
    #expect(TradeLabels.money(Decimal(string: "-0.004")!) == "0.00")
    #expect(TradeLabels.money(Decimal(string: "0.004")!) == "0.00")
    #expect(TradeLabels.money(Decimal(string: "-0.004")!, signed: false) == "0.00")
    #expect(TradeLabels.moneyTone(Decimal(string: "-0.004")!) == 0)
    #expect(TradeLabels.percent(Decimal(string: "-0.0004")!) == "0.0%")
    #expect(TradeLabels.percent(Decimal(string: "0.0004")!, signed: true) == "0.0%")
  }

  @Test func visibleNumbersKeepTheirSign() {
    #expect(TradeLabels.money(Decimal(string: "-12.5")!) == "-12.50")
    #expect(TradeLabels.money(Decimal(string: "1234")!) == "+1.23K")
    #expect(TradeLabels.moneyTone(Decimal(string: "-12.5")!) == -1)
    #expect(TradeLabels.moneyTone(Decimal(string: "0.01")!) == 1)
    #expect(TradeLabels.percent(Decimal(string: "-0.123")!) == "-12.3%")
    #expect(TradeLabels.percent(Decimal(string: "0.05")!, signed: true) == "+5.0%")
  }

  /// 「离开后」那一路是比值：颜色要跟一位小数的百分比走，不能借金额的两位小数。
  /// 0.004 按金额写是「0.00」，按百分比写是「+0.4%」——原来照金额判成中性色。
  @Test func percentToneFollowsThePercentText() {
    #expect(TradeLabels.percent(Decimal(string: "0.004")!, signed: true) == "+0.4%")
    #expect(TradeLabels.percentTone(Decimal(string: "0.004")!) == 1)
    #expect(TradeLabels.percentTone(Decimal(string: "-0.004")!) == -1)
    #expect(TradeLabels.percentTone(Decimal(string: "0.0004")!) == 0)
    #expect(TradeLabels.percentTone(Decimal(string: "-0.0004")!) == 0)
    #expect(TradeLabels.moneyTone(Decimal(string: "0.004")!) == 0)
  }
}
