import Foundation
import KanpanCore

/// OKX USDT 永续的 `books`（400 档），只走网关：订 `/market/okx/stream` 的 `<sym>@depth@100ms`，
/// okx_hub 把 OKX 原消息原样包进 `{"stream","source":"okx","ctVal","data":<OKX 原消息>}`。
///
/// - 首帧 `action=snapshot`（prevSeqId = -1），之后 `update` 按 seqId / prevSeqId 首尾相接。
/// - 同一本簿已经有人在看时，后来者会先收到几条 update 再收到重订拿来的 snapshot——
///   snapshot 之前的增量由本地簿丢掉；已经在看的人会多收一份 snapshot，整本替换即可。
/// - 数量是张数，乘 `ctVal` 换成币数；没带 `ctVal` 的帧网关不发。
/// - checksum 网关给的恒为 0，不校验，只靠序号。
/// - 成交订同一条连接上的 `<sym>@aggTrade`，okx_hub 映射到 OKX `trades`，外层信封相同；
///   `side` 是主动方（buy 吃卖盘），`sz` 也是张数。
///
/// 解码对应原项目 `bit-orderbook-okx/src/lib.rs:878 decode_depth_message`。
public struct OKXBooksAdapter: DepthFeedAdapter {
  public static let snapshotLevels = 400

  public let symbol: String
  public var upstream: String { BinanceUpstream.okx.rawValue }
  public var sequenceModel: DepthSequenceModel { .previousFinalExact }
  public var snapshotInBand: Bool { true }

  let hosts: BinanceHosts
  let sockets: any WSSocketFactory

  public init(symbol: String, hosts: BinanceHosts,
              sockets: any WSSocketFactory = URLSessionSocketFactory()) {
    self.symbol = InstrumentID(symbol).symbol.uppercased()
    self.hosts = hosts; self.sockets = sockets
  }

  var channel: String { "\(symbol.lowercased())@depth@100ms" }
  var tradeChannel: String { BinanceHosts.aggTradeStream(symbol: symbol) }

  public var streamURLs: [URL] {
    Self.gatewayStreams(hosts, path: "/market/okx/stream", streams: [channel, tradeChannel])
  }

  public func connect(candidate: Int) async throws -> any WSSocket {
    try await sockets.connect(to: try url(candidate))
  }

  public func decode(_ text: String) -> [DepthMessage] {
    guard let outer = DepthWire.object(text), outer["source"] as? String == "okx",
          let stream = outer["stream"] as? String,
          let scale = DepthWire.number(outer["ctVal"]), scale > 0, scale.isFinite,
          let message = outer["data"] as? [String: Any], message["event"] == nil,
          let arg = message["arg"] as? [String: Any],
          let items = message["data"] as? [[String: Any]] else { return [] }
    if stream == tradeChannel, arg["channel"] as? String == "trades" {
      return items.compactMap { t in
        guard let p = DepthWire.number(t["px"]), let q = DepthWire.number(t["sz"]), p > 0, q > 0,
              let side = t["side"] as? String, side == "buy" || side == "sell" else { return nil }
        return .trade(OrderFlowTrade(price: p, quantity: q * scale, hitSide: side == "buy" ? .ask : .bid,
                                     timeMs: DepthWire.integer(t["ts"]) ?? 0))
      }
    }
    guard stream == channel, arg["channel"] as? String == "books",
          let action = message["action"] as? String, items.count == 1 else { return [] }
    let item = items[0]
    guard let seq = DepthWire.integer(item["seqId"]),
          let bids = DepthWire.levels(item["bids"], scale: scale),
          let asks = DepthWire.levels(item["asks"], scale: scale) else { return [] }
    let time = DepthWire.integer(item["ts"])
    switch action {
    case "snapshot":
      return [.snapshot(BookSnapshot(lastUpdateID: seq, requestedLevels: Self.snapshotLevels,
                                     bids: bids, asks: asks, eventTimeMs: time))]
    case "update":
      guard let previous = DepthWire.integer(item["prevSeqId"]) else { return [] }
      // 序号倒退：OKX 那边重置过，整本重来。
      if seq < previous { return [.reset] }
      return [.delta(BookDelta(firstUpdateID: seq, finalUpdateID: seq, previousFinalUpdateID: previous,
                               bids: bids, asks: asks, eventTimeMs: time ?? 0))]
    default:
      return []
    }
  }
}
