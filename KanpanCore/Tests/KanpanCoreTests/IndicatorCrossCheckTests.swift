import Foundation
import Testing

@testable import KanpanCore

/// 与手机网页版（`Web/src/m/indicator/engine.ts`）逐位交叉验证的 iOS 这一半。
///
/// 两边用同一个 LCG 造同样 9 种场景（含 1e-8 价 / 1e12 量、全同价零成交、真实日历月 +
/// 0 / 负数参数、周线缺口、单根 / 两根、夹 NaN），全量算 14 把 K 线指标，每把的输出按
/// float64 位模式做 FNV-1a 摘要。下面这张表和 `Web/tests/m-indicator-xcheck.test.ts`
/// 里的 `OUTPUT` **必须一字不差**：改了任一边的指标算法，两边各自的这条用例都会红，
/// 两边改齐、表一起更新才算完。
///
/// 从前这张表只活在 TS 那边、Swift 那一半是审查时跑一次的小程序，iOS 改了算法自己
/// 不会红（审查 B 线 2026-10-04 改 SAR / 锚定周期 / VWAP 坏量时就是网页那边先红的）。
@Suite("指标：与网页版逐位交叉验证")
struct IndicatorCrossCheckTests {
  // ---------------------------------------------------------------- 生成器（与 TS 同一份）

  final class LCG {
    var seed: UInt64 = 20260930
    func next() -> Double {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return Double(seed >> 11) / 9007199254740992
    }
  }

  struct Cols { var o: [Double] = [], h: [Double] = [], l: [Double] = [], c: [Double] = [], v: [Double] = [], tb: [Double] = [] }

  static func makeCols(_ r: LCG, _ n: Int, _ scale: Double, _ vol: Double, _ nanTaker: Bool) -> Cols {
    var x = Cols()
    var px = 100 * scale
    for k in 0 ..< n {
      let op = px
      px = max(scale * 0.01, px * (1 + (r.next() - 0.5) * 0.04))
      x.o.append(op); x.c.append(px)
      x.h.append(max(op, px) * (1 + r.next() * 0.01)); x.l.append(min(op, px) * (1 - r.next() * 0.01))
      let vv = vol * (0.1 + r.next())
      x.v.append(vv); x.tb.append(nanTaker && k % 11 == 4 ? .nan : vv * r.next())
    }
    return x
  }

  static func mk(_ c: Cols, _ interval: Interval, _ t0: Int64, _ openTime: [Int64] = []) -> BarSeries {
    BarSeries(symbol: "XC", interval: interval, t0: t0, open: c.o, high: c.h, low: c.l, close: c.c,
              volume: c.v, takerBuy: c.tb, openTime: openTime)
  }

  /// `Date.UTC(y, m0, 1)`：UTC 某月 1 号 0 点的毫秒。
  static func utcMonth(_ y: Int, _ m0: Int) -> Int64 {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let d = cal.date(from: DateComponents(year: y, month: m0 + 1, day: 1))!
    return Int64(d.timeIntervalSince1970 * 1000)
  }

  struct Case { let name: String; let s: BarSeries; let params: [IndicatorID: [Int]] }

  static func cases() -> [Case] {
    let r = LCG()
    var out: [Case] = []
    let h1t0: Int64 = 1_700_000_000_000 - 1_700_000_000_000 % 3_600_000 + 3_600_000 * 5
    out.append(Case(name: "h1", s: mk(makeCols(r, 300, 1, 1000, true), .h1, h1t0), params: [:]))
    out.append(Case(name: "d1", s: mk(makeCols(r, 200, 1, 1000, false), .d1, 1_704_067_200_000),
                    params: [.supertrend: [7, 2], .dmi: [5]]))
    out.append(Case(name: "tiny", s: mk(makeCols(r, 150, 1e-8, 1e12, true), .m15, 1_700_000_100_000 - 1_700_000_100_000 % 900_000),
                    params: [.ma: [1, 2, 7], .rsi: [1, 2], .kdj: [1, 1, 1]]))
    _ = makeCols(r, 60, 1, 5, false)  // 先造一份再整列换成常数，随机数照样要消耗掉
    let k3 = { (x: Double) in [Double](repeating: x, count: 60) }
    out.append(Case(name: "flat", s: mk(Cols(o: k3(3), h: k3(3), l: k3(3), c: k3(3), v: k3(0), tb: k3(0)), .h4, 1_700_006_400_000), params: [:]))
    do {
      let c = makeCols(r, 40, 1, 100, true)
      let times = (0 ..< 40).map { utcMonth(2021 + $0 / 12, $0 % 12) }
      out.append(Case(name: "mo1", s: mk(c, .mo1, times[0], times), params: [
        .ma: [0, -3, 1, 2], .macd: [30, 10, 9], .boll: [1, 0], .kdj: [1, 1, 1], .srsi: [1, 1, 1, 1],
        .supertrend: [1, 0], .dmi: [1], .rsi: [0, 1, 40],
      ]))
    }
    do {
      let c = makeCols(r, 50, 1, 100, false)
      var times: [Int64] = []
      var t: Int64 = 1_704_672_000_000
      for k in 0 ..< 50 { times.append(t); t += 604_800_000 * (k == 20 ? 3 : 1) }
      out.append(Case(name: "w1gap", s: mk(c, .w1, times[0], times), params: [:]))
    }
    out.append(Case(name: "one", s: mk(makeCols(r, 1, 1, 1, false), .m1, 1_700_000_040_000),
                    params: [.ma: [1], .rsi: [1], .atr: [1], .supertrend: [1, 3], .dmi: [1]]))
    out.append(Case(name: "two", s: mk(makeCols(r, 2, 1, 1, false), .m1, 1_700_000_040_000),
                    params: [.ma: [1, 2], .rsi: [1], .atr: [1], .supertrend: [1, 3], .dmi: [1]]))
    do {
      var c = makeCols(r, 80, 1, 100, true)
      c.c[30] = .nan
      c.h[50] = .nan
      out.append(Case(name: "nan", s: mk(c, .h1, 1_700_002_800_000), params: [:]))
    }
    return out
  }

  // ---------------------------------------------------------------- 摘要：FNV-1a 64 over float64 LE，NaN 归一

  static func digest(_ cols: [[Double]]) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    func feed<T: FixedWidthInteger>(_ v: T) {
      withUnsafeBytes(of: v.littleEndian) { for b in $0 { h = (h ^ UInt64(b)) &* 0x100000001b3 } }
    }
    for col in cols {
      feed(UInt32(col.count))
      for x in col { feed(x.isNaN ? UInt64(0x7ff8000000000000) : x.bitPattern) }
    }
    let s = String(h, radix: 16)
    return String(repeating: "0", count: 16 - s.count) + s
  }

  static func outDigest(_ r: IndicatorResult) -> String {
    digest(r.lines + [r.histogram ?? [], r.dir ?? []])
  }

  // ---------------------------------------------------------------- 两边共用的摘要表

  static let input: [String: String] = ["h1": "fa2de35131f7afbf", "d1": "98d29b634ed55d44", "tiny": "c4ef071cc0708e03", "flat": "12f4f2a2ac45c835", "mo1": "e88e60c47187212b", "w1gap": "e2921b1e8d3482a4", "one": "ce09ed9abd7b5aea", "two": "09a28fc8fa85bf83", "nan": "d45ac2c625b6857b"]
  static let output: [String: [String: String]] = [
    "h1": ["MA": "74a6effa78ee4aba", "EMA": "eedbe4514a6a362d", "BOLL": "ecca21208727e7c9", "VWAP": "eadba3c65f0a083a", "ST": "61c7e868c746d9b7", "SAR": "386229da125506ca", "VOL": "b39d74c548a4f64d", "MACD": "ff40a59ce665dbf1", "RSI": "0e6c57b6963309c5", "KDJ": "6ff419262e43bce7", "SRSI": "367b66a341542d05", "ATR": "44620c09ae21d7fd", "DMI": "bc3228de96ab5c66", "CVD": "d04eb09c7539daa4"],
    "d1": ["MA": "5aa55cb3069d50c3", "EMA": "d9f35552f993e2a3", "BOLL": "921850282c93efe9", "VWAP": "65e80e4ffffe8b03", "ST": "6dba196ac3accd1e", "SAR": "e3851f401016411d", "VOL": "c1c692a94bd1731a", "MACD": "13a34ead870a77e4", "RSI": "46fa5d9fe67f529e", "KDJ": "4980edd448519ceb", "SRSI": "3109ea455813276e", "ATR": "4b85cd23895bc015", "DMI": "a0f4edb1c0b1fe3f", "CVD": "cb8184123b38da4e"],
    "tiny": ["MA": "8ece4d9e6f59134e", "EMA": "a9bec474dba76646", "BOLL": "385a9e4478bfa95a", "VWAP": "663d0b07fc056293", "ST": "4992a9ded5e27860", "SAR": "6e650beb6bf37402", "VOL": "8afd326ae2add781", "MACD": "6c1d32347caa1c5a", "RSI": "41ca4e1bb5ed7485", "KDJ": "5204688117abd904", "SRSI": "d51ffd2de82cb3b7", "ATR": "ef8ebc366367e119", "DMI": "eb4f17881163f081", "CVD": "7a6124df6c9d2b3a"],
    "flat": ["MA": "18a6a74b281ad875", "EMA": "106ea16318c36c28", "BOLL": "e1b9bb3849c0d064", "VWAP": "6d39b767489f2dc9", "ST": "00850a537666d270", "SAR": "bc6f185fdb987b15", "VOL": "f6cf101cd79502ec", "MACD": "72d36b8ad64625ac", "RSI": "ed256dcbcf1d839d", "KDJ": "4c3e1c8537652c89", "SRSI": "91f6ee14ea290af5", "ATR": "c46d13f942216d2c", "DMI": "fb65abeee0267f29", "CVD": "5b1146924351dfc9"],
    "mo1": ["MA": "2929e69bb6ccfc58", "EMA": "cb3b7f1a2fba962c", "BOLL": "fbdea6707b328f0f", "VWAP": "e7d6402bcdc8988d", "ST": "aaad50f79d41bbf4", "SAR": "77f486d7f630afc0", "VOL": "3cf4645e8ae49d19", "MACD": "b3ff16ae7e1a3baa", "RSI": "2e0bbd2b7db2dd19", "KDJ": "8cb67be7c04f0493", "SRSI": "0349c7c63788e8e5", "ATR": "9adec31be378781b", "DMI": "d1a61b7b013cbcf1", "CVD": "68029f6678dfb2b8"],
    "w1gap": ["MA": "cd5c8913e7a5e5f5", "EMA": "2c014701d20a8e0b", "BOLL": "275df1fd8903cfbc", "VWAP": "3cf9a297d973a60b", "ST": "c7dccfb28064b0d0", "SAR": "a001669e54d3c6c7", "VOL": "a76ee1d0d5d9d08d", "MACD": "ddf8b3aea67fc943", "RSI": "d084cc77771796a4", "KDJ": "8d5105932e7731c7", "SRSI": "cb548d39f2693713", "ATR": "1e4c4908d8423dd2", "DMI": "0d3936d131304214", "CVD": "08fa2deff0d35e94"],
    "one": ["MA": "265468066aed930d", "EMA": "e99b93259d3bd005", "BOLL": "12c4d4a06167b171", "VWAP": "cf2f4f9d9aeaf211", "ST": "5aaabed19b02928b", "SAR": "f6a3d69d259b4b55", "VOL": "e0a7fe3409157c11", "MACD": "2142700dbcb096e1", "RSI": "709be02ce520d285", "KDJ": "12c4d4a06167b171", "SRSI": "39f4522364c08565", "ATR": "efc3f0ac682b925e", "DMI": "367bb3e45e27e594", "CVD": "0e630f5f00f60673"],
    "two": ["MA": "0400e73e8f93bdfe", "EMA": "5468ba8b5cf97ae5", "BOLL": "ed4ca6dc33621527", "VWAP": "b3552f6926bd2c47", "ST": "47e12e678a7a5945", "SAR": "1e9c42c204450845", "VOL": "a18c1bfeafc089b7", "MACD": "4d8dd88628fe7237", "RSI": "bf61af80727731f6", "KDJ": "ed4ca6dc33621527", "SRSI": "5c331e2b3e062755", "ATR": "78c37c461eb669ad", "DMI": "359082a6e2d92a8b", "CVD": "6d36f8934172bb4a"],
    "nan": ["MA": "cb5fdc54edd9c5fb", "EMA": "6e76387f002ac46e", "BOLL": "7c22a372a99497e0", "VWAP": "36f227bda7405544", "ST": "cce2f9d606494ced", "SAR": "c36ad8ca2581cade", "VOL": "4267152d90dfe2c4", "MACD": "eb9da08f1fb74c3c", "RSI": "7144c11b3eefb0a3", "KDJ": "bd311451879a514e", "SRSI": "9e3df7302d158d39", "ATR": "da153ef939fe9c38", "DMI": "c7ec3db3b0563a76", "CVD": "dc5581cc3110ba2e"],
  ]

  static let ids: [IndicatorID] = [.ma, .ema, .boll, .vwap, .supertrend, .sar, .vol, .macd, .rsi, .kdj, .srsi, .atr, .dmi, .cvd]

  @Test("9 种场景、14 把指标的摘要和网页版那张表一字不差")
  func digestsMatchTheWebTable() throws {
    let all = Self.cases()
    #expect(Set(all.map(\.name)) == Set(Self.output.keys))
    for c in all {
      let s = c.s
      let openTime = s.openTime.map(Double.init)
      #expect(Self.digest([s.open, s.high, s.low, s.close, s.volume, s.takerBuy, openTime]) == Self.input[c.name],
              "\(c.name) 输入")
      var e = IndicatorEngine()
      e.ensure(series: s, wanted: Self.ids, params: c.params, dataKey: "x")
      for id in Self.ids {
        let got = Self.outDigest(try #require(e[id]))
        #expect(got == Self.output[c.name]?[id.rawValue], "XCHECK \(c.name).\(id.rawValue)=\(got)")
      }
    }
  }
}
