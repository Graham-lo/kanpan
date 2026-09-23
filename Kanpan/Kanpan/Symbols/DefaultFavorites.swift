import Foundation
import KanpanCore

// ============================================================ 默认自选
//
// 第一次打开这个 app 的人看到的是一张空的自选页：没有账号、没有收藏，
// 底栏点「自选」进去只有一句空话。他还什么都没做，凭什么要先替他挑品种？
// ——因为没得挑的那一页什么都教不了他（方案第 3 节第四件）。
//
// 给的是 **BTC、ETH、SOL ＋ 当日 24h 成交额前五的币**，去重后八条上下。
// 前三个是锚：不管今天谁在涨，这三个总在。后五个是「今天大家在看什么」。
//
// 两条界限：
//
// · **非币的合约不算**（记忆 kanpan-not-every-contract-is-a-coin）。那张合约表里
//   有三分之一是美股、ETF、黄金、指数，成交额榜前列常年混着 TSLA、XAU 这种。
//   新人的第一页自选不该是这些——判据只认目录里的 `underlyingType == "COIN"`
//   （`SymbolClassifier`），字段缺了就当它不是币，不猜。
// · **一个币只占一行**。`BTCUSDT` 和 `BTCUSDC`、`1000PEPE` 和 `PEPE` 是同一个币的
//   不同合约，按 base 去重，先来的那条留下。
//
// 这一层是纯的：给目录和一份行情，算出该摆哪几条。什么时候摆、摆过没有、
// 摆完还回不回来，在 `DefaultFavoritesSeeder`（那边要碰 UserDefaults 和网络）。

enum DefaultFavorites {
  /// 不管行情怎么样都要有的三条，顺序就是摆出来的顺序。
  static let anchors = ["BTC", "ETH", "SOL"]

  /// 锚之外再按成交额取几条。
  static let hotCount = 5

  /// 算出第一次该给的自选（`SymbolInfo.symbol` 的大写形式，已按摆放顺序排好）。
  ///
  /// - Parameters:
  ///   - catalog: 合约目录。
  ///   - tickers: 全市场 24h 行情。取不到就传空数组——那时只有三个锚，
  ///     总比一页空白强。
  static func pick(catalog: [SymbolInfo], tickers: [Ticker]) -> [String] {
    let coins = catalog.filter { $0.status == .tradable && SymbolClassifier.classify($0).asset == .crypto }
    guard !coins.isEmpty else { return [] }

    // base → 该币用哪一条合约。同一个币有多条时选成交额最大的那条
    // （`BTCUSDT` 一定比 `BTCUSDC` 大），没有行情就按代号短的那条。
    let volume = Dictionary(tickers.map { (InstrumentID.canonical($0.symbol), $0.quoteVolume) },
                            uniquingKeysWith: { a, _ in a })
    var pickOf: [String: SymbolInfo] = [:]
    for info in coins {
      let base = self.base(info)
      guard let old = pickOf[base] else { pickOf[base] = info; continue }
      let new = volume[InstrumentID.canonical(info.symbol)] ?? 0
      let had = volume[InstrumentID.canonical(old.symbol)] ?? 0
      if new > had || (new == had && info.symbol.count < old.symbol.count) { pickOf[base] = info }
    }

    var out: [String] = []
    var taken = Set<String>()
    func take(_ base: String) {
      guard let info = pickOf[base], taken.insert(base).inserted else { return }
      out.append(InstrumentID.canonical(info.symbol))
    }

    for base in anchors { take(base) }

    // 成交额榜：按 base 归并之后再排，免得同一个币的两条合约占掉两个名额。
    var hot: [(base: String, volume: Double)] = []
    hot.reserveCapacity(pickOf.count)
    for (base, info) in pickOf {
      let v: Double = volume[InstrumentID.canonical(info.symbol)] ?? 0
      guard v > 0 else { continue }
      hot.append((base: base, volume: v))
    }
    hot.sort { $0.volume == $1.volume ? $0.base < $1.base : $0.volume > $1.volume }
    for row in hot {
      guard out.count < anchors.count + hotCount else { break }
      take(row.base)
    }
    return out
  }

  /// 合约代号里的币。倍数前缀（`1000PEPE`、`1MBABYDOGE`）不是名字的一部分，
  /// 不然 `PEPE` 和 `1000PEPE` 会各占一行——剥法只有 `SymbolAliases.key` 一份。
  private static func base(_ info: SymbolInfo) -> String { SymbolAliases.key(info.base) }
}
