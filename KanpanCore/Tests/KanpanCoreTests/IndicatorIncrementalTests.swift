import Testing

@testable import KanpanCore

/// A1.2：增量重算必须和全量重算**逐位**一样，不是「差不多」。
/// 随机做 1000 次「改末根 / 追加新根」，每次都拿一台全新的引擎当裁判。
@Suite("指标增量重算")
struct IndicatorIncrementalTests {
  static let all: [IndicatorID] = [.ma, .ema, .boll, .vol, .macd, .rsi, .kdj, .srsi, .atr]

  /// 全量：新引擎从零算。
  static func full(_ s: BarSeries) -> [IndicatorID: IndicatorResult] {
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: all, dataKey: "full")
    return e.values
  }

  static func compare(
    _ got: [IndicatorID: IndicatorResult], _ want: [IndicatorID: IndicatorResult], _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    for id in all {
      let g = got[id]!, w = want[id]!
      #expect(g.lines.count == w.lines.count, "\(label) \(id.rawValue) 线数", sourceLocation: sourceLocation)
      for (i, line) in g.lines.enumerated() {
        expectSame(line, w.lines[i], "\(label) \(id.rawValue)[\(i)]", tol: 0, sourceLocation: sourceLocation)
      }
      if let h = w.histogram {
        expectSame(g.histogram ?? [], h, "\(label) \(id.rawValue) hist", tol: 0, sourceLocation: sourceLocation)
      }
    }
  }

  /// 1000 次随机操作，四条链路并行跑（每条 250 次），全程与全量对照。
  @Test("随机改末根 / 追加新根 1000 次", arguments: [0, 1, 2, 3])
  func incrementalMatchesFull(_ lane: Int) {
    var r = Rng(UInt64(20260914 + lane))
    var s = synthSeries(count: 320, seed: UInt64(101 + lane))
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: Self.all, dataKey: "inc")
    Self.compare(e.values, Self.full(s), "lane\(lane) 初始")

    for step in 0..<250 {
      let last = s.bar(at: s.count - 1)
      if r.d() < 0.5 {
        // 改末根：价格抖一下，量重报一次。
        let c = max(1, last.close * (1 + r.d(-0.01, 0.01)))
        s.replaceLast(with: Bar(
          openTime: last.openTime, open: last.open,
          high: max(max(last.open, c), last.high * (1 + r.d(0, 0.004))),
          low: min(min(last.open, c), last.low * (1 - r.d(0, 0.004))),
          close: c, volume: last.volume + r.d(0, 40)))
      } else {
        // 收一根、开一根。
        let o = last.close
        let c = max(1, o * (1 + r.d(-0.02, 0.02)))
        s.append(Bar(
          openTime: last.openTime + s.step, open: o,
          high: max(o, c) * (1 + r.d(0, 0.008)), low: min(o, c) * (1 - r.d(0, 0.008)),
          close: c, volume: r.d(10, 5000)))
      }
      e.updateTail(series: s, dataKey: "inc")
      if step % 25 == 0 || step == 249 {
        Self.compare(e.values, Self.full(s), "lane\(lane) 第 \(step) 步")
      }
    }
    Self.compare(e.values, Self.full(s), "lane\(lane) 收尾")
  }

  /// 连追 500 根不回头对一次，最后仍要和全量一致——递推状态不许漂。
  @Test("连续追加 500 根不漂移")
  func longRunNoDrift() {
    var r = Rng(4242)
    var s = synthSeries(count: 200, seed: 9)
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: Self.all, dataKey: "drift")
    for _ in 0..<500 {
      let last = s.bar(at: s.count - 1)
      let o = last.close
      let c = max(1, o * (1 + r.d(-0.03, 0.03)))
      s.append(Bar(openTime: last.openTime + s.step, open: o,
                   high: max(o, c) * 1.001, low: min(o, c) * 0.999, close: c, volume: r.d(1, 999)))
      e.updateTail(series: s, dataKey: "drift")
    }
    Self.compare(e.values, Self.full(s), "追 500 根")
  }

  /// 根数少于指标周期时（前导全 NaN）增量也不能出岔子。
  ///
  /// 改完末根还要接着往下长：短序列上多数线此时还全是 NaN，只比那一刻等于什么都没比——
  /// 错的累计和会顺着后面的追加一路带到均线开始出值之后才露头。
  @Test("短序列", arguments: [1, 2, 5, 13, 27])
  func shortSeries(_ n: Int) {
    var r = Rng(UInt64(6000 + n))
    var s = synthSeries(count: n, seed: UInt64(n))
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: Self.all, dataKey: "short")
    Self.compare(e.values, Self.full(s), "n=\(n) 初始")
    let last = s.bar(at: s.count - 1)
    s.replaceLast(with: Bar(openTime: last.openTime, open: last.open, high: last.high * 1.01,
                            low: last.low * 0.99, close: last.close * 1.005, volume: last.volume + 1))
    e.updateTail(series: s, dataKey: "short")
    Self.compare(e.values, Self.full(s), "n=\(n) 改末根")

    // 一直追到所有线都出过值（SRSI 默认要 14 + 14 + 3 根才有第一个点）。
    for step in 0..<(64 - n) {
      let prev = s.bar(at: s.count - 1)
      let o = prev.close
      let c = max(1, o * (1 + r.d(-0.02, 0.02)))
      s.append(Bar(openTime: prev.openTime + s.step, open: o,
                   high: max(o, c) * (1 + r.d(0, 0.006)), low: min(o, c) * (1 - r.d(0, 0.006)),
                   close: c, volume: r.d(10, 5000)))
      e.updateTail(series: s, dataKey: "short")
      Self.compare(e.values, Self.full(s), "n=\(n) 追到第 \(s.count) 根（第 \(step) 步）")
    }
  }

  // ------------------------------------------------------------ A4：可变的第 0 根

  /// 全 OHLC 都等于收盘的一根，便于手算。
  static func flatBar(_ t: Int64, _ close: Double) -> Bar {
    Bar(openTime: t, open: close, high: close, low: close, close: close, volume: 100)
  }

  /// A4：序列只剩一根时，那一根既是首根也是末根——它自己就是「可变的第 0 根」。
  ///
  /// 重算起点如果被夹到 1，`1..<1` 是空区间，改掉的收盘价压根没进累计和；
  /// 更要命的是 `sum[0]` 从此是错的，后面每追一根都接着这个错的和往下算。
  /// 所以这里一路追到 MA(5) 第一次出值，手算的 102 是对账凭据。
  @Test("唯一一根改掉之后再长：MA(1) 立刻跟上，MA(5) 首次出值仍等于全量")
  func singleBarEditThenGrow() {
    var s = BarSeries(symbol: "A4", interval: .h1, bars: [Self.flatBar(0, 100)])
    let params: [IndicatorID: [Int]] = [.ma: [1, 5]]
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: [.ma], params: params, dataKey: "a4")

    s.replaceLast(with: Self.flatBar(0, 110))
    e.updateTail(series: s, dataKey: "a4")
    #expect(e.values[.ma]!.lines[0][0] == 110,
            "MA(1) 就是价格本身，改成 110 之后得到 \(e.values[.ma]!.lines[0][0])")

    for i in 1...4 {
      s.append(Self.flatBar(Int64(i) * s.step, 100))
      e.updateTail(series: s, dataKey: "a4")
    }
    // (110 + 100 * 4) / 5
    #expect(e.values[.ma]!.lines[1][4] == 102,
            "MA(5) 首次出值应当是 102，得到 \(e.values[.ma]!.lines[1][4])")

    var fresh = IndicatorEngine()
    fresh.ensure(series: s, wanted: [.ma], params: params, dataKey: "a4-full")
    for (i, line) in e.values[.ma]!.lines.enumerated() {
      expectSame(line, fresh.values[.ma]!.lines[i], "MA 增量 vs 全量[\(i)]", tol: 0)
    }
  }

  /// A4 的同族边界：ATR 的 `tr[0]` 是「首根特殊输入」（只有 high − low，没有前收）。
  ///
  /// 唯一一根的振幅改了之后，`tr[0]` 必须跟着改；夹到 1 的话它会一直停在旧值，
  /// 等 RMA 开始出值时才看得出来——ATR(2) 的第一个点是 (tr[0] + tr[1]) / 2。
  @Test("唯一一根的振幅改掉之后，ATR 首次出值仍等于全量")
  func singleBarEditThenATR() {
    var s = BarSeries(symbol: "A4ATR", interval: .h1,
                      bars: [Bar(openTime: 0, open: 100, high: 110, low: 90, close: 100, volume: 1)])
    let params: [IndicatorID: [Int]] = [.atr: [2]]
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: [.atr], params: params, dataKey: "a4atr")

    // tr[0] 由 20 变成 40。
    s.replaceLast(with: Bar(openTime: 0, open: 100, high: 130, low: 90, close: 100, volume: 1))
    e.updateTail(series: s, dataKey: "a4atr")

    // tr[1] = max(105 − 95, |105 − 100|, |95 − 100|) = 10。
    s.append(Bar(openTime: s.step, open: 100, high: 105, low: 95, close: 100, volume: 1))
    e.updateTail(series: s, dataKey: "a4atr")
    #expect(e.values[.atr]!.lines[0][1] == 25,
            "ATR(2) 首次出值应当是 (40 + 10) / 2 = 25，得到 \(e.values[.atr]!.lines[0][1])")

    var fresh = IndicatorEngine()
    fresh.ensure(series: s, wanted: [.atr], params: params, dataKey: "a4atr-full")
    expectSame(e.values[.atr]!.lines[0], fresh.values[.atr]!.lines[0], "ATR 增量 vs 全量", tol: 0)
  }

  /// A4 的同族边界：脏参数（0 / 负数）撞上起点 0。
  ///
  /// 起点现在能取到 0，而 `RecursiveLine` 的「能不能接着上一根算」判据里带着 `n`——
  /// `n <= 0` 时那个判据会把起点 0 放进来，接着就去读上一根，也就是 `out[-1]`。
  /// 所以判据里必须另外写死「起点至少是 1」。参数是用户能在设置里调的，0 不是假想。
  @Test("参数是 0 / 负数时，起点 0 也不能越界")
  func degenerateParamsAtIndexZero() {
    var s = BarSeries(symbol: "A4BAD", interval: .h1, bars: [Self.flatBar(0, 100)])
    let params: [IndicatorID: [Int]] = [
      .ma: [0], .ema: [0], .vol: [-1], .rsi: [0], .atr: [0],
      .boll: [0, 2], .macd: [0, 0, 0], .kdj: [0, 0, 0], .srsi: [0, 0, 0, 0],
    ]
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: Self.all, params: params, dataKey: "bad")
    s.replaceLast(with: Self.flatBar(0, 110))
    e.updateTail(series: s, dataKey: "bad")
    for i in 1...3 {
      s.append(Self.flatBar(Int64(i) * s.step, 100))
      e.updateTail(series: s, dataKey: "bad")
    }
    var fresh = IndicatorEngine()
    fresh.ensure(series: s, wanted: Self.all, params: params, dataKey: "bad-full")
    for id in Self.all {
      for (i, line) in e.values[id]!.lines.enumerated() {
        expectSame(line, fresh.values[id]!.lines[i], "脏参数 \(id.rawValue)[\(i)]", tol: 0)
      }
    }
  }

  /// 随机对拍从 n = 1 起步：先改唯一那一根，再一根根长到所有线都出过值，每一步都对账。
  ///
  /// 原来的随机用例从 320 根开始，暖机边界根本走不到；这条补的就是那一段。
  @Test("从一根长到一百多根，每一步都等于全量", arguments: [0, 1])
  func growFromSingleBar(_ lane: Int) {
    var r = Rng(UInt64(20260919 + lane))
    var s = synthSeries(count: 1, seed: UInt64(301 + lane))
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: Self.all, dataKey: "grow")

    // A4 的起点：唯一一根被改掉。
    let first = s.bar(at: 0)
    s.replaceLast(with: Bar(openTime: first.openTime, open: first.open,
                            high: first.high * 1.08, low: first.low * 0.92,
                            close: first.close * 1.1, volume: first.volume + 7))
    e.updateTail(series: s, dataKey: "grow")
    Self.compare(e.values, Self.full(s), "lane\(lane) n=1 改末根")

    for step in 0..<130 {
      let last = s.bar(at: s.count - 1)
      let o = last.close
      let c = max(1, o * (1 + r.d(-0.02, 0.02)))
      s.append(Bar(openTime: last.openTime + s.step, open: o,
                   high: max(o, c) * (1 + r.d(0, 0.008)), low: min(o, c) * (1 - r.d(0, 0.008)),
                   close: c, volume: r.d(10, 5000)))
      e.updateTail(series: s, dataKey: "grow")
      // 一半的步数再把刚追的这根改一次，模拟 WS 的同根多次更新。
      if r.d() < 0.5 {
        let cur = s.bar(at: s.count - 1)
        let c2 = max(1, cur.close * (1 + r.d(-0.01, 0.01)))
        s.replaceLast(with: Bar(
          openTime: cur.openTime, open: cur.open,
          high: max(max(cur.open, c2), cur.high), low: min(min(cur.open, c2), cur.low),
          close: c2, volume: cur.volume + r.d(0, 30)))
        e.updateTail(series: s, dataKey: "grow")
      }
      Self.compare(e.values, Self.full(s), "lane\(lane) 第 \(step) 步（\(s.count) 根）")
    }
  }
}

/// 持仓量的尾部对齐必须和整列对齐**逐位**一样。
///
/// 三种形态各测一遍：稠密（无时间戳）、稀疏（带时间戳、不限桶）、稀疏 + 限桶。
/// 稀疏那两种的游标是一路扫过来的，尾部对齐靠二分把游标接回去，最容易出岔子。
@Suite("持仓量增量对齐")
struct OIAlignedTailTests {
  /// 做一份持仓量。`kind`：0 稠密、1 稀疏不限桶、2 稀疏限桶（h1）、3 稀疏限桶（m1，5 分钟窗）。
  static func makeOI(kind: Int, t0: Int64, step: Int64, n: Int, seed: UInt64) -> OISeries {
    var r = Rng(seed)
    if kind == 0 {
      return OISeries(t0: t0, step: step, values: (0..<n).map { _ in r.d(1000, 9000) })
    }
    // 稀疏：时间戳有疏有密，偶尔缺一段，正好压到「没有匹配桶」的分支。
    var pts: [OIPoint] = []
    var t = t0 - step
    for _ in 0..<n {
      t += step * Int64(r.i(1, 3))
      pts.append(OIPoint(time: t, value: r.d(1000, 9000)))
    }
    let bucket: Interval? = kind == 2 ? .h1 : (kind == 3 ? .m1 : nil)
    return OISeries(points: pts, step: step, bucketInterval: bucket)
  }

  @Test("随机 300 轮：尾部对齐 == 整列对齐", arguments: [0, 1, 2, 3])
  func tailMatchesFull(_ kind: Int) {
    var r = Rng(UInt64(20260917 + kind))
    var s = synthSeries(count: 260, seed: UInt64(31 + kind))
    let oi = Self.makeOI(kind: kind, t0: s.t0, step: s.step, n: 300, seed: UInt64(77 + kind))
    var prev = oi.aligned(to: s)
    expectSame(prev, oi.aligned(to: s), "kind\(kind) 初始", tol: 0)

    for round in 0..<300 {
      let last = s.bar(at: s.count - 1)
      if r.d() < 0.5 {
        let c = max(1, last.close * (1 + r.d(-0.01, 0.01)))
        s.replaceLast(with: Bar(openTime: last.openTime, open: last.open,
                                high: max(last.high, c), low: min(last.low, c),
                                close: c, volume: last.volume + r.d(0, 40)))
      } else {
        let o = last.close
        let c = max(1, o * (1 + r.d(-0.02, 0.02)))
        s.append(Bar(openTime: last.openTime + s.step, open: o,
                     high: max(o, c), low: min(o, c), close: c, volume: r.d(10, 5000)))
      }
      // 引擎给的起点就是这个：`max(0, count - tailBars)`（下限是 0，见 A4）。
      let start = max(0, s.count - IndicatorID.oi.tailBars(params: IndicatorID.oi.defaultParams))
      prev = oi.aligned(to: s, from: start, previous: prev)
      if round % 10 == 0 || round == 299 {
        expectSame(prev, oi.aligned(to: s), "kind\(kind) 第 \(round) 轮", tol: 0)
      }
    }
    expectSame(prev, oi.aligned(to: s), "kind\(kind) 收尾", tol: 0)
  }

  /// 起点随便挑一个都得对：二分找回来的游标必须和一路扫过来的那个一致。
  @Test("任意起点的尾部对齐都等于整列", arguments: [1, 2, 3])
  func anyStart(_ kind: Int) {
    var r = Rng(UInt64(4096 + kind))
    let s = synthSeries(count: 180, seed: UInt64(5 + kind))
    let oi = Self.makeOI(kind: kind, t0: s.t0, step: s.step, n: 200, seed: UInt64(11 + kind))
    let want = oi.aligned(to: s)
    for _ in 0..<60 {
      let start = r.i(0, s.count)
      // 前缀给真值、尾巴故意填脏，确保被重写的就是 `[start, count)`。
      var seeded = want
      for i in start..<s.count { seeded[i] = -12345 }
      expectSame(oi.aligned(to: s, from: start, previous: seeded), want, "kind\(kind) start=\(start)", tol: 0)
    }
  }

  /// 走引擎这条路：持仓量跟着 K 线一起增量，结果要和全量引擎一致。
  @Test("引擎里的 OI 增量与全量一致")
  func engineOIMatchesFull() {
    var r = Rng(20260101)
    var s = synthSeries(count: 240, seed: 3)
    let oi = Self.makeOI(kind: 1, t0: s.t0, step: s.step, n: 280, seed: 19)
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: [.oi, .ma, .rsi, .atr], oi: oi, dataKey: "oi")

    for round in 0..<200 {
      let last = s.bar(at: s.count - 1)
      if r.d() < 0.5 {
        let c = max(1, last.close * (1 + r.d(-0.01, 0.01)))
        s.replaceLast(with: Bar(openTime: last.openTime, open: last.open,
                                high: max(last.high, c), low: min(last.low, c),
                                close: c, volume: last.volume + 1))
      } else {
        let o = last.close
        let c = max(1, o * (1 + r.d(-0.02, 0.02)))
        s.append(Bar(openTime: last.openTime + s.step, open: o,
                     high: max(o, c), low: min(o, c), close: c, volume: r.d(10, 5000)))
      }
      e.updateTail(series: s, oi: oi, dataKey: "oi")
      if round % 20 == 0 || round == 199 {
        var fresh = IndicatorEngine()
        fresh.ensure(series: s, wanted: [.oi, .ma, .rsi, .atr], oi: oi, dataKey: "oi")
        for id in [IndicatorID.oi, .ma, .rsi, .atr] {
          for (i, line) in e.values[id]!.lines.enumerated() {
            expectSame(line, fresh.values[id]!.lines[i], "第 \(round) 轮 \(id.rawValue)[\(i)]", tol: 0)
          }
        }
      }
    }
  }

  /// 换一份持仓量（K 线一个字没动）必须重算，不能拿着老的那一列接着用。
  @Test("换一份持仓量就得重算")
  func swappingOIRebuilds() {
    let s = synthSeries(count: 120, seed: 8)
    let a = Self.makeOI(kind: 0, t0: s.t0, step: s.step, n: 140, seed: 21)
    let b = Self.makeOI(kind: 0, t0: s.t0, step: s.step, n: 140, seed: 22)
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: [.oi], oi: a, dataKey: "swap")
    let first = e.values[.oi]!.lines[0]
    // 缓存键里没有持仓量的影子，所以这次 `ensure` 的键和上次一模一样——
    // 键相同会直接返回，这是既有行为（见报告里的可疑点）。走 `updateTail` 才能看出换没换。
    e.updateTail(series: s, oi: b, dataKey: "swap")
    expectSame(e.values[.oi]!.lines[0], b.aligned(to: s), "换了之后", tol: 0)
    #expect(first != e.values[.oi]!.lines[0])
  }
}

/// `ensure` 按指标失效：改一个指标的参数不该动到别人。
@Suite("指标按需失效")
struct IndicatorEnsureInvalidationTests {
  static let ids: [IndicatorID] = [.ma, .ema, .boll, .macd, .rsi, .kdj, .srsi, .atr, .vol]

  static func full(_ s: BarSeries, _ ids: [IndicatorID], _ p: [IndicatorID: [Int]]) -> [IndicatorID: IndicatorResult] {
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: ids, params: p, dataKey: "k")
    return e.values
  }

  static func same(_ got: [IndicatorID: IndicatorResult], _ want: [IndicatorID: IndicatorResult], _ label: String) {
    for (id, w) in want {
      guard let g = got[id] else { #expect(Bool(false), "\(label) 少了 \(id.rawValue)"); continue }
      #expect(g.lines.count == w.lines.count, "\(label) \(id.rawValue) 线数")
      for (i, line) in w.lines.enumerated() where i < g.lines.count {
        expectSame(g.lines[i], line, "\(label) \(id.rawValue)[\(i)]", tol: 0)
      }
      if let h = w.histogram { expectSame(got[id]?.histogram ?? [], h, "\(label) \(id.rawValue) hist", tol: 0) }
    }
    #expect(Set(got.keys) == Set(want.keys), "\(label) 指标集合")
  }

  /// 随机改参数 / 加减指标 200 轮，每轮都和「全新引擎从零算」对照。
  @Test("随机改参数与增删指标 200 轮", arguments: [0, 1])
  func perIndicatorInvalidation(_ lane: Int) {
    var r = Rng(UInt64(777 + lane))
    let s = synthSeries(count: 300, seed: UInt64(41 + lane))
    var p: [IndicatorID: [Int]] = [:]
    var wanted = Self.ids
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: wanted, params: p, dataKey: "k")
    Self.same(e.values, Self.full(s, wanted, p), "lane\(lane) 初始")

    for round in 0..<200 {
      switch r.i(0, 2) {
      case 0:
        // 挑一个指标改参数。
        let id = Self.ids[r.i(0, Self.ids.count - 1)]
        var q = p[id] ?? id.defaultParams
        if !q.isEmpty { q[r.i(0, q.count - 1)] = r.i(2, 40) }
        p[id] = q
      case 1:
        // 去掉一个。
        if wanted.count > 1 { wanted.remove(at: r.i(0, wanted.count - 1)) }
      default:
        // 加回一个。
        let id = Self.ids[r.i(0, Self.ids.count - 1)]
        if !wanted.contains(id) { wanted.append(id) }
      }
      e.ensure(series: s, wanted: wanted, params: p, dataKey: "k")
      Self.same(e.values, Self.full(s, wanted, p), "lane\(lane) 第 \(round) 轮")
    }
  }

  /// 数据换了（K 线内容变了）但键碰巧还能对上时，留用老状态是错的——这里确认不会留用。
  @Test("数据变了就不许留用老状态")
  func dataChangeForcesRebuild() {
    var s = synthSeries(count: 200, seed: 12)
    var e = IndicatorEngine()
    e.ensure(series: s, wanted: [.ma, .rsi], dataKey: "d")
    // 直接戳中间某一根：根数、品种、周期、参数全没变，只有内容变了。
    s.close[100] *= 1.5
    s.high[100] *= 1.5
    // 键会一样，所以先换个参数把 `ensure` 逼进重建分支。
    e.ensure(series: s, wanted: [.ma, .rsi], params: [.ma: [5, 10, 20]], dataKey: "d")
    Self.same(e.values, Self.full(s, [.ma, .rsi], [.ma: [5, 10, 20]]), "戳过之后")
  }
}
