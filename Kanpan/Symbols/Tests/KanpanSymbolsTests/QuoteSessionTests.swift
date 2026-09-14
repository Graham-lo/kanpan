import Foundation
import Testing
@testable import KanpanSymbols

@Suite("实时报价会话")
struct QuoteSessionTests {
  @Test func lateRESTCannotOverwriteWS() {
    var session = QuoteSession()
    let now = Date(timeIntervalSince1970: 100)
    let request = session.request("BTCUSDT", now: now)
    #expect(session.accepts(request, symbol: "BTCUSDT", now: now.addingTimeInterval(1)))
    session.receive("ETHUSDT")
    #expect(session.accepts(request, symbol: "BTCUSDT", now: now.addingTimeInterval(1)))
    session.receive("BTCUSDT")
    #expect(!session.accepts(request, symbol: "BTCUSDT", now: now.addingTimeInterval(1)))
  }
  @Test func previousForegroundRequestIsRejected() {
    var session = QuoteSession()
    let now = Date(timeIntervalSince1970: 100)
    let request = session.request("BTCUSDT", now: now)
    session.reset()
    #expect(!session.accepts(request, symbol: "BTCUSDT", now: now.addingTimeInterval(1)))
    #expect(session.accepts(session.request("BTCUSDT", now: now), symbol: "BTCUSDT", now: now))
  }
  @Test func slowResponseDoesNotBecomeLivePrice() {
    let session = QuoteSession(), now = Date(timeIntervalSince1970: 100)
    let request = session.request("BTCUSDT", now: now)
    #expect(session.accepts(request, symbol: "BTCUSDT", now: now.addingTimeInterval(8)))
    #expect(!session.accepts(request, symbol: "BTCUSDT", now: now.addingTimeInterval(8.1)))
    #expect(!session.accepts(request, symbol: "BTCUSDT", now: now.addingTimeInterval(-1)))
  }
  @Test func foregroundFavoritesStaySubscribedAcrossPages() {
    #expect(QuoteSubscriptionPlan.needsConnection(foreground: true, favorites: ["BTCUSDT"], visible: false))
    #expect(!QuoteSubscriptionPlan.needsConnection(foreground: false, favorites: ["BTCUSDT"], visible: true))
    #expect(!QuoteSubscriptionPlan.needsConnection(foreground: true, favorites: [], visible: false))
    let favorites = (0..<100).map { "S\($0)" }
    let wanted = QuoteSubscriptionPlan.symbols(favorites: favorites, visible: ["VISIBLE", "S0"])
    #expect(wanted.count == 64 && Set(wanted).count == 64)
    #expect(wanted.contains("VISIBLE") && wanted.contains("S0"))
    #expect(!wanted.contains("S99"))
  }

}
