import Foundation
import Testing
import KanpanCore
@testable import KanpanNetwork

/// P2.15：`onboardDate` 从品种表带进 `SymbolInfo`，「新」记号按它判 30 天。
@Suite("品种上线时间与「新」记号")
struct ExchangeInfoOnboardTests {
  @Test("onboardDate 原样带进来，缺字段为空")
  func parsesOnboardDate() throws {
    var a = ExchangeInfoStatusTests.row("AUSDT", status: "TRADING")
    a["onboardDate"] = 1_788_343_200_000
    let b = ExchangeInfoStatusTests.row("BUSDT", status: "TRADING")
    let list = try BinanceREST.parseExchangeInfo(try ExchangeInfoStatusTests.body([a, b]))
    #expect(list.first { $0.symbol == "AUSDT" }?.onboardDate == 1_788_343_200_000)
    #expect(list.first { $0.symbol == "BUSDT" }?.onboardDate == nil)
  }

  @Test("上线 30 天以内才算新；预告上线、没有日期都不算")
  func thirtyDayWindow() {
    let day: Int64 = 86_400_000
    let now: Int64 = 1_790_000_000_000
    func info(_ onboard: Int64?) -> SymbolInfo {
      SymbolInfo(symbol: "XUSDT", base: "X", pricePrecision: 2, tickSize: 0.01, onboardDate: onboard)
    }
    #expect(info(now - day).isNewListing(nowMs: now))
    #expect(info(now - 30 * day).isNewListing(nowMs: now))
    #expect(!info(now - 30 * day - 1).isNewListing(nowMs: now))
    #expect(!info(now + day).isNewListing(nowMs: now))
    #expect(!info(nil).isNewListing(nowMs: now))
  }

  @Test("旧目录缓存没有 onboardDate 照样解得开，编码来回不丢")
  func codableRoundTrip() throws {
    let old = #"{"symbol":"AUSDT","base":"A","quote":"USDT","pricePrecision":2,"tickSize":0.01}"#
    let decoded = try JSONDecoder().decode(SymbolInfo.self, from: Data(old.utf8))
    #expect(decoded.onboardDate == nil)
    var withDate = decoded
    withDate.onboardDate = 1_788_000_000_000
    let again = try JSONDecoder().decode(SymbolInfo.self, from: JSONEncoder().encode(withDate))
    #expect(again == withDate)
  }
}
