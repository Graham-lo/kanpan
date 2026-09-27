import CryptoKit
import Foundation

// 回合 = 某品种某持仓方向的仓位从 0 建起、到回到 0（或反手穿过 0）为止。
// 每个回合是一条「交易复盘」：用户不用填任何字段，只可以补一句「当时怎么想」。
// JSON 形状是和服务端对账的唯一口径，见 `docs/交易复盘-协议-2026-09-27.md` 第 2 节；
// 这里改一个字段，同一次改动里先改那份文档。

public enum TradeRoundStatus: String, Codable, Sendable, Hashable {
  /// 持仓中：结果留空，平仓后补齐。
  case open
  case closed
}

/// 回合里一笔成交在这一回合中扮演的角色；复盘图上标开 / 加 / 减 / 平用。
public enum FillRole: String, Codable, Sendable, Hashable {
  case open, add, reduce, close
}

/// 回合里的一笔成交。反手时一笔成交会被拆成两半，分别出现在前后两个回合里（`split = true`）。
public struct RoundFill: Codable, Sendable, Hashable {
  public let id: String
  public let orderId: String
  public let time: Int64
  public let side: TradeSide
  public let positionSide: PositionSide
  public let price: Decimal
  /// 计入这一回合的数量（拆分后的那一部分）。
  public let qty: Decimal
  public let quoteQty: Decimal
  public let commission: Decimal
  public let commissionAsset: String
  public let realizedPnl: Decimal
  public let maker: Bool
  public let role: FillRole
  public let split: Bool

  public init(id: String, orderId: String, time: Int64, side: TradeSide, positionSide: PositionSide,
              price: Decimal, qty: Decimal, quoteQty: Decimal, commission: Decimal, commissionAsset: String,
              realizedPnl: Decimal, maker: Bool, role: FillRole, split: Bool) {
    self.id = id; self.orderId = orderId; self.time = time; self.side = side
    self.positionSide = positionSide; self.price = price; self.qty = qty; self.quoteQty = quoteQty
    self.commission = commission; self.commissionAsset = commissionAsset; self.realizedPnl = realizedPnl
    self.maker = maker; self.role = role; self.split = split
  }

  private enum CodingKeys: String, CodingKey {
    case id, orderId, time, side, positionSide, price, qty, quoteQty, commission, commissionAsset
    case realizedPnl, maker, role, split
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    orderId = try c.decode(String.self, forKey: .orderId)
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
    role = try c.decode(FillRole.self, forKey: .role)
    split = try c.decode(Bool.self, forKey: .split)
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(orderId, forKey: .orderId)
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
    try c.encode(role, forKey: .role)
    try c.encode(split, forKey: .split)
  }
}

/// 一个回合。字段含义、单位、可空性见协议文档 2.1。
public struct TradeRound: Codable, Sendable, Hashable, Identifiable {
  /// 结构版本。
  public static let currentVersion = 1

  public var version: Int
  public var id: String
  public var venue: String
  public var market: String
  public var symbol: String
  public var accountTag: String
  public var positionSide: PositionSide
  public var direction: TradeDirection
  public var status: TradeRoundStatus
  public var quoteAsset: String
  public var openedAt: Int64
  public var closedAt: Int64?
  public var holdingMs: Int64?
  public var openAvgPrice: Decimal
  public var closeAvgPrice: Decimal?
  public var openedQty: Decimal
  public var closedQty: Decimal
  public var maxQty: Decimal
  public var peakNotional: Decimal
  public var leverage: Int?
  public var realizedPnl: Decimal
  /// 手续费合计，正数 = 付出，已折成 `quoteAsset`。
  public var commission: Decimal
  public var commissionByAsset: [String: Decimal]
  public var commissionUnpriced: Bool
  /// 资金费合计，正数 = 收入。
  public var funding: Decimal
  /// `realizedPnl − commission + funding`。
  public var netPnl: Decimal
  public var fills: [RoundFill]
  public var updatedAt: Int64

  public init(version: Int = TradeRound.currentVersion, id: String, venue: String, market: String,
              symbol: String, accountTag: String, positionSide: PositionSide, direction: TradeDirection,
              status: TradeRoundStatus, quoteAsset: String, openedAt: Int64, closedAt: Int64?,
              holdingMs: Int64?, openAvgPrice: Decimal, closeAvgPrice: Decimal?, openedQty: Decimal,
              closedQty: Decimal, maxQty: Decimal, peakNotional: Decimal, leverage: Int?,
              realizedPnl: Decimal, commission: Decimal, commissionByAsset: [String: Decimal],
              commissionUnpriced: Bool, funding: Decimal, netPnl: Decimal, fills: [RoundFill],
              updatedAt: Int64) {
    self.version = version; self.id = id; self.venue = venue; self.market = market
    self.symbol = symbol; self.accountTag = accountTag; self.positionSide = positionSide
    self.direction = direction; self.status = status; self.quoteAsset = quoteAsset
    self.openedAt = openedAt; self.closedAt = closedAt; self.holdingMs = holdingMs
    self.openAvgPrice = openAvgPrice; self.closeAvgPrice = closeAvgPrice; self.openedQty = openedQty
    self.closedQty = closedQty; self.maxQty = maxQty; self.peakNotional = peakNotional
    self.leverage = leverage; self.realizedPnl = realizedPnl; self.commission = commission
    self.commissionByAsset = commissionByAsset; self.commissionUnpriced = commissionUnpriced
    self.funding = funding; self.netPnl = netPnl; self.fills = fills; self.updatedAt = updatedAt
  }

  /// 品种身份（和多交易所模块同一套键）。
  public var instrument: InstrumentID { InstrumentID(venue: venue, market: market, symbol: symbol) }
  public var isOpen: Bool { status == .open }

  // MARK: 幂等 id（协议 2.2）

  /// 回合 id：同一个回合在两台手机上、或者重装后重新回溯，拼出来必须是同一条记录，
  /// 所以是哈希不是随机；做成 UUID 是因为服务端 `review_records.id` 是 uuid 列。
  ///
  /// SHA-256 取前 16 字节，打上 UUIDv8 的版本位与变体位。服务端用 sha2 能逐字节复现。
  public static func makeID(venue: String, market: String, accountTag: String, symbol: String,
                            positionSide: PositionSide, firstFillID: String) -> String {
    let material = ["trade-round-v1", venue, market, accountTag, symbol, positionSide.rawValue, firstFillID]
      .joined(separator: "\n")
    var bytes = Array(SHA256.hash(data: Data(material.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x80
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
                 hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
    return parts.map(String.init).joined(separator: "-")
  }

  // MARK: Codable（十进制写字符串、可空键写 null）

  private enum CodingKeys: String, CodingKey {
    case version, id, venue, market, symbol, accountTag, positionSide, direction, status, quoteAsset
    case openedAt, closedAt, holdingMs, openAvgPrice, closeAvgPrice, openedQty, closedQty, maxQty
    case peakNotional, leverage, realizedPnl, commission, commissionByAsset, commissionUnpriced
    case funding, netPnl, fills, updatedAt
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decode(Int.self, forKey: .version)
    id = try c.decode(String.self, forKey: .id)
    venue = try c.decode(String.self, forKey: .venue)
    market = try c.decode(String.self, forKey: .market)
    symbol = try c.decode(String.self, forKey: .symbol)
    accountTag = try c.decode(String.self, forKey: .accountTag)
    positionSide = try c.decode(PositionSide.self, forKey: .positionSide)
    direction = try c.decode(TradeDirection.self, forKey: .direction)
    status = try c.decode(TradeRoundStatus.self, forKey: .status)
    quoteAsset = try c.decode(String.self, forKey: .quoteAsset)
    openedAt = try c.decode(Int64.self, forKey: .openedAt)
    closedAt = try c.decodeIfPresent(Int64.self, forKey: .closedAt)
    holdingMs = try c.decodeIfPresent(Int64.self, forKey: .holdingMs)
    openAvgPrice = try c.decimal(.openAvgPrice)
    closeAvgPrice = try c.decimalIfPresent(.closeAvgPrice)
    openedQty = try c.decimal(.openedQty)
    closedQty = try c.decimal(.closedQty)
    maxQty = try c.decimal(.maxQty)
    peakNotional = try c.decimal(.peakNotional)
    leverage = try c.decodeIfPresent(Int.self, forKey: .leverage)
    realizedPnl = try c.decimal(.realizedPnl)
    commission = try c.decimal(.commission)
    let raw = try c.decode([String: String].self, forKey: .commissionByAsset)
    var byAsset: [String: Decimal] = [:]
    for (asset, text) in raw {
      guard let d = TradeDecimal.parse(text) else {
        throw DecodingError.dataCorruptedError(forKey: .commissionByAsset, in: c,
                                               debugDescription: "\(asset) 不是十进制字符串：\(text)")
      }
      byAsset[asset] = d
    }
    commissionByAsset = byAsset
    commissionUnpriced = try c.decode(Bool.self, forKey: .commissionUnpriced)
    funding = try c.decimal(.funding)
    netPnl = try c.decimal(.netPnl)
    fills = try c.decode([RoundFill].self, forKey: .fills)
    updatedAt = try c.decode(Int64.self, forKey: .updatedAt)
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(version, forKey: .version)
    try c.encode(id, forKey: .id)
    try c.encode(venue, forKey: .venue)
    try c.encode(market, forKey: .market)
    try c.encode(symbol, forKey: .symbol)
    try c.encode(accountTag, forKey: .accountTag)
    try c.encode(positionSide, forKey: .positionSide)
    try c.encode(direction, forKey: .direction)
    try c.encode(status, forKey: .status)
    try c.encode(quoteAsset, forKey: .quoteAsset)
    try c.encode(openedAt, forKey: .openedAt)
    try c.encodeOrNull(closedAt, .closedAt)
    try c.encodeOrNull(holdingMs, .holdingMs)
    try c.encodeDecimal(openAvgPrice, .openAvgPrice)
    try c.encodeDecimalOrNull(closeAvgPrice, .closeAvgPrice)
    try c.encodeDecimal(openedQty, .openedQty)
    try c.encodeDecimal(closedQty, .closedQty)
    try c.encodeDecimal(maxQty, .maxQty)
    try c.encodeDecimal(peakNotional, .peakNotional)
    try c.encodeOrNull(leverage, .leverage)
    try c.encodeDecimal(realizedPnl, .realizedPnl)
    try c.encodeDecimal(commission, .commission)
    try c.encode(commissionByAsset.mapValues(TradeDecimal.format), forKey: .commissionByAsset)
    try c.encode(commissionUnpriced, forKey: .commissionUnpriced)
    try c.encodeDecimal(funding, .funding)
    try c.encodeDecimal(netPnl, .netPnl)
    try c.encode(fills, forKey: .fills)
    try c.encode(updatedAt, forKey: .updatedAt)
  }
}
