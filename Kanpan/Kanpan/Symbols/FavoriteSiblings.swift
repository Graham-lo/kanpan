import Foundation
import KanpanCore
import KanpanNetwork

// ============================================================ 同一个品种的几条挨着放
//
// 用户 2026-10-07 定的：加自选时，如果自选里已经有**同一个底层品种**在别家交易所
// （或别的市场、别的计价）的那一条——币安 BTC 永续在，再加 Coinbase 的 BTC 现货——
// 新加的那条就挨着它放、归进它那一类，不追加到最末；几条挨在一起才方便对比。
// 并且**现货排在最前面**：现货先、永续跟在后面。
//
// 「同一个底层品种」只看 base（`SymbolAliases.key`：1000PEPE 和 PEPE 算同一个）；
// 品种键不同（交易所 / 市场 / 代号任一不同）才算另一条。
//
// 这一层是纯的：给一份自选顺序和一个「代号 → base」的查法，算出该插在第几位、挨着谁。
// 落盘、分类、重排在 `SymbolPickerModel.addFavorite` / `seedFavorites`。

enum FavoriteSiblings {
  /// 这条品种的底层名。目录里有它就按目录的 `base`，没有就按代号拆（`SymbolInfo.placeholder`）。
  static func base(of symbol: String, info: SymbolInfo?) -> String {
    SymbolAliases.key((info ?? SymbolInfo.placeholder(symbol: symbol)).base)
  }

  /// 现货排在最前面：现货 0，其余 1。
  static func rank(_ symbol: String) -> Int {
    InstrumentID(symbol).market == CoinbaseProvider.market ? 0 : 1
  }

  /// 新加的 `symbol` 该插在 `favorites` 的第几位、挨着哪一条。自选里没有它的同品种就返回 nil
  /// （照旧追加到最末）。现货插在第一条同品种**前面**；其余插在最后一条同品种**后面**。
  static func insertion(of symbol: String, base: String, in favorites: [String],
                        baseOf: (String) -> String) -> (index: Int, neighbor: String)? {
    let siblings = favorites.indices.filter { favorites[$0] != symbol && baseOf(favorites[$0]) == base }
    guard let first = siblings.first, let last = siblings.last else { return nil }
    if rank(symbol) == 0 { return (first, favorites[first]) }
    return (last + 1, favorites[last])
  }

  /// 把挨在一起的同品种那几条按「现货在前」重排（稳定：同档的相对顺序不动）。
  /// 只动**已经挨在一起**的——用户自己拆开摆的两条不碰。返回重排后的顺序。
  static func spotFirst(_ favorites: [String], baseOf: (String) -> String) -> [String] {
    var out: [String] = []
    out.reserveCapacity(favorites.count)
    var run: [String] = []
    var runBase = ""
    func flush() {
      if run.count > 1 {
        let ranked = run.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
        out.append(contentsOf: ranked.map(\.element))
      } else {
        out.append(contentsOf: run)
      }
      run.removeAll(keepingCapacity: true)
    }
    for symbol in favorites {
      let b = baseOf(symbol)
      if !run.isEmpty, b != runBase { flush() }
      runBase = b
      run.append(symbol)
    }
    flush()
    return out
  }
}
