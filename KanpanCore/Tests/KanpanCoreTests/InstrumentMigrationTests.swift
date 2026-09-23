import Foundation
import Testing
@testable import KanpanCore

@Suite("品种身份迁移") struct InstrumentMigrationTests {
  @Test func stableKey() throws {
    let old = InstrumentID(" btcusdt ")
    #expect(old.key == "binance/usd_m/BTCUSDT")
    #expect(InstrumentID(old.key) == old)
    #expect(InstrumentID("coinbase/spot/BTC-USD") != old)
    // 给人看的代号：带横杠的写成斜杠，连写的原样。
    #expect(InstrumentID("coinbase/spot/BTC-USD").display == "BTC/USD")
    #expect(old.display == "BTCUSDT")
    #expect(!InstrumentID("coinbase/../BTC-USD").isValid)
    let data = Data(#"{"symbol":"BTCUSDT","base":"BTC","pricePrecision":1,"tickSize":0.1}"#.utf8)
    #expect(try JSONDecoder().decode(SymbolInfo.self, from: data).id == old)
  }

  @Test func drawingsMergeWithoutLosingObjects() throws {
    let first = Drawing(id: "one", kind: .hline, points: [.init(t: 1, p: 2)])
    let second = Drawing(id: "two", kind: .hline, points: [.init(t: 1, p: 3)])
    let encoded = try JSONEncoder().encode(["BTCUSDT": [first], "binance/usd_m/BTCUSDT": [second], "coinbase/spot/BTC-USD": [first]])
    let json = Data("{\"v\":2,\"d\":".utf8) + encoded + Data("}".utf8)
    let archive = try JSONDecoder().decode(DrawArchive.self, from: json)
    #expect(Set(archive["BTCUSDT"].map(\.id)) == ["one", "two"])
    #expect(archive["coinbase/spot/BTC-USD"].count == 1)
    #expect(try JSONDecoder().decode(DrawArchive.self, from: JSONEncoder().encode(archive)) == archive)
  }

  @Test func oldAlertRetainsIdentityAndState() throws {
    let json = Data(#"{"id":"a-old","symbol":"BTCUSDT","market":"binance/usd_m","drawingID":"d-old","status":"paused","armedAt":123,"created":99,"title":"原提醒"}"#.utf8)
    let alert = try JSONDecoder().decode(Alert.self, from: json)
    #expect(alert.symbol == "binance/usd_m/BTCUSDT")
    #expect(alert.drawingID == "d-old" && alert.status == .paused && alert.armedAt == 123)
    #expect(try JSONDecoder().decode(Alert.self, from: JSONEncoder().encode(alert)) == alert)
    let spot = Alert(symbol: "coinbase/spot/BTC-USD", armedAt: 1, title: "提醒", created: 1)
    #expect(spot.market == "coinbase/spot")
    #expect(try JSONDecoder().decode(Alert.self, from: JSONEncoder().encode(spot)) == spot)
  }
}
