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
                          light: colors(), dark: colors(), appearance: .auto, rolling: rolling)
  }

  @Test("小号：全部取前四只，没价的品种照样占一行")
  func rowsKeepFavoritesOrder() {
    let rows = snapshot().rows(group: nil)
    #expect(rows.map(\.symbol) == ["BTCUSDT", "ETHUSDT", "SOLUSDT", "DOGEUSDT"])
    #expect(rows[3].price.isNaN)
    #expect(rows[3].changeLabel == "--")
  }

  @Test("价的写法：品种小数位 + 千分位，与列表一致；缺数写「--」")
  func priceLabelIsGrouped() {
    let q = WidgetSnapshot.Quote(symbol: "BTCUSDT", price: 84549.6, change: 0.15, decimals: 1, timeMs: 1_000)
    #expect(q.priceLabel == "84,549.6")
    let small = WidgetSnapshot.Quote(symbol: "SOLUSDT", price: 117.39, change: 2.52, decimals: 2, timeMs: 1_000)
    #expect(small.priceLabel == "117.39")
    let none = WidgetSnapshot.Quote(symbol: "XRPUSDT", price: .nan, change: .nan, decimals: nil, timeMs: 0)
    #expect(none.priceLabel == "--")
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

  @Test("小组件补价：直连模板打币安本家、载荷不带信封")
  func refreshDirect() throws {
    let r = WidgetSnapshot.Refresh(market: "binance/usdm", hosts: ["fapi.binance.com"],
                                   ticker: "/fapi/v1/ticker/24hr?symbol={symbol}",
                                   closes: "/fapi/v1/klines?symbol={symbol}&interval=1h&limit={limit}")
    #expect(r.tickerURL(host: "fapi.binance.com", symbol: "BTCUSDT")?.absoluteString
            == "https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=BTCUSDT")
    #expect(r.closesURL(host: "fapi.binance.com", symbol: "BTCUSDT")?.absoluteString
            == "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1h&limit=\(WidgetSnapshot.sparkBars)")
    let ticker = try #require(r.parseTicker(Data(#"{"lastPrice":"101.5","priceChangePercent":"-1.2","closeTime":1700}"#.utf8)))
    #expect(ticker.price == 101.5 && ticker.change == -1.2 && ticker.timeMs == 1700)
    #expect(r.parseCloses(Data(#"[[0,"1","2","0","10"],[1,"1","2","0","11"]]"#.utf8)) == [10, 11])
    // 代号里夹了查询串分隔符的，不拼。
    #expect(r.tickerURL(host: "fapi.binance.com", symbol: "BTC&x=1") == nil)
  }

  @Test("小组件补价：网关模板打网关、载荷从信封里取；主机可带端口")
  func refreshGateway() throws {
    let r = WidgetSnapshot.Refresh(market: "binance/usdm", hosts: ["a.example", "b.example:8443"],
                                   ticker: "/market/v1/ticker?symbol={symbol}&source=okx",
                                   closes: "/market/v1/klines?symbol={symbol}&interval=1h&limit={limit}&source=okx",
                                   tickerField: "ticker", closesField: "bars")
    #expect(r.tickerURL(host: "b.example:8443", symbol: "ETHUSDT")?.absoluteString
            == "https://b.example:8443/market/v1/ticker?symbol=ETHUSDT&source=okx")
    let ticker = try #require(r.parseTicker(Data(#"{"source":"okx","symbol":"ETHUSDT","ticker":{"lastPrice":"2000","priceChangePercent":"3","closeTime":5}}"#.utf8)))
    #expect(ticker.price == 2000 && ticker.change == 3)
    #expect(r.parseCloses(Data(#"{"source":"okx","bars":[[0,"1","2","0",7],[1,"1","2","0","8"]]}"#.utf8)) == [7, 8])
    // 没有信封的直连载荷在网关模板下不算数。
    #expect(r.parseTicker(Data(#"{"lastPrice":"2000"}"#.utf8)) == nil)
  }

  @Test("旧快照（带 fapiHost / hostMarket）照样解得开，补价方式是 nil")
  func legacySnapshotDecodes() throws {
    var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot())) as? [String: Any])
    json["fapiHost"] = "fapi.binance.com"; json["hostMarket"] = "binance/usdm"
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.refresh == nil)
    #expect(decoded.favorites == snapshot().favorites)
  }
}
