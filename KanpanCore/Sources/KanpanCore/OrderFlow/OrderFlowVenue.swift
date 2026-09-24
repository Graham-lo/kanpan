import Foundation

// 主力订单流 · 一本簿是谁。
//
// 照 CoinAnk「主力大额挂单」：打开一只币（按 base 资产），把这只币在各家交易所、各种产品上的
// 每一本簿都订上，各算各的大单，叠在同一张图上。一本簿 = 交易所 × 产品 × 合约
// （例如「币安 · 币本位永续 · BTCUSD_PERP」「OKX · 交割 · BTC-USD-260925」）。
// Core 不认识任何一家的报文，只认这里的描述：显示名、产品、数量怎么换成美元、序号怎么接。
// 哪只币有哪几本簿由 KanpanNetwork 查（`OrderFlowVenues`），某家没有、连不上就少一本。

/// 产品。门槛按产品分开设（现货 / U 本位永续 / 币本位永续 / 交割）。
public enum OrderFlowProduct: String, Sendable, Hashable, Codable, CaseIterable {
  case spot, usdtPerp, coinPerp, delivery

  /// 设置面板上的名字。
  public var label: String {
    switch self {
    case .spot: "现货"
    case .usdtPerp: "U本位永续"
    case .coinPerp: "币本位永续"
    case .delivery: "交割"
    }
  }

  /// 十字线读数里的短名：「币安 永续 卖 84,120 …」。
  public var shortLabel: String {
    switch self {
    case .spot: "现货"
    case .usdtPerp: "永续"
    case .coinPerp: "币本位"
    case .delivery: "交割"
    }
  }

  /// 合约（永续、交割）与现货分开着色、分开开关。
  public var isContract: Bool { self != .spot }
}

/// 一档挂单的数量怎么换成美元名义。USDT、USDC、USD 都按 1 美元算。
public enum OrderFlowNotional: Sendable, Hashable {
  /// 正向：一个数量单位是 `multiplier` 个币（币安现货 / U 本位、Coinbase 为 1；OKX U 本位是 ctVal），
  /// 名义 = 价 × 量 × multiplier。
  case linear(multiplier: Double)
  /// 反向（币本位永续、币本位交割）：数量是张数，一张 `contractUsd` 美元（币安 BTC 100、其他 10；
  /// OKX 看 ctVal），名义 = 张数 × 面值，与价格无关。
  case inverse(contractUsd: Double)

  public func usd(price: Double, quantity: Double) -> Double {
    let value: Double
    switch self {
    case .linear(let multiplier): value = price * quantity * multiplier
    case .inverse(let contractUsd): value = quantity * contractUsd
    }
    return value.isFinite && value > 0 ? value : 0
  }

  public var isValid: Bool {
    switch self {
    case .linear(let m): m.isFinite && m > 0
    case .inverse(let c): c.isFinite && c > 0
    }
  }
}

/// 一本簿。`id` 是稳定键（落盘的大单按它认簿），`label` 是给人看的交易所名（由 Network 给）。
public struct OrderFlowVenue: Sendable, Equatable {
  /// 交易所代号：`binance` / `okx` / `coinbase`。
  public var exchange: String
  /// 交易所显示名：「币安」「OKX」「Coinbase」。
  public var label: String
  public var product: OrderFlowProduct
  /// 这一家的合约代号（`BTCUSD_PERP`、`BTC-USD-260925`……）。
  public var instrument: String
  public var notional: OrderFlowNotional
  public var sequenceModel: DepthSequenceModel
  /// 快照在流里（OKX、Coinbase）；false 就要另拉 REST 快照（币安）。
  public var snapshotInBand: Bool

  public init(exchange: String, label: String, product: OrderFlowProduct, instrument: String,
              notional: OrderFlowNotional, sequenceModel: DepthSequenceModel, snapshotInBand: Bool) {
    self.exchange = exchange; self.label = label; self.product = product; self.instrument = instrument
    self.notional = notional; self.sequenceModel = sequenceModel; self.snapshotInBand = snapshotInBand
  }

  public var id: String { "\(exchange):\(product.rawValue):\(instrument)" }
}
