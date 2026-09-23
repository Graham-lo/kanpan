import Foundation
import Testing
@testable import KanpanCore

/// 桌面小组件那份快照（P3.2）。
@Suite struct WidgetSnapshotTests {
  private func colors() -> WidgetSnapshot.Colors {
    WidgetSnapshot.Colors(ground: "#FFFFFF", ink: "#000000", ink2: "#333333", ink3: "#666666",
                          line: "#EEEEEE", accent: "#00AA00", up: "#00AA00", down: "#DD0000")
  }

  private func snapshot(rolling: Bool = true) -> WidgetSnapshot {
    let q = { (s: String, p: Double, c: Double) in
      WidgetSnapshot.Quote(symbol: s, price: p, change: c, decimals: 2, closes: [1, 2, 3], timeMs: 1_000, open: p / (1 + c / 100))
    }
    return WidgetSnapshot(updatedAt: 1_000, favorites: ["BTCUSDT", "ETHUSDT", "SOLUSDT", "DOGEUSDT", "XRPUSDT"],
                          groups: [.init(id: "g1", name: "主流", symbols: ["ETHUSDT", "BTCUSDT"])],
                          quotes: ["BTCUSDT": q("BTCUSDT", 100, 1), "ETHUSDT": q("ETHUSDT", 50, -2),
                                   "SOLUSDT": q("SOLUSDT", 10, 0)],
                          light: colors(), dark: colors(), appearance: .auto, fapiHost: "fapi.binance.com",
                          rolling: rolling)
  }

  @Test("小号：全部取前四只，没价的品种照样占一行")
  func rowsKeepFavoritesOrder() {
    let rows = snapshot().rows(group: nil)
    #expect(rows.map(\.symbol) == ["BTCUSDT", "ETHUSDT", "SOLUSDT", "DOGEUSDT"])
    #expect(rows[3].price.isNaN)
    #expect(rows[3].changeLabel == "--")
  }

  @Test("小号：选了分类只列那一类，顺序仍跟自选；分类被删了回到全部")
  func rowsFollowGroup() {
    let s = snapshot()
    #expect(s.rows(group: "g1").map(\.symbol) == ["BTCUSDT", "ETHUSDT"])
    #expect(s.rows(group: "gone").count == 4)
    #expect(s.rows(group: WidgetSnapshot.allGroupID).count == 4)
  }

  @Test("中号：选过的那只；没选或已不在自选里用第一只")
  func focusFallsBack() {
    let s = snapshot()
    #expect(s.focus(symbol: "ETHUSDT")?.symbol == "ETHUSDT")
    #expect(s.focus(symbol: nil)?.symbol == "BTCUSDT")
    #expect(s.focus(symbol: "PEPEUSDT")?.symbol == "BTCUSDT")
  }

  @Test("补价：滚动口径用交易所的百分比，按日口径拿开盘价重算；旧的一口不收")
  func applyFreshPrice() {
    var s = snapshot()
    s.apply(symbol: "BTCUSDT", price: 110, rollingChange: 3.5, timeMs: 2_000, closes: [4, 5, 6])
    #expect(s.quotes["BTCUSDT"]?.price == 110)
    #expect(s.quotes["BTCUSDT"]?.change == 3.5)
    #expect(s.quotes["BTCUSDT"]?.closes == [4, 5, 6])
    s.apply(symbol: "BTCUSDT", price: 90, rollingChange: 1, timeMs: 1_500)
    #expect(s.quotes["BTCUSDT"]?.price == 110)

    var daily = snapshot(rolling: false)
    let open = daily.quotes["BTCUSDT"]!.open!
    daily.apply(symbol: "BTCUSDT", price: open * 1.05, rollingChange: 9, timeMs: 2_000)
    #expect(abs(daily.quotes["BTCUSDT"]!.change - 5) < 1e-9)
  }

  @Test("折线：单位方框里从左到右，高的在上；平的居中；不足两点为空")
  func sparklineShape() {
    let pts = WidgetSnapshot.sparkline([1, 3, 2])
    #expect(pts.count == 3)
    #expect(pts.first?.x == 0 && pts.last?.x == 1)
    #expect(pts[1].y == 0 && pts[0].y == 1)
    #expect(WidgetSnapshot.sparkline([5, 5]).allSatisfy { $0.y == 0.5 })
    #expect(WidgetSnapshot.sparkline([1]).isEmpty)
    #expect(WidgetSnapshot.sparkline([1, .nan, 2]).count == 2)
  }

  @Test("深浅：跟随系统时按系统，定死了就不跟")
  func appearance() {
    var s = snapshot()
    s.dark.ground = "#101010"
    #expect(s.colors(systemDark: true).ground == "#101010")
    s.appearance = .light
    #expect(s.colors(systemDark: true).ground == "#FFFFFF")
  }

  @Test("写下去再读回来一字不差")
  func roundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let s = snapshot()
    try s.write(to: WidgetSnapshot.url(in: dir))
    #expect(WidgetSnapshot.read(from: WidgetSnapshot.url(in: dir)) == s)
  }
}
