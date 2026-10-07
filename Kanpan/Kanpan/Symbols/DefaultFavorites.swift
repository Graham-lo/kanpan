import Foundation
import KanpanCore
import KanpanNetwork

// ============================================================ 默认自选
//
// 第一次打开这个 app 的人看到的是一张空的自选页：底栏点「自选」进去只有一句空话。
// 他还什么都没做，凭什么要先替他挑品种？——因为没得挑的那一页什么都教不了他
// （方案第 3 节第四件）。
//
// 2026-10-07 用户定的名单，访客和登录账号**一模一样**，分两类：
//
// · 「加密」：
//   1. **黄金、白银摆在最上面**（XAU / XAG）。它们照交易所是贵金属，但用户要它们
//      直接跟加密放在一起看，所以这两条明着归进「加密」，不按资产类型开「贵金属」。
//   2. **BTC、ETH、SOL、XRP、DOGE、ZEC 各两条**：Coinbase 现货（`coinbase/spot/BTC-USD`）
//      在前，紧跟着它的币安永续——现货和永续挨着，一眼就能对比；现货排前面是用户
//      2026-10-07 定的「一般来说现货放最前面」（`FavoriteSiblings`）。
//      Coinbase 那条不在币安目录里，六个都核对过在线，直接按代号给。
//   3. 再加当日 24h 成交额前五、还没占上的币。
// · 「美股」：NVDA、QQQ、SOXL、SK 海力士两条（SKHY 是 ADR、SKHYNIX 是韩股）、美光、
//   闪迪、MRVL、ARM、SPCX、INTC、AVGO，按这个顺序。目录里没有的那条就跳过，不报错。
//
// 两条界限照旧：
//
// · **成交额榜只认币**（记忆 kanpan-not-every-contract-is-a-coin）。合约表里有三分之一
//   是美股、ETF、黄金、指数，成交额榜前列常年混着 TSLA、XAU；它们只能按上面点名的
//   名单进来，不能靠成交额挤进「加密」——判据只认 `SymbolClassifier`（`underlyingType`），
//   字段缺了就当它不是币，不猜。
// · **一个币只占一行合约**。`BTCUSDT` 和 `BTCUSDC`、`1000PEPE` 和 `PEPE` 是同一个币的
//   不同合约，按 base 去重，留成交额大的那条。
//
// 这一层是纯的：给目录和一份行情，算出该摆哪几条、各归哪一类。什么时候摆、摆过没有、
// 怎么并进已有的自选，在 `DefaultFavoritesSeeder` 与 `SymbolPickerModel.seedFavorites`。

enum DefaultFavorites {
  /// 一条默认自选：品种键，以及它该落进哪一类（分类名）。
  struct Entry: Equatable, Sendable {
    let symbol: String
    let group: String
  }

  static let cryptoGroup = "加密"
  static let usGroup = "美股"

  /// 摆在「加密」最上面的贵金属，顺序就是摆出来的顺序。
  static let metals = ["XAU", "XAG"]
  /// Coinbase 现货在前、币安永续紧跟的那几个币，顺序就是摆出来的顺序。
  static let pairedCoins = ["BTC", "ETH", "SOL", "XRP", "DOGE", "ZEC"]
  /// 「美股」那一类，顺序就是摆出来的顺序。底名对着币安目录的 `base`。
  static let usEquities = ["NVDA", "QQQ", "SOXL", "SKHY", "SKHYNIX", "MU", "SNDK",
                           "MRVL", "ARM", "SPCX", "INTC", "AVGO"]
  /// 点名的币之外再按成交额取几条。
  static let hotCount = 5

  /// Coinbase 现货的品种键（`coinbase/spot/BTC-USD`）。只收美元计价（记忆 kanpan-coinbase-spot-only）。
  static func coinbaseSpot(_ base: String) -> String {
    InstrumentID(venue: CoinbaseProvider.venue, market: CoinbaseProvider.market,
                 symbol: base.uppercased() + "-USD").key
  }

  /// 算出该给的默认自选，已按摆放顺序排好、去过重。
  ///
  /// - Parameters:
  ///   - catalog: 合约目录。空的就什么都不给——调用方接着等目录。
  ///   - tickers: 全市场 24h 行情。取不到就传空数组——那时没有成交额榜，
  ///     点名的那几条照样给（同一个底名有几条合约时退回代号短的那条）。
  static func pick(catalog: [SymbolInfo], tickers: [Ticker]) -> [Entry] {
    guard !catalog.isEmpty else { return [] }
    // 只挑默认交易所的合约（币安永续）：目录里要是混进了别家的行（Coinbase 现货、美元指数），
    // 按底名挑「成交额最大那条」时不能让它顶掉永续——现货那条下面另外按代号给。
    let tradable = catalog.filter { $0.status == .tradable && $0.id.isDefaultMarket }
    let volume = Dictionary(tickers.map { (InstrumentID.canonical($0.symbol), $0.quoteVolume) },
                            uniquingKeysWith: { a, _ in a })

    // 底名 → 该用哪一条合约。同一个底名有多条时选成交额最大的那条
    // （`BTCUSDT` 一定比 `BTCUSDC` 大），没有行情就按代号短的那条。
    func best(_ rows: [SymbolInfo], by base: (SymbolInfo) -> String) -> [String: SymbolInfo] {
      var out: [String: SymbolInfo] = [:]
      for info in rows {
        let key = base(info)
        guard let old = out[key] else { out[key] = info; continue }
        let new = volume[InstrumentID.canonical(info.symbol)] ?? 0
        let had = volume[InstrumentID.canonical(old.symbol)] ?? 0
        if new > had || (new == had && info.symbol.count < old.symbol.count) { out[key] = info }
      }
      return out
    }
    let coins = best(tradable.filter { SymbolClassifier.classify($0).asset == .crypto }, by: coinBase)
    let metalRows = best(tradable.filter { SymbolClassifier.classify($0).asset == .preciousMetal },
                         by: { $0.base.uppercased() })
    // 韩股（SKHYNIX 是 `KR_EQUITY`）也在这一类里，所以只问是不是股票、不问地区。
    let equityRows = best(tradable.filter { SymbolClassifier.classify($0).asset == .equity },
                          by: { $0.base.uppercased() })

    var out: [Entry] = []
    var seen = Set<String>()
    func add(_ symbol: String, _ group: String) {
      guard seen.insert(symbol).inserted else { return }
      out.append(Entry(symbol: symbol, group: group))
    }

    for base in metals { if let info = metalRows[base] { add(info.symbol, cryptoGroup) } }

    // 点名的币算「已经占上了」，不管币安那条在不在——Coinbase 那条总在。
    var taken = Set<String>()
    for base in pairedCoins {
      let key = SymbolAliases.key(base)
      taken.insert(key)
      add(coinbaseSpot(base), cryptoGroup)
      if let info = coins[key] { add(info.symbol, cryptoGroup) }
    }

    // 成交额榜：按 base 归并之后再排，免得同一个币的两条合约占掉两个名额。
    var hot: [(base: String, volume: Double)] = []
    hot.reserveCapacity(coins.count)
    for (base, info) in coins where !taken.contains(base) {
      let v: Double = volume[InstrumentID.canonical(info.symbol)] ?? 0
      guard v > 0 else { continue }
      hot.append((base: base, volume: v))
    }
    hot.sort { $0.volume == $1.volume ? $0.base < $1.base : $0.volume > $1.volume }
    for row in hot.prefix(hotCount) {
      if let info = coins[row.base] { add(info.symbol, cryptoGroup) }
    }

    for base in usEquities { if let info = equityRows[base] { add(info.symbol, usGroup) } }
    return out
  }

  /// 合约代号里的币。倍数前缀（`1000PEPE`、`1MBABYDOGE`）不是名字的一部分，
  /// 不然 `PEPE` 和 `1000PEPE` 会各占一行——剥法只有 `SymbolAliases.key` 一份。
  private static func coinBase(_ info: SymbolInfo) -> String { SymbolAliases.key(info.base) }
}
