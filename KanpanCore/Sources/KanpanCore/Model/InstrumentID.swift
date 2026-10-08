import Foundation

/// Stable identity, independent of the route used to retrieve a market.
/// Bare identifiers are accepted only for backwards compatibility with pre-v2 archives.
public struct InstrumentID: Hashable, Codable, Sendable, CustomStringConvertible {
  public let venue: String
  public let market: String
  public let symbol: String
  public var key: String { "\(venue)/\(market)/\(symbol)" }
  public var description: String { key }
  public var marketKey: String { "\(venue)/\(market)" }
  /// 给人看的代号：交易所代号里的 `-` 分隔（`BTC-USD`）显示成 `BTC/USD`，
  /// 没有分隔的（`BTCUSDT`）原样。存储、请求、文件名一律用 `symbol`，不用它。
  public var display: String { symbol.replacingOccurrences(of: "-", with: "/") }

  /// 裸代号（v2 之前的存档、老客户端、老服务端字段缺省）一律算这一家的这个市场。
  ///
  /// **客户端只此一份**：`"binance/usd_m"` 这串字面量以前在 Core、数据层、复盘、提醒里
  /// 各写一遍（审查 2026-09-24 §2）。它必须等于默认交易所的 `VenueRegistry.default.marketKey`
  /// （`KanpanNetworkTests` 钉着），也必须等于服务端 `instruments::DEFAULT_MARKET_KEY`
  /// ——两端都对着 `Backend/kanpan-api/contract/instruments.json` 的 `defaultMarket`。
  public static let defaultVenue = "binance"
  public static let defaultMarket = "usd_m"
  /// `defaultVenue/defaultMarket`：提醒同步对象里那种「整串」写法的 market。
  public static let defaultMarketKey = defaultVenue + "/" + defaultMarket

  /// 是默认交易所的默认市场（老的裸代号存档只可能落在这里）。
  public var isDefaultMarket: Bool { marketKey == Self.defaultMarketKey }

  public init(venue: String, market: String, symbol: String) {
    self.venue = venue.lowercased()
    self.market = market.lowercased()
    self.symbol = symbol.uppercased()
  }

  public init(_ legacyOrKey: String) {
    let parts = legacyOrKey.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: false)
    if parts.count == 3 {
      self.init(venue: String(parts[0]), market: String(parts[1]), symbol: String(parts[2]))
    } else {
      self.init(venue: Self.defaultVenue, market: Self.defaultMarket, symbol: legacyOrKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  public var isValid: Bool {
    func component(_ s: String, extra: String) -> Bool {
      !s.isEmpty && s.count <= 64 && s.utf8.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || extra.utf8.contains($0)
      }
    }
    return component(venue, extra: "_") && component(market, extra: "_") && component(symbol, extra: "-_")
  }

  // MARK: - 同步身份规则（对着服务端 `sync_validation::identity`）

  /// 代号段最长多少个字符——按 Unicode 标量数，不按字节（中文一个字三个字节）。
  /// 对着 Rust `SYMBOL_MAX_CHARS`。
  public static let syncSymbolMaxChars = 40
  /// 整串 `venue/market/SYMBOL` 切分之前的粗上限（字节）。对着 Rust `compare_key` 里的 128：
  /// 合法键最长 `binance/usd_m/` + 36 个汉字 + `USDT` = 126 字节。
  public static let syncKeyMaxBytes = 128

  /// 服务端认不认这只品种：**客户端只此一份**，逐条对着 Rust
  /// `Backend/kanpan-api/src/sync_validation.rs` 的 `identity(venue, market, symbol)`——
  /// 自选、画线、提醒、对比 K 线在服务端都走那一条，客户端要预先挡住的也只能是那一条。
  ///
  /// - `binance/usd_m`：最长 40 个字符；每个字符是 ASCII 大写、数字，或**非 ASCII 的
  ///   Unicode 字母数字**（币安上架过 `币安人生USDT` 这类中文底名合约）；必须以
  ///   `QuoteAssets.tradable` 里的一个计价资产结尾，前面还得有底名。ASCII 小写不收
  ///   （币安代号永远是大写，小写只会是拼错了）。
  /// - `coinbase/spot`：`BASE-USD`，BASE 只有 ASCII 大写与数字。
  /// - `macro/index`：只有 `DXY`（美元指数，2026-10-05）。服务端只采得到这一只，
  ///   不开放成「任意大写」——收下了也永远没价、判不响。
  /// - 别的交易所 / 市场、大小写不对的交易所名：一律不收。
  ///
  /// 不做任何规范化：传进来什么就判什么（`InstrumentID.init` 会把小写代号抬成大写，
  /// 那是另一回事，这里要的是「这串原样发上去服务端收不收」）。
  public static func isSyncIdentity(venue: String, market: String, symbol: String) -> Bool {
    switch (venue, market) {
    case ("binance", "usd_m"): return isQuoteSuffixedSymbol(symbol)
    // OKX / Bybit 的 U 本位永续在看盘里用币安形状的键（`BTCUSDT`，服务端 `okx::symbol_ok` / `bybit::symbol_ok`：
    // 大写字母数字 5–40 个、以 USDT 结尾）。
    case ("okx", "usd_m"), ("bybit", "usd_m"): return isUSDTPerpSymbol(symbol)
    // Hyperliquid 的键是 coin 名大写（`BTC`、`KPEPE`，服务端 `hyperliquid::symbol_ok`：大写字母数字 1–16 个）。
    case ("hyperliquid", "usd_m"): return isUpperAlnum(symbol, 1...16)
    case ("coinbase", "spot"): return isDashUSDSymbol(symbol)
    case ("macro", "index"): return symbol == "DXY"
    default: return false
    }
  }

  /// 整串 `venue/market/SYMBOL` 版的 `isSyncIdentity`，和 Rust `compare_key` 同一个切法：
  /// 只切前两刀，第三段里再有 `/` 就留在代号里（代号规则会拒它）。
  public static func isSyncKey(_ key: String) -> Bool {
    guard key.utf8.count <= syncKeyMaxBytes else { return false }
    let parts = key.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3 else { return false }
    return isSyncIdentity(venue: String(parts[0]), market: String(parts[1]), symbol: String(parts[2]))
  }

  /// 文法一：底名 + `QuoteAssets.tradable` 里的计价资产（大写 ASCII / 数字 / 非 ASCII 字母数字）。
  private static func isQuoteSuffixedSymbol(_ s: String) -> Bool {
    let scalars = s.unicodeScalars
    guard scalars.count <= syncSymbolMaxChars,
      // 后缀按标量比，不按 `Character`：Rust `strip_suffix` 是逐字节比的，结合符挨着计价资产时
      // 字素簇会把两边判得不一样。
      QuoteAssets.tradable.contains(where: { quote in
        let q = quote.unicodeScalars
        return scalars.count > q.count && scalars.suffix(q.count).elementsEqual(q)
      })
    else { return false }
    return scalars.allSatisfy { c in
      if c.isASCII { return (65...90).contains(c.value) || (48...57).contains(c.value) }
      // Rust `char::is_alphanumeric` = Alphabetic 或 Numeric（Nd / Nl / No）。
      switch c.properties.generalCategory {
      case .decimalNumber, .letterNumber, .otherNumber: return true
      default: return c.properties.isAlphabetic
      }
    }
  }

  /// 文法三（OKX / Bybit 的 U 本位永续）：ASCII 大写字母数字 5–40 个、以 `USDT` 结尾、底名非空。
  /// 对着 Rust `venues::okx::symbol_ok` / `venues::bybit::symbol_ok`（`upper_alnum(5..=40)` + `strip_suffix("USDT")`）。
  private static func isUSDTPerpSymbol(_ s: String) -> Bool {
    isUpperAlnum(s, 5...40) && s.hasSuffix("USDT") && s.utf8.count > 4
  }

  /// ASCII 大写字母数字、长度在 `range` 内。对着 Rust `venues::upper_alnum`。
  private static func isUpperAlnum(_ s: String, _ range: ClosedRange<Int>) -> Bool {
    range.contains(s.utf8.count) && s.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
  }

  /// 文法二：`BASE-USD`，BASE 只有 ASCII 大写与数字。
  private static func isDashUSDSymbol(_ s: String) -> Bool {
    guard s.utf8.count <= syncSymbolMaxChars, s.hasSuffix("-USD") else { return false }
    let base = s.utf8.dropLast(4)
    return !base.isEmpty && base.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
  }

  public static func canonical(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : InstrumentID(value).key
  }

  /// Canonical keys win over an equivalent legacy alias; unrelated markets never collide.
  public static func migrate<Value>(_ values: [String: Value]) -> [String: Value] {
    var output: [String: Value] = [:]
    for key in values.keys.sorted(by: { ($0.contains("/") ? 1 : 0, $0) < ($1.contains("/") ? 1 : 0, $1) }) {
      output[canonical(key)] = values[key]
    }
    return output
  }
}
