import Foundation
import KanpanCore

// ============================================================ 假品种表
//
// 预览和单测共用的一份离线数据，形状照原型 data.js 的 `catalog` / `quote`：
//   catalog 行 = [symbol, base, quote, pricePrecision, tickSize]
//   quote 值   = [最新价, 涨跌幅%, 24h 成交额]
// 取的是原型快照（2026-09-14 币安合约）里的头几个，外加几个专门用来
// 试搜索名次的（ETHFI / ETHW 跟 ETH 撞前缀，1000PEPE 带数字前缀）。

enum SymbolFixtures {
  /// (symbol, base, pricePrecision, tickSize, last, changePercent, quoteVolume)
  private static let raw: [(String, String, Int, Double, Double, Double, Double)] = [
    ("BTCUSDT",     "BTC",      2, 0.10,     76_800.00, 1.24,  9.82e9),
    ("ETHUSDT",     "ETH",      2, 0.01,      2_913.45, -0.86, 4.11e9),
    ("SOLUSDT",     "SOL",      3, 0.001,       141.226, 3.07, 1.76e9),
    ("BNBUSDT",     "BNB",      2, 0.01,        612.30, 0.00,  6.40e8),
    ("XRPUSDT",     "XRP",      4, 0.0001,        2.1843, -2.15, 5.92e8),
    ("DOGEUSDT",    "DOGE",     5, 0.00001,       0.16204, 5.41, 4.03e8),
    ("1000PEPEUSDT", "1000PEPE", 7, 0.0000001,    0.0074812, -1.02, 2.88e8),
    ("ETHFIUSDT",   "ETHFI",    4, 0.0001,        1.2073, 0.42, 6.10e7),
    ("ETHWUSDT",    "ETHW",     4, 0.0001,        1.8840, -3.31, 1.20e7),
    ("BCHUSDT",     "BCH",      2, 0.01,        486.70, 0.71,  9.30e7),
    ("LTCUSDT",     "LTC",      2, 0.01,         92.14, -0.33, 8.80e7),
    ("AVAXUSDT",    "AVAX",     3, 0.001,        23.417, 1.88, 1.02e8),
  ]

  /// 品种表，顺序即「交易所给的顺序」（不是成交额序，正好用来验排序）。
  ///
  /// 这十二行都是币，所以照真实 `exchangeInfo` 那样带上 `underlyingType: "COIN"`——
  /// 缺这个字段就等于「不知道这是什么」，分类那一层不会再去猜（审查 B-04）。
  static let catalog: [SymbolInfo] = raw.map {
    SymbolInfo(symbol: $0.0, base: $0.1, pricePrecision: $0.2, tickSize: $0.3,
               underlyingType: "COIN")
  }

  /// 24h 行情快照。
  static let tickers: [Ticker] = raw.map {
    Ticker(symbol: $0.0, last: $0.4, changePercent: $0.5,
           high: $0.4 * 1.03, low: $0.4 * 0.97, quoteVolume: $0.6)
  }

  static func info(_ symbol: String) -> SymbolInfo {
    catalog.first { $0.symbol == symbol } ?? catalog[0]
  }
}
