import Testing

@testable import KanpanCore

/// A1.1：九个指标在 15 个快照上与原型逐点相同（误差 ≤ 1e-9，NaN 位置一致）。
@Suite("指标黄金值")
struct IndicatorGoldenTests {
  @Test("MA", arguments: Golden.indices)
  func maGolden(_ ci: Int) {
    let c = Golden.cases[ci]
    for (k, n) in Golden.params["MA"]!.enumerated() {
      expectSame(sma(c.close, n), c.line("ma", k), "\(c.name) MA\(n)")
    }
  }

  @Test("EMA", arguments: Golden.indices)
  func emaGolden(_ ci: Int) {
    let c = Golden.cases[ci]
    for (k, n) in Golden.params["EMA"]!.enumerated() {
      expectSame(ema(c.close, n), c.line("ema", k), "\(c.name) EMA\(n)")
    }
  }

  @Test("BOLL", arguments: Golden.indices)
  func bollGolden(_ ci: Int) {
    let c = Golden.cases[ci]
    let p = Golden.params["BOLL"]!
    let got = boll(c.close, p[0], Double(p[1]))
    expectSame(got.mid, c.part("boll", "mid"), "\(c.name) BOLL mid")
    expectSame(got.up, c.part("boll", "up"), "\(c.name) BOLL up")
    expectSame(got.dn, c.part("boll", "dn"), "\(c.name) BOLL dn")
  }

  @Test("VOL", arguments: Golden.indices)
  func volGolden(_ ci: Int) {
    let c = Golden.cases[ci]
    for (k, n) in Golden.params["VOL"]!.enumerated() {
      expectSame(sma(c.volume, n), c.line("vol", k), "\(c.name) VOL MA\(n)")
    }
  }

  @Test("MACD", arguments: Golden.indices)
  func macdGolden(_ ci: Int) {
    let c = Golden.cases[ci]
    let p = Golden.params["MACD"]!
    let got = macd(c.close, p[0], p[1], p[2])
    expectSame(got.dif, c.part("macd", "dif"), "\(c.name) MACD dif")
    expectSame(got.dea, c.part("macd", "dea"), "\(c.name) MACD dea")
    expectSame(got.hist, c.part("macd", "hist"), "\(c.name) MACD hist")
  }

  @Test("RSI", arguments: Golden.indices)
  func rsiGolden(_ ci: Int) {
    let c = Golden.cases[ci]
    for (k, n) in Golden.params["RSI"]!.enumerated() {
      expectSame(rsi(c.close, n), c.line("rsi", k), "\(c.name) RSI\(n)")
    }
  }

  @Test("KDJ", arguments: Golden.indices)
  func kdjGolden(_ ci: Int) {
    let c = Golden.cases[ci]
    let p = Golden.params["KDJ"]!
    let got = kdj(c.high, c.low, c.close, p[0], p[1], p[2])
    expectSame(got.k, c.part("kdj", "k"), "\(c.name) KDJ K")
    expectSame(got.d, c.part("kdj", "d"), "\(c.name) KDJ D")
    expectSame(got.j, c.part("kdj", "j"), "\(c.name) KDJ J")
  }

  @Test("StochRSI", arguments: Golden.indices)
  func srsiGolden(_ ci: Int) {
    let c = Golden.cases[ci]
    let p = Golden.params["SRSI"]!
    var e = IndicatorEngine()
    e.ensure(series: c.series, wanted: [.srsi], params: [.srsi: p], dataKey: "golden-srsi")
    expectSame(e[.srsi]!.lines[0], c.part("srsi", "k"), "\(c.name) SRSI K")
    expectSame(e[.srsi]!.lines[1], c.part("srsi", "d"), "\(c.name) SRSI D")
  }

  @Test("ATR", arguments: Golden.indices)
  func atrGolden(_ ci: Int) {
    let c = Golden.cases[ci]
    expectSame(atr(c.high, c.low, c.close, Golden.params["ATR"]![0]), c.atr, "\(c.name) ATR")
  }

  /// 引擎算出来的要和裸函数一模一样——缓存层不许悄悄改数。
  @Test("引擎与裸函数一致", arguments: Golden.indices)
  func engineMatchesPlain(_ ci: Int) {
    let c = Golden.cases[ci]
    var e = IndicatorEngine()
    // 黄金值按夹具自己的参数算（教科书值），不是出厂参数——参数显式递进去。
    let params = Dictionary(uniqueKeysWithValues: Golden.params.compactMap { k, v in
      IndicatorID(rawValue: k).map { ($0, v) } })
    e.ensure(series: c.series, wanted: [.ma, .ema, .boll, .vol, .macd, .rsi, .kdj, .srsi, .atr],
             params: params, dataKey: "golden")
    expectSame(e[.ma]!.lines[0], c.line("ma", 0), "引擎 \(c.name) MA")
    expectSame(e[.ema]!.lines[1], c.line("ema", 1), "引擎 \(c.name) EMA")
    expectSame(e[.boll]!.lines[2], c.part("boll", "dn"), "引擎 \(c.name) BOLL dn")
    expectSame(e[.vol]!.lines[0], c.line("vol", 0), "引擎 \(c.name) VOL")
    expectSame(e[.macd]!.histogram!, c.part("macd", "hist"), "引擎 \(c.name) MACD hist")
    expectSame(e[.rsi]!.lines[2], c.line("rsi", 2), "引擎 \(c.name) RSI")
    expectSame(e[.kdj]!.lines[2], c.part("kdj", "j"), "引擎 \(c.name) KDJ J")
    expectSame(e[.srsi]!.lines[1], c.part("srsi", "d"), "引擎 \(c.name) SRSI D")
    expectSame(e[.atr]!.lines[0], c.atr, "引擎 \(c.name) ATR")
  }

  /// 键一样就不重算；参数或根数一变就得重算。
  @Test("缓存键")
  func cacheKey() {
    let c = Golden.first
    var e = IndicatorEngine()
    let first = e.ensure(series: c.series, wanted: [.ma], dataKey: "k")
    #expect(first)
    let again = e.ensure(series: c.series, wanted: [.ma], dataKey: "k")
    #expect(!again)
    let reparam = e.ensure(series: c.series, wanted: [.ma], params: [.ma: [5]], dataKey: "k")
    #expect(reparam)
    let added = e.ensure(series: c.series, wanted: [.ma, .rsi], params: [.ma: [5]], dataKey: "k")
    #expect(added)
    var s = c.series
    s.close.removeLast(); s.open.removeLast(); s.high.removeLast()
    s.low.removeLast(); s.volume.removeLast()
    let shorter = e.ensure(series: s, wanted: [.ma, .rsi], params: [.ma: [5]], dataKey: "k")
    #expect(shorter)
  }

  /// 空序列不许崩，也不许给出长度不对的数组。
  @Test("空序列")
  func emptySeries() {
    let s = BarSeries(symbol: "X", interval: .h1, t0: 0, open: [], high: [], low: [], close: [], volume: [])
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: IndicatorID.allCases, dataKey: "empty")
    for id in IndicatorID.allCases {
      for line in e[id]!.lines { #expect(line.isEmpty, "\(id.rawValue) 应为空") }
    }
  }
}
