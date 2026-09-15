import Foundation
import Testing

@testable import KanpanCore

/// M7 的模型层：吸附、拖动、撤销重做、按品种落盘。
///
/// 屏幕上那一半（手势状态机、命中、overlay）在 `KanpanChartTests/ChartDrawingTests`，
/// 这里只证「给定数，算出来对不对」。
@Suite("画线编辑")
struct DrawingEditTests {

  // ------------------------------------------------------------ 吸附

  @Test("磁吸开：时间吸根、价格吸开高低收")
  func snapOn() throws {
    let s = synthSeries(count: 200, interval: .h1, seed: 31)
    let i = 57
    let t = Double(s.time(at: i)) + Double(s.step) * 0.31      // 这根靠右一点的位置
    // 随便挑一个离「高」最近的价格
    let want = s.high[i]
    let snap = snapDrawPoint(t: t, p: want * 1.0001, series: s, magnet: true)
    #expect(snap.index == i)
    #expect(snap.point.t == Double(s.time(at: i)), "时间要吸到这根的 openTime")
    #expect(snap.point.p == want, "价格要吸到最近的 OHLC，得到 \(snap.point.p)")

    // 四个价位逐个验：稍微偏一点也要吸回自己
    for p in [s.open[i], s.high[i], s.low[i], s.close[i]] {
      let got = snapDrawPoint(t: t, p: p, series: s, magnet: true).point.p
      #expect(got == p, "\(p) 吸成了 \(got)")
    }
  }

  @Test("磁吸关：原样落点")
  func snapOff() {
    let s = synthSeries(count: 50, seed: 3)
    let snap = snapDrawPoint(t: 1.5, p: 2.5, series: s, magnet: false)
    #expect(snap.point == DrawPoint(t: 1.5, p: 2.5))
    #expect(snap.index == -1, "没吸就不该报根号，不然手势层会瞎震")
  }

  @Test("空序列不吸也不崩")
  func snapEmpty() {
    let empty = BarSeries(
      symbol: "X", interval: .h1, t0: 0, open: [], high: [], low: [], close: [], volume: [])
    let snap = snapDrawPoint(t: 9, p: 9, series: empty, magnet: true)
    #expect(snap.point == DrawPoint(t: 9, p: 9) && snap.index == -1)
  }

  /// 不等距周期（1M）：吸到的时间必须是那根真正的 openTime，不能按 `t0 + i*step` 推。
  @Test("不等距周期吸到真 openTime")
  func snapIrregular() throws {
    let times: [Int64] = [
      1_704_067_200_000,  // 2024-01
      1_706_745_600_000,  // 2024-02
      1_709_251_200_000,  // 2024-03
      1_711_929_600_000,  // 2024-04
    ]
    let s = BarSeries(
      symbol: "X", interval: .mo1, t0: times[0], step: Interval.mo1.stepMs,
      open: [1, 2, 3, 4], high: [2, 3, 4, 5], low: [0.5, 1.5, 2.5, 3.5],
      close: [1.5, 2.5, 3.5, 4.5], volume: [1, 1, 1, 1], openTime: times)
    // 三月那根靠后一点
    let t = Double(times[2]) + 5 * 86_400_000
    let snap = snapDrawPoint(t: t, p: 3.4, series: s, magnet: true)
    #expect(snap.index == 2)
    #expect(snap.point.t == Double(times[2]))
    #expect(snap.point.p == 3.5, "3.4 最近的是 close=3.5，得到 \(snap.point.p)")
  }

  // ------------------------------------------------------------ 拖动

  @Test("拖端点 / 拖整条")
  func moveParts() throws {
    let d = Drawing(
      id: "t", kind: .trend, a: DrawPoint(t: 1000, p: 10), b: DrawPoint(t: 2000, p: 20))
    let shift: (Double) -> Double = { $0 + 3 }

    let a = movedDrawing(d, part: .a, dt: 500, priceShift: shift)
    #expect(a.a == DrawPoint(t: 1500, p: 13))
    #expect(a.b == d.b, "动 a 不该碰 b")

    let b = movedDrawing(d, part: .b, dt: -500, priceShift: shift)
    #expect(b.b == DrawPoint(t: 1500, p: 23))
    #expect(b.a == d.a)

    let body = movedDrawing(d, part: .body, dt: 100, priceShift: shift)
    #expect(body.a == DrawPoint(t: 1100, p: 13))
    #expect(body.b == DrawPoint(t: 2100, p: 23))

    // 同一次手势连给两次量：都以 `from` 为基准，不累加
    let again = movedDrawing(d, part: .body, dt: 200, priceShift: { $0 + 6 })
    #expect(again.a == DrawPoint(t: 1200, p: 16))
  }

  @Test("水平线整条拖只动价格")
  func moveHLine() {
    let h = Drawing(id: "h", kind: .hline, a: DrawPoint(t: 1000, p: 10))
    let moved = movedDrawing(h, part: .body, dt: 9999, priceShift: { $0 - 2 })
    #expect(moved.a == DrawPoint(t: 1000, p: 8), "横着拖水平线没有视觉效果，时间不该动")
    #expect(moved.b == nil)
    // 没有 b 的线去动 b：当没这回事，不能崩
    #expect(movedDrawing(h, part: .b, dt: 1, priceShift: { $0 + 1 }) == h)
  }

  /// 价格按像素平移，不是按价差：对数模式下同样的 dy，低价那头走的价差更小。
  @Test("对数模式下按像素平移")
  func moveInLogMode() throws {
    let pane = Pane(indicator: nil, y: 0, h: 400)
    let r = PriceRange(lo: 100, hi: 10_000, base: 100)
    let mode = PriceMode.log
    let dy = 40.0
    let shift: (Double) -> Double = { p in
      pOf(yOf(p, pane: pane, range: r, mode: mode) + dy, pane: pane, range: r, mode: mode)
    }
    let d = Drawing(
      id: "t", kind: .trend, a: DrawPoint(t: 0, p: 200), b: DrawPoint(t: 1, p: 5000))
    let m = movedDrawing(d, part: .body, dt: 0, priceShift: shift)
    let da = 200 - m.a.p
    let db = try #require(m.b).p
    #expect(da > 0 && 5000 - db > 0, "往下拖价格该变小")
    #expect(5000 - db > da * 5, "对数轴上高价那头同样像素要走更大的价差：\(da) vs \(5000 - db)")
    // 两端在屏幕上都正好挪了 dy
    for (p0, p1) in [(200.0, m.a.p), (5000.0, db)] {
      let y0 = yOf(p0, pane: pane, range: r, mode: mode)
      let y1 = yOf(p1, pane: pane, range: r, mode: mode)
      #expect(abs(y1 - y0 - dy) < 1e-6, "像素位移对不上：\(y1 - y0)")
    }
  }

  // ------------------------------------------------------------ 撤销重做

  @Test("撤销重做走一圈")
  func historyRoundTrip() throws {
    func line(_ n: Int) -> Drawing { Drawing(id: "d\(n)", kind: .hline, a: DrawPoint(t: 0, p: Double(n))) }
    var h = DrawHistory()
    var items: [Drawing] = []
    #expect(!h.canUndo && !h.canRedo)

    for n in 1...3 {
      h.commit(before: items)
      items.append(line(n))
    }
    #expect(items.count == 3 && h.canUndo && !h.canRedo)

    // `#require` 的宏展开会把 `h` 捕成不可变的，mutating 方法只能先算再断言
    items = try #require(h.undo(current: items) as [Drawing]?)
    #expect(items.map(\.id) == ["d1", "d2"])
    items = try #require(h.undo(current: items) as [Drawing]?)
    #expect(items.map(\.id) == ["d1"])
    #expect(h.canRedo)

    items = try #require(h.redo(current: items) as [Drawing]?)
    #expect(items.map(\.id) == ["d1", "d2"])
    items = try #require(h.redo(current: items) as [Drawing]?)
    #expect(items.map(\.id) == ["d1", "d2", "d3"])
    #expect(!h.canRedo)
    #expect(h.redo(current: items) == nil)
  }

  @Test("撤销到底就停")
  func undoBottoms() {
    var h = DrawHistory()
    #expect(h.undo(current: []) == nil)
    h.commit(before: [])
    #expect(h.undo(current: [Drawing(kind: .hline, a: DrawPoint(t: 0, p: 1))]) != nil)
    #expect(h.undo(current: []) == nil)
  }

  @Test("撤销之后再动一笔，重做作废")
  func newActionDropsRedo() throws {
    let a = Drawing(id: "a", kind: .hline, a: DrawPoint(t: 0, p: 1))
    let b = Drawing(id: "b", kind: .hline, a: DrawPoint(t: 0, p: 2))
    var h = DrawHistory()
    h.commit(before: [])
    var items = [a]
    items = try #require(h.undo(current: items) as [Drawing]?)
    #expect(h.canRedo)
    h.commit(before: items)       // 撤销完又画了一条：分支了
    items = [b]
    #expect(!h.canRedo, "重做那一摞必须作废")
  }

  @Test("撤销栈有上限")
  func historyDepth() {
    var h = DrawHistory()
    for n in 0..<(DrawHistory.depth + 20) {
      h.commit(before: [Drawing(id: "d\(n)", kind: .hline, a: DrawPoint(t: 0, p: 1))])
    }
    #expect(h.past.count == DrawHistory.depth)
    #expect(h.past.first?.first?.id == "d20", "砍的该是最早那些")
  }

  @Test("clear 清两摞")
  func historyClear() {
    var h = DrawHistory()
    h.commit(before: [])
    _ = h.undo(current: [Drawing(kind: .hline, a: DrawPoint(t: 0, p: 1))])
    h.clear()
    #expect(!h.canUndo && !h.canRedo)
  }

  // ------------------------------------------------------------ 落盘

  private func hline(_ p: Double, _ id: String = Drawing.newID()) -> Drawing {
    Drawing(id: id, kind: .hline, a: DrawPoint(t: 1_700_000_000_000, p: p))
  }

  @Test("按品种隔离")
  func archivePerSymbol() {
    var a = DrawArchive()
    a["BTCUSDT"] = [hline(1), hline(2), hline(3)]
    #expect(a["BTCUSDT"].count == 3)
    #expect(a["ETHUSDT"].isEmpty, "别的品种不该看见 BTC 的线")
    a["ETHUSDT"] = [hline(9)]
    #expect(a["BTCUSDT"].count == 3 && a["ETHUSDT"].count == 1)
    // 清空的品种不占位
    a["ETHUSDT"] = []
    #expect(a.bySymbol["ETHUSDT"] == nil)
  }

  @Test("每品种上限 50")
  func archiveLimit() {
    var a = DrawArchive()
    #expect(DrawArchive.perSymbolLimit == 50)
    a["BTCUSDT"] = (0..<49).map { hline(Double($0), "d\($0)") }
    #expect(a.hasRoom(for: "BTCUSDT"))
    a["BTCUSDT"] = a["BTCUSDT"] + [hline(49, "d49")]
    #expect(a["BTCUSDT"].count == 50)
    #expect(!a.hasRoom(for: "BTCUSDT"), "满了要能报出来，交给上层提示")
    // 同步或导入超过创建上限时，存档仍保留全部用户对象。
    a["BTCUSDT"] = (0..<60).map { hline(Double($0), "d\($0)") }
    #expect(a["BTCUSDT"].count == 60)
    #expect(a["BTCUSDT"].first?.id == "d0")
  }

  @Test("存档编解码来回")
  func archiveCodable() throws {
    var a = DrawArchive()
    a["BTCUSDT"] = [
      hline(64_321.5, "h1"),
      Drawing(id: "t1", kind: .trend, a: DrawPoint(t: 1, p: 2), b: DrawPoint(t: 3, p: 4),
              color: Hex("#ff8800")),
    ]
    a["ETHUSDT"] = [hline(3210.25, "h2")]
    let data = try JSONEncoder().encode(a)
    let back = try JSONDecoder().decode(DrawArchive.self, from: data)
    #expect(back == a)
    #expect(back["BTCUSDT"].last?.color == Hex("#ff8800"))
  }

  @Test("磁盘往返")
  func diskRoundTrip() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-draw-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = DrawStore(url: dir.appendingPathComponent("nested/draws.json"))

    #expect(store.load().bySymbol.isEmpty, "还没有文件时该给一份空档，不是崩")

    var a = DrawArchive()
    a["BTCUSDT"] = [hline(64_321.5, "h1"), hline(70_000, "h2")]
    try store.save(a)                       // 目录不存在也要自己建出来
    #expect(store.load() == a)

    // 覆盖写：第二次存的才算数
    a["BTCUSDT"] = [hline(1, "h3")]
    try store.save(a)
    #expect(store.load()["BTCUSDT"].map(\.id) == ["h3"])

    // 坏文件：当空档，不抛
    try Data("{ 这不是 JSON".utf8).write(to: store.url)
    #expect(store.load().bySymbol.isEmpty)
  }

  @Test("比自己新的存档不乱读")
  func futureVersion() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-draw-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("draws.json")
    let store = DrawStore(url: url)
    try Data(#"{"v":99,"d":{"BTCUSDT":[{"id":"h","kind":"hline","a":{"t":1,"p":2}}]}}"#.utf8)
      .write(to: url)
    #expect(store.load().bySymbol.isEmpty, "看不懂的版本当空的")
    // 但磁盘上那份不许动，降级安装回去还在
    #expect(try Data(contentsOf: url).count > 0)
  }

  @Test("老存档缺字段也能读")
  func legacyArchive() throws {
    // 没有 v、没有 d 的空壳
    let bare = try JSONDecoder().decode(DrawArchive.self, from: Data("{}".utf8))
    #expect(bare.version == DrawArchive.currentVersion && bare.bySymbol.isEmpty)
    // 只有 d
    let noVersion = try JSONDecoder().decode(
      DrawArchive.self,
      from: Data(#"{"d":{"BTCUSDT":[{"id":"h","kind":"hline","a":{"t":1,"p":2}}]}}"#.utf8))
    #expect(noVersion["BTCUSDT"].count == 1)
  }
}

@Suite("Drawing v2 persistence and geometry")
struct DrawingV2Tests {
  @Test func migrateV1AndRoundTripAllTools() throws {
    let legacy = Data(#"{"v":1,"d":{"BTCUSDT":[{"id":"old","kind":"trend","a":{"t":1,"p":100},"b":{"t":2,"p":200}}]}}"#.utf8)
    var archive = try JSONDecoder().decode(DrawArchive.self, from: legacy)
    #expect(archive["BTCUSDT"][0].points == [DrawPoint(t: 1, p: 100), DrawPoint(t: 2, p: 200)])
    archive["ETHUSDT"] = Drawing.Kind.allCases.map { kind in
      var d = Drawing(kind: kind, points: (0..<kind.pointCount).map { DrawPoint(t: Double($0 + 1), p: Double(100 + $0 * 20)) })
      d.color = "#4A90E2"; d.lineWidth = 3; d.dash = .dashed; d.locked = true; d.hidden = true; d.filled = false
      return d
    }
    archive.preferences.magnet = false; archive.preferences.continuous = true
    archive.preferences.favorites = [.channel, .hray]
    archive.preferences.styles["trend"] = DrawingStyle(archive["BTCUSDT"][0])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("draws.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try DrawStore(url: url).save(archive)
    let restored = try DrawStore(url: url).read()
    #expect(restored.bySymbol == archive.bySymbol)
    #expect(restored.preferences == archive.preferences)
    #expect(restored["OTHER"].isEmpty)
  }
  @Test func failedReadCannotOverwriteOriginal() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    for content in ["broken", #"{"v":999,"d":{}}"#] {
      let bytes = Data(content.utf8); try bytes.write(to: url)
      #expect(throws: (any Error).self) { try DrawStore(url: url).save(DrawArchive()) }
      #expect(try Data(contentsOf: url) == bytes)
    }
  }
  @Test func raysClipAndNeverHitBehindOrigin() {
    let bounds = DrawBounds(left: 0, top: 0, right: 300, bottom: 200)
    let ray = Drawing(kind: .ray, a: DrawPoint(t: 100, p: 100), b: DrawPoint(t: 150, p: 100))
    let g = drawingGeometry(ray, bounds: bounds, xOf: { $0 }, yOf: { $0 })
    #expect(g.segments.count == 1)
    #expect(g.segments.first?.b == DrawPixel(300, 100))
    #expect(g.hit(x: 250, y: 100) == .body)
    #expect(g.hit(x: 50, y: 100) == nil)
    var hidden = ray; hidden.hidden = true
    #expect(drawingGeometry(hidden, bounds: bounds, xOf: { $0 }, yOf: { $0 }).hit(x: 125, y: 100) == nil)
  }
  @Test func channelIsParallelInLogCoordinates() {
    let d = Drawing(kind: .channel, points: [DrawPoint(t: 20, p: 100), DrawPoint(t: 100, p: 300), DrawPoint(t: 50, p: 400)])
    let g = drawingGeometry(d, bounds: DrawBounds(left: 0, top: 0, right: 300, bottom: 300), xOf: { $0 }, yOf: { log($0) * 30 })
    #expect(g.segments.count == 3)
    let slopes = g.segments.map { ($0.b.y - $0.a.y) / ($0.b.x - $0.a.x) }
    #expect(abs(slopes[0] - slopes[1]) < 1e-10)
    #expect(abs(slopes[0] - slopes[2]) < 1e-10)
    var locked = d; locked.locked = true
    #expect(movedDrawing(locked, part: .c, dt: 10, priceShift: { $0 + 10 }) == locked)
  }
  @Test func weakMagnetUsesPixels() {
    let s = synthSeries(count: 30, seed: 3)
    let i = 12, t = Double(s.time(at: 12)), p = s.high[12]
    let x: (Double) -> Double = { ($0 - t) / Double(s.step) * 8 }
    let y: (Double) -> Double = { log($0) * 300 }
    let near = snapDrawPoint(t: t, p: exp(log(p) + 0.01), series: s, magnet: true, xOf: x, yOf: y)
    #expect(near.index == i)
    let far = snapDrawPoint(t: t, p: p * 3, series: s, magnet: true, xOf: x, yOf: y)
    #expect(far.index == -1 && far.point.p == p * 3)
    let future = snapDrawPoint(t: t + Double(s.step) * 100, p: p, series: s, magnet: true, xOf: x, yOf: y)
    #expect(future.index == -1)
  }
}
