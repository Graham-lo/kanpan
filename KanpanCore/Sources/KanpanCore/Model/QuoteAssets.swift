import Foundation

/// 计价资产：代号结尾那一截（`BTCUSDT` 的 `USDT`）。**客户端只此一份**。
///
/// 审查（2026-09-24 §2）点过名：这张表以前在 Swift 里抄了好几份——`SymbolInfo.placeholder`
/// 一份（没有 `USDD`，`XTUSD` 剥出来是 `XT`）、`SectorQuotePreference` 一份、板块取数与
/// 板块历史各自拿它再写一遍遍历。服务端那一份在 `Backend/kanpan-api/src/instruments.rs`。
///
/// 两端对的是同一份契约：`Backend/kanpan-api/contract/instruments.json`（手工维护，
/// 两端都不生成它；改表就先改它，再改两边的常量，两边的对账测试会逐项比）。
/// Swift 的对账在 `KanpanCoreTests/InstrumentContractTests`，Rust 的在
/// `instruments::tests::the_contract_file_is_what_both_sides_use`。
public enum QuoteAssets {
  /// 看盘交易、同步、分享时认的计价资产，**按偏好排序**：同一个 base 挂着好几张合约时
  /// 越靠前越该留下（板块页挑「首选合约」就按它）。对着 Rust `QUOTE_ASSETS`。
  public static let tradable = ["USDT", "USDC", "FDUSD", "BUSD", "USD1", "TUSD"]

  /// 从代号上剥计价资产时认的全部后缀，**长的、更具体的在前**（`FDUSD` 必须排在 `USD`
  /// 前面，否则 `ETHFDUSD` 会剥成 `ETHFD`）。比 `tradable` 多 `USDD` 与裸 `USD`：
  /// 它们不是币安 U 本位的计价资产，但供应量表、别家交易所的代号会带着。
  /// 对着 Rust `QUOTE_SUFFIXES`。
  static let suffixes = ["FDUSD", "BUSD", "TUSD", "USDT", "USDC", "USDD", "USD1", "USD"]

  /// 偏好档次：`tradable` 里的下标，表里没有的一律垫底（`tradable.count`）。
  public static func rank(_ quote: String) -> Int {
    tradable.firstIndex(of: quote.uppercased()) ?? tradable.count
  }

  /// 一个代号拆成 base 与计价资产，和 Rust `instruments::base` 同一口径：
  ///
  /// - 带分隔符的（现货 `BTC-USD` 这类）：横杠前后就是 base 与计价；横杠前面是空的
  ///   就是坏代号，原样返回、不给计价。
  /// - 否则按 `suffixes` 的顺序试，剥完还剩东西的第一个就是它（`USDTUSD` → `USD` + `TUSD`）。
  /// - 认不出计价资产、或者剥完什么都不剩（`USDT` 本身）：原样返回，不猜。
  ///
  /// 传进来的可以是完整品种 key（`binance/usd_m/BTCUSDT`），只看最后那一段。
  public static func split(_ symbol: String) -> (base: String, quote: String?) {
    let s = InstrumentID(symbol).symbol
    if let dash = s.firstIndex(of: "-") {
      let base = String(s[..<dash])
      return base.isEmpty ? (s, nil) : (base, String(s[s.index(after: dash)...]))
    }
    for quote in suffixes where s.hasSuffix(quote) && s.count > quote.count {
      return (String(s.dropLast(quote.count)), quote)
    }
    return (s, nil)
  }

  /// `split` 的 base 那一半。
  public static func base(of symbol: String) -> String { split(symbol).base }

  /// 只按**可交易**的计价资产拆：板块页拿行情里的代号挑首选合约时用——`USDD` / 裸 `USD`
  /// 结尾的不是币安合约，不该和同一个 base 的 USDT 合约抢位子。拆不出来的 rank 垫底。
  ///
  /// `tradable` 里没有哪一项以另一项结尾，所以按偏好顺序试和按长度试结果一样。
  public static func tradableSplit(_ symbol: String) -> (base: String, rank: Int) {
    for (index, quote) in tradable.enumerated() where symbol.hasSuffix(quote) && symbol.count > quote.count {
      return (String(symbol.dropLast(quote.count)), index)
    }
    return (symbol, tradable.count)
  }
}
