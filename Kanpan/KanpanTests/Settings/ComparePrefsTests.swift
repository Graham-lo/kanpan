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

  /// 币安上架过纯中文底名的合约（`币安人生USDT`）：自选、画线、提醒都收得下，对比也得收。
  /// 原来这里代号段只收 `A-Z 0-9 - _`，加进对比后下一次解码就被静默丢掉。
  @Test func chineseBaseSurvivesDecodeAndAddUsesTheSameRule() {
    let chinese = "binance/usd_m/币安人生USDT"
    var prefs = Prefs.defaults
    prefs.compareSymbols = [chinese, "coinbase/spot/BTC-USD"]
    #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)).compareSymbols == prefs.compareSymbols)

    // 超长（按字符数 41）、缺计价资产、小写、夹空格：解码逐个丢，剩下的照留。
    let tooLong = "binance/usd_m/" + String(repeating: "币", count: 37) + "USDT"
    prefs.compareSymbols = [tooLong, "binance/usd_m/币安人生", "binance/usd_m/币安人生usdt",
                            "binance/usd_m/币安 人生USDT", chinese, chinese, keys[0], keys[1], keys[2]]
    #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)).compareSymbols == [chinese, keys[0], keys[1]],
            "坏的逐个丢、重复只留一个、最多三只")

    // 添加走同一条规则（`#expect` 里不能直接调 mutating，先把结果接住）。
    var added = Prefs.defaults
    let tries: [(key: String, current: String?, ok: Bool, why: String)] = [
      (chinese, "binance/usd_m/BTCUSDT", true, "中文底名加得进去"),
      (chinese, nil, false, "已经在里面"),
      (tooLong, nil, false, "超长"),
      ("binance/usd_m/币安人生", nil, false, "缺计价资产"),
      ("binance/usd_m/ethusdt", nil, false, "小写"),
      ("binance/usd_m/ETH USDT", nil, false, "夹空格"),
      (keys[0], keys[0], false, "当前这只不对比自己"),
      (keys[0], nil, true, "第二只"),
      (keys[1], nil, true, "第三只"),
      (keys[2], nil, false, "满三只"),
    ]
    for attempt in tries {
      let ok = added.addCompareSymbol(attempt.key, current: attempt.current)
      #expect(ok == attempt.ok, "\(attempt.why)：\(attempt.key)")
    }
    #expect(added.compareSymbols == [chinese, keys[0], keys[1]])
    #expect(PrefsCodec.decode(PrefsCodec.encode(added)).compareSymbols == added.compareSymbols,
            "加得进去的，读回来一只不少")
  }
}
