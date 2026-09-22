import Foundation
import Testing
@testable import KanpanSymbols

@Suite("实时报价会话")
struct QuoteSessionTests {
  @Test func lateRESTCannotOverwriteWS() {
    var session = QuoteSession()
    let now = Date(timeIntervalSince1970: 100)
    let request = session.request("binance/usd_m/BTCUSDT", now: now)
    #expect(session.accepts(request, symbol: "binance/usd_m/BTCUSDT", now: now.addingTimeInterval(1)))
    session.receive("binance/usd_m/ETHUSDT")
    #expect(session.accepts(request, symbol: "binance/usd_m/BTCUSDT", now: now.addingTimeInterval(1)))
    session.receive("binance/usd_m/BTCUSDT")
    #expect(!session.accepts(request, symbol: "binance/usd_m/BTCUSDT", now: now.addingTimeInterval(1)))
  }
  @Test func previousForegroundRequestIsRejected() {
    var session = QuoteSession()
    let now = Date(timeIntervalSince1970: 100)
    let request = session.request("binance/usd_m/BTCUSDT", now: now)
    session.reset()
    #expect(!session.accepts(request, symbol: "binance/usd_m/BTCUSDT", now: now.addingTimeInterval(1)))
    #expect(session.accepts(session.request("binance/usd_m/BTCUSDT", now: now), symbol: "binance/usd_m/BTCUSDT", now: now))
  }
  @Test func slowResponseDoesNotBecomeLivePrice() {
    let session = QuoteSession(), now = Date(timeIntervalSince1970: 100)
    let request = session.request("binance/usd_m/BTCUSDT", now: now)
    #expect(session.accepts(request, symbol: "binance/usd_m/BTCUSDT", now: now.addingTimeInterval(8)))
    #expect(!session.accepts(request, symbol: "binance/usd_m/BTCUSDT", now: now.addingTimeInterval(8.1)))
    #expect(!session.accepts(request, symbol: "binance/usd_m/BTCUSDT", now: now.addingTimeInterval(-1)))
  }
  @Test func foregroundFavoritesStaySubscribedAcrossPages() {
    #expect(QuoteSubscriptionPlan.needsConnection(foreground: true, favorites: ["binance/usd_m/BTCUSDT"], visible: false))
    #expect(!QuoteSubscriptionPlan.needsConnection(foreground: false, favorites: ["binance/usd_m/BTCUSDT"], visible: true))
    #expect(!QuoteSubscriptionPlan.needsConnection(foreground: true, favorites: [], visible: false))
    let favorites = (0..<100).map { "S\($0)" }
    let wanted = QuoteSubscriptionPlan.symbols(favorites: favorites, visible: ["VISIBLE", "S0"])
    #expect(wanted.count == 64 && Set(wanted).count == 64)
    #expect(wanted.contains("VISIBLE") && wanted.contains("S0"))
    #expect(!wanted.contains("S99"))
  }

  /// 挂着活动提醒的品种要被钉进订阅范围：不占那 64 个名额、也不会被裁掉。
  ///
  /// 这条就是「提醒是跨品种的」那一半——前台判定只能判盘上有价的品种，
  /// 一条画在 ETHUSDT 上的提醒，用户正看着 BTCUSDT、ETHUSDT 又不在自选里的话，
  /// 没有这一条它一辈子不会响。
  @Test func alertedSymbolsAreAlwaysSubscribed() {
    let favorites = (0..<100).map { "S\($0)" }
    let wanted = QuoteSubscriptionPlan.symbols(favorites: favorites, visible: ["S0"],
                                               alerted: ["binance/usd_m/ETHUSDT", "S3"])
    #expect(wanted.contains("binance/usd_m/ETHUSDT"))
    // 已经在名额里的不重复排一遍。
    #expect(wanted.filter { $0 == "S3" }.count == 1)
    #expect(Set(wanted).count == wanted.count)
    #expect(wanted.count == 65)
    // 光有提醒、没有自选也没有可见行，也得把连接拉起来。
    #expect(QuoteSubscriptionPlan.needsConnection(foreground: true, favorites: [], visible: false,
                                                  alerted: ["binance/usd_m/ETHUSDT"]))
    #expect(!QuoteSubscriptionPlan.needsConnection(foreground: false, favorites: [], visible: false,
                                                   alerted: ["binance/usd_m/ETHUSDT"]))
  }
}
