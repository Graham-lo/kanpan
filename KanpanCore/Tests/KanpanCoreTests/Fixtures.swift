import Foundation
import Testing

@testable import KanpanCore

/// 黄金值从定版原型导出（`node Tools/export-fixtures.mjs`）。
/// 这里只负责读进来：算法一行都不在测试里重写，不然就成了自己和自己比。
enum Fixture {
  enum Failure: Error { case missing(String), shape(String) }

  static func data(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
      ?? Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")
    else { throw Failure.missing(name) }
    return try Data(contentsOf: url)
  }

  static func dict(_ name: String) throws -> [String: Any] {
    guard let d = try JSONSerialization.jsonObject(with: data(name)) as? [String: Any]
    else { throw Failure.shape(name) }
    return d
  }

  /// JSON 里 NaN 写成 null，读回来还原成 NaN。
  static func nums(_ any: Any?) -> [Double] {
    guard let a = any as? [Any] else { return [] }
    return a.map { ($0 as? NSNumber)?.doubleValue ?? .nan }
  }

  static func rows(_ any: Any?) -> [[Double]] {
    (any as? [Any]).map { $0.map(nums) } ?? []
  }

  static func dictIn(_ name: String, _ key: String) -> [String: Any] {
    (try! dict(name))[key] as! [String: Any]
  }

  static func group(_ any: Any?) -> [String: [Double]] {
    guard let d = any as? [String: Any] else { return [:] }
    return d.mapValues(nums)
  }
}

/// 指标黄金值的一个快照。全部字段都是值类型，测试可以并行跑。
struct GoldenCase: Sendable {
  var symbol: String
  var interval: String
  var t0: Int64
  var step: Int64
  var decimals: Int
  var open: [Double], high: [Double], low: [Double], close: [Double], volume: [Double]
  /// 多条线的指标：`ma` / `ema` / `vol` / `rsi`。
  var lines: [String: [[Double]]]
  /// 有名字的分量：`boll.mid` / `macd.hist` / `kdj.j` / `srsi.k`。
  var groups: [String: [String: [Double]]]
  var atr: [Double]

  var series: BarSeries {
    BarSeries(
      symbol: symbol, interval: Interval(rawValue: interval) ?? .m1, t0: t0,
      open: open, high: high, low: low, close: close, volume: volume)
  }

  var name: String { "\(symbol)|\(interval)" }
  func line(_ key: String, _ i: Int) -> [Double] { lines[key]?[i] ?? [] }
  func part(_ key: String, _ sub: String) -> [Double] { groups[key]?[sub] ?? [] }
}

enum Golden {
  static let params: [String: [Int]] = {
    let d = try! Fixture.dict("indicators")
    return d["params"] as! [String: [Int]]
  }()

  static let cases: [GoldenCase] = {
    let d = try! Fixture.dict("indicators")
    return (d["cases"] as! [[String: Any]]).map { c in
      GoldenCase(
        symbol: c["symbol"] as! String,
        interval: c["interval"] as! String,
        t0: (c["t0"] as! NSNumber).int64Value,
        step: (c["step"] as! NSNumber).int64Value,
        decimals: (c["p"] as! NSNumber).intValue,
        open: Fixture.nums(c["open"]), high: Fixture.nums(c["high"]),
        low: Fixture.nums(c["low"]), close: Fixture.nums(c["close"]),
        volume: Fixture.nums(c["volume"]),
        lines: ["ma": Fixture.rows(c["ma"]), "ema": Fixture.rows(c["ema"]),
                "vol": Fixture.rows(c["vol"]), "rsi": Fixture.rows(c["rsi"])],
        groups: ["boll": Fixture.group(c["boll"]), "macd": Fixture.group(c["macd"]),
                 "kdj": Fixture.group(c["kdj"]), "srsi": Fixture.group(c["srsi"])],
        atr: Fixture.nums(c["atr"]))
    }
  }()

  /// 只跑一个快照的测试用它，省时间。
  static let first = cases[0]
  static let indices = Array(cases.indices)
}

/// 逐点比：NaN 的位置必须一样，数字的绝对误差 ≤ 1e-9（§A1.1）。
func expectSame(
  _ got: [Double], _ want: [Double], _ label: String, tol: Double = 1e-9,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(got.count == want.count, "\(label) 长度 \(got.count) ≠ \(want.count)", sourceLocation: sourceLocation)
  guard got.count == want.count else { return }
  var bad = 0
  var firstBad = ""
  for i in 0..<got.count {
    let ok = want[i].isNaN ? got[i].isNaN : (got[i].isFinite && abs(got[i] - want[i]) <= tol)
    if !ok {
      bad += 1
      if firstBad.isEmpty { firstBad = "[\(i)] want \(want[i]) got \(got[i])" }
    }
  }
  #expect(bad == 0, "\(label)：\(bad) 点不符，首个 \(firstBad)", sourceLocation: sourceLocation)
}

// MARK: - 其余 fixture

/// A1.3：11 风格 × 3 倍率 × spacing 0.4…40 的根宽表。
struct WidthRow: Sendable {
  var style: String, bodyR: Double, scale: Double
  var body: [Double], wick: [Double]
  /// 第 i 个采样点对应的 spacing。
  func spacing(_ i: Int) -> Double { Double(4 + i) / 10 }
}

/// A1.5：一条惯性曲线的 101 个采样点。
struct FlingRow: Sendable {
  var speed: Double
  /// `(t, pastPx, done)`
  var points: [[Double]]
}

/// A1.10：原型 styles.js 里的一行。
struct StyleRow: Sendable {
  var s: [String: String] = [:]
  var n: [String: Double] = [:]
  init(_ d: [String: Any]) {
    for (k, v) in d {
      if let x = v as? String { s[k] = x }
      else if let b = v as? NSNumber {
        // JSON 里 true/false 也是 NSNumber，靠 objCType 分辨。
        if String(cString: b.objCType) == "c" { n[k] = b.boolValue ? 1 : 0 } else { n[k] = b.doubleValue }
      }
    }
  }
}

/// A1.10：原型 styles.js 导出的一套配色。
struct PaletteRow: Sendable {
  var css: [String: String]
  var chart: [String: String]
  var palette: [String]
  var green: String, red: String
  init(_ d: [String: Any]) {
    css = (d["css"] as! [String: Any]).compactMapValues { $0 as? String }
    chart = (d["chart"] as! [String: Any]).compactMapValues { $0 as? String }
    palette = d["palette"] as! [String]
    green = d["green"] as! String
    red = d["red"] as! String
  }
}

/// A1.6：时间轴标签一例。
struct LabelRow: Sendable {
  var tz: String, off: Int, ms: Double, step: Double, tick: String, full: String
}

enum Fx {
  static let widths: [WidthRow] = {
    let d = try! Fixture.dict("candle-widths")
    return (d["rows"] as! [[String: Any]]).map {
      WidthRow(
        style: $0["style"] as! String,
        bodyR: ($0["bodyR"] as! NSNumber).doubleValue,
        scale: ($0["dpr"] as! NSNumber).doubleValue,
        body: Fixture.nums($0["body"]), wick: Fixture.nums($0["wick"]))
    }
  }()

  static let fling: [FlingRow] = {
    let d = try! Fixture.dict("fling")
    return (d["samples"] as! [[String: Any]]).map {
      FlingRow(speed: ($0["speed"] as! NSNumber).doubleValue, points: Fixture.rows($0["points"]))
    }
  }()

  static let flingTau: Double = {
    (try! Fixture.dict("fling")["tau"] as! NSNumber).doubleValue
  }()

  /// `(span, want, step)`
  static let nice: [[Double]] = { Fixture.rows(try! Fixture.dict("ticks")["nice"]) }()
  /// `(spanMs, plotW, perLabelPx, step)`
  static let time: [[Double]] = { Fixture.rows(try! Fixture.dict("ticks")["time"]) }()
  static let timeStepsJS: [Double] = { Fixture.nums(try! Fixture.dict("ticks")["timeSteps"]) }()

  static let labels: [LabelRow] = {
    let d = try! Fixture.dict("ticks")
    return (d["labels"] as! [[String: Any]]).map {
      LabelRow(
        tz: $0["tz"] as! String, off: ($0["off"] as! NSNumber).intValue,
        ms: ($0["ms"] as! NSNumber).doubleValue, step: ($0["step"] as! NSNumber).doubleValue,
        tick: $0["tick"] as! String, full: $0["full"] as! String)
    }
  }()

  /// `(x, p, 文本)`
  static let fmtNumCases: [(Double, Int, String)] = {
    ((try! Fixture.dict("format"))["num"] as! [[Any]]).map {
      (($0[0] as! NSNumber).doubleValue, ($0[1] as! NSNumber).intValue, $0[2] as! String)
    }
  }()

  /// A1.10：原型风格表（几何字段都在顶层）。
  static let styles: [StyleRow] = {
    ((try! Fixture.dict("styles"))["styles"] as! [[String: Any]]).map(StyleRow.init)
  }()

  static let light = PaletteRow(Fixture.dictIn("styles", "light"))
  static let dark = PaletteRow(Fixture.dictIn("styles", "dark"))

  /// `(px, py, x1, y1, x2, y2, dist)`
  static let distSeg: [[Double]] = { Fixture.rows(try! Fixture.dict("distseg")["cases"]) }()
}

/// 造一段能算指标的合成行情：固定种子，跑多少次都一样。
struct Rng: Sendable {
  var s: UInt64
  init(_ seed: UInt64) { s = seed &* 6_364_136_223_846_793_005 &+ 1 }
  mutating func next() -> UInt64 {
    s ^= s << 13; s ^= s >> 7; s ^= s << 17
    return s
  }
  /// [0, 1)
  mutating func d() -> Double { Double(next() >> 11) / Double(1 << 53) }
  mutating func d(_ a: Double, _ b: Double) -> Double { a + d() * (b - a) }
  mutating func i(_ a: Int, _ b: Int) -> Int { a + Int(next() % UInt64(b - a + 1)) }
}

func synthSeries(
  count: Int, interval: Interval = .h1, t0: Int64 = 1_700_000_000_000, seed: UInt64 = 7
) -> BarSeries {
  var r = Rng(seed)
  var o = [Double](), h = [Double](), l = [Double](), c = [Double](), v = [Double]()
  // 主动买成交量：大部分根有，每隔十几根故意缺一根。缺失是实盘常态
  // （撮合价合成的根、OKX、被截断的镜像行），CVD 必须在有洞的序列上也算得对。
  var tb = [Double]()
  var px = 100.0
  for _ in 0..<count {
    let op = px
    px = max(1, px * (1 + r.d(-0.02, 0.02)))
    o.append(op); c.append(px)
    h.append(max(op, px) * (1 + r.d(0, 0.01)))
    l.append(min(op, px) * (1 - r.d(0, 0.01)))
    let vol = r.d(10, 5000)
    v.append(vol)
    tb.append(tb.count % 17 == 5 ? .nan : vol * r.d(0.2, 0.8))
  }
  return BarSeries(symbol: "SYN", interval: interval, t0: t0, open: o, high: h, low: l, close: c,
                   volume: v, takerBuy: tb)
}
