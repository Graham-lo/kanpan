import Foundation
import Testing
import KanpanCore
@testable import KanpanSymbols

@Suite("自选 v1 到 v2") @MainActor struct InstrumentMigrationTests {
  @Test func migrationRetainsEveryUserFieldAndOriginal() throws {
    let json = Data(#"{"favorites":["BTCUSDT","ETHUSDT"],"recents":["ETHUSDT","BTCUSDT"],"groups":[{"id":"g","name":"原分类"}],"groupForSymbol":{"BTCUSDT":"g"},"pinned":["ETHUSDT"],"viewScores":{"BTCUSDT":7},"scoredAt":123}"#.utf8)
    let storage = MemoryPrefsStorage([SymbolPrefsStore.legacyDefaultsKey: json])
    let store = SymbolPrefsStore(storage: storage)
    let p = try store.read()
    #expect(p.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(p.recents == Array(p.favorites.reversed()))
    #expect(p.groupForSymbol["binance/usd_m/BTCUSDT"] == "g")
    #expect(p.pinned == ["binance/usd_m/ETHUSDT"])
    #expect(p.viewScores["binance/usd_m/BTCUSDT"] == 7 && p.scoredAt == 123)
    store.save(p)
    #expect(try store.read() == p)
    #expect(storage.raw[SymbolPrefsStore.legacyDefaultsKey] == json)
    #expect(storage.raw[SymbolPrefsStore.defaultsKey] != nil)
    store.clear()
    #expect(try store.read().favorites.isEmpty)
  }
}
