import Foundation
import KanpanCore
import KanpanNetwork

/// 上次看到的自选报价，只为冷启动第一帧不白板（§4.3 的报价版）。
///
/// 存的是交易所真实返回过的值，连同交易所时钟 `timeMs` 一起落盘——
/// 读回来仍然是真实成交价，不是编出来的数。是否还能当「实时」由上层按
/// 时钟判断：列表顶部的实时指示灯只认 5 秒内的更新，超过就自己灭掉。
///
/// 但「不是实时」和「还能不能摆出来」是两件事（审查 B-06）。原来读回来的行没有年龄，
/// 一个月没开过 app、或者一个已经下架的合约，冷启动第一帧照样把那口价摆在自选表上，
/// 和真的价长得一模一样。现在读的时候就按年龄筛：超过 `maxAgeMs` 的行根本不返回——
/// 空着比一个月前的价好。年龄按**交易所时钟**算（行里那个 `t`）；老版本写下的行
/// 没有 `t`，那就按文件自己的修改时间算，两者都没有才放它过去。
public enum QuoteSnapshot {
  /// 自选通常几十个，留够余量即可；这不是行情库。
  public static let maxEntries = 256

  /// 一行报价还能当「上次看到的价」摆出来的最长年龄：24 小时。
  ///
  /// 为什么是一天：这份快照的用途只有「冷启动第一帧不白板」，而第一帧之后几百毫秒
  /// 真行情就来了。隔夜开一次 app，昨天的收盘价还能给人一个正确的量级；隔一周
  /// 再打开，那个数已经什么都不代表了。
  public static let maxAgeMs: Int64 = 24 * 3_600_000

  /// 盘上那一行。
  ///
  /// 除了 `s` / `l`，每一项都是**可空**的，`null` 就是「这一项没有」。
  /// 这不是洁癖：JSON 里没有 NaN 这个值，`JSONEncoder` 碰到非有限的 `Double`
  /// 会抛 `EncodingError.invalidValue`，而 `write` 是一次性编码整批——
  /// 于是**一行的成交额是 NaN，整份快照就一个字节都写不下去**（审查复核项 1）。
  /// 缺失写成 `null`、读回来还原成 `.nan`，一行坏值只影响它自己那一格。
  ///
  /// 旧版本写下的文件里这几项是数（不可能是 NaN，那种文件根本没写成功过），
  /// 解成 `Double?` 照样认得，不需要迁移。
  private struct Entry: Codable {
    var s: String        // symbol
    var l: Double        // last
    var c: Double?       // changePercent
    var p: Double?       // priceChange
    var h: Double?
    var lo: Double?
    var v: Double?       // quoteVolume
    var m: Double?       // markPrice
    var o: Double?       // open24h
    var t: Int64?        // exchange timeMs
    var i: Int64?        // lastTradeID
  }

  /// 非有限值（NaN / ±∞）一律按「没有这一项」落盘。
  private static func finite(_ v: Double?) -> Double? {
    guard let v, v.isFinite else { return nil }
    return v
  }

  public static func write(_ tickers: [Ticker], to url: URL, log: FeedLog = .silent) {
    let rows = tickers
      .filter { !$0.symbol.isEmpty && $0.last.isFinite && $0.last > 0 }
      .prefix(maxEntries)
      .map { Entry(s: $0.symbol, l: $0.last, c: finite($0.changePercent), p: finite($0.priceChange), h: finite($0.high),
                   lo: finite($0.low), v: finite($0.quoteVolume), m: finite($0.markPrice),
                   o: finite($0.open24h), t: $0.timeMs, i: $0.lastTradeID) }
    guard !rows.isEmpty else { remove(url); return }
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                              withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(Array(rows))
      try data.write(to: url, options: .atomic)
    } catch {
      // 写失败不影响使用（下次再写），但不许悄悄吞掉：上一版就是这么把
      // 「整份快照因为一个 NaN 而永远写不下去」藏了好几个月。
      log("自选报价快照落盘失败：\(error)")
    }
  }

  /// - Parameters:
  ///   - now: 现在几点（毫秒）。用例传固定值。
  ///   - maxAgeMs: 超过这个年龄的行不返回。传 `nil` 表示不筛（目前没人这么用，
  ///     留着是为了让「筛掉了」这件事在用例里能和「本来就没有」分开）。
  public static func read(_ url: URL,
                          now: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
                          maxAgeMs: Int64? = maxAgeMs) -> [Ticker] {
    guard let data = try? Data(contentsOf: url),
          let rows = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
    // 没有 `t` 的老行按文件的修改时间算年龄——写下它的那一刻就是那个时间。
    let fileMs = fileModifiedMs(url)
    return rows.prefix(maxEntries).compactMap { row in
      guard !row.s.isEmpty, row.l.isFinite, row.l > 0 else { return nil }
      if let maxAgeMs, let stamp = row.t ?? fileMs, now - stamp > maxAgeMs { return nil }
      // `null` 还原成 NaN：「没有这一项」在内存里的写法就是它，上层按缺数处理
      // （该留空的留空，不会把 0 当成真的 0）。
      return Ticker(symbol: row.s.uppercased(), last: row.l, changePercent: row.c ?? .nan,
                    high: row.h ?? .nan, low: row.lo ?? .nan, quoteVolume: row.v ?? .nan,
                    markPrice: row.m, open24h: row.o, timeMs: row.t, lastTradeID: row.i, priceChange: row.p)
    }
  }

  private static func fileModifiedMs(_ url: URL) -> Int64? {
    guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate]
            as? Date else { return nil }
    return Int64(date.timeIntervalSince1970 * 1000)
  }

  public static func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}
