import Foundation
import Testing

@testable import KanpanCore

/// 锚定 VWAP 与两把成交量分布（2026-09-20）。
///
/// 这三把是仓库里头一回出现「形状要从 K 线算出来」的画线，所以这份单测分三层打：
/// 算法（数字对不对）、几何（算出来的数字摆成了什么）、以及**老工具一个像素都没动**。
/// 最后那条是这一轮改动风险最大的地方：`drawingGeometry` 多了一个参数，
/// 38 把老工具必须对它完全无感。
@Suite("锚定 VWAP 与成交量分布")
struct DrawVolumeTests {
  // ---------------------------------------------------------------- 场地

  static let t0: Int64 = 1_700_000_000_000
  static let step = Interval.h1.stepMs

  static func time(_ i: Int) -> Double { Double(t0 + Int64(i) * step) }

  /// 手造一段 K 线。写成 (开, 高, 低, 收, 量) 的元组，单测里一眼看得见每根长什么样。
  static func series(_ bars: [(Double, Double, Double, Double, Double)]) -> BarSeries {
    BarSeries(symbol: "TEST", interval: .h1, bars: bars.enumerated().map { i, b in
      Bar(openTime: t0 + Int64(i) * step, open: b.0, high: b.1, low: b.2, close: b.3, volume: b.4)
    })
  }

  /// 三根手算过的 K 线。hlc3 分别是 10、18、27。
  static let three = series([
    (10, 12, 8, 10, 100),
    (15, 22, 14, 18, 200),
    (25, 30, 24, 27, 300),
  ])

  // 几何用的坐标轴：时间线性铺 600pt，价格 0…40 线性铺 400pt（价格越高 y 越小）。
  static let bounds = DrawBounds(left: 0, top: 0, right: 600, bottom: 400)
  static func x(_ t: Double) -> Double { (t - Double(t0)) / Double(step) * 100 + 50 }
  static func y(_ p: Double) -> Double { 400 - p / 40 * 400 }

  // ================================================================ 算法：VWAP

  @Test("VWAP 逐根就是 Σ(hlc3·v)/Σv")
  func vwapIsCumulativeHLC3() throws {
    let trail = try #require(Drawing.vwapTrail(anchorT: Self.time(0), series: Self.three))
    #expect(trail.start == 0)
    #expect(trail.values.count == 3)
    // 手算：10·100/100；(10·100 + 18·200)/300；(4600 + 27·300)/600。
    #expect(abs(trail.values[0] - 10) < 1e-9)
    #expect(abs(trail.values[1] - 4600.0 / 300) < 1e-9)
    #expect(abs(trail.values[2] - 12700.0 / 600) < 1e-9)
    #expect(abs((trail.latest ?? 0) - 12700.0 / 600) < 1e-9)
  }

  @Test("锚落在两根之间，从后面那根算起")
  func anchorBetweenBarsTakesTheNextOne() throws {
    let trail = try #require(Drawing.vwapTrail(anchorT: Self.time(0) + Double(Self.step) / 2,
                                               series: Self.three))
    #expect(trail.start == 1, "锚点之前那根不该被算进去")
    #expect(trail.values.count == 2)
    #expect(abs(trail.values[0] - 18) < 1e-9, "从第二根起算，第一个值就是它自己的 hlc3")
    #expect(abs(trail.values[1] - (3600.0 + 8100) / 500) < 1e-9)
  }

  @Test("锚在末根之后 → 没有轨迹")
  func anchorAfterTheLastBarHasNothingToCompute() {
    #expect(Drawing.vwapTrail(anchorT: Self.time(2) + 1, series: Self.three) == nil)
    #expect(Drawing.vwapTrail(anchorT: Self.time(0), series: Self.series([])) == nil)
  }

  @Test("还没有成交的那一段是 NaN，不是 0")
  func theZeroVolumePrefixIsNotANumber() throws {
    let s = Self.series([(10, 12, 8, 10, 0), (15, 22, 14, 18, 0), (25, 30, 24, 27, 50)])
    let trail = try #require(Drawing.vwapTrail(anchorT: Self.time(0), series: s))
    #expect(trail.values[0].isNaN)
    #expect(trail.values[1].isNaN)
    #expect(abs(trail.values[2] - 27) < 1e-9)
  }

  // ================================================================ 算法：分布

  @Test("按价格重叠摊量，总量守恒")
  func volumeIsSplitByPriceOverlapAndConserved() throws {
    // 两根盖住完全不同的价带：第一根 0…12，第二根 12…24。
    let s = Self.series([(1, 12, 0, 10, 480), (13, 24, 12, 20, 240)])
    let vp = try #require(Drawing.volumeProfile(fromT: Self.time(0), toT: Self.time(1), series: s))
    #expect(vp.rowCount == VolumeProfile.rows)
    #expect(abs(vp.lo - 0) < 1e-9 && abs(vp.hi - 24) < 1e-9)
    #expect(abs(vp.total - 720) < 1e-9, "摊出去的量必须和原始成交量一样多")
    // 24 行 × 每行 1 个价位：下半张全是第一根的量（480/12 一行），上半张全是第二根的（240/12）。
    for row in 0 ..< 12 { #expect(abs(vp.rowTotal(row) - 40) < 1e-9, "第 \(row) 行摊错了") }
    for row in 12 ..< 24 { #expect(abs(vp.rowTotal(row) - 20) < 1e-9, "第 \(row) 行摊错了") }
  }

  @Test("一字线区间只有一行")
  func aFlatRangeCollapsesToOneRow() throws {
    let s = Self.series([(7, 7, 7, 7, 30), (7, 7, 7, 7, 70)])
    let vp = try #require(Drawing.volumeProfile(fromT: Self.time(0), toT: Self.time(1), series: s))
    #expect(vp.rowCount == 1, "24 行摊在同一个价位上只会得到 24 根零高柱子")
    #expect(vp.rowHeight == 0)
    #expect(abs(vp.total - 100) < 1e-9)
    #expect(vp.poc == 0 && vp.vaLow == 0 && vp.vaHigh == 0)
  }

  @Test("涨跌按蜡烛的口径拆")
  func upAndDownFollowTheCandleRule() throws {
    // 第一根收在开之上（涨），第二根收在开之下（跌），价带一样，量不同。
    let s = Self.series([(2, 12, 0, 11, 120), (11, 12, 0, 2, 240)])
    let vp = try #require(Drawing.volumeProfile(fromT: Self.time(0), toT: Self.time(1), series: s))
    #expect(abs(vp.up.reduce(0, +) - 120) < 1e-9)
    #expect(abs(vp.down.reduce(0, +) - 240) < 1e-9)
    // 平收（close == open）算涨，和 `ChartRenderer` 画蜡烛是同一条规矩。
    let flat = Self.series([(5, 12, 0, 5, 60)])
    let fp = try #require(Drawing.volumeProfile(fromT: Self.time(0), toT: nil, series: flat))
    #expect(abs(fp.up.reduce(0, +) - 60) < 1e-9)
    #expect(fp.down.reduce(0, +) == 0)
  }

  /// 把量精确地放进某一行：`lo = 0`、`hi = 24` 时一行正好 1 个价位。
  static func peaks(_ rows: [(row: Int, volume: Double)]) -> BarSeries {
    var bars: [(Double, Double, Double, Double, Double)] = []
    for r in rows {
      let lo = Double(r.row) + 0.25, hi = Double(r.row) + 0.75
      bars.append((lo, hi, lo, hi, r.volume))
    }
    // 撑开价格区间，让 24 行正好落在 0…24 上（这两根自己的量也要算进去）。
    bars.insert((0, 0.5, 0, 0.5, 1), at: 0)
    bars.append((23.5, 24, 23.5, 24, 1))
    return series(bars)
  }

  @Test("三峰分布：POC 在最厚那层，价值区往量大的一侧扩")
  func pocAndValueAreaLandOnTheExpectedRows() throws {
    // 第 12 行 100、第 13 行 40、第 14 行 5、第 11 行 10、第 10 行 10，两头各 1。
    let s = Self.peaks([(12, 100), (13, 40), (14, 5), (11, 10), (10, 10)])
    let vp = try #require(Drawing.volumeProfile(fromT: Self.time(0), toT: nil, series: s))
    #expect(abs(vp.total - 167) < 1e-9)
    #expect(vp.poc == 12)
    #expect(abs(vp.rowTotal(12) - 100) < 1e-9)
    // 手算：目标 167×0.7 = 116.9；从 POC 起上方两行 40+5=45 比下方两行 10+10=20 大，
    // 往上并两行到第 14 行，累计 145 ≥ 116.9，收工。
    #expect(vp.vaLow == 12 && vp.vaHigh == 14)
    let inside = (vp.vaLow ... vp.vaHigh).reduce(0.0) { $0 + vp.rowTotal($1) }
    #expect(inside >= vp.total * VolumeProfile.valueArea)
  }

  @Test("toT 为空就一直算到末根")
  func anOpenEndedProfileRunsToTheLastBar() throws {
    let s = Self.series([(1, 12, 0, 10, 480), (13, 24, 12, 20, 240), (20, 24, 18, 22, 60)])
    let open = try #require(Drawing.volumeProfile(fromT: Self.time(0), toT: nil, series: s))
    #expect(open.first == 0 && open.last == 2)
    #expect(abs(open.total - 780) < 1e-9)
    let closed = try #require(Drawing.volumeProfile(fromT: Self.time(0), toT: Self.time(1), series: s))
    #expect(closed.last == 1)
    #expect(abs(closed.total - 720) < 1e-9)
    // 区间整段落在已加载历史之前 / 之后：前者从第一根算起，后者压根没有 K 线。
    #expect(Drawing.volumeProfile(fromT: Double(Self.t0) - 1e9, toT: Self.time(0), series: s)?.first == 0)
    #expect(Drawing.volumeProfile(fromT: Self.time(2) + 1, toT: nil, series: s) == nil)
  }

  // ================================================================ 几何

  @Test("VWAP 的几何：n-1 段 + 一枚读数 + 一个手柄")
  func vwapGeometryIsATrailAReadoutAndOneHandle() {
    let d = Drawing(kind: .anchoredVWAP, a: DrawPoint(t: Self.time(0), p: 10))
    let g = drawingGeometry(d, bounds: Self.bounds, xOf: Self.x, yOf: Self.y,
                            decimals: 2, series: Self.three)
    #expect(g.segments.count == 2, "三根 K 线之间只有两段")
    #expect(g.segments.allSatisfy { !$0.dashed })
    #expect(g.fills.isEmpty)
    #expect(g.handles.count == 1)
    #expect(g.labels.count == 1 && g.labels[0].plate == .chip)
    #expect(g.labels[0].text == "21.17", "读数要按价格轴的小数位写")
    // 末段的终点就是末根的 VWAP。
    #expect(abs(g.segments[1].b.y - Self.y(12700.0 / 600)) < 1e-9)
  }

  @Test("计算结果按序列戳缓存：同一条序列只算一次，序列一改就重算，nil 也记住")
  func computedResultsAreMemoizedByRevision() {
    let memo = ComputedMemo()
    var runs = 0
    let key = ComputedMemo.Key(revision: 7, kind: 0, from: 1, to: nil)
    _ = memo.trail(key) { runs += 1; return nil }
    _ = memo.trail(key) { runs += 1; return nil }
    #expect(runs == 1, "画不出（nil）也是答案，下一帧不该再扫一遍")
    _ = memo.trail(ComputedMemo.Key(revision: 8, kind: 0, from: 1, to: nil)) { runs += 1; return nil }
    #expect(runs == 2, "换了戳就是另一条序列")
    _ = memo.profile(ComputedMemo.Key(revision: 7, kind: 1, from: 1, to: 2)) { runs += 1; return nil }
    _ = memo.profile(ComputedMemo.Key(revision: 7, kind: 1, from: 1, to: 3)) { runs += 1; return nil }
    #expect(runs == 4, "锚点不同不能串")

    // 走公开入口：缓存给的和现算的一样；序列被改过（戳变了）之后不会拿到旧答案。
    var s = Self.three
    #expect(Drawing.vwapTrail(anchorT: Self.time(0), series: s)
            == Drawing.computeVWAPTrail(anchorT: Self.time(0), series: s))
    #expect(Drawing.volumeProfile(fromT: Self.time(0), toT: nil, series: s)
            == Drawing.computeVolumeProfile(fromT: Self.time(0), toT: nil, series: s))
    let before = Drawing.vwapTrail(anchorT: Self.time(0), series: s)
    s.close[2] += 9
    s.volume[2] *= 3
    let after = Drawing.vwapTrail(anchorT: Self.time(0), series: s)
    #expect(after != before)
    #expect(after == Drawing.computeVWAPTrail(anchorT: Self.time(0), series: s))
    #expect(Drawing.volumeProfile(fromT: Self.time(0), toT: nil, series: s)
            == Drawing.computeVolumeProfile(fromT: Self.time(0), toT: nil, series: s))
  }

  @Test("VWAP 只换算屏内那一段：和逐根全扫出来的线段、读数一模一样")
  func vwapWindowMatchesTheFullScan() throws {
    // 3000 根、中间夹一段零成交（NaN 断开）；每根 2 px，图区只露出其中一截。
    var bars: [(Double, Double, Double, Double, Double)] = []
    for i in 0 ..< 3000 {
      let c = 20 + sin(Double(i) / 37) * 5
      bars.append((c - 0.3, c + 1, c - 1, c, (1200 ..< 1210).contains(i) ? 0 : 50 + Double(i % 7)))
    }
    let s = Self.series(bars)
    let d = Drawing(kind: .anchoredVWAP, a: DrawPoint(t: Self.time(5), p: 20))
    let bounds = Self.bounds
    for shift in [0.0, -900, -2380, -5800, 400, -7000] {
      let xOf = { (t: Double) in (t - Double(Self.t0)) / Double(Self.step) * 2 + shift }
      let g = drawingGeometry(d, bounds: bounds, xOf: xOf, yOf: Self.y, decimals: 2, series: s)

      // 参照：逐根全扫，屏外两端都在外的段不收。
      let trail = try #require(Drawing.computeVWAPTrail(anchorT: d.a.t, series: s))
      var want: [DrawSegment] = []
      var prev: DrawPixel?
      for (k, v) in trail.values.enumerated() {
        guard v.isFinite else { prev = nil; continue }
        let p = DrawPixel(xOf(Double(s.time(at: trail.start + k))), Self.y(v))
        if let q = prev, max(q.x, p.x) >= bounds.left - 2, min(q.x, p.x) <= bounds.right + 2 {
          want.append(DrawSegment(a: q, b: p))
        }
        prev = p
      }
      #expect(g.segments.map { [$0.a, $0.b] } == want.map { [$0.a, $0.b] }, "shift \(shift)")
      let last = try #require(trail.values.last)
      #expect(g.labels.count == 1 && g.labels[0].text == String(format: "%.2f", last))
    }
  }

  @Test("分布的几何：柱子是填充，三条横线 + 边界竖线，一枚 POC 读数")
  func profileGeometryIsBarsLinesAndOneReadout() {
    let s = Self.peaks([(12, 100), (13, 40), (14, 5), (11, 10), (10, 10)])
    let fixed = Drawing(kind: .fixedVolumeProfile, points: [
      DrawPoint(t: Self.time(0), p: 20), DrawPoint(t: Self.time(6), p: 4),
    ])
    let g = drawingGeometry(fixed, bounds: Self.bounds, xOf: Self.x, yOf: Self.y,
                            decimals: 2, series: s)
    #expect(!g.fills.isEmpty && g.fills.count <= 2 * VolumeProfile.rows)
    #expect(g.fills.allSatisfy { $0.points.count == 4 && $0.opacity != nil })
    #expect(g.segments.count == 5, "POC + VAH + VAL + 两条区间边界")
    #expect(g.segments.filter(\.dashed).count == 4, "只有 POC 是实的")
    #expect(g.handles.count == 2)
    #expect(g.labels.count == 1 && g.labels[0].plate == .chip)

    // 锚定分布只有左边一条边界。
    let anchored = Drawing(kind: .anchoredVolumeProfile, a: DrawPoint(t: Self.time(0), p: 20))
    let ag = drawingGeometry(anchored, bounds: Self.bounds, xOf: Self.x, yOf: Self.y,
                             decimals: 2, series: s)
    #expect(ag.segments.count == 4)
    #expect(ag.handles.count == 1)
  }

  @Test("整段区间滚出图区就不画：不在边上凭空钉一摞柱子和一枚 POC 胶囊")
  func profileOffScreenDrawsNothing() {
    let s = Self.peaks([(12, 100), (13, 40), (14, 5), (11, 10), (10, 10)])
    let fixed = Drawing(kind: .fixedVolumeProfile, points: [
      DrawPoint(t: Self.time(0), p: 20), DrawPoint(t: Self.time(6), p: 4),
    ])
    let anchored = Drawing(kind: .anchoredVolumeProfile, a: DrawPoint(t: Self.time(0), p: 20))
    for d in [fixed, anchored] {
      for shift in [-5000.0, 5000.0] {
        let g = drawingGeometry(d, bounds: Self.bounds, xOf: { Self.x($0) + shift }, yOf: Self.y,
                                decimals: 2, series: s)
        #expect(g.fills.isEmpty && g.segments.isEmpty && g.labels.isEmpty, "\(d.kind) 平移 \(shift)")
        #expect(g.handles.count == d.points.count, "手柄照旧给（屏外，点不到）")
      }
      // 只滚出去一半：柱子钉在图区左沿照画——根看不见也得能比长短。
      let half = drawingGeometry(d, bounds: Self.bounds, xOf: { Self.x($0) - 300 }, yOf: Self.y,
                                 decimals: 2, series: s)
      #expect(!half.fills.isEmpty && half.fills.allSatisfy { $0.points.allSatisfy { $0.x >= 0 } },
              "\(d.kind)")
    }
  }

  @Test("水平射线起点滚出右沿：线没了，价签也不留")
  func hrayPastRightEdgeHasNoLabel() {
    let off = Drawing(kind: .hray, a: DrawPoint(t: Self.time(10), p: 20))
    let g = drawingGeometry(off, bounds: Self.bounds, xOf: Self.x, yOf: Self.y, decimals: 2)
    #expect(Self.x(Self.time(10)) > Self.bounds.right, "起点确实在右沿外，这条用例才有分量")
    #expect(g.segments.isEmpty && g.labels.isEmpty)
    let on = Drawing(kind: .hray, a: DrawPoint(t: Self.time(2), p: 20))
    let og = drawingGeometry(on, bounds: Self.bounds, xOf: Self.x, yOf: Self.y, decimals: 2)
    #expect(og.segments.count == 1 && og.labels.count == 1)
  }

  @Test("点在柱子上就是点中了这条线")
  func tappingABarSelectsTheProfile() throws {
    let s = Self.peaks([(12, 100), (13, 40), (14, 5), (11, 10), (10, 10)])
    let d = Drawing(kind: .anchoredVolumeProfile, a: DrawPoint(t: Self.time(0), p: 20))
    let g = drawingGeometry(d, bounds: Self.bounds, xOf: Self.x, yOf: Self.y, decimals: 2, series: s)
    // 最长那根（POC 那一行）的正中间。
    let widest = try #require(g.fills.max(by: { $0.points[1].x - $0.points[0].x < $1.points[1].x - $1.points[0].x }))
    let cx = (widest.points[0].x + widest.points[1].x) / 2
    let cy = (widest.points[0].y + widest.points[2].y) / 2
    #expect(g.nearestHandle(x: cx, y: cy) == nil, "这一点要离手柄足够远，不然这条用例证明不了什么")
    #expect(g.hit(x: cx, y: cy) == .body)
  }

  @Test("拿不到 K 线时只剩手柄")
  func withoutASeriesOnlyTheHandlesRemain() {
    for kind in Drawing.Kind.allCases where kind.isComputed {
      let points = (0 ..< kind.pointCount).map { DrawPoint(t: Self.time($0), p: 10) }
      let g = drawingGeometry(Drawing(kind: kind, points: points), bounds: Self.bounds,
                              xOf: Self.x, yOf: Self.y, decimals: 2)
      #expect(g.segments.isEmpty && g.fills.isEmpty && g.labels.isEmpty, "\(kind) 凭空画出了形状")
      #expect(g.handles.count == kind.pointCount)
    }
  }

  // ================================================================ 老工具零回归

  /// 一份几何的逐字节写照：所有像素、颜色档、文字都摊平成一串数。
  static func digest(_ g: DrawGeometry) -> String {
    var out = ""
    for s in g.segments { out += "S \(s.a.x) \(s.a.y) \(s.b.x) \(s.b.y) \(s.tint) \(s.dashed)\n" }
    for f in g.fills {
      out += "F \(f.tint) \(String(describing: f.opacity)) "
      out += f.points.map { "\($0.x),\($0.y)" }.joined(separator: " ") + "\n"
    }
    for h in g.handles { out += "H \(h.x) \(h.y)\n" }
    for l in g.labels { out += "L \(l.point.x) \(l.point.y) \(l.text) \(l.tint) \(l.centered) \(l.plate)\n" }
    return out
  }

  @Test("老工具对 series 完全无感")
  func existingToolsAreUnaffectedByTheNewParameter() {
    // 38 把全过一遍，不只挑三把：这个参数是加在所有工具共用的那个入口上的，
    // 漏掉哪一把都可能是「这一把悄悄变了形」。
    for kind in Drawing.Kind.allCases where !kind.isComputed {
      var d = Drawing(kind: kind, points: (0 ..< kind.pointCount).map {
        DrawPoint(t: Self.time($0 * 2), p: 8 + Double($0) * 3)
      })
      d.text = "记一笔"
      let without = drawingGeometry(d, bounds: Self.bounds, xOf: Self.x, yOf: Self.y, decimals: 2)
      let with = drawingGeometry(d, bounds: Self.bounds, xOf: Self.x, yOf: Self.y,
                                 decimals: 2, series: Self.three)
      #expect(Self.digest(without) == Self.digest(with), "\(kind) 的几何被 series 改动了")
    }
  }
}
