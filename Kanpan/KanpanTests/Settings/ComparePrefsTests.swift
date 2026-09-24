import Foundation
import Testing
@testable import Kanpan

@Suite("对比集合持久化") struct ComparePrefsTests {
  let keys = ["binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT", "binance/usd_m/DOGEUSDT"]

  @Test @MainActor func restartAndClearPersistAndAreSyncedFields() {
    let storage = InMemoryPrefsStorage(), store = PrefsStore(storage: InMemoryPrefsStorage())
    let saved = PrefsStore(storage: storage)
    saved.update { $0.compareSymbols = keys }
    #expect(PrefsStore(storage: storage).prefs.compareSymbols == keys)
    #expect(Prefs.syncedFieldNames.contains("compareSymbols"))
    #expect(store.prefs.compareSymbols.isEmpty)
    saved.update { $0.compareSymbols = [] }
    #expect(PrefsStore(storage: storage).prefs.compareSymbols.isEmpty)
  }

  @Test func malformedAndDuplicateIdentitiesCannotFillTheCollection() {
    var prefs = Prefs.defaults
    prefs.compareSymbols = ["ETHUSDT", "binance//ETHUSDT", "binance/usd_m/ethusdt", " binance/usd_m/ETHUSDT", keys[0], keys[0], keys[1], keys[2], "coinbase/spot/BTC-USD"]
    #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)).compareSymbols == keys)
    prefs.compareSymbols = ["coinbase/spot/BTC-USD"]
    #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)).compareSymbols == prefs.compareSymbols)
    #expect(PrefsCodec.decode(Data("{\"v\":2}".utf8)).compareSymbols.isEmpty)
  }
}
