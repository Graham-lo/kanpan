import Foundation

// 交易复盘的输入：交易所账户里的一笔成交、一条资金费。
//
// 用户 2026-09-27 定的方向：只读交易所 API「不是显示在上面，而是做成自动复盘，直接帮用户处理」。
// 所以这里的成交从不上主图，只拿来拼「回合」（`RoundBuilder`），每个回合变成一条交易复盘。
// 这一层只认交易所中立的字段；把某一家交易所的 JSON 翻成它，是 app 里那家交易所自己的事
// （`Kanpan/Kanpan/Exchange/<交易所>/`）。

/// 买卖方向，照交易所原样。
public enum TradeSide: String, Codable, Sendable, Hashable {
  case buy = "BUY"
  case sell = "SELL"

  /// 有符号变化量的符号：买 +、卖 −。单向、双向持仓都这么算——双向的空头仓就是负数。
  var sign: Decimal { self == .buy ? 1 : -1 }
}

/// 持仓方向。单向持仓只有 `.both`；双向持仓多空各记一本账。
public enum PositionSide: String, Codable, Sendable, Hashable, CaseIterable {
  case both = "BOTH"
  case long = "LONG"
  case short = "SHORT"
}

/// 回合的方向：这一回合开出来的是多仓还是空仓。
public enum TradeDirection: String, Codable, Sendable, Hashable, CaseIterable {
  case long
  case short
}

/// 累计净持仓的那本账：品种 + 持仓方向。
public struct PositionKey: Hashable, Codable, Sendable, CustomStringConvertible {
  public let symbol: String
  public let positionSide: PositionSide

  public init(symbol: String, positionSide: PositionSide) {
    self.symbol = symbol
    self.positionSide = positionSide
  }

  public var description: String { "\(symbol)|\(positionSide.rawValue)" }
}

/// 交易所账户里的一笔成交（已翻成交易所中立的字段）。
public struct Fill: Codable, Sendable, Hashable {
  /// 交易所成交 id（数字转字符串）。
  public let id: String
  public let orderId: String
  public let symbol: String
  /// 成交时间（毫秒）。
  public let time: Int64
  public let side: TradeSide
  public let positionSide: PositionSide
  public let price: Decimal
  /// 成交数量（正数）。
  public let qty: Decimal
  public let quoteQty: Decimal
  /// 手续费原值（正数 = 付出）。
  public let commission: Decimal
  public let commissionAsset: String
  /// 交易所算的已实现盈亏（开仓成交为 0）。
  public let realizedPnl: Decimal
  public let maker: Bool
  /// 保证金资产（U 本位合约通常是 USDT，也可能是 USDC）。回合的金额都以它计。
  public let marginAsset: String

  public init(id: String, orderId: String, symbol: String, time: Int64, side: TradeSide,
              positionSide: PositionSide, price: Decimal, qty: Decimal, quoteQty: Decimal? = nil,
              commission: Decimal, commissionAsset: String, realizedPnl: Decimal, maker: Bool,
              marginAsset: String) {
    self.id = id; self.orderId = orderId; self.symbol = symbol; self.time = time
    self.side = side; self.positionSide = positionSide; self.price = price; self.qty = qty
    self.quoteQty = quoteQty ?? (price * qty)
    self.commission = commission; self.commissionAsset = commissionAsset
    self.realizedPnl = realizedPnl; self.maker = maker; self.marginAsset = marginAsset
  }

  public var key: PositionKey { PositionKey(symbol: symbol, positionSide: positionSide) }

  /// 去重键：同一笔成交拉到两次只算一次。自成交时同一个 id 会有买、卖两条，所以带上方向。
  public var dedupeKey: String { "t|\(symbol)|\(id)|\(side.rawValue)" }

  /// 同一毫秒的成交按 id 的数值先后排（id 是数字字符串，先比长度再比字面）。
  static func chronological(_ a: Fill, _ b: Fill) -> Bool {
    if a.time != b.time { return a.time < b.time }
    if a.id.count != b.id.count { return a.id.count < b.id.count }
    if a.id != b.id { return a.id < b.id }
    return a.side == .sell && b.side == .buy  // 自成交：先卖后买，只是为了排序稳定
  }

  private enum CodingKeys: String, CodingKey {
    case id, orderId, symbol, time, side, positionSide, price, qty, quoteQty
    case commission, commissionAsset, realizedPnl, maker, marginAsset
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    orderId = try c.decode(String.self, forKey: .orderId)
    symbol = try c.decode(String.self, forKey: .symbol)
    time = try c.decode(Int64.self, forKey: .time)
    side = try c.decode(TradeSide.self, forKey: .side)
    positionSide = try c.decode(PositionSide.self, forKey: .positionSide)
    price = try c.decimal(.price)
    qty = try c.decimal(.qty)
    quoteQty = try c.decimal(.quoteQty)
    commission = try c.decimal(.commission)
    commissionAsset = try c.decode(String.self, forKey: .commissionAsset)
    realizedPnl = try c.decimal(.realizedPnl)
    maker = try c.decode(Bool.self, forKey: .maker)
    marginAsset = try c.decode(String.self, forKey: .marginAsset)
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(orderId, forKey: .orderId)
    try c.encode(symbol, forKey: .symbol)
    try c.encode(time, forKey: .time)
    try c.encode(side, forKey: .side)
    try c.encode(positionSide, forKey: .positionSide)
    try c.encodeDecimal(price, .price)
    try c.encodeDecimal(qty, .qty)
    try c.encodeDecimal(quoteQty, .quoteQty)
    try c.encodeDecimal(commission, .commission)
    try c.encode(commissionAsset, forKey: .commissionAsset)
    try c.encodeDecimal(realizedPnl, .realizedPnl)
    try c.encode(maker, forKey: .maker)
    try c.encode(marginAsset, forKey: .marginAsset)
  }
}

/// 一条资金费流水。`amount` 正数 = 收入、负数 = 支出（照交易所 income 的正负）。
public struct FundingEntry: Codable, Sendable, Hashable {
  /// 交易所流水 id（去重用）。
  public let id: String
  public let symbol: String
  /// 结算时刻（毫秒）。
  public let time: Int64
  public let amount: Decimal
  public let asset: String

  public init(id: String, symbol: String, time: Int64, amount: Decimal, asset: String) {
    self.id = id; self.symbol = symbol; self.time = time; self.amount = amount; self.asset = asset
  }

  public var dedupeKey: String { "f|\(symbol)|\(id)" }

  private enum CodingKeys: String, CodingKey { case id, symbol, time, amount, asset }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    symbol = try c.decode(String.self, forKey: .symbol)
    time = try c.decode(Int64.self, forKey: .time)
    amount = try c.decimal(.amount)
    asset = try c.decode(String.self, forKey: .asset)
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(symbol, forKey: .symbol)
    try c.encode(time, forKey: .time)
    try c.encodeDecimal(amount, .amount)
    try c.encode(asset, forKey: .asset)
  }
}
