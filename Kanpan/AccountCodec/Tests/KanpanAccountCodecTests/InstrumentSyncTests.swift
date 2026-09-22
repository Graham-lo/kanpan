import Foundation
import Testing
import KanpanCore
import KanpanAccount
@testable import KanpanAccountCodec

@Suite("交易所身份同步往返") struct InstrumentSyncTests {
  @Test func legacyIDsStayStableAndSpotStaysSeparate() throws {
    let old = try JSONDecoder().decode(SymbolPrefs.self, from: Data(#"{"favorites":["BTCUSDT"],"recents":["BTCUSDT"]}"#.utf8))
    var prefs = old
    _ = prefs.toggleFavorite("coinbase/spot/BTC-USD")
    let favorites = PersonalSyncCodec.symbols(prefs).filter { $0.collection == "favorites" }
    #expect(Set(favorites.map(\.id)) == ["binance/usd_m/BTCUSDT", "coinbase/spot/BTC-USD"])
    let spot = try #require(favorites.first { $0.id == "coinbase/spot/BTC-USD" })
    #expect(spot.body["symbol"] == .string("BTC-USD"))
    #expect(spot.body["venue"] == .string("coinbase"))
    #expect(PersonalSyncCodec.instrument(spot) == "coinbase/spot/BTC-USD")

    let drawing = Drawing(id: "same-id", kind: .trend, points: [DrawPoint(t: 1, p: 100), DrawPoint(t: 2, p: 110)])
    let archive = DrawArchive(bySymbol: ["BTCUSDT": [drawing], "coinbase/spot/BTC-USD": [drawing]])
    let objects = try PersonalSyncCodec.drawings(archive).filter { $0.collection == "drawings" }
    #expect(Set(objects.map(\.id)) == ["binance/usd_m/BTCUSDT/same-id", "coinbase/spot/BTC-USD/same-id"])
    for object in objects { #expect(try PersonalSyncCodec.drawing(object) == drawing) }

    let alert = Alert(id: "alert", symbol: "coinbase/spot/BTC-USD", drawingID: drawing.id,
                      armedAt: 12, status: .fired, firedAt: 13, firedPrice: 105, title: "价格触线", created: 10)
    let object = try #require(try PersonalSyncCodec.alerts([alert]).first)
    #expect(object.id == "coinbase/spot/BTC-USD/alert")
    #expect(object.body["market"] == .string("coinbase/spot"))
    #expect(try PersonalSyncCodec.alert(object) == alert)
  }
}
