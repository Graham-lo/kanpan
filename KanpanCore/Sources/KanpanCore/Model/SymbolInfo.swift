import Foundation

/// 品种。字段取自 `exchangeInfo`（§4.1）。
public struct SymbolInfo: Sendable, Equatable, Codable, Identifiable {
  public var symbol: String            // BTCUSDT
  public var base: String              // BTC
  public var quote: String             // USDT
  public var pricePrecision: Int
  public var quantityPrecision: Int
  public var tickSize: Double

  public var id: String { symbol }
  /// 顶栏和品种页里显示的名字：BTC/USDT。
  public var display: String { base + "/" + quote }

  public init(symbol: String, base: String, quote: String = "USDT",
              pricePrecision: Int, quantityPrecision: Int = 3, tickSize: Double) {
    self.symbol = symbol
    self.base = base
    self.quote = quote
    self.pricePrecision = pricePrecision
    self.quantityPrecision = quantityPrecision
    self.tickSize = tickSize
  }

  /// 价格按 `tickSize` 定小数位：0.1 → 1 位，0.001 → 3 位（§A1.11）。
  public var priceDecimals: Int {
    guard tickSize > 0 else { return pricePrecision }
    let d = Int((-log10(tickSize)).rounded())
    return max(0, min(12, d))
  }
}

/// 24h 行情（顶栏）。涨跌幅用币安的 `P` 字段，不自己算（§4.4）。
public struct Ticker: Sendable, Equatable {
  public var symbol: String
  public var last: Double
  public var changePercent: Double
  public var high: Double
  public var low: Double
  public var quoteVolume: Double
  public var markPrice: Double?

  public init(symbol: String, last: Double, changePercent: Double,
              high: Double, low: Double, quoteVolume: Double, markPrice: Double? = nil) {
    self.symbol = symbol
    self.last = last
    self.changePercent = changePercent
    self.high = high
    self.low = low
    self.quoteVolume = quoteVolume
    self.markPrice = markPrice
  }
}
