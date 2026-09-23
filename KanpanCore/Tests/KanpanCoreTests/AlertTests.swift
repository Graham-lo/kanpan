import Foundation
import Testing

@testable import KanpanCore

/// 提醒的纯逻辑：摊平（每个支持的种类都过一遍）与触发判定。
///
/// 方案：`71bd340:docs/提醒与体验细节-实施方案-2026-09-20.md` 第 2 节。
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

  // -------------------------------------------------------------- 收盘穿过

  /// 一条两端都延的横线，价在 100。
  private var flat100: AlertLine {
    AlertLine(points: [DrawPoint(t: Self.t0, p: 100)], extendLeft: true, extendRight: true)
  }

  /// 一根 `.close` 用的 K 线：收没收、收在哪、上一根收在哪。
  private func closedBar(_ openTime: Double, previous: Double?, close: Double,
                         isClosed: Bool = true) -> AlertEvaluator.Bar {
    // 最高最低故意画得很宽（盘中确实穿过了线），好证明 `.close` 看的不是它们。
    .init(openTime: openTime, high: max(close, previous ?? close) + 50,
          low: min(close, previous ?? close) - 50,
          close: close, isClosed: isClosed, previousClose: previous)
  }

  @Test("盘中穿过但这根还没收，不响")
  func closeIgnoresUnclosedBars() {
    let a = alert([flat100], condition: .close)
    // 上一根收在 95、此刻的价已经是 105，盘中确实穿到线上面去了——但这一根没收。
    #expect(!AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: 95,
                                                    close: 105, isClosed: false)))
    // 同一根收了就响，证明拦住它的只有「没收」这一条。
    #expect(AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: 95, close: 105)))
  }

  @Test("收盘价从一侧穿到另一侧才响，上下两个方向都算")
  func closeCrossesInBothDirections() throws {
    let a = alert([flat100], condition: .close)
    let up = try #require(AlertEvaluator.hit(a, bar: closedBar(Self.t0 + Self.hour, previous: 95, close: 105)))
    #expect(up.line == 0)
    #expect(up.price == 100)
    #expect(AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: 105, close: 95)))
  }

  @Test("一直在同一侧，每一根都不响")
  func closeDoesNotRepeatOnTheSameSide() {
    let a = alert([flat100], condition: .close)
    // 全程在线上方：涨、跌、贴着线但没到，一根都不该响。
    for (previous, close) in [(105.0, 110.0), (110.0, 101.0), (101.0, 100.5)] {
      #expect(!AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: previous, close: close)))
    }
    // 全程在线下方同理。
    for (previous, close) in [(95.0, 90.0), (90.0, 99.5)] {
      #expect(!AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: previous, close: close)))
    }
  }

  @Test("收盘价正好落在线上算穿过")
  func closeLandingExactlyOnTheLineCounts() {
    let a = alert([flat100], condition: .close)
    #expect(AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: 95, close: 100)))
    #expect(AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: 105, close: 100)))
    // 但**从**线上走开不算：那一下在上一根就已经判过了，再响一次是重复。
    #expect(!AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: 100, close: 105)))
    #expect(!AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: 100, close: 95)))
    #expect(!AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: 100, close: 100)))
  }

  @Test("没有上一根收盘价就不判，不拿单边当穿越")
  func closeNeedsAPreviousClose() {
    let a = alert([flat100], condition: .close)
    // 刚开始盯（或者中间断过线）：只知道这一根收在 105，不知道之前在哪一侧。
    #expect(!AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: nil, close: 105)))
    #expect(!AlertEvaluator.fires(a, bar: .init(openTime: Self.t0 + Self.hour, high: 110, low: 90,
                                                close: nil, isClosed: true, previousClose: 95)))
  }

  @Test("收盘穿过也认 armedAt，挪线之前的历史 K 线不算")
  func closeRespectsArmedAt() {
    let a = alert([flat100], condition: .close, armedAt: Self.t0 + 5 * Self.hour)
    #expect(!AlertEvaluator.fires(a, bar: closedBar(Self.t0, previous: 95, close: 105)))
    #expect(AlertEvaluator.fires(a, bar: closedBar(Self.t0 + 5 * Self.hour, previous: 95, close: 105)))
  }

  @Test("收盘穿过的阈值跟着线走：趋势线在这一根上的价才是那条线")
  func closeUsesTheLinePriceAtThisBar() {
    // 一条从 100 涨到 200 的趋势线，两端都不延。
    let trendLine = AlertLine(points: [DrawPoint(t: Self.t0, p: 100),
                                       DrawPoint(t: Self.t0 + 2 * Self.hour, p: 200)])
    let a = alert([trendLine], condition: .close)
    // 中点线价 150：145 → 155 穿过。
    #expect(AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: 145, close: 155)))
    // 同样两根收盘价，换到起点那一根（线价 100）就没穿——两根都在线上方。
    #expect(!AlertEvaluator.fires(a, bar: closedBar(Self.t0, previous: 145, close: 155)))
    // 线在这一刻没有价（线段之外、不延）就不判。
    #expect(!AlertEvaluator.fires(a, bar: closedBar(Self.t0 + 5 * Self.hour, previous: 145, close: 155)))
  }

  @Test("已触发 / 已暂停的收盘穿过也不响")
  func closeIgnoresInactive() {
    for status in [Alert.Status.fired, .paused] {
      #expect(!AlertEvaluator.fires(alert([flat100], condition: .close, status: status),
                                    bar: closedBar(Self.t0 + Self.hour, previous: 95, close: 105)))
    }
  }

  @Test("多条线里哪一条被收盘穿过就报哪一条")
  func closeReportsWhichLine() throws {
    let a = alert([
      AlertLine(points: [DrawPoint(t: Self.t0, p: 500)], extendLeft: true, extendRight: true),
      flat100,
    ], condition: .close)
    let hit = try #require(AlertEvaluator.hit(a, bar: closedBar(Self.t0 + Self.hour, previous: 95, close: 105)))
    #expect(hit.line == 1)
    #expect(hit.price == 100)
  }

  // --------------------------------------------------- 裸价格与复盘到点（P3.1）

  /// `price`：目标价是一条两端都延的水平线，和画线提醒同一套规则。
  @Test("裸价格提醒按同一套几何判：碰到目标价就响，收盘穿过一档同样认")
  func priceAlertsFireLikeAFlatLine() {
    var a = Alert.price(symbol: "BTCUSDT", target: 100, current: 90, label: "100", now: Self.t0)
    #expect(a.kind == .price && a.targetPrice == 100 && a.drawingID == nil)
    #expect(a.title == "BTC 涨到 100")
    #expect(AlertEvaluator.fires(a, bar: .init(openTime: Self.t0, high: 101, low: 99)))
    #expect(!AlertEvaluator.fires(a, bar: .init(openTime: Self.t0, high: 99, low: 95)))
    // 建之前开盘的那一根不算——建的那一刻价常常就贴在线上。
    #expect(!AlertEvaluator.fires(a, bar: .init(openTime: Self.t0 - 60_000, high: 101, low: 99)))
    a.condition = .close
    #expect(AlertEvaluator.fires(a, bar: closedBar(Self.t0 + Self.hour, previous: 95, close: 105)))
    #expect(Alert.price(symbol: "ETHUSDT", target: 100, current: 120, label: "100", now: 0).title == "ETH 跌到 100")
    #expect(Alert.price(symbol: "ETHUSDT", target: 100, current: nil, label: "100", now: 0).title == "ETH 到了 100")
  }

  /// `reviewDue` 不看 K 线，只看时间。
  @Test("复盘到点不走 K 线判定，只按 dueAt 判")
  func reviewDueIsJudgedByTimeOnly() {
    var a = alert([flat100])
    a.kind = .reviewDue; a.lines = []; a.dueAt = Self.t0 + Self.hour; a.reviewID = "r1"
    #expect(!AlertEvaluator.fires(a, bar: .init(openTime: Self.t0 + 2 * Self.hour, high: 105, low: 95)))
    #expect(!AlertEvaluator.dueHit(a, now: Self.t0))
    #expect(AlertEvaluator.dueHit(a, now: Self.t0 + Self.hour))
    a.status = .fired
    #expect(!AlertEvaluator.dueHit(a, now: Self.t0 + 2 * Self.hour), "响过的不再响")
    var drawing = alert([flat100]); drawing.dueAt = Self.t0
    #expect(!AlertEvaluator.dueHit(drawing, now: Self.t0 + Self.hour), "别的种类不按时间判")
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

  @Test("提醒总表那一行的价位：价格提醒取目标价，画线取离现价最近的那条线此刻的价")
  func levelForListRow() {
    let price = Alert.price(symbol: "BTCUSDT", target: 81_963.9, current: 86_000, label: "81,963.9",
                            now: Self.t0)
    #expect(AlertEvaluator.level(of: price, near: 86_000, at: Self.t0 + Self.hour) == 81_963.9)
    #expect(AlertEvaluator.level(of: price, near: nil, at: Self.t0) == 81_963.9)
    let channel = alert([
      AlertLine(points: [DrawPoint(t: Self.t0, p: 110)], extendLeft: true, extendRight: true),
      // 斜线：t0 时 90，t0+1h 时 100——取「此刻」的价，不是画的那一刻。
      AlertLine(points: [DrawPoint(t: Self.t0, p: 90), DrawPoint(t: Self.t0 + Self.hour, p: 100)],
                extendRight: true),
    ])
    #expect(AlertEvaluator.level(of: channel, near: 104, at: Self.t0 + Self.hour) == 100)
    #expect(AlertEvaluator.level(of: channel, near: 108, at: Self.t0 + Self.hour) == 110)
    #expect(AlertEvaluator.level(of: channel, near: nil, at: Self.t0) == 110)
    // 线段已经走完、两头不延：取不到价就不写。
    let ended = alert([AlertLine(points: [DrawPoint(t: Self.t0, p: 90), DrawPoint(t: Self.t0 + 1, p: 91)])])
    #expect(AlertEvaluator.level(of: ended, near: 100, at: Self.t0 + Self.hour) == nil)
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
