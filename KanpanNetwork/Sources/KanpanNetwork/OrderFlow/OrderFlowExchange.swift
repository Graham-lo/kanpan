import Foundation
import KanpanCore

// 主力订单流 · 交易所注册表的条目。
//
// 一家交易所接进主力订单流要说清楚的全部事情都在这一条里：代号、显示名、各产品的序号模型、
// 快照在不在流里、一条连接最多几本、品种表查不到时保底订哪几本、怎么把一批簿分到连接上。
// 条目本身由各家目录（`KanpanNetwork/Sources/KanpanNetwork/<交易所>/`）定义，清单（顺序）只在
// `VenueRegistry.orderFlow`。本目录（OrderFlow/）里的通用代码只查表，不认识任何一家。

/// 建适配器时要的东西：线路（中继、kanpan-api 都是 `route.apiHosts`）、socket 与 HTTP。
public struct OrderFlowConnectContext: Sendable {
  public var route: MarketRoute
  public var sockets: any WSSocketFactory
  public var http: any HTTPTransport

  public init(route: MarketRoute, sockets: any WSSocketFactory, http: any HTTPTransport) {
    self.route = route; self.sockets = sockets; self.http = http
  }
}

/// 品种表查不到时保底订的一本：产品、合约代号、面值、价格换算（见 `DepthBook.priceFactor`）。
public struct OrderFlowFallbackBook: Sendable, Equatable {
  public var product: OrderFlowProduct
  public var instrument: String
  public var notional: OrderFlowNotional
  public var priceFactor: Double

  public init(product: OrderFlowProduct, instrument: String,
              notional: OrderFlowNotional = .linear(multiplier: 1), priceFactor: Double = 1) {
    self.product = product; self.instrument = instrument; self.notional = notional; self.priceFactor = priceFactor
  }
}

/// 主力订单流里的一家交易所。
public struct OrderFlowExchange: Sendable {
  /// 交易所代号（`OrderFlowVenue.exchange`、品种表 `exchange` 列、落盘簿 id 的第一段）。
  public let key: String
  /// 显示名（图例、详情卡、日志）。
  public let displayName: String
  /// 一条连接最多几本簿（中继的订阅配额定的；一本一条连接的就是 1）。
  public let maxBooksPerConnection: Int
  /// 服务端 /liq「哪家」列的编号；这家没有强平推送就是 nil。
  public let liquidationCode: Int?
  /// 这一产品（面值口径）的簿怎么接序号。
  let sequenceModel: @Sendable (OrderFlowProduct, OrderFlowNotional) -> DepthSequenceModel
  /// 快照随增量流一起下发（true），还是要另拉 REST 快照（false）。
  let snapshotInBand: @Sendable (OrderFlowProduct) -> Bool
  /// 品种表查不到时保底订哪几本：参数是图上那只的 base（`1000PEPE`）、去掉缩放前缀的 base（`PEPE`）
  /// 与图上一个价格单位是几个币（1000）。
  let fallback: @Sendable (_ viewedBase: String, _ base: String, _ chartScale: Double) -> [OrderFlowFallbackBook]
  /// 把这一家的一批簿分到连接上（批里只有这一家的簿）。连不了（例如只能走中继却没有 kanpan-api 主机）就回空。
  let makeAdapters: @Sendable ([DepthBook], OrderFlowConnectContext) -> [any DepthFeedAdapter]

  public init(key: String, displayName: String, maxBooksPerConnection: Int, liquidationCode: Int? = nil,
              sequenceModel: @escaping @Sendable (OrderFlowProduct, OrderFlowNotional) -> DepthSequenceModel,
              snapshotInBand: @escaping @Sendable (OrderFlowProduct) -> Bool,
              fallback: @escaping @Sendable (String, String, Double) -> [OrderFlowFallbackBook] = { _, _, _ in [] },
              makeAdapters: @escaping @Sendable ([DepthBook], OrderFlowConnectContext) -> [any DepthFeedAdapter]) {
    self.key = key; self.displayName = displayName
    self.maxBooksPerConnection = maxBooksPerConnection; self.liquidationCode = liquidationCode
    self.sequenceModel = sequenceModel; self.snapshotInBand = snapshotInBand
    self.fallback = fallback; self.makeAdapters = makeAdapters
  }

  /// 按清单查一家。
  public static func named(_ key: String) -> OrderFlowExchange? {
    VenueRegistry.orderFlow.first { $0.key == key }
  }

  /// 按 /liq「哪家」编号查一家。
  public static func liquidationVenue(_ code: Int) -> OrderFlowExchange? {
    VenueRegistry.orderFlow.first { $0.liquidationCode == code }
  }

  /// 把一批簿按 `size` 本一组切开（分连接用）。
  static func chunks(_ books: [DepthBook], _ size: Int) -> [[DepthBook]] {
    let n = max(1, size)
    return stride(from: 0, to: books.count, by: n).map { Array(books[$0..<min($0 + n, books.count)]) }
  }
}
