import Testing

@testable import KanpanCore

/// `InstrumentID.isSyncIdentity` / `isSyncKey` 逐条对着服务端
/// `sync_validation::identity` 与 `compare_key`（Rust 那边的同名用例是
/// `compare_symbols_follow_the_favorites_symbol_rule`，这里的夹具照它抄）。
@Suite("品种同步身份：和服务端 identity 同一条规则")
struct InstrumentSyncIdentityTests {
  @Test("中文底名的币安合约、各计价资产、Coinbase 现货都收")
  func accepts() {
    for good in ["binance/usd_m/币安人生USDT", "binance/usd_m/我踏马来了USDT", "binance/usd_m/1000币USDC",
                 "binance/usd_m/SPCXUSD1", "binance/usd_m/ETHUSDT", "binance/usd_m/ETHFDUSD",
                 "coinbase/spot/BTC-USD", "coinbase/spot/1INCH-USD"] {
      #expect(InstrumentID.isSyncKey(good), "\(good) 应该收")
    }
    #expect(InstrumentID.isSyncIdentity(venue: "binance", market: "usd_m", symbol: "币安人生USDT"))
  }

  @Test("代号最长 40 个字符，按字符数不按字节")
  func lengthIsInCharacters() {
    let longest = "binance/usd_m/" + String(repeating: "币", count: 36) + "USDT"
    #expect(longest.utf8.count <= InstrumentID.syncKeyMaxBytes)
    #expect(InstrumentID.isSyncKey(longest))
    #expect(!InstrumentID.isSyncKey("binance/usd_m/" + String(repeating: "币", count: 37) + "USDT"))
    #expect(!InstrumentID.isSyncKey("binance/usd_m/" + String(repeating: "A", count: 37) + "USDT"))
    #expect(InstrumentID.isSyncKey("binance/usd_m/" + String(repeating: "A", count: 36) + "USDT"))
  }

  @Test("缺底名、缺计价资产、小写、夹空格或横杠、表情、认不得的市场都拒")
  func refuses() {
    for bad in ["binance/usd_m/USDT", "binance/usd_m/币安人生", "binance/usd_m/币安人生usdt",
                "binance/usd_m/ethusdt", "binance/usd_m/币安 人生USDT", "binance/usd_m/ETH USDT",
                "binance/usd_m/币安-人生USDT", "binance/usd_m/😀USDT", "binance/usd_m/BTCUSD_PERP",
                "binance/usd_m/BTCUSDT_251226", "binance/usd_m/ETHUSDD",
                "coinbase/spot/-USD", "coinbase/spot/币安-USD", "coinbase/spot/btc-USD", "coinbase/spot/BTCUSDT",
                "future/spot/ABC", "binance/spot/BTCUSDT", "coinbase/usd_m/BTC-USD", "BINANCE/usd_m/ETHUSDT",
                " binance/usd_m/ETHUSDT", "binance/usd_m/ETHUSDT ", "binance//ETHUSDT", "ETHUSDT",
                "binance/usd_m/ETHUSDT/x", "binance/usd_m/", ""] {
      #expect(!InstrumentID.isSyncKey(bad), "\(bad) 应该拒")
    }
  }
}
