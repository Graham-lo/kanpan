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
  /// 偏移是「在某个时刻」问出来的，所以这里都带上时刻（审查 B-08）。
  @Test("时区偏移")
  func timezones() {
    let now = Date().timeIntervalSince1970 * 1000
    #expect(TZChoice.utc.offsetMinutes.minutes(at: now) == 0)
    #expect(TZChoice.exchange.offsetMinutes.minutes(at: now) == 480)
    #expect(TZChoice.local.offsetMinutes.minutes(at: now)
            == TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: now / 1000)) / 60)
    #expect(TZChoice.allCases.count == 3)
  }

  /// B-T17：本地时区的偏移必须按**被格式化的那个时刻**取，不是「现在」。
  ///
  /// 用纽约冬 / 夏两个时刻钉死，和跑测试的机器在哪个时区无关：
  /// 冬天 −5（EST），夏天 −4（EDT）。同一段历史用「当下偏移」去格式化，
  /// 两者之中必有一个整体平移一小时。
  @Test("本地时区按被格式化的时刻取偏移")
  func localOffsetFollowsTheInstant() {
    let ny = TZOffset.zone(TimeZone(identifier: "America/New_York")!)
    // 2026-01-05 00:00 UTC（冬季，EST = UTC−5）
    let winter = 1_767_571_200_000.0
    // 2026-07-06 00:00 UTC（夏季，EDT = UTC−4）
    let summer = 1_783_296_000_000.0
    #expect(ny.minutes(at: winter) == -300)
    #expect(ny.minutes(at: summer) == -240)
    #expect(fmtFull(ms: winter, offsetMinutes: ny) == "2026-01-04 19:00")
    #expect(fmtFull(ms: summer, offsetMinutes: ny) == "2026-07-05 20:00")
    // 固定偏移的两档不受夏令时影响。
    #expect(TZOffset.fixed(480).minutes(at: winter) == 480)
    #expect(TZOffset.fixed(480).minutes(at: summer) == 480)
    #expect(fmtFull(ms: winter, offsetMinutes: TZChoice.exchange.offsetMinutes) == "2026-01-05 08:00")
    #expect(fmtFull(ms: winter, offsetMinutes: TZChoice.utc.offsetMinutes) == "2026-01-05 00:00")
  }

  /// B.6 的时区契约：日/周/月线的标签带的是 **UTC 交易日**，
  /// 所以在负偏移的地区看日线，标签会落在前一天——这是对的，不是 bug。
  @Test("日线标签在纽约落到前一天")
  func dailyLabelsCarryTheUTCTradingDate() {
    let ny = TZOffset.zone(TimeZone(identifier: "America/New_York")!)
    let day = 86_400_000.0
    // 2026-09-19 00:00 UTC 的日线
    let daily = 1_789_776_000_000.0
    #expect(fmtTick(ms: daily, step: day, offsetMinutes: TZChoice.utc.offsetMinutes) == "09-19")
    #expect(fmtTick(ms: daily, step: day, offsetMinutes: TZChoice.exchange.offsetMinutes) == "09-19")
    #expect(fmtTick(ms: daily, step: day, offsetMinutes: ny) == "09-18")
    #expect(fmtFull(ms: daily, offsetMinutes: ny) == "2026-09-18 20:00")
    // 周线 2026-09-21（周一）在纽约落到 09-20；月线 2026-10-01 落到 09-30。
    let weekly = 1_789_948_800_000.0
    #expect(fmtTick(ms: weekly, step: 7 * day, offsetMinutes: ny) == "09-20")
    let monthly = 1_790_812_800_000.0
    #expect(fmtTick(ms: monthly, step: 30 * day, offsetMinutes: ny) == "09-30")
  }

  /// B-T18：复盘浮层上的时间和图上的时间必须是**同一只钟**。
  ///
  /// 图设成「交易所」（固定 +8）而机器在纽约时，浮层那一行仍然要写交易所时间。
  /// `ReviewRangeOverlay` 从前自己造一个 `DateFormatter`——那只钟跟着**设备**时区走，
  /// 于是选区标签和坐标轴能差上十几个小时；现在它走的是这儿这一支
  /// `fmtDayTime(ms:offsetMinutes:)`，并且拿的是图自己的 `TZChoice`。
  /// 复核项 5 之后这条用例不再只证「同一支格式化」：选区标签的**文案本体**已经搬进
  /// `ReviewLabels.range`，`ReviewRangeOverlay.paint` 里那一行就是调它
  /// （UIKit 那层进不了这个包，但它画的那串字是这儿这个函数算出来的），
  /// 所以下面 ④ 驱动的是屏上那一行本身。复盘本、找相似列表、记一笔卡走的也是这一支。
  @Test("复盘浮层与坐标轴同一只钟")
  func overlayLabelsFollowTheChartsTimezone() {
    // 2026-01-05 00:00 UTC（北半球冬季，纽约 EST = UTC−5）
    let instant = 1_767_571_200_000.0
    let chart = TZChoice.exchange.offsetMinutes          // 图上那一档
    let device = TZOffset.zone(TimeZone(identifier: "America/New_York")!)  // 机器在哪儿
    // ① 浮层用的那支 = 坐标轴用的那支，同一档时区给同一串字。
    #expect(fmtDayTime(ms: instant, offsetMinutes: chart) == "1/5 08:00")
    #expect(fmtTick(ms: instant, step: 60_000, offsetMinutes: chart) == "08:00")
    #expect(fmtFull(ms: instant, offsetMinutes: chart) == "2026-01-05 08:00")
    // ② 设备时区不参与：它给出的是另一串字，而浮层现在不读它。
    #expect(fmtDayTime(ms: instant, offsetMinutes: device) == "1/4 19:00")
    #expect(fmtDayTime(ms: instant, offsetMinutes: device)
            != fmtDayTime(ms: instant, offsetMinutes: chart))
    // ③ 交易所那一档永不随夏令时平移；本地那一档必须平移。
    let summer = 1_783_296_000_000.0                     // 2026-07-06 00:00 UTC
    #expect(fmtDayTime(ms: summer, offsetMinutes: chart) == "7/6 08:00")
    #expect(chart.minutes(at: instant) == chart.minutes(at: summer))
    #expect(device.minutes(at: instant) != device.minutes(at: summer))
    // ④ 屏上那一行（`ReviewRangeOverlay.paint` → `ReviewLabels.range`）。
    let start = Int64(instant), end = start + 7_200_000
    #expect(ReviewLabels.range(bars: 120, start: start, end: end, offsetMinutes: chart)
            == "120 根 · 1/5 08:00 – 1/5 10:00")
    // 换成设备那只钟就是另一串字——说明这一行真的读了传进去的时区档。
    #expect(ReviewLabels.range(bars: 120, start: start, end: end, offsetMinutes: device)
            == "120 根 · 1/4 19:00 – 1/4 21:00")
    // 复盘本里的「记于」与「到期」（`ReviewFeature.dayTime` / `.fullTime` 调的就是这两支）。
    #expect(ReviewLabels.dayTime(ms: start, offsetMinutes: chart) == "1/5 08:00")
    #expect(ReviewLabels.full(ms: start, offsetMinutes: chart) == "2026-01-05 08:00")
    #expect(ReviewLabels.full(ms: start, offsetMinutes: device) == "2026-01-04 19:00")
    // 到期这类跨年的时刻必须带年份：`M/d HH:mm` 会把 2025 和 2026 的同一天写成一样。
    #expect(ReviewLabels.full(ms: start, offsetMinutes: chart)
            != ReviewLabels.full(ms: start - 365 * 86_400_000, offsetMinutes: chart))
    // `TZOffset.timeZone` 是「到期」那颗原生轮盘用的（挑的时区 = 写出来的时区）。
    #expect(TZChoice.exchange.offsetMinutes.timeZone.secondsFromGMT() == 28_800)
    #expect(TZChoice.utc.offsetMinutes.timeZone.secondsFromGMT() == 0)
    #expect(TZOffset.zone(TimeZone(identifier: "America/New_York")!).timeZone.identifier
            == "America/New_York")
  }

  @Test("展示按报价步长，缺步长才退回字段精度，未知目录保留小价兜底")
  func displayDecimalsUseTickSize() {
    let cases: [(String, Int, Double, Double, String)] = [
      ("SNDKUSDT", 5, 0.01, 1774.23, "1774.23"),
      ("MUUSDT", 5, 0.01, 1045.4, "1045.40"),
      ("BTCUSDT", 2, 0.1, 76800.06, "76800.1"),
      ("1000SATSUSDT", 8, 0.00000001, 0.00001234, "0.00001234"),
      ("WHOLEUSDT", 5, 1.0, 123.0, "123"),
      ("MISSINGUSDT", 3, 0.0, 1.234, "1.234")
    ]
    for (symbol, precision, tick, price, expected) in cases {
      let info = SymbolInfo(symbol: symbol, base: symbol, pricePrecision: precision, tickSize: tick)
      #expect(fmtPrice(price, decimals: info.displayDecimals(for: price)) == expected)
    }
    let unknown = SymbolInfo.placeholder(symbol: "GONEUSDT")
    #expect(Double(fmtPrice(0.0000004, decimals: unknown.displayDecimals(for: 0.0000004)))! > 0)
  }

  /// B-T16：价格小数位由品种说，极小的正价绝不能显示成 0。
  @Test("价格小数位来自品种")
  func priceDecimalsComeFromTheSymbol() {
    // BTC：tickSize 0.1，一位
    #expect(fmtPrice(76_800, decimals: 1) == "76800.0")
    // 1000PEPE：7 位
    #expect(fmtPrice(0.0123456, decimals: 7) == "0.0123456")
    // tickSize 0.0001 的合约：4 位
    #expect(fmtPrice(1.2345, decimals: 4) == "1.2345")
    // 美股：2 位
    #expect(fmtPrice(238.4, decimals: 2) == "238.40")
    // 极小价：按 2 位会四舍五入成 0，必须自动多给位数
    #expect(fmtPrice(0.00000001234, decimals: 2) != "0.00")
    #expect(Double(fmtPrice(0.00000001234, decimals: 2))! > 0)
    #expect(fmtPrice(0.000004, decimals: 4) != "0.0000")
    // 真的是 0 就写 0，不要凭空加位数
    #expect(fmtPrice(0, decimals: 2) == "0.00")
    #expect(fmtPrice(.nan, decimals: 2) == "--")
    // 复盘那几处口价走的是同一支（`ReviewLabels.price`，复核项 5）：图上的目标 / 失效线、
    // 复盘本里的「目标 / 失效」、记一笔卡上的参考价，从前各写一套
    // （「最多 6 位」/「最多 8 位」/ 现造 formatter），同一口价能有三种写法。
    #expect(ReviewLabels.price("目标", value: 76_800, decimals: 2) == "目标 76800.00")
    #expect(ReviewLabels.price("失效", value: 0.0123456, decimals: 7) == "失效 0.0123456")
    #expect(ReviewLabels.price(76_800, decimals: 2) == fmtPrice(76_800, decimals: 2))
    // 品种表问不到精度（占位行 `pricePrecision == 0`）时按这口价自己猜，
    // 绝不能写死 2 位把 0.0000004 摆成 `0.00`。
    #expect(ReviewLabels.price(0.0000004, decimals: nil)
            == fmtPrice(0.0000004, decimals: priceDecimalsFallback(0.0000004)))
    #expect(Double(ReviewLabels.price(0.0000004, decimals: nil))! > 0)
    // 缺值按项目规矩写 `--`，不写 0、不写空串。
    #expect(ReviewLabels.price(.nan, decimals: 2) == "--")
    #expect(ReviewLabels.price("目标", value: .nan, decimals: 2) == "目标 --")
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
