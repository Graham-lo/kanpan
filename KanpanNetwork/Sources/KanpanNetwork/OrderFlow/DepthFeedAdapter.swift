import Foundation
import KanpanCore

// 主力订单流的数据链路：一家交易所一个适配器，说清楚三件事——
// 连哪儿、订什么（`connect`），收到的一帧是什么（`decode`），快照从哪儿拿（`fetchSnapshot`）。
// 本地簿、分桶、门槛与交易所无关，全在 KanpanCore/OrderFlow；连接与重连在 `DepthStream`。
//
// | 交易所 | 品种 | 增量 | 快照 | 线路 |
// |---|---|---|---|---|
// | 币安 | USDT 永续 | `<sym>@depth@100ms` + `@aggTrade` | REST，直连 fapi / 网关 kanpan-api | 直连 / 网关 |
// | OKX | USDT 永续 | 网关 okx_hub 转来的 `books` update + `trades` | 流内首帧 snapshot | 只有网关 |
// | Coinbase | 现货 | `level2` update + `market_trades` | 流内 snapshot | 直连 |

/// 一家交易所的深度接入。实现都在本目录，出了这个目录谁也不认识哪家的报文。
public protocol DepthFeedAdapter: Sendable {
  /// 供数的那一家（`binance` / `okx` / `coinbase`）。落盘标定按它分开存。
  var upstream: String { get }
  /// 这一家的品种代号（不带交易所前缀）。
  var symbol: String { get }
  var sequenceModel: DepthSequenceModel { get }
  /// 快照在流里（OKX、Coinbase）；false 就要在连上后另外拉 REST 快照（币安）。
  var snapshotInBand: Bool { get }
  /// 候选推送地址，主在前、备在后（网关两台；直连只有一条）。
  var streamURLs: [URL] { get }
  /// 拨第 `candidate` 条（按候选数取模）并订好，返回的 socket 直接开始收帧。
  ///
  /// 不经 `MarketSocketRouter`：它要先收到一帧认得出的 K 线 / 报价才算连通，
  /// 深度信封它不认，Coinbase 更是要先发订阅才有帧，经它会一直判超时。
  func connect(candidate: Int) async throws -> any WSSocket
  /// 一帧文本 → 零到多条深度消息。不认识的帧返回空。
  func decode(_ text: String) -> [DepthMessage]
  /// REST 快照（只有 `snapshotInBand == false` 的那家会被调用）。
  func fetchSnapshot() async throws -> BookSnapshot
}

public extension DepthFeedAdapter {
  func fetchSnapshot() async throws -> BookSnapshot {
    throw FeedError.unsupported("深度快照")
  }
}

/// 每家提供者给出自己那一路深度接入；给不出（线路上没有深度）就是 nil。
/// 实现在本目录的 `DepthFeedFactory.swift`，提供者文件本身不动。
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
  static func gatewayStreams(_ hosts: BinanceHosts, path: String, streams: [String]) -> [URL] {
    hosts.oiProxies.compactMap { host in
      guard var c = URLComponents(string: "wss://" + host), c.host != nil, c.user == nil else { return nil }
      c.path = path
      c.queryItems = [URLQueryItem(name: "streams", value: streams.joined(separator: "/"))]
      return c.url
    }
  }
}

/// 深度报文里的数值小工具（三家都是字符串数值）。
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

  /// `[[价, 量, ...], ...]` → 档位；量乘 `scale`（OKX 张数换币数）。坏档整条丢掉。
  static func levels(_ value: Any?, scale: Double = 1) -> [BookLevel]? {
    guard let rows = value as? [[Any]] else { return value == nil ? [] : nil }
    var out: [BookLevel] = []
    out.reserveCapacity(rows.count)
    for row in rows {
      guard row.count >= 2, let p = number(row[0]), let q = number(row[1]),
            p.isFinite, q.isFinite, p > 0, q >= 0 else { return nil }
      out.append(BookLevel(price: p, quantity: q * scale))
    }
    return out
  }
}
