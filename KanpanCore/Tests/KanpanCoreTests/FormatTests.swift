import Foundation
import Testing

@testable import KanpanCore

/// A1.11：数字、成交量、时间标签全部对齐原型。
///
/// 例外是 `fmtVol`：定版原型给的是万 / 亿，2026-09-18 用户把成交额单位定为
/// 千进制 K / M / B / T，这一条以用户决定为准，黄金值不再从原型导。
@Suite("格式化")
struct FormatTests {
  @Test("fmtNum 与原型全等")
  func numMatches() {
    for (x, p, want) in Fx.fmtNumCases {
      #expect(fmtNum(x, p) == want, "fmtNum(\(x), \(p)) = \(fmtNum(x, p))，原型 \(want)")
    }
    #expect(fmtNum(.nan, 2) == "--")
    #expect(fmtNum(.infinity, 2) == "--")
  }

  /// 分档边界：100 以下两位小数、100 起整数、1e3 起 K、1e6 起 M、1e9 起 B、1e12 起 T。
  @Test("成交量分档")
  func volBuckets() {
    #expect(fmtVol(0) == "0.00")
    #expect(fmtVol(1.5) == "1.50")
    #expect(fmtVol(99.994) == "99.99")
    #expect(fmtVol(100) == "100")
    #expect(fmtVol(999) == "999")
    #expect(fmtVol(1000) == "1.00K")
    #expect(fmtVol(1234) == "1.23K")
    #expect(fmtVol(9999.5) == "10.00K")
    #expect(fmtVol(123456) == "123.46K")
    #expect(fmtVol(1e6) == "1.00M")
    #expect(fmtVol(84_200_000) == "84.20M")
    #expect(fmtVol(98_765_432) == "98.77M")
    #expect(fmtVol(1e9) == "1.00B")
    #expect(fmtVol(8.32e9) == "8.32B")
    #expect(fmtVol(-5.5e9) == "-5.50B")
    #expect(fmtVol(1e12) == "1.00T")
    #expect(fmtVol(1.5415e12) == "1.54T")
    #expect(fmtVol(.nan) == "--")
  }

  /// 单位由外面钉住：同一个数字，换一个单位就换一种读法（`MarketModel.volumeUnit`
  /// 记住品种第一次见到的档位，换线路时不跟着数字跳档）。
  @Test("单位由外面传进来")
  func volPinnedUnit() {
    #expect(fmtVol(8.32e9, unit: .m) == "8320.00M")
    #expect(fmtVol(9.9e8, unit: .b) == "0.99B")
    #expect(fmtVol(1234, unit: .plain) == "1234")
    #expect(volUnit(8.32e9) == .b)
    #expect(volUnit(999) == .plain)
    #expect(volUnit(-1.2e12) == .t)
  }

  /// `toFixed` 用 JS 的「逢五远离零」，不是 printf 的「逢五取偶」。
  @Test("toFixed 与 JS 同规则")
  func toFixedRule() {
    #expect(toFixed(0.125, 2) == "0.13", "printf 会给 0.12")
    #expect(toFixed(1.005, 2) == "1.00", "1.005 的二进制值比 1.005 小，JS 也给 1.00")
    #expect(toFixed(2.675, 2) == "2.67")
    #expect(toFixed(-0.125, 2) == "-0.13")
    #expect(toFixed(1.5, 0) == "2")
    #expect(toFixed(2.5, 0) == "3", "printf 会给 2")
    #expect(toFixed(0.5, 0) == "1")
    #expect(toFixed(-2.5, 0) == "-3")
    #expect(toFixed(0, 2) == "0.00")
    #expect(toFixed(-0.0001, 2) == "0.00", "抹平成零就不带负号")
    #expect(toFixed(9.999, 2) == "10.00", "进位要能长一位")
    #expect(toFixed(0.0001234, 8) == "0.00012340")
  }

  /// 价格按品种精度：`tickSize` 决定几位小数。
  @Test("价格精度跟 tickSize 走")
  func priceDecimals() {
    let cases: [(Double, Int)] = [(0.01, 2), (0.1, 1), (1, 0), (0.001, 3), (0.0001, 4), (0.00001, 5)]
    for (tick, want) in cases {
      let info = SymbolInfo(
        symbol: "XUSDT", base: "X", pricePrecision: 8, quantityPrecision: 3, tickSize: tick)
      #expect(info.priceDecimals == want, "tickSize=\(tick) 应是 \(want) 位，得到 \(info.priceDecimals)")
    }
    let btc = SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, quantityPrecision: 3, tickSize: 0.1)
    #expect(fmtNum(76800.06, btc.priceDecimals) == "76800.1")
    #expect(btc.display == "BTC/USDT")
  }

  /// 时区偏移：本地跟着系统走，UTC 是 0，交易所固定 +8。
  @Test("时区偏移")
  func timezones() {
    #expect(TZChoice.utc.offsetMinutes == 0)
    #expect(TZChoice.exchange.offsetMinutes == 480)
    #expect(TZChoice.local.offsetMinutes == TimeZone.current.secondsFromGMT() / 60)
    #expect(TZChoice.allCases.count == 3)
  }

  /// 三个时区 × 日内 / 跨日 / 跨年，标签与原型全等。
  @Test("时间标签与原型全等")
  func labelsMatch() {
    #expect(Fx.labels.count == 18, "fixture 只有 \(Fx.labels.count) 组")
    for row in Fx.labels {
      let tick = fmtTick(ms: row.ms, step: row.step, offsetMinutes: row.off)
      #expect(tick == row.tick, "\(row.tz) step=\(row.step) 得到 \(tick)，原型 \(row.tick)")
      let full = fmtFull(ms: row.ms, offsetMinutes: row.off)
      #expect(full == row.full, "\(row.tz) 完整时间得到 \(full)，原型 \(row.full)")
    }
  }

  /// 标签形态：日内 `HH:mm`、跨日 `MM-dd`、跨年 `yyyy-MM`。
  @Test("标签形态")
  func labelShapes() {
    let t = 1_789_318_920_000.0   // 2026-09-14 某个非整点
    #expect(fmtTick(ms: t, step: 60_000, offsetMinutes: 0).count == 5, "日内应是 HH:mm")
    #expect(fmtTick(ms: t, step: 86_400_000, offsetMinutes: 0).count == 5, "跨日应是 MM-dd")
    let yearly = fmtTick(ms: t, step: 365 * 86_400_000, offsetMinutes: 0)
    #expect(yearly.count == 7 && yearly.hasPrefix("20"), "跨年应是 yyyy-MM，得到 \(yearly)")
    // 日内刻度正好落在零点时改画日期，不然一整天分不清。
    let midnight = 1_789_257_600_000.0
    #expect(fmtTick(ms: midnight, step: 3_600_000, offsetMinutes: 0).contains("-"), "零点该给日期")
  }

  /// 日期拆解自己实现（不走 `Calendar`），拿系统日历当裁判核一遍。
  @Test("日期拆解与系统日历一致")
  func datePartsMatchCalendar() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var r = Rng(606)
    for _ in 0..<5000 {
      let off = [0, 480, -300, 330, 570][r.i(0, 4)]
      let ms = r.d(-2.2e12, 2.2e12).rounded()
      let p = DateParts(ms: ms, offsetMinutes: off)
      let d = Date(timeIntervalSince1970: (ms + Double(off) * 60_000) / 1000)
      let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
      #expect(p.year == c.year! && p.month == c.month! && p.day == c.day!
              && p.hour == c.hour! && p.minute == c.minute!,
              "ms=\(ms) off=\(off)：自己算 \(p)，系统 \(c)")
    }
  }

  /// 闰年、月末、跨年这几个点单独钉一下。
  @Test("闰年与月末")
  func leapYears() {
    let cases: [(Double, String)] = [
      (951_782_400_000, "2000-02-29 00:00"),   // 400 年闰
      (1_709_164_800_000, "2024-02-29 00:00"), // 4 年闰
      (1_677_628_800_000, "2023-03-01 00:00"), // 平年 2 月只有 28 天
      (1_735_689_599_000, "2024-12-31 23:59"),
      (1_735_689_600_000, "2025-01-01 00:00"),
      (0, "1970-01-01 00:00"),
      (-86_400_000, "1969-12-31 00:00"),       // 纪元之前
    ]
    for (ms, want) in cases {
      #expect(fmtFull(ms: ms, offsetMinutes: 0) == want, "ms=\(ms) 得到 \(fmtFull(ms: ms, offsetMinutes: 0))")
    }
  }
}
