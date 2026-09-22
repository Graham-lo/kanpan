import Foundation
import KanpanCore

/// 行情推送的连接状态。各家交易所共用。
public enum FeedStatus: String, Sendable, Equatable {
  case live, reconnecting, offline
}

/// 一条行情推送连接吐出来的东西。
///
/// 报文（`payload`）已经由各家自己的推送客户端翻成统一的 `StreamPayload`
/// （K 线 / 逐笔 / 24h 行情 / 标记价 / 盘口……），上层不认识任何一家的线协议。
public enum WSEvent: Sendable {
  case payload(StreamPayload)
  /// 每次真的建立了一条新连接。`id` 不变就说明没重连（A2.9）。
  case connected(id: Int)
  case status(FeedStatus)
}

/// 日志出口。命令行工具打到 stdout，app 里丢给 os_log，测试里收进数组。
public struct FeedLog: Sendable {
  public var write: @Sendable (String) -> Void
  public init(_ write: @escaping @Sendable (String) -> Void = { _ in }) { self.write = write }
  public static let silent = FeedLog()
  public static let stdout = FeedLog { print($0) }
  public func callAsFunction(_ s: String) { write(s) }
}

/// 要订阅的一条行情，按「是什么」说，不按哪家的频道名说。
///
/// 各家推送客户端自己把它翻成线上的频道名（币安 `btcusdt@kline_1h`、
/// 别家 `candles` / `market_trades` 频道……）。`symbol` 一律是 `InstrumentID.key`。
public enum StreamTopic: Hashable, Sendable, CustomStringConvertible {
  /// 原生 K 线推送。只有 `ProviderCapabilities.liveKlineIntervals` 里的周期才有。
  case kline(symbol: String, interval: Interval)
  /// 24h 行情。
  case ticker(symbol: String)
  /// 标记价（含资金费率）。只有 `hasMarkPrice` 的才有。
  case markPrice(symbol: String)
  /// 逐笔成交。没有原生 K 线推送的周期靠它在本地拼末根。
  case trade(symbol: String)
  /// 带主动方向的成交（主动买卖量副图）。
  case aggTrade(symbol: String)
  /// 五档盘口。
  case depth(symbol: String)
  /// 买一卖一。
  case bookTicker(symbol: String)

  public var symbol: String {
    switch self {
    case .kline(let s, _), .ticker(let s), .markPrice(let s), .trade(let s),
         .aggTrade(let s), .depth(let s), .bookTicker(let s):
      return s
    }
  }

  public var description: String {
    let bare = InstrumentID(symbol).symbol
    switch self {
    case .kline(_, let iv): return "\(bare) K线\(iv.rawValue)"
    case .ticker: return "\(bare) 行情"
    case .markPrice: return "\(bare) 标记价"
    case .trade: return "\(bare) 逐笔"
    case .aggTrade: return "\(bare) 主动成交"
    case .depth: return "\(bare) 盘口"
    case .bookTicker: return "\(bare) 买一卖一"
    }
  }
}
