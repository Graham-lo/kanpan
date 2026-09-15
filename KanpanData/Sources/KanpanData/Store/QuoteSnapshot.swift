import Foundation
import KanpanCore

/// 上次看到的自选报价，只为冷启动第一帧不白板（§4.3 的报价版）。
///
/// 存的是交易所真实返回过的值，连同交易所时钟 `timeMs` 一起落盘——
/// 读回来仍然是真实成交价，不是编出来的数。是否还能当「实时」由上层按
/// 时钟判断：列表顶部的实时指示灯只认 5 秒内的更新，超过就自己灭掉。
public enum QuoteSnapshot {
  /// 自选通常几十个，留够余量即可；这不是行情库。
  public static let maxEntries = 256

  private struct Entry: Codable {
    var s: String        // symbol
    var l: Double        // last
    var c: Double        // changePercent
    var h: Double
    var lo: Double
    var v: Double        // quoteVolume
    var m: Double?       // markPrice
    var o: Double?       // open24h
    var t: Int64?        // exchange timeMs
    var i: Int64?        // lastTradeID
  }

  private static func finite(_ v: Double) -> Double { v.isFinite ? v : .nan }

  public static func write(_ tickers: [Ticker], to url: URL) {
    let rows = tickers
      .filter { !$0.symbol.isEmpty && $0.last.isFinite && $0.last > 0 }
      .prefix(maxEntries)
      .map { Entry(s: $0.symbol, l: $0.last, c: finite($0.changePercent), h: finite($0.high),
                   lo: finite($0.low), v: finite($0.quoteVolume), m: $0.markPrice,
                   o: $0.open24h, t: $0.timeMs, i: $0.lastTradeID) }
    guard !rows.isEmpty else { remove(url); return }
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                              withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(Array(rows))
      try data.write(to: url, options: .atomic)
    } catch {
      // 缓存写失败不影响使用，下次再写。
    }
  }

  public static func read(_ url: URL) -> [Ticker] {
    guard let data = try? Data(contentsOf: url),
          let rows = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
    return rows.prefix(maxEntries).compactMap { row in
      guard !row.s.isEmpty, row.l.isFinite, row.l > 0 else { return nil }
      return Ticker(symbol: row.s.uppercased(), last: row.l, changePercent: row.c,
                    high: row.h, low: row.lo, quoteVolume: row.v, markPrice: row.m,
                    open24h: row.o, timeMs: row.t, lastTradeID: row.i)
    }
  }

  public static func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}
