import Foundation
import Testing

@testable import KanpanCore

/// 第五轮审查 A.5「测试缺口」里落在纯计算这一层的那几条。
///
/// 编号沿用报告里的表格（1、2、6、8、14、15、16、17）。另外那几条要真 `UITouch`
/// 或者宿主视图，在 `KanpanChart/Tests/KanpanChartTests/ChartReviewA5Tests.swift`；
/// 转屏往返那条（10）只能是 UI 用例，在 `Kanpan/KanpanUITests`。
@Suite("A.5 测试缺口 · 纯计算")
struct ReviewA5Tests {
  // ---------------------------------------------------------------- 场地

  static let plotW = 390.0
  static let paneY = 40.0
  static let paneH = 420.0
  static let bounds = DrawBounds(left: 0, top: paneY, right: plotW, bottom: paneY + paneH)
  static let t0 = 1_700_000_000_000.0
  static let t1 = t0 + 120 * 3_600_000
  static let pLow = 60_000.0
  static let pHigh = 66_000.0

  static func x(_ t: Double) -> Double { (t - t0) / (t1 - t0) * plotW }
  static func t(_ x: Double) -> Double { t0 + x / plotW * (t1 - t0) }
  static func y(_ p: Double) -> Double { paneY + (pHigh - p) / (pHigh - pLow) * paneH }
  static func p(_ y: Double) -> Double { pHigh - (y - paneY) / paneH * (pHigh - pLow) }
  /// 对数轴。用例 14 要求两种价格轴都过一遍。
  static func logY(_ v: Double) -> Double {
    let lo = log(pLow), hi = log(pHigh)
    return paneY + (hi - log(max(v, 1e-9))) / (hi - lo) * paneH
  }

  /// 量字：测试里不请 UIKit，按等宽近似给一个稳定尺寸就够——排版算法只关心宽高。
  static func measure(_ s: String) -> DrawTextSize {
    DrawTextSize(width: Double(s.count) * 6, height: 11)
  }

  static func point(x px: Double, y py: Double) -> DrawPoint {
    DrawPoint(t: t(px), p: p(py))
  }

  // ---------------------------------------------------------------- 1 文字命中

  @Test("用例 1：文字标注点字中段命中线体，字外不命中")
  func case1_labelIsHittable() throws {
    var note = Drawing(kind: .note, a: Self.point(x: 120, y: 300))
    note.text = "这里是一段足够长的文字标注，用来验证点在字中段也能选中"
    var g = drawingGeometry(note, bounds: Self.bounds, xOf: Self.x, yOf: Self.y, decimals: 2)
    let placed = g.layoutLabels(plotW: Self.plotW, paneY: Self.paneY, paneH: Self.paneH,
                                measure: Self.measure)
    let box = try #require(placed.first?.box, "文字标注排不出任何一块字")
    // 字块本身宽出手柄的命中半径一大截，正是 A-01 报的那件事：从前只有锚点周围 9.5pt 有反应。
    #expect(box.right - box.left > Chart.selectedHandlePt * 2)
    let mid = DrawPixel((box.left + box.right) / 2, (box.top + box.bottom) / 2)
    #expect(hypot(mid.x - 120, mid.y - 300) > Chart.selectedHandlePt,
            "字中段离锚点不到 22pt，这条用例就证明不了什么")
    #expect(g.inkDistance(x: mid.x, y: mid.y) == 0, "点字中段没命中")
    #expect(g.hit(x: mid.x, y: mid.y) == .body, "点字中段该算线体，不是手柄")
    // 字外面：右侧 40pt，纵向同高。
    #expect(g.inkDistance(x: box.right + 40, y: mid.y) == nil, "字外面也命中了")
    #expect(g.hit(x: box.right + 40, y: mid.y) == nil)
  }

  @Test("用例 1：排版与命中共用同一批矩形")
  func case1_boxesAreTheSameSource() throws {
    var note = Drawing(kind: .note, a: Self.point(x: 200, y: 260))
    note.text = "同源"
    var g = drawingGeometry(note, bounds: Self.bounds, xOf: Self.x, yOf: Self.y, decimals: 2)
    let placed = g.layoutLabels(plotW: Self.plotW, paneY: Self.paneY, paneH: Self.paneH,
                                measure: Self.measure)
    #expect(g.labelBoxes.count == placed.count)
    for (a, b) in zip(g.labelBoxes, placed.map(\.box)) {
      #expect(a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom)
    }
  }

  // ---------------------------------------------------------------- 2 选中体不吞下层

  @Test("用例 2：选中的大矩形吞不掉压在里面的趋势线")
  func case2_fillDoesNotSwallowInnerLine() throws {
    let rect = Drawing(kind: .rectangle, a: Self.point(x: 60, y: 120), b: Self.point(x: 330, y: 400))
    let line = Drawing(kind: .trend, a: Self.point(x: 90, y: 300), b: Self.point(x: 300, y: 300))
    let rg = drawingGeometry(rect, bounds: Self.bounds, xOf: Self.x, yOf: Self.y, decimals: 2)
    let lg = drawingGeometry(line, bounds: Self.bounds, xOf: Self.x, yOf: Self.y, decimals: 2)
    // 矩形被选中时手柄靶放大到 22pt，但**只放大手柄**：线体和填充照旧。
    let q = DrawPixel(200, 300)
    #expect(rg.nearestHandle(x: q.x, y: q.y, radius: Chart.selectedHandlePt) == nil,
            "线身正中离矩形四角远得很，不该被当成手柄")
    #expect(rg.inkDistance(x: q.x, y: q.y) == nil, "矩形的边离这儿很远，不该算线体")
    #expect(rg.hitsFill(x: q.x, y: q.y), "矩形的填充确实盖住了这一点")
    // 三遍仲裁的次序：线体整层比完才轮到填充，所以这一点归趋势线。
    let ink = try #require(lg.inkDistance(x: q.x, y: q.y), "内部趋势线该在线体这一层被收走")
    #expect(ink < Chart.hitLinePt)
  }

  @Test("用例 2：真点在矩形手柄上仍然优先手柄")
  func case2_handleStillWins() throws {
    let rect = Drawing(kind: .rectangle, a: Self.point(x: 60, y: 120), b: Self.point(x: 330, y: 400))
    let g = drawingGeometry(rect, bounds: Self.bounds, xOf: Self.x, yOf: Self.y, decimals: 2)
    let near = try #require(g.nearestHandle(x: 62, y: 122, radius: Chart.selectedHandlePt),
                            "点在角上没抓到手柄")
    #expect(g.hit(x: 62, y: 122, handleRadius: Chart.selectedHandlePt) == .anchor(near.index))
    // 两个角都够得着时比的是真实距离，不是谁先被遍历到。
    let mid = g.nearestHandle(x: Self.x(rect.a.t) + 1, y: Self.y(rect.a.p) + 1,
                              radius: Chart.selectedHandlePt)
    #expect(mid?.index == 0)
  }

  // ---------------------------------------------------------------- 6 切周期锚点

  @Test("用例 6：历史右缘切周期来回，右缘与根宽都不动")
  func case6_historyAnchorSurvivesRoundTrip() {
    let h1 = synthSeries(count: 2000, interval: .h1, t0: 1_700_000_000_000)
    let h4 = synthSeries(count: 800, interval: .h4, t0: 1_700_000_000_000)
    let spacing = 8.0
    let span = Self.plotW / spacing * Double(h1.step)
    let history = clampView(ViewWindow(to: Double(h1.lastTime) - span * 3, span: span),
                            series: h1, plotW: Self.plotW)
    let measured = history.barSpacing(step: h1.step, plotW: Self.plotW)
    let toH4 = ViewMath.switchInterval(to: h4, plotW: Self.plotW, spacing: measured,
                                       anchorRight: history.to)
    #expect(abs(toH4.barSpacing(step: h4.step, plotW: Self.plotW) - 8) < 1e-9)
    #expect(abs(toH4.to - history.to) < 1e-6)
    let back = ViewMath.switchInterval(to: h1, plotW: Self.plotW,
                                       spacing: toH4.barSpacing(step: h4.step, plotW: Self.plotW),
                                       anchorRight: toH4.to)
    #expect(abs(back.barSpacing(step: h1.step, plotW: Self.plotW) - 8) < 1e-9)
    #expect(abs(back.to - history.to) < 1e-6, "来回一趟右缘漂了")
  }

  @Test("用例 6：跟着最新的视野切周期永远贴住新末根")
  func case6_followingLatestSticksToTheNewLastBar() {
    let spacing = 8.0
    for iv in Interval.allCases {
      let s = synthSeries(count: 600, interval: iv, t0: 1_700_000_000_000)
      // `anchorRight: nil` = 「我跟着最新」。这正是 `ChartHost` 在右缘时该传的东西。
      let v = ViewMath.switchInterval(to: s, plotW: Self.plotW, spacing: spacing, anchorRight: nil)
      let latest = ViewMath.reset(series: s, plotW: Self.plotW, spacing: spacing)
      #expect(abs(v.to - latest.to) < 1e-9, "\(iv.rawValue)：跟随态没贴住新末根")
      #expect(v.to >= Double(s.lastTime), "\(iv.rawValue)：末根被切到视野外面去了")
      // 拿旧周期那个具体的右缘去锚，只会把视野钉在旧时刻上——这是从前那条路。
      let stale = ViewMath.switchInterval(to: s, plotW: Self.plotW, spacing: spacing,
                                          anchorRight: Double(s.lastTime) - Double(s.step) * 40)
      #expect(stale.to < latest.to, "拿具体右缘锚的那条路本该停在历史上")
    }
  }

  // ---------------------------------------------------------------- 8 无关桶不清 undo

  @Test("用例 8：只有 ETH 变了，BTC 那一桶判定为没变")
  func case8_unrelatedBucketIsNotAChange() {
    var before = DrawArchive()
    before["BTCUSDT"] = [Drawing(kind: .trend, a: DrawPoint(t: 1, p: 2), b: DrawPoint(t: 3, p: 4))]
    before["ETHUSDT"] = [Drawing(kind: .hline, a: DrawPoint(t: 5, p: 6))]
    var after = before
    after["ETHUSDT"] = before["ETHUSDT"] + [Drawing(kind: .hline, a: DrawPoint(t: 7, p: 8))]
    #expect(after != before, "整份存档确实不相等——这正是从前无条件重灌的原因")
    #expect(!after.bucketChanged(from: before, symbol: "BTCUSDT"), "BTC 那一桶没动，却报了变")
    #expect(after.bucketChanged(from: before, symbol: "ETHUSDT"))
    // 偏好跟着云端走，不影响任何一桶的判定。
    var prefsOnly = before
    prefsOnly.preferences.magnet.toggle()
    #expect(prefsOnly != before)
    #expect(!prefsOnly.bucketChanged(from: before, symbol: "BTCUSDT"))
  }

  @Test("用例 8：BTC 真被外部替换时照样报变")
  func case8_realExternalReplacementStillReports() {
    var before = DrawArchive()
    let keep = Drawing(kind: .trend, a: DrawPoint(t: 1, p: 2), b: DrawPoint(t: 3, p: 4))
    before["BTCUSDT"] = [keep]
    var after = before
    after["BTCUSDT"] = [keep, Drawing(kind: .hline, a: DrawPoint(t: 9, p: 9))]
    #expect(after.bucketChanged(from: before, symbol: "BTCUSDT"))
    var removed = before
    removed["BTCUSDT"] = []
    #expect(removed.bucketChanged(from: before, symbol: "BTCUSDT"))
    // 没听说过的品种：两边都是空桶，不算变。
    #expect(!after.bucketChanged(from: before, symbol: "SOLUSDT"))
  }

  // ---------------------------------------------------------------- 14 41 种几何矩阵

  /// 这张场地对应的 K 线：t0…t1 之间每小时一根，价格在 pLow…pHigh 之间来回走。
  ///
  /// 锚定 VWAP 和两把成交量分布的形状是**从 K 线算出来的**，没有 `series` 就什么都画不出来
  /// （这是有意的：宁可空着也不画一条骗人的线）。所以这条矩阵得把 K 线一起递进去，
  /// 否则那三把工具会以「图上一片空白」的名义误报。其余 38 把对这个参数完全无感，
  /// 「老工具零回归」那条在 `DrawVolumeTests` 里按位比过。
  static let series: BarSeries = {
    let step = Interval.h1.stepMs
    let bars = (0...120).map { i -> Bar in
      let phase = Double(i) / 120 * 2 * Double.pi
      let mid = (pLow + pHigh) / 2 + sin(phase) * (pHigh - pLow) / 3
      let open = mid - 40, close = mid + 40
      return Bar(openTime: Int64(t0) + Int64(i) * step,
                 open: open, high: max(open, close) + 60, low: min(open, close) - 60,
                 close: close, volume: 100 + Double(i % 7) * 30)
    }
    return BarSeries(symbol: "BTCUSDT", interval: .h1, bars: bars)
  }()

  /// 每种工具摆一份合法的最小点数。点位一律落在图区里面，彼此错开。
  static func sample(_ kind: Drawing.Kind, degenerate: Bool = false) -> Drawing {
    var pts: [DrawPoint] = []
    for i in 0..<kind.pointCount {
      let px = degenerate ? 150.0 : 60 + Double(i) * 38
      let py = degenerate ? 250.0 : 130 + Double(i % 4) * 47
      pts.append(point(x: px, y: py))
    }
    var d = Drawing(kind: kind, points: pts)
    d.text = "标注"
    return d
  }

  @Test("用例 14：41 种工具，两种价格轴，几何全是有限数且看得见就点得中",
        arguments: Drawing.Kind.allCases)
  func case14_geometryMatrix(_ kind: Drawing.Kind) {
    #expect(Drawing.Kind.allCases.count == 41, "工具清单变了，这条矩阵要跟着更新")
    for logAxis in [false, true] {
      let yOf: (Double) -> Double = { logAxis ? Self.logY($0) : Self.y($0) }
      let item = Self.sample(kind)
      #expect(item.isValid, "\(kind.rawValue)：最小点数摆出来的这条线自己就不合法")
      var g = drawingGeometry(item, bounds: Self.bounds, xOf: Self.x, yOf: yOf, decimals: 2,
                              series: Self.series)
      g.layoutLabels(plotW: Self.plotW, paneY: Self.paneY, paneH: Self.paneH, measure: Self.measure)

      let finite = g.segments.allSatisfy {
        $0.a.x.isFinite && $0.a.y.isFinite && $0.b.x.isFinite && $0.b.y.isFinite
      }
        && g.handles.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        && g.fills.allSatisfy { $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite } }
      #expect(finite, "\(kind.rawValue) log=\(logAxis)：几何里有 NaN / 无穷")
      #expect(!g.segments.isEmpty || !g.fills.isEmpty || !g.labels.isEmpty,
              "\(kind.rawValue)：什么都没生成，图上会是一片空白")

      // 看得见的线段：取中点，必须点得中。
      for s in g.segments {
        let mid = DrawPixel((s.a.x + s.b.x) / 2, (s.a.y + s.b.y) / 2)
        guard Self.bounds.contains(mid) else { continue }
        #expect(g.inkDistance(x: mid.x, y: mid.y) != nil,
                "\(kind.rawValue) log=\(logAxis)：线段中点点不中")
      }
      // 看得见的字：排好版的矩形中心必须点得中。
      for box in g.labelBoxes {
        let c = DrawPixel((box.left + box.right) / 2, (box.top + box.bottom) / 2)
        #expect(g.inkDistance(x: c.x, y: c.y) == 0, "\(kind.rawValue)：字点不中")
      }
      // 每个锚点都是手柄。
      for (i, h) in g.handles.enumerated() where Self.bounds.contains(h) {
        #expect(g.nearestHandle(x: h.x, y: h.y)?.index == i, "\(kind.rawValue)：第 \(i) 个手柄点不中")
      }
    }
  }

  @Test("用例 14：退化成一点也不产生 NaN，隐藏就整条不命中",
        arguments: Drawing.Kind.allCases)
  func case14_degenerateAndHidden(_ kind: Drawing.Kind) {
    let flat = Self.sample(kind, degenerate: true)
    let g = drawingGeometry(flat, bounds: Self.bounds, xOf: Self.x, yOf: Self.y, decimals: 2)
    let finite = g.segments.allSatisfy {
      $0.a.x.isFinite && $0.a.y.isFinite && $0.b.x.isFinite && $0.b.y.isFinite
    } && g.handles.allSatisfy { $0.x.isFinite && $0.y.isFinite }
    #expect(finite, "\(kind.rawValue)：点全重合时算出了 NaN")

    var hidden = Self.sample(kind)
    hidden.hidden = true
    let hg = drawingGeometry(hidden, bounds: Self.bounds, xOf: Self.x, yOf: Self.y, decimals: 2)
    #expect(hg.segments.isEmpty && hg.fills.isEmpty && hg.handles.isEmpty && hg.labels.isEmpty)
    #expect(hg.hit(x: 150, y: 250) == nil, "\(kind.rawValue)：隐藏了还能点中")
  }

  @Test("用例 14：整条拖动时每个锚点的像素位移一模一样",
        arguments: Drawing.Kind.allCases)
  func case14_dragMatchesProjection(_ kind: Drawing.Kind) {
    let item = Self.sample(kind)
    let dx = 23.0, dy = 17.0
    let dt = Self.t(dx) - Self.t(0)
    let moved = movedDrawing(item, part: .body, dt: dt,
                             priceShift: { Self.p(Self.y($0) + dy) })
    let before = drawingGeometry(item, bounds: Self.bounds, xOf: Self.x, yOf: Self.y).handles
    let after = drawingGeometry(moved, bounds: Self.bounds, xOf: Self.x, yOf: Self.y).handles
    #expect(before.count == after.count)
    for (a, b) in zip(before, after) {
      // 水平线不跟着横移，竖线不跟着纵移——这是 `movedDrawing` 的既定规则。
      let ex = kind == .hline ? 0 : dx
      let ey = kind == .vline ? 0 : dy
      #expect(abs((b.x - a.x) - ex) < 1e-6, "\(kind.rawValue)：横向位移 \(b.x - a.x) != \(ex)")
      #expect(abs((b.y - a.y) - ey) < 1e-6, "\(kind.rawValue)：纵向位移 \(b.y - a.y) != \(ey)")
    }
    // 锁上的线一个像素都不许动。
    var locked = item
    locked.locked = true
    #expect(movedDrawing(locked, part: .body, dt: dt, priceShift: { Self.p(Self.y($0) + dy) }) == locked)
  }

  // ---------------------------------------------------------------- 15 磁吸与未来

  @Test("用例 15：末根右侧 2pt 吸末根，20pt 保留未来时刻")
  func case15_magnetNearFutureOnly() {
    let s = synthSeries(count: 300, interval: .h1, t0: 1_700_000_000_000)
    // 把末根摆在图区中间，右边留一大片「未来」。
    let spacing = 8.0
    let span = Self.plotW / spacing * Double(s.step)
    let view = ViewWindow(to: Double(s.lastTime) + span * 0.4, span: span)
    let xOf: (Double) -> Double = { view.x($0, plotW: Self.plotW) }
    let lastX = xOf(Double(s.lastTime))
    let i = s.count - 1
    let close = s.close[i]

    let near = snapDrawPoint(t: view.t(atX: lastX + 2, plotW: Self.plotW), p: close + 0.0001,
                             series: s, magnet: true, xOf: xOf, yOf: Self.y)
    #expect(near.index == i, "末根右边 2pt 没吸住末根")
    #expect(near.point.t == Double(s.lastTime))
    #expect([s.open[i], s.high[i], s.low[i], s.close[i]].contains(near.point.p))

    let farT = view.t(atX: lastX + 20, plotW: Self.plotW)
    let far = snapDrawPoint(t: farT, p: close, series: s, magnet: true, xOf: xOf, yOf: Self.y)
    #expect(far.index == -1, "离末根 20pt 还被吸回去了")
    #expect(far.point.t == farT, "未来那个时刻被改写了")
    #expect(far.point.t > Double(s.lastTime), "落在未来的锚点本来就该留在未来")
  }

  @Test("用例 15：价格够近才吸，远了停在手指上")
  func case15_priceProximity() {
    let s = synthSeries(count: 300, interval: .h1, t0: 1_700_000_000_000)
    let i = s.count - 1
    let view = ViewWindow(to: Double(s.lastTime), span: Double(s.step) * 48)
    let xOf: (Double) -> Double = { view.x($0, plotW: Self.plotW) }
    let t = Double(s.time(at: i))
    // 纵向离最近的那个 OHLC 差 40pt：超出 10pt 的弱磁吸半径。
    let farP = Self.p(Self.y(s.close[i]) + 40)
    let far = snapDrawPoint(t: t, p: farP, series: s, magnet: true, xOf: xOf, yOf: Self.y)
    #expect(far.index == -1)
    #expect(far.point.p == farP)
    // 关掉磁吸：原样返回，索引恒为 -1。
    let off = snapDrawPoint(t: t, p: s.high[i], series: s, magnet: false, xOf: xOf, yOf: Self.y)
    #expect(off.index == -1 && off.point.t == t && off.point.p == s.high[i])
  }

  @Test("用例 15：换品种之后第一笔吸的是新品种那根")
  func case15_firstStrokeAfterSymbolSwitch() {
    let a = synthSeries(count: 300, interval: .h1, t0: 1_700_000_000_000, seed: 11)
    let b = synthSeries(count: 300, interval: .h1, t0: 1_700_000_000_000, seed: 77)
    let view = ViewWindow(to: Double(a.lastTime), span: Double(a.step) * 48)
    let xOf: (Double) -> Double = { view.x($0, plotW: Self.plotW) }
    let i = 200
    let t = Double(a.time(at: i))
    let snapA = snapDrawPoint(t: t, p: a.high[i], series: a, magnet: true, xOf: xOf, yOf: Self.y)
    let snapB = snapDrawPoint(t: t, p: b.high[i], series: b, magnet: true, xOf: xOf, yOf: Self.y)
    #expect(snapA.point.p == a.high[i])
    #expect(snapB.point.p == b.high[i])
    // 吸附只看传进来的这份序列，没有任何跨品种的记忆。
    #expect(snapA.point.p != snapB.point.p)
  }

  // ---------------------------------------------------------------- 16 cap 与撤销

  @Test("用例 16：49 → 50 还能加，第 51 条一律拒绝")
  func case16_capNeverShows51() {
    var archive = DrawArchive()
    let make = { (k: Int) in Drawing(kind: .hline, a: DrawPoint(t: Double(k), p: Double(k))) }
    archive["BTCUSDT"] = (0..<49).map(make)
    #expect(archive.hasRoom(for: "BTCUSDT"))
    archive["BTCUSDT"] = archive["BTCUSDT"] + [make(49)]
    #expect(archive["BTCUSDT"].count == DrawArchive.perSymbolLimit)
    #expect(!archive.hasRoom(for: "BTCUSDT"), "满了还说有位置，界面就会先显示第 51 条再丢掉")
    // 别的品种自己算自己的。
    #expect(archive.hasRoom(for: "ETHUSDT"))
  }

  @Test("用例 16：新的编辑把重做那一摞作废，撤销不跨品种")
  func case16_undoRedoBranching() {
    let one = [Drawing(kind: .hline, a: DrawPoint(t: 1, p: 1))]
    let two = one + [Drawing(kind: .hline, a: DrawPoint(t: 2, p: 2))]
    let three = two + [Drawing(kind: .hline, a: DrawPoint(t: 3, p: 3))]
    var h = DrawHistory()
    h.commit(before: one)
    h.commit(before: two)
    #expect(h.undo(current: three) == two)
    #expect(h.canRedo)
    // 撤销之后又画了新的一条：分支了，重做回不去。
    h.commit(before: two)
    #expect(!h.canRedo, "新的编辑没把重做作废")
    #expect(h.undo(current: three) == two)
    // 换品种把整摞清掉：BTC 的撤销绝不能撤到 ETH 上去。
    h.clear()
    #expect(!h.canUndo && !h.canRedo)
    #expect(h.undo(current: three) == nil)
  }

  // ---------------------------------------------------------------- 17 手势归属

  @Test("用例 17：主区 / 副图 / 轴，每一点恰好一个所有者")
  func case17_everyPointHasExactlyOneOwner() {
    let main = Pane(indicator: nil, y: 0, h: 300)
    let macd = Pane(indicator: .macd, y: 300, h: 90)
    let kdj = Pane(indicator: .kdj, y: 390, h: 90)
    let panes = [main, macd, kdj]
    let plotW = 344.0
    for x in stride(from: 4.0, through: 380, by: 8) {
      for y in stride(from: 4.0, through: 470, by: 6) {
        let pane = ChartGestureRoute.reorderPane(x: x, y: y, plotWidth: plotW, panes: panes)
        if x >= plotW {
          #expect(pane == nil, "价格轴上的 (\(x), \(y)) 被判给了副图")
          continue
        }
        let expected: IndicatorID? =
          y >= kdj.y ? (y < kdj.y + kdj.h ? .kdj : nil)
          : (y >= macd.y ? .macd : nil)
        #expect(pane == expected, "(\(x), \(y)) 的所有者判错了")
      }
    }
  }

  @Test("用例 17：主区纵拖不滚整页，副图换序不改 X 的归属")
  func case17_pageScrollOwnership() {
    let plotW = 344.0, mainH = 300.0
    // 主区、自动纵轴：纵向拖动交给父容器滚页（这是既定分工）。
    #expect(ChartGestureRoute.pageScroll(x: 150, y: 100, dx: 0, dy: 40, touches: 1,
                                         plotWidth: plotW, mainHeight: mainH,
                                         manualY: false, selecting: false))
    // 同一点，用户已经手动定过标：纵拖归图自己，不许滚页。
    #expect(!ChartGestureRoute.pageScroll(x: 150, y: 100, dx: 0, dy: 40, touches: 1,
                                          plotWidth: plotW, mainHeight: mainH,
                                          manualY: true, selecting: false))
    // 价格轴上纵拖是改缩放，不滚页。
    #expect(!ChartGestureRoute.pageScroll(x: plotW + 20, y: 100, dx: 0, dy: 40, touches: 1,
                                          plotWidth: plotW, mainHeight: mainH,
                                          manualY: false, selecting: false))
    // 十字线在跟手时一概不滚页。
    #expect(!ChartGestureRoute.pageScroll(x: 150, y: 100, dx: 0, dy: 40, touches: 1,
                                          plotWidth: plotW, mainHeight: mainH,
                                          manualY: false, selecting: true))
    // 横向为主的手势是拖图，不是滚页；两指也不滚页。
    #expect(!ChartGestureRoute.pageScroll(x: 150, y: 100, dx: 40, dy: 10, touches: 1,
                                          plotWidth: plotW, mainHeight: mainH,
                                          manualY: false, selecting: false))
    #expect(!ChartGestureRoute.pageScroll(x: 150, y: 100, dx: 0, dy: 40, touches: 2,
                                          plotWidth: plotW, mainHeight: mainH,
                                          manualY: false, selecting: false))
    // 副图区（y > mainH）纵拖照常滚页，换不换序都一样——归属只看 y，和顺序无关。
    #expect(ChartGestureRoute.pageScroll(x: 150, y: 360, dx: 0, dy: 40, touches: 1,
                                         plotWidth: plotW, mainHeight: mainH,
                                         manualY: true, selecting: false))
  }
}
