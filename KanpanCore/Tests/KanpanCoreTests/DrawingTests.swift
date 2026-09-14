import Foundation
import Testing

@testable import KanpanCore

/// A1.12：画线几何与命中。
///
/// 与任务书的两处出入，以定版原型为准：
/// - 命中阈值任务书写「≤ 8pt」，原型是线身 `< 9`、手柄 `< 12`；
/// - 「延伸」只有水平线有（横跨整个 plot 宽），趋势线是两点之间的线段，不外延。
@Suite("画线")
struct DrawingTests {
  @Test("distSeg 与原型全等")
  func distSegMatches() {
    #expect(Fx.distSeg.count == 120, "fixture 只有 \(Fx.distSeg.count) 组")
    for r in Fx.distSeg {
      let got = distSeg(r[0], r[1], r[2], r[3], r[4], r[5])
      #expect(abs(got - r[6]) < 1e-12, "distSeg\(r.prefix(6)) = \(got)，原型 \(r[6])")
    }
  }

  /// 退化线段（两端重合）要当成点距，不能除零出 NaN。
  @Test("退化线段当点距算")
  func degenerateSegment() {
    let d = distSeg(3, 4, 0, 0, 0, 0)
    #expect(abs(d - 5) < 1e-12, "得到 \(d)")
    #expect(distSeg(0, 0, 0, 0, 0, 0) == 0)
  }

  /// 几何性质：非负、端点为零、投影落在段外时取端点距、对称。
  @Test("distSeg 的几何性质")
  func distSegProperties() {
    var r = Rng(812)
    for _ in 0..<20000 {
      let x1 = r.d(-500, 500), y1 = r.d(-500, 500)
      let x2 = r.d(-500, 500), y2 = r.d(-500, 500)
      let px = r.d(-500, 500), py = r.d(-500, 500)
      let d = distSeg(px, py, x1, y1, x2, y2)
      #expect(d >= 0 && d.isFinite)
      // 端点到自己是 0
      #expect(distSeg(x1, y1, x1, y1, x2, y2) < 1e-9)
      #expect(distSeg(x2, y2, x1, y1, x2, y2) < 1e-9)
      // 换个方向写线段，结果不变
      #expect(abs(d - distSeg(px, py, x2, y2, x1, y1)) < 1e-9)
      // 不可能比到任一端点更远
      let da = ((px - x1) * (px - x1) + (py - y1) * (py - y1)).squareRoot()
      let db = ((px - x2) * (px - x2) + (py - y2) * (py - y2)).squareRoot()
      #expect(d <= min(da, db) + 1e-9)
      // 中点连线上的点距离应当是 0
      let t = r.d(0, 1)
      let mx = x1 + t * (x2 - x1), my = y1 + t * (y2 - y1)
      #expect(distSeg(mx, my, x1, y1, x2, y2) < 1e-9)
    }
  }

  /// 三个固定映射，够测命中了：t 直接当 x、p 直接当 y（y 轴翻转在 PriceScale 里测）。
  private func xOf(_ t: Double) -> Double { t }
  private func yOf(_ p: Double) -> Double { p }

  private func hit(_ ds: [Drawing], _ px: Double, _ py: Double) -> DrawHit? {
    hitDraw(ds, px: px, py: py, xOf: xOf, yOf: yOf)
  }

  /// 水平线：横跨整宽，只看 y 距，阈值 9。
  @Test("水平线命中")
  func hlineHit() {
    let h = Drawing(id: "h1", kind: .hline, a: DrawPoint(t: 0, p: 100))
    // x 随便给，只要 y 够近就命中
    for x in [-1e6, 0.0, 37.0, 1e6] {
      #expect(hit([h], x, 100) == DrawHit(id: "h1", part: .body))
      #expect(hit([h], x, 108.9) == DrawHit(id: "h1", part: .body))
      #expect(hit([h], x, 91.1) == DrawHit(id: "h1", part: .body))
      #expect(hit([h], x, 109.6) == nil)
      #expect(hit([h], x, 90.4) == nil)
    }
    // 阈值是严格小于
    #expect(hit([h], 0, 109.5) == nil, "9 是开区间")
    #expect(hit([h], 0, 90.5) == nil)
  }

  /// 趋势线：线身阈值 9，投影落在段外不算。
  @Test("趋势线线身命中")
  func trendBodyHit() {
    let d = Drawing(id: "t1", kind: .trend,
                    a: DrawPoint(t: 0, p: 0), b: DrawPoint(t: 100, p: 0))
    #expect(hit([d], 50, 0) == DrawHit(id: "t1", part: .body))
    #expect(hit([d], 50, 8.9) == DrawHit(id: "t1", part: .body))
    #expect(hit([d], 50, 9.6) == nil)
    // 段外：离端点 20 远，超出手柄也超出线身
    #expect(hit([d], 120, 0) == nil, "线段不外延")
    #expect(hit([d], -20, 0) == nil)
    // 缺第二点的 trend（数据脏了）直接跳过，不能崩
    let broken = Drawing(id: "t2", kind: .trend, a: DrawPoint(t: 0, p: 0), b: nil)
    #expect(hit([broken], 0, 0) == nil)
  }

  /// 手柄阈值 12，且优先于线身——两者都命中时返回端点。
  @Test("手柄优先于线身")
  func handleBeatsBody() {
    let d = Drawing(id: "t1", kind: .trend,
                    a: DrawPoint(t: 0, p: 0), b: DrawPoint(t: 200, p: 0))
    // 端点正上方 5px：线身也在 9 以内，但要判成手柄
    #expect(hit([d], 0, 5) == DrawHit(id: "t1", part: .a))
    #expect(hit([d], 200, 5) == DrawHit(id: "t1", part: .b))
    // 端点正上方 11px：线身够不着了，手柄还在
    #expect(hit([d], 0, 9) == DrawHit(id: "t1", part: .a))
    #expect(hit([d], 200, -9) == DrawHit(id: "t1", part: .b))
    #expect(hit([d], 0, 12.1) == nil)
    // 沿线方向离 a 点 10：仍在手柄半径内 → a 而不是 body
    #expect(hit([d], 9, 0) == DrawHit(id: "t1", part: .a))
    #expect(hit([d], 13, 0) == DrawHit(id: "t1", part: .body))
    // 两端手柄重叠时先给 a（原型的判定顺序）
    let tiny = Drawing(id: "t3", kind: .trend,
                       a: DrawPoint(t: 0, p: 0), b: DrawPoint(t: 2, p: 0))
    #expect(hit([tiny], 1, 0) == DrawHit(id: "t3", part: .a))
  }

  /// 叠在一起时后画的在上面（从尾往前找）。
  @Test("后画的先命中")
  func topmostFirst() {
    let a = Drawing(id: "d1", kind: .hline, a: DrawPoint(t: 0, p: 100))
    let b = Drawing(id: "d2", kind: .hline, a: DrawPoint(t: 0, p: 101))
    #expect(hit([a, b], 0, 100.5)?.id == "d2")
    #expect(hit([b, a], 0, 100.5)?.id == "d1")
    #expect(hit([], 0, 0) == nil)
  }

  /// 随机对拍：命中结果必须与「按原型顺序逐条判」的朴素实现一致。
  @Test("随机命中对拍")
  func randomHitAgreesWithNaive() {
    var r = Rng(1229)
    for _ in 0..<3000 {
      var ds: [Drawing] = []
      for k in 0..<r.i(1, 5) {
        if r.d() < 0.35 {
          ds.append(Drawing(id: "h\(k)", kind: .hline, a: DrawPoint(t: 0, p: r.d(-200, 200))))
        } else {
          ds.append(Drawing(id: "t\(k)", kind: .trend,
                            a: DrawPoint(t: r.d(-200, 200), p: r.d(-200, 200)),
                            b: DrawPoint(t: r.d(-200, 200), p: r.d(-200, 200))))
        }
      }
      let px = r.d(-220, 220), py = r.d(-220, 220)
      var want: DrawHit?
      for d in ds.reversed() {
        if d.kind == .hline {
          if abs(d.a.p - py) < 9.5 { want = DrawHit(id: d.id, part: .body); break }
          continue
        }
        let b = d.b!
        if (((px - d.a.t) * (px - d.a.t) + (py - d.a.p) * (py - d.a.p)).squareRoot()) < 9.5 {
          want = DrawHit(id: d.id, part: .a); break
        }
        if (((px - b.t) * (px - b.t) + (py - b.p) * (py - b.p)).squareRoot()) < 9.5 {
          want = DrawHit(id: d.id, part: .b); break
        }
        if distSeg(px, py, d.a.t, d.a.p, b.t, b.p) < 9.5 {
          want = DrawHit(id: d.id, part: .body); break
        }
      }
      #expect(hit(ds, px, py) == want)
    }
  }

  // ------------------------------------------------------------ Store

  @Test("水平线一点落成")
  func placeHline() {
    var s = DrawingStore()
    s.place(DrawPoint(t: 1, p: 2), id: "x")   // 没选工具，什么都不该发生
    #expect(s.items.isEmpty)

    s.tool = .hline
    s.place(DrawPoint(t: 1000, p: 50), id: "h1")
    #expect(s.items.count == 1)
    #expect(s.items[0].kind == .hline)
    #expect(s.items[0].b == nil)
    #expect(s.tool == nil, "落完自动退出工具")
    #expect(s.pending == nil)
  }

  @Test("趋势线两点落成")
  func placeTrend() {
    var s = DrawingStore()
    s.tool = .trend
    s.place(DrawPoint(t: 1000, p: 50), id: "t1")
    #expect(s.items.isEmpty, "第一点只是 pending")
    #expect(s.pending == DrawPoint(t: 1000, p: 50))
    #expect(s.tool == .trend, "还在画，工具不退")

    s.place(DrawPoint(t: 2000, p: 60), id: "t1")
    #expect(s.items.count == 1)
    #expect(s.items[0].a == DrawPoint(t: 1000, p: 50))
    #expect(s.items[0].b == DrawPoint(t: 2000, p: 60))
    #expect(s.pending == nil)
    #expect(s.tool == nil)
  }

  @Test("删除与清空")
  func removeAndClear() {
    var s = DrawingStore()
    s.tool = .hline; s.place(DrawPoint(t: 0, p: 1), id: "a")
    s.tool = .hline; s.place(DrawPoint(t: 0, p: 2), id: "b")
    s.tool = .hline; s.place(DrawPoint(t: 0, p: 3), id: "c")

    s.removeSelected()
    #expect(s.items.count == 3, "没选中就不该删东西")

    s.selected = "b"
    s.removeSelected()
    #expect(s.items.map(\.id) == ["a", "c"])
    #expect(s.selected == nil)

    s.tool = .trend; s.place(DrawPoint(t: 0, p: 9))
    s.selected = "a"
    s.clear()
    #expect(s.items.isEmpty && s.selected == nil && s.pending == nil)
  }

  /// 拖动：端点只动一端、body 两端一起走，且相对量来自拖动起点的快照
  /// （不是累加当前值，否则手指抖一下就越漂越远）。
  @Test("拖动端点与整条")
  func moveParts() {
    var s = DrawingStore()
    s.tool = .trend
    s.place(DrawPoint(t: 1000, p: 50))
    s.place(DrawPoint(t: 2000, p: 60))
    let start = s.items[0]
    let id = start.id

    s.move(id: id, part: .a, from: start, dt: 100, dp: -5)
    #expect(s.items[0].a == DrawPoint(t: 1100, p: 45))
    #expect(s.items[0].b == start.b, "动 a 不该碰 b")

    s.move(id: id, part: .b, from: start, dt: -300, dp: 7)
    #expect(s.items[0].b == DrawPoint(t: 1700, p: 67))
    #expect(s.items[0].a == DrawPoint(t: 1100, p: 45), "动 b 不该回滚 a")

    // 同一次手势里连续给量，始终以 start 为基准 → 不累加
    s.move(id: id, part: .body, from: start, dt: 10, dp: 1)
    s.move(id: id, part: .body, from: start, dt: 20, dp: 2)
    #expect(s.items[0].a == DrawPoint(t: 1020, p: 52))
    #expect(s.items[0].b == DrawPoint(t: 2020, p: 62))

    // 水平线拖 body 只动它那一个点，没有 b 不能崩
    var h = DrawingStore()
    h.tool = .hline
    h.place(DrawPoint(t: 0, p: 100), id: "h")
    let hs = h.items[0]
    h.move(id: "h", part: .body, from: hs, dt: 500, dp: -10)
    #expect(h.items[0].a == DrawPoint(t: 500, p: 90))
    #expect(h.items[0].b == nil)
    h.move(id: "h", part: .b, from: hs, dt: 1, dp: 1)
    #expect(h.items[0].b == nil, "没有 b 就当没这回事")

    // 不存在的 id 静默忽略
    h.move(id: "nope", part: .a, from: hs, dt: 1, dp: 1)
    #expect(h.items.count == 1)
  }

  /// 价格区间要把画线端点算进去（§5.4）。
  @Test("画线价格进区间")
  func pricesFeedRange() {
    var s = DrawingStore()
    #expect(s.prices.isEmpty)
    s.tool = .hline; s.place(DrawPoint(t: 0, p: 100))
    s.tool = .trend; s.place(DrawPoint(t: 0, p: 50)); s.place(DrawPoint(t: 1, p: 150))
    #expect(s.prices.sorted() == [50, 100, 150])

    let series = synthSeries(count: 200, interval: .h1, t0: 1_700_000_000_000, seed: 7)
    let view = ViewWindow(to: Double(series.t0 + series.step * Int64(series.count)), span: 100 * 3_600_000)
    let base = priceRange(view: view, series: series)
    let with = priceRange(view: view, series: series, drawingPrices: s.prices)
    #expect(with.lo <= min(base.lo, 50) + 1e-9 && with.hi >= max(base.hi, 150) - 1e-9,
            "画线端点没被算进区间：\(with) vs \(base)")
  }

  /// ID 唯一：连着落几条不能撞号。
  @Test("默认 ID 不撞")
  func idsUnique() {
    var s = DrawingStore()
    for _ in 0..<50 {
      s.tool = .hline
      s.place(DrawPoint(t: 0, p: 1))
    }
    #expect(Set(s.items.map(\.id)).count == 50, "有重号：\(s.items.map(\.id))")
  }

  /// 画线是可编解码的（存本地用），来回一趟不掉字段。
  @Test("编解码来回")
  func codableRoundTrip() throws {
    let ds = [
      Drawing(id: "h", kind: .hline, a: DrawPoint(t: 1e12, p: 0.00012345)),
      Drawing(id: "t", kind: .trend, a: DrawPoint(t: 1, p: 2), b: DrawPoint(t: 3, p: 4), color: Hex("#ff8800")),
    ]
    let data = try JSONEncoder().encode(ds)
    #expect(try JSONDecoder().decode([Drawing].self, from: data) == ds)
  }
}
