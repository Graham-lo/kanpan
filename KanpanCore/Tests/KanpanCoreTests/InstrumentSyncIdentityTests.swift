import Foundation
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

  @Test("OKX / Bybit 的 U 本位永续是币安形状的 USDT 代号，Hyperliquid 是大写 coin 名；形状不对的拒")
  func otherVenues() {
    for good in ["okx/usd_m/BTCUSDT", "okx/usd_m/1000PEPEUSDT", "bybit/usd_m/BTCUSDT", "bybit/usd_m/1000PEPEUSDT",
                 "hyperliquid/usd_m/BTC", "hyperliquid/usd_m/KPEPE", "hyperliquid/usd_m/HYPE"] {
      #expect(InstrumentID.isSyncKey(good), "\(good) 应该收")
    }
    for bad in ["okx/usd_m/BTC-USDT-SWAP", "okx/usd_m/BTCUSDC", "okx/usd_m/USDT", "okx/usd_m/btcusdt", "okx/spot/BTCUSDT",
                "bybit/usd_m/币安人生USDT", "bybit/usd_m/BTC-USDT", "bybit/linear/BTCUSDT",
                "hyperliquid/usd_m/kPEPE", "hyperliquid/usd_m/BTC-USD", "hyperliquid/usd_m/", "hyperliquid/usd_m/" + String(repeating: "A", count: 17),
                "hyperliquid/spot/BTC"] {
      #expect(!InstrumentID.isSyncKey(bad), "\(bad) 应该拒")
    }
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

/// 三端交叉契约：`Backend/kanpan-api/contract/venue-identity-cases.json`。服务端
/// `sync_validation::venue_identity_contract_cases`、网页 `venue-identity-contract.test.ts` 读同一份；
/// 任何一边单改代号规则，自己这一侧就红。
@Suite("品种身份三端契约（venue-identity-cases.json）")
struct VenueIdentityContractTests {
  struct Cases: Decodable { var accept: [String]; var reject: [String] }

  static func load() throws -> Cases {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("Backend/kanpan-api/contract/venue-identity-cases.json")
    return try JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
  }

  @Test("accept 每条都收")
  func accepts() throws {
    let c = try Self.load()
    #expect(c.accept.count >= 10)
    for key in c.accept { #expect(InstrumentID.isSyncKey(key), "\(key) 三端都该收") }
  }

  @Test("reject 每条都拒")
  func rejects() throws {
    let c = try Self.load()
    #expect(c.reject.count >= 10)
    for key in c.reject { #expect(!InstrumentID.isSyncKey(key), "\(key) 三端都该拒") }
  }

  @Test("两张表不重叠，六家都有收有拒（契约本身没写歪）")
  func coverage() throws {
    let c = try Self.load()
    #expect(Set(c.accept).isDisjoint(with: c.reject))
    for venue in ["binance", "okx", "bybit", "hyperliquid", "coinbase", "macro"] {
      #expect(c.accept.contains { $0.hasPrefix(venue + "/") }, "\(venue) 缺 accept 用例")
    }
    for venue in ["okx", "bybit", "hyperliquid", "coinbase", "macro"] {
      #expect(c.reject.contains { $0.hasPrefix(venue + "/") }, "\(venue) 缺 reject 用例")
    }
  }
}
