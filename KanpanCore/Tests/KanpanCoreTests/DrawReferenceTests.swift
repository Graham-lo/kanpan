import Foundation
import Testing

@testable import KanpanCore

/// 画线列表的「距现价」与「画在哪个周期」（2026-10-08 视觉整改）。
@Suite("画线 · 代表价与周期")
struct DrawReferenceTests {
  private func line(_ kind: Drawing.Kind, _ pts: [(Double, Double)], id: String = "x") -> Drawing {
    Drawing(id: id, kind: kind, points: pts.map { DrawPoint(t: $0.0, p: $0.1) })
  }

  @Test("水平线：代表价就是那一价，距现价带正负号")
  func hline() throws {
    let up = line(.hline, [(0, 120)])
    #expect(up.referencePrice(at: 50, latest: 100) == 120)
    #expect(abs(try #require(up.distancePercent(at: 50, latest: 100)) - 20) < 1e-9)
    let down = line(.hline, [(0, 90)])
    #expect(abs(try #require(down.distancePercent(at: 50, latest: 100)) + 10) < 1e-9)
    #expect(changePercentText(down.distancePercent(at: 50, latest: 100)!) == "\u{2212}10.00%")
  }

  @Test("趋势线：投影到最新那根的时刻；落在线段外就夹到端点")
  func trendProjectsAndClamps() {
    let trend = line(.trend, [(0, 100), (100, 200)])
    #expect(trend.referencePrice(at: 50, latest: 140) == 150)
    #expect(trend.referencePrice(at: 300, latest: 140) == 200, "线段没延长：取右端点")
    #expect(trend.referencePrice(at: -50, latest: 140) == 100, "在线段左边：取左端点")
  }

  @Test("射线向右延长：一直投影下去")
  func rayExtends() {
    let ray = line(.ray, [(0, 100), (100, 200)])
    #expect(ray.referencePrice(at: 200, latest: 250) == 300)
  }

  @Test("矩形取离现价最近的那条边；没有提醒几何的线退到锚点")
  func nearestEdgeAndFallback() {
    let box = line(.rectangle, [(0, 110), (100, 90)])
    #expect(box.referencePrice(at: 50, latest: 104) == 110)
    #expect(box.referencePrice(at: 50, latest: 95) == 90)
    let v = line(.vline, [(10, 123)])
    #expect(v.referencePrice(at: 50, latest: 100) == 123)
    #expect(line(.hline, [(0, 120)]).distancePercent(at: 0, latest: 0) == nil)
  }

  // ---------------------------------------------------------------- 周期

  @Test("记周期：只补没记过的线，清掉已经不在的；空表不进存档")
  func noteIntervals() throws {
    var archive = DrawArchive()
    let sym = "binance/usd_m/BTCUSDT"
    archive[sym] = [line(.hline, [(0, 1)], id: "a")]
    let changed1 = archive.noteIntervals(.m15, for: sym)
    #expect(changed1)
    #expect(archive.interval(of: "a") == .m15)
    archive[sym] = archive[sym] + [line(.hline, [(0, 2)], id: "b")]
    let changed2 = archive.noteIntervals(.h1, for: sym)
    #expect(changed2)
    #expect(archive.interval(of: "a") == .m15, "记过的不改")
    #expect(archive.interval(of: "b") == .h1)
    let changed3 = archive.noteIntervals(.h4, for: sym)
    #expect(!changed3, "没有新线就不算改")
    archive[sym] = [line(.hline, [(0, 3)], id: "c")]
    let changed4 = archive.noteIntervals(.d1, for: sym)
    #expect(changed4)
    #expect(archive.interval(of: "a") == nil && archive.interval(of: "c") == .d1, "删掉的线不留记录")

    let data = try JSONEncoder().encode(archive)
    let back = try JSONDecoder().decode(DrawArchive.self, from: data)
    #expect(back.interval(of: "c") == .d1)
    let empty = try JSONEncoder().encode(DrawArchive())
    #expect(!String(decoding: empty, as: UTF8.self).contains("\"iv\""))
  }

  @Test("周期表坏了不连累画线")
  func tolerantDecode() throws {
    var archive = DrawArchive()
    archive["binance/usd_m/BTCUSDT"] = [line(.hline, [(0, 1)], id: "a")]
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
    json["iv"] = 42
    let back = try JSONDecoder().decode(DrawArchive.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(back["binance/usd_m/BTCUSDT"].map(\.id) == ["a"])
    #expect(back.intervals.isEmpty)
  }
}
