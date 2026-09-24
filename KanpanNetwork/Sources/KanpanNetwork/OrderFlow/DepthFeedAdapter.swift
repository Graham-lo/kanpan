import Foundation
import KanpanCore

// 主力订单流的数据链路。照 CoinAnk「主力大额挂单」：打开一只币，把它在各家交易所、各种产品上的
// 每一本簿都订上。一本簿是一个 `DepthBook`（Core 的 `OrderFlowVenue` + 价格换算），
// 几本簿合用一条连接的是一个适配器（`DepthFeedAdapter`）——币安合约一条组合流带好几只合约，
// OKX 一条中继订好几只 instId，省连接（网关中继全进程只有 64 条）。
//
// 适配器说清楚四件事：连哪儿、订什么（`connect`），一帧属于哪本簿、是什么（`decode`），
// 快照从哪儿拿（`fetchSnapshot`），要不要定时发保活（`keepAlive`）。
// 本地簿、分桶、门槛与交易所无关，全在 KanpanCore/OrderFlow；连接与重连在 `DepthStream`；
// 这只币有哪几本簿、怎么分组在 `OrderFlowCatalog`。
//
// | 分组 | 产品 | 增量 | 快照 | 连接 |
// |---|---|---|---|---|
// | 币安 U 本位 | U 本位永续、U 本位交割 | `@depth@100ms` + `@aggTrade` | kanpan-api `/v1/market/depth?market=um` | 恒走中继 `/v1/market/ws/binance`（服务端分 fstream `/public` 与 `/market`） |
// | 币安币本位 | 币本位永续、币本位交割 | 同上 | kanpan-api `market=cm` | 恒走中继（服务端连 dstream） |
// | 币安现货 | 现货 | 同上（无 pu） | REST data-api.binance.vision | 恒直连 data-stream.binance.vision |
// | OKX | 四种都有 | `books` + `trades` | 流内 snapshot | 恒走中继 `/v1/market/ws/okx`（国内连不上 OKX） |
// | Coinbase | 现货 | `level2` + `market_trades` | 流内 snapshot | 恒直连 |
//
// 「中继」「kanpan-api」都是 `MarketRoute.apiHosts`（只有主机），不随线路两档变：线路只管币安主行情。

/// 一本簿：Core 的描述 + 把这一家报的价格换到图上那只品种的价格口径。
///
/// 币安把 PEPE、SHIB 这类挂成 `1000PEPEUSDT`（价格按 1000 个币报）。看的是 `1000PEPEUSDT` 时
/// 图上的价是「1000 个币」的价，OKX `PEPE-USDT-SWAP` 报的是一个币的价，要乘 1000 才能叠到同一张图上。
/// `priceFactor` 就是这个倍数：本家价格 × priceFactor = 图上的价格。
/// 数量同步除以它（正向合约），名义美元不变；反向合约的数量是张数，与价格无关，不动。
public struct DepthBook: Sendable, Equatable {
  public var venue: OrderFlowVenue
  public var priceFactor: Double
  /// 交割时间（只有交割有）。
  public var expiryMs: Int64?

  public init(venue: OrderFlowVenue, priceFactor: Double = 1, expiryMs: Int64? = nil) {
    self.venue = venue
    self.priceFactor = priceFactor.isFinite && priceFactor > 0 ? priceFactor : 1
    self.expiryMs = expiryMs
  }

  public var id: String { venue.id }

  /// 数量乘它（见上）。
  public var quantityFactor: Double {
    switch venue.notional {
    case .linear: 1 / priceFactor
    case .inverse: 1
    }
  }

  func levels(_ value: Any?) -> [BookLevel]? {
    DepthWire.levels(value, price: priceFactor, quantity: quantityFactor)
  }

  func trade(price: Double, quantity: Double, hit: BookSide, timeMs: Int64) -> OrderFlowTrade {
    OrderFlowTrade(price: price * priceFactor, quantity: quantity * quantityFactor, hitSide: hit, timeMs: timeMs)
  }
}

/// 一帧里的一条消息，带上它属于哪本簿（`OrderFlowVenue.id`）。
public struct VenueMessage: Sendable, Equatable {
  public var venueID: String
  public var message: DepthMessage
  public init(_ venueID: String, _ message: DepthMessage) { self.venueID = venueID; self.message = message }
}

/// 一条深度连接上的几本簿。实现都在本目录，出了这个目录谁也不认识哪家的报文。
public protocol DepthFeedAdapter: Sendable {
  /// 日志里认这条连接用（「币安 U 本位 BTCUSDT,BTCUSDT_260925」）。
  var name: String { get }
  /// 这条连接上的簿。
  var books: [DepthBook] { get }
  /// 候选推送地址，主在前、备在后（网关两台；直连只有一条）。
  var streamURLs: [URL] { get }
  /// 拨第 `candidate` 条（按候选数取模）并订好，返回的 socket 直接开始收帧。
  ///
  /// 不经 `MarketSocketRouter`：它要先收到一帧认得出的 K 线 / 报价才算连通，
  /// 深度信封它不认，Coinbase、OKX 更是要先发订阅才有帧，经它会一直判超时。
  func connect(candidate: Int) async throws -> any WSSocket
  /// 一帧文本 → 零到多条消息。不认识的帧返回空。
  func decode(_ text: String) -> [VenueMessage]
  /// REST 快照（只有 `snapshotInBand == false` 的簿会被调用）。
  func fetchSnapshot(venueID: String) async throws -> BookSnapshot
  /// 连上之后每隔多久发一句什么保活（OKX 30 秒没有帧就断，要自己发 `ping`）。不用就是 nil。
  var keepAlive: DepthKeepAlive? { get }
}

public struct DepthKeepAlive: Sendable, Equatable {
  public var text: String
  public var everyMs: Double
  public init(text: String, everyMs: Double) { self.text = text; self.everyMs = everyMs }
}

public extension DepthFeedAdapter {
  var venues: [OrderFlowVenue] { books.map(\.venue) }
  var keepAlive: DepthKeepAlive? { nil }
  func fetchSnapshot(venueID: String) async throws -> BookSnapshot {
    throw FeedError.unsupported("深度快照")
  }
}

/// 能给出主力订单流接入的提供者（币安、Coinbase）。实现在 `DepthFeedFactory.swift`，提供者文件不动。
///
/// `MarketProvider.orderFlowAdapter(symbol:)` 是一只品种一家一条的旧入口，逐单模型要一只币
/// 各家各产品都订，入口换成这里；那个协议要求留着给默认实现（nil），调用方已经不用它。
public protocol OrderFlowSourcing: Sendable {
  var orderFlowCatalog: OrderFlowCatalog { get }
}

public extension MarketProvider {
  func orderFlowAdapter(symbol: String) -> (any DepthFeedAdapter)? { nil }
}

extension DepthFeedAdapter {
  func url(_ candidate: Int) throws -> URL {
    let urls = streamURLs
    guard !urls.isEmpty else { throw FeedError.badResponse("行情服务暂不可用") }
    return urls[((candidate % urls.count) + urls.count) % urls.count]
  }

  /// 网关上某条路径的组合流地址，按网关表逐台（主在前）。
  static func gatewayStreams(_ gateways: [String], path: String, streams: [String]) -> [URL] {
    gateways.compactMap { host in
      guard var c = URLComponents(string: "wss://" + host), c.host != nil, c.user == nil else { return nil }
      c.path = path
      if !streams.isEmpty { c.queryItems = [URLQueryItem(name: "streams", value: streams.joined(separator: "/"))] }
      return c.url
    }
  }
}

/// 深度报文里的数值小工具（各家都是字符串数值）。
enum DepthWire {
  static func object(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  static func number(_ value: Any?) -> Double? {
    switch value {
    case let s as String: return Double(s)
    case let n as NSNumber: return n.doubleValue
    default: return nil
    }
  }

  static func integer(_ value: Any?) -> Int64? {
    switch value {
    case let n as NSNumber: return n.int64Value
    case let s as String: return Int64(s)
    default: return nil
    }
  }

  /// `[[价, 量, ...], ...]` → 档位；价乘 `price`、量乘 `quantity`（见 `DepthBook.priceFactor`）。坏档整条丢掉。
  static func levels(_ value: Any?, price: Double = 1, quantity: Double = 1) -> [BookLevel]? {
    guard let rows = value as? [[Any]] else { return value == nil ? [] : nil }
    var out: [BookLevel] = []
    out.reserveCapacity(rows.count)
    for row in rows {
      guard row.count >= 2, let p = number(row[0]), let q = number(row[1]),
            p.isFinite, q.isFinite, p > 0, q >= 0 else { return nil }
      out.append(BookLevel(price: p * price, quantity: q * quantity))
    }
    return out
  }
}
