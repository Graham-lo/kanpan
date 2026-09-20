import Foundation
import Testing

@testable import KanpanCore

/// 提醒的纯逻辑：摊平（每个支持的种类都过一遍）与触发判定。
///
/// 方案：`docs/提醒与体验细节-实施方案-2026-09-20.md` 第 2 节。
@Suite("提醒")
struct AlertTests {
  // 时间取整点毫秒，好读；价格取整数。
  static let t0: Double = 1_700_000_000_000
  static let hour: Double = 3_600_000

  private func drawing(_ kind: Drawing.Kind, _ points: [(Double, Double)]) -> Drawing {
    Drawing(kind: kind, points: points.map { DrawPoint(t: $0.0, p: $0.1) })
  }

  // ------------------------------------------------------------------ 摊平

  @Test("水平线摊成一条两端都延的横线")
  func hline() throws {
    let lines = try #require(AlertGeometry.lines(for: drawing(.hline, [(Self.t0, 100)])))
    #expect(lines.count == 1)
    #expect(lines[0].extendLeft && lines[0].extendRight)
    #expect(lines[0].price(at: Self.t0 - 10 * Self.hour) == 100)
    #expect(lines[0].price(at: Self.t0 + 10 * Self.hour) == 100)
  }

  @Test("水平射线只往右延")
  func hray() throws {
    let lines = try #require(AlertGeometry.lines(for: drawing(.hray, [(Self.t0, 100)])))
    #expect(lines.count == 1)
    #expect(lines[0].price(at: Self.t0 - Self.hour) == nil)
    #expect(lines[0].price(at: Self.t0 + Self.hour) == 100)
  }

  @Test("十字线只取水平那一条")
  func crossLine() throws {
    let lines = try #require(AlertGeometry.lines(for: drawing(.crossLine, [(Self.t0, 100)])))
    #expect(lines.count == 1)
    #expect(lines[0].price(at: Self.t0 + 5 * Self.hour) == 100)
  }

  @Test("趋势线是线段，两头都取不到价")
  func trend() throws {
    let d = drawing(.trend, [(Self.t0, 100), (Self.t0 + 2 * Self.hour, 200)])
    let lines = try #require(AlertGeometry.lines(for: d))
    #expect(lines.count == 1)
    #expect(lines[0].price(at: Self.t0 + Self.hour) == 150)
    #expect(lines[0].price(at: Self.t0 - Self.hour) == nil)
    #expect(lines[0].price(at: Self.t0 + 3 * Self.hour) == nil)
  }

  @Test("箭头和趋势线一样是线段")
  func arrowLine() throws {
    let d = drawing(.arrowLine, [(Self.t0, 100), (Self.t0 + 2 * Self.hour, 200)])
    let lines = try #require(AlertGeometry.lines(for: d))
    #expect(lines.count == 1)
    #expect(!lines[0].extendLeft && !lines[0].extendRight)
    #expect(lines[0].price(at: Self.t0 + Self.hour) == 150)
  }

  @Test("射线往右外推")
  func ray() throws {
    let d = drawing(.ray, [(Self.t0, 100), (Self.t0 + 2 * Self.hour, 200)])
    let lines = try #require(AlertGeometry.lines(for: d))
    #expect(lines[0].price(at: Self.t0 - Self.hour) == nil)
    #expect(lines[0].price(at: Self.t0 + 4 * Self.hour) == 300)
  }

  @Test("直线两头都外推")
  func extended() throws {
    let d = drawing(.extended, [(Self.t0, 100), (Self.t0 + 2 * Self.hour, 200)])
    let lines = try #require(AlertGeometry.lines(for: d))
    #expect(lines[0].price(at: Self.t0 - 2 * Self.hour) == 0)
    #expect(lines[0].price(at: Self.t0 + 4 * Self.hour) == 300)
  }

  @Test("矩形摊成上下两条横边，左右两条竖边不要")
  func rectangle() throws {
    let d = drawing(.rectangle, [(Self.t0 + 2 * Self.hour, 90), (Self.t0, 110)])
    let lines = try #require(AlertGeometry.lines(for: d))
    #expect(lines.count == 2)
    #expect(lines[0].price(at: Self.t0 + Self.hour) == 110)
    #expect(lines[1].price(at: Self.t0 + Self.hour) == 90)
    // 只在两个锚点之间那一段。
    #expect(lines[0].price(at: Self.t0 + 3 * Self.hour) == nil)
  }

  @Test("通道摊成两条平行边，第二条过第三个点")
  func channel() throws {
    let d = drawing(.channel, [(Self.t0, 100), (Self.t0 + 2 * Self.hour, 200), (Self.t0, 130)])
    let lines = try #require(AlertGeometry.lines(for: d))
    #expect(lines.count == 2)
    // 基准边。
    #expect(lines[0].price(at: Self.t0 + Self.hour) == 150)
    // 平行边整体高 30，斜率一样，而且两端都延。
    #expect(lines[1].price(at: Self.t0 + Self.hour) == 180)
    #expect(lines[1].price(at: Self.t0 - 2 * Self.hour) == 30)
    #expect(lines[1].price(at: Self.t0 + 4 * Self.hour) == 330)
  }

  @Test("回撤每一级一条横线")
  func fibonacci() throws {
    var d = drawing(.fibonacci, [(Self.t0, 200), (Self.t0 + 2 * Self.hour, 100)])
    d.levels = [0, 0.5, 1]
    let lines = try #require(AlertGeometry.lines(for: d))
    #expect(lines.count == 3)
    // 0 是这一段行情的终点（第二个点），1 是起点（第一个点）。
    #expect(lines[0].price(at: Self.t0 + Self.hour) == 100)
    #expect(lines[1].price(at: Self.t0 + Self.hour) == 150)
    #expect(lines[2].price(at: Self.t0 + Self.hour) == 200)
  }

  @Test("摊平最多 32 条，和服务端那道闸一样")
  func fibonacciClamped() throws {
    var d = drawing(.fibonacci, [(Self.t0, 200), (Self.t0 + Self.hour, 100)])
    d.levels = (0..<50).map { Double($0) / 50 }
    let lines = try #require(AlertGeometry.lines(for: d))
    #expect(lines.count == AlertGeometry.maxLines)
  }

  @Test("不支持的种类返回 nil（不弹确认卡）")
  func unsupported() {
    #expect(AlertGeometry.lines(for: drawing(.vline, [(Self.t0, 100)])) == nil)
    #expect(AlertGeometry.lines(for: drawing(.note, [(Self.t0, 100)])) == nil)
    #expect(AlertGeometry.lines(for: drawing(.measure, [(Self.t0, 100), (Self.t0, 110)])) == nil)
    #expect(AlertGeometry.lines(for: drawing(.anchoredVWAP, [(Self.t0, 100)])) == nil)
  }

  @Test("点不够的支持种类也返回 nil，不许摊出半条线")
  func truncated() {
    #expect(AlertGeometry.lines(for: drawing(.trend, [(Self.t0, 100)])) == nil)
    #expect(AlertGeometry.lines(for: drawing(.channel, [(Self.t0, 100), (Self.t0 + 1, 110)])) == nil)
  }

  // ------------------------------------------------------------------ 触发

  private func alert(_ lines: [AlertLine], condition: Alert.Condition = .touch,
                     status: Alert.Status = .active, armedAt: Double = AlertTests.t0) -> Alert {
    Alert(symbol: "BTCUSDT", drawingID: "d1", lines: lines, condition: condition,
          armedAt: armedAt, status: status, title: "BTC 触到你画的趋势线", created: armedAt)
  }

  @Test("最高最低夹住线价就响")
  func fires() throws {
    let a = alert([AlertLine(points: [DrawPoint(t: Self.t0, p: 100)], extendLeft: true, extendRight: true)])
    let hit = try #require(AlertEvaluator.hit(a, bar: .init(openTime: Self.t0 + Self.hour, high: 105, low: 98)))
    #expect(hit.line == 0)
    #expect(hit.price == 100)
    #expect(!AlertEvaluator.fires(a, bar: .init(openTime: Self.t0 + Self.hour, high: 99, low: 95)))
    #expect(!AlertEvaluator.fires(a, bar: .init(openTime: Self.t0 + Self.hour, high: 120, low: 101)))
  }

  @Test("刚好碰到边上也算")
  func touchesEdge() {
    let a = alert([AlertLine(points: [DrawPoint(t: Self.t0, p: 100)], extendLeft: true, extendRight: true)])
    #expect(AlertEvaluator.fires(a, bar: .init(openTime: Self.t0, high: 100, low: 90)))
    #expect(AlertEvaluator.fires(a, bar: .init(openTime: Self.t0, high: 110, low: 100)))
  }

  @Test("armedAt 之前的 K 线不算")
  func beforeArmed() {
    let a = alert([AlertLine(points: [DrawPoint(t: Self.t0, p: 100)], extendLeft: true, extendRight: true)],
                  armedAt: Self.t0 + 5 * Self.hour)
    #expect(!AlertEvaluator.fires(a, bar: .init(openTime: Self.t0, high: 105, low: 95)))
    #expect(AlertEvaluator.fires(a, bar: .init(openTime: Self.t0 + 5 * Self.hour, high: 105, low: 95)))
  }

  @Test("已触发 / 已暂停的不再响")
  func inactive() {
    let line = AlertLine(points: [DrawPoint(t: Self.t0, p: 100)], extendLeft: true, extendRight: true)
    let bar = AlertEvaluator.Bar(openTime: Self.t0, high: 105, low: 95)
    #expect(!AlertEvaluator.fires(alert([line], status: .fired), bar: bar))
    #expect(!AlertEvaluator.fires(alert([line], status: .paused), bar: bar))
  }

  @Test("收盘穿过本轮前台不判")
  func closeNotEvaluatedYet() {
    let line = AlertLine(points: [DrawPoint(t: Self.t0, p: 100)], extendLeft: true, extendRight: true)
    #expect(!AlertEvaluator.fires(alert([line], condition: .close),
                                 bar: .init(openTime: Self.t0, high: 105, low: 95)))
  }

  @Test("线在这一刻没有价就不判")
  func outOfSpan() {
    let a = alert([AlertLine(points: [DrawPoint(t: Self.t0, p: 100),
                                      DrawPoint(t: Self.t0 + Self.hour, p: 100)])])
    #expect(!AlertEvaluator.fires(a, bar: .init(openTime: Self.t0 + 5 * Self.hour, high: 105, low: 95)))
    #expect(AlertEvaluator.fires(a, bar: .init(openTime: Self.t0 + Self.hour, high: 105, low: 95)))
  }

  @Test("多条线里有一条被夹住就算响，并报出是哪一条")
  func anyLine() throws {
    let a = alert([
      AlertLine(points: [DrawPoint(t: Self.t0, p: 500)], extendLeft: true, extendRight: true),
      AlertLine(points: [DrawPoint(t: Self.t0, p: 100)], extendLeft: true, extendRight: true),
    ])
    let hit = try #require(AlertEvaluator.hit(a, bar: .init(openTime: Self.t0, high: 101, low: 99)))
    #expect(hit.line == 1)
  }

  // ------------------------------------------------------------------ 距离

  @Test("离提醒线的距离按比例算，取最近的那条")
  func distance() throws {
    let a = alert([
      AlertLine(points: [DrawPoint(t: Self.t0, p: 110)], extendLeft: true, extendRight: true),
      AlertLine(points: [DrawPoint(t: Self.t0, p: 101)], extendLeft: true, extendRight: true),
    ])
    let d = try #require(AlertEvaluator.distance(from: 100, to: a, at: Self.t0))
    #expect(abs(d - 0.01) < 1e-9)
    // 已触发的不参与。
    #expect(AlertEvaluator.distance(from: 100, to: alert([], status: .fired), at: Self.t0) == nil)
  }

  // ------------------------------------------------------------------ 线协议

  @Test("身体的键和服务端那张表一字不差")
  func wireShape() throws {
    let a = alert([AlertLine(points: [DrawPoint(t: Self.t0, p: 100)], extendRight: true)])
    let data = try JSONEncoder().encode(a)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    // `id` 是本地的，上行时由 codec 摘掉拼进对象 id；这里只核对身体那 15 个。
    let body = Set(json.keys).subtracting(["id"])
    #expect(body == ["kind", "symbol", "market", "drawingID", "lines", "condition", "armedAt",
                     "once", "status", "firedAt", "firedPrice", "dueAt", "reviewID", "title", "created"])
    let lines = try #require(json["lines"] as? [[String: Any]])
    #expect(Set(lines[0].keys) == ["points", "extendLeft", "extendRight"])
    let points = try #require(lines[0]["points"] as? [[String: Any]])
    #expect(Set(points[0].keys) == ["t", "p"])
    #expect(a.market == "binance/usd_m")
  }
}
