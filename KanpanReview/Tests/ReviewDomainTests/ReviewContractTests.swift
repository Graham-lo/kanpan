import XCTest
import ReviewDomain

/// **本地过不了的，上去也一定被拒；本地过得了的，上去不许被拒。**（审查 B-06 / B-02）
///
/// `ReviewContractReconciliationTests` 管「常量有没有漂」，这一组管「规则有没有按那些
/// 常量真的执行」。两条腿缺一条都不行：常量对了但 `failure` 里忘了查，照样能存下一条
/// 服务端必拒的记录，然后它坐在队首，把这个账号后面所有的记录一起卡住。
final class ReviewContractTests: XCTestCase {

  private let hour: Int64 = 3_600_000
  private let now: Int64 = 1_700_000_000_000

  /// 一条各方面都合规的记录，下面每条测试只破坏其中一样。
  private func draft(symbol: String = "BTCUSDT", venue: String = "binance", interval: String = "1h",
                     bars: Int = 48) -> ReviewDraft {
    let step: Int64 = ReviewInterval(rawValue: interval).flatMap(\.fixedSeconds).map { $0 * 1000 } ?? hour
    let end = now - step
    let range = ReviewRange(venue: venue, symbol: symbol, interval: interval,
                            start: end - step * Int64(bars), end: end, bars: bars)
    return ReviewDraft(range: range, reference: 100, high: 110, low: 90, now: now)
  }

  private func long(_ value: ReviewDraft) -> ReviewDraft {
    var value = value
    value.rule.direction = .long
    value.rule.expires = value.created + 86_400_000
    return value
  }

  func testTheBaselineDraftIsAccepted() {
    XCTAssertNil(ReviewContract.failure(draft(), now: now), "基准这条要是本身就过不了，下面每条断言都失去意义")
    XCTAssertNil(ReviewContract.failure(long(draft()), now: now))
  }

  // MARK: - 交易所 / 品种 / 周期：圈之前就该拦住

  /// USDC 永续在图上是真的能打开的，但服务端只收 `USDT` 结尾的（`ends_with("USDT")`）。
  /// 从前它一路过到入队，然后 `invalid_chart_range` 卡死整条队列（审查 B-02 的现场）。
  func testUsdcPerpetualIsRefusedBeforeTheUserWritesAnything() {
    XCTAssertNotNil(ReviewContract.captureFailure(venue: "binance", symbol: "BTCUSDC", interval: "1h"),
                    "USDC 永续必须在**进捕获模式之前**就被挡住，不能让人圈完写完才说不行")
    XCTAssertNotNil(ReviewContract.failure(draft(symbol: "BTCUSDC"), now: now))
  }

  func testOtherVenuesAreRefused() {
    XCTAssertNotNil(ReviewContract.captureFailure(venue: "okx", symbol: "BTCUSDT", interval: "1h"))
    XCTAssertNotNil(ReviewContract.failure(draft(venue: "okx"), now: now))
  }

  func testSymbolShapeFollowsTheServer() {
    XCTAssertNotNil(ReviewContract.captureFailure(venue: "binance", symbol: "btcusdt", interval: "1h"),
                    "服务端要求全大写 / 数字（`is_ascii_uppercase || is_ascii_digit`）")
    XCTAssertNotNil(ReviewContract.captureFailure(venue: "binance", symbol: "BTC-USDT", interval: "1h"))
    XCTAssertNotNil(ReviewContract.captureFailure(
      venue: "binance", symbol: String(repeating: "A", count: 37) + "USDT", interval: "1h"), "41 个字符，超了 40")
    XCTAssertNil(ReviewContract.captureFailure(venue: "binance", symbol: "1000PEPEUSDT", interval: "1h"),
                 "带数字前缀的品种是正经品种，不能连它一起拦掉")
  }

  /// 图表那份周期表（`KanpanCore.Interval`）和复盘这份不是一回事：它有服务端不认的
  /// `1y`，也少了 `8h` / `3d`。拿图表那份去猜，`1y` 的记录会被 `unsupported_interval` 拒。
  func testIntervalsFollowTheServerList() {
    XCTAssertNotNil(ReviewContract.captureFailure(venue: "binance", symbol: "BTCUSDT", interval: "1y"),
                    "`1y` 只存在于图表那份周期表里，服务端不认")
    for interval in ["8h", "3d", "1M"] {
      XCTAssertNil(ReviewContract.captureFailure(venue: "binance", symbol: "BTCUSDT", interval: interval),
                   "`\(interval)` 是服务端认的周期，不许拦")
    }
    XCTAssertNotNil(ReviewContract.captureFailure(venue: "binance", symbol: "BTCUSDT", interval: "1min"),
                    "服务端只收币安的官方写法，别名不算")
  }

  // MARK: - 根数与区间

  func testBarCountBoundaries() {
    XCTAssertNil(ReviewContract.failure(draft(bars: 3), now: now), "3 根是服务端的下限，正好 3 根要过")
    XCTAssertNotNil(ReviewContract.failure(draft(bars: 2), now: now))
    XCTAssertNil(ReviewContract.failure(draft(bars: 1500), now: now), "1500 根是上限，正好 1500 根要过")
    XCTAssertNotNil(ReviewContract.failure(draft(bars: 1501), now: now), "1501 根服务端必拒，本地就得挡住")
  }

  func testBarCountMustMatchTheSpan() {
    var value = draft(bars: 48)
    value.range.bars = 47   // 区间没变、根数改小：服务端拿 `bars_between` 复核，对不上就拒。
    XCTAssertNotNil(ReviewContract.failure(value, now: now))
  }

  func testRangeMustBeInThePast() {
    var value = draft()
    value.range.end = now + hour
    XCTAssertNotNil(ReviewContract.failure(value, now: now), "圈到还没收盘的地方，服务端不收")
  }

  /// 月线只能按日历数根数。拿「30 天一根」去算，2 月那一根会算成 0 根，
  /// 和服务端 `bars_between` 对不上 → `invalid_chart_range`。
  func testMonthlyBarsAreCountedByTheCalendar() {
    let month = ReviewInterval.mo1
    let jan = Int64(1_704_067_200_000)   // 2024-01-01T00:00Z
    let feb = Int64(1_706_745_600_000)   // 2024-02-01
    let mar = Int64(1_709_251_200_000)   // 2024-03-01（2024 年 2 月只有 29 天）
    let apr = Int64(1_711_929_600_000)   // 2024-04-01
    XCTAssertEqual(month.barsBetween(start: feb, end: mar), 1, "2 月就是一整根，哪怕它只有 29 天")
    XCTAssertEqual(month.barsBetween(start: jan, end: apr), 3)
    XCTAssertEqual(month.barsBetween(start: jan, end: mar + 14 * 86_400_000), 2, "3 月中旬那根还没收，不算")
    XCTAssertNil(month.fixedSeconds, "月线不该有固定秒数")
    XCTAssertEqual((mar - feb) / 1000 / (30 * 86_400), 0, "反证：按 30 天算这一段是 0 根，两边就对不上了")
  }

  func testFixedIntervalBarsMatchTheServerArithmetic() {
    XCTAssertEqual(ReviewInterval.h1.barsBetween(start: 0, end: 3_600_000), 1)
    XCTAssertEqual(ReviewInterval.h1.barsBetween(start: 0, end: 3_599_999), 0, "不满一根就是 0 根，向下取整")
    XCTAssertEqual(ReviewInterval.d3.barsBetween(start: 0, end: 259_200_000 * 5), 5)
    XCTAssertEqual(ReviewInterval.w1.barsBetween(start: 0, end: 604_800_000 * 2), 2)
    XCTAssertEqual(ReviewInterval.h1.barsBetween(start: 3_600_000, end: 0), -1, "反着来要给负数，别绕回正数")
  }

  // MARK: - 记录本身

  func testRuleVersionAndEnumsFollowTheServer() {
    var value = draft()
    value.rule.version = "criteria-v1"
    XCTAssertNotNil(ReviewContract.failure(value, now: now))
  }

  func testConfidenceMustBeOneOfTheFiveSteps() {
    var value = draft()
    value.confidence = 65
    XCTAssertNotNil(ReviewContract.failure(value, now: now))
    for step in ReviewContract.confidences {
      value.confidence = step
      XCTAssertNil(ReviewContract.failure(value, now: now), "\(step) 是合法档位")
    }
    value.confidence = nil
    XCTAssertNil(ReviewContract.failure(value, now: now), "不填把握也是合法的")
  }

  /// 正文量的是 **UTF-8 字节**（服务端 `String::len()`），不是字符数。
  /// 按字符数挡，两万多个汉字就能造出一条六万四千字节以上、服务端必拒的记录。
  func testTextLimitIsMeasuredInUtf8Bytes() {
    var value = draft()
    value.text = String(repeating: "看", count: 21_334)   // 64_002 字节
    XCTAssertEqual(value.text.utf8.count, 64_002)
    XCTAssertLessThan(value.text.count, ReviewContract.textMaxBytes, "字符数还没到上限，但字节数已经超了")
    XCTAssertNotNil(ReviewContract.failure(value, now: now))
    value.text = String(repeating: "看", count: 21_333)   // 63_999 字节
    XCTAssertNil(ReviewContract.failure(value, now: now))
  }

  /// 图表设置 / 画线快照在线上是 Base64 字符串，服务端量的是那串字符的长度，
  /// 不是原始字节数——差着三分之一，按原始字节算会漏放一批必拒的记录。
  func testSnapshotLimitsAreMeasuredAfterBase64() {
    var value = draft()
    value.chartSettings = Data(repeating: 0, count: 96_000)
    XCTAssertEqual(ReviewContract.base64Length(value.chartSettings ?? Data()), 128_000)
    XCTAssertNil(ReviewContract.failure(value, now: now), "编码出来正好 128_000，是上限本身")
    value.chartSettings = Data(repeating: 0, count: 96_001)
    XCTAssertNotNil(ReviewContract.failure(value, now: now))

    value.chartSettings = nil
    value.drawingSnapshot = Data(repeating: 0, count: 192_000)
    XCTAssertNil(ReviewContract.failure(value, now: now))
    value.drawingSnapshot = Data(repeating: 0, count: 192_001)
    XCTAssertNotNil(ReviewContract.failure(value, now: now), "画线多到超过 256_000 个字符，服务端不收")
  }

  /// 服务端对三个方向一视同仁地要求三口价是正的有限数，`observe` 也不例外。
  /// 客户端原来在 observe 上提前 return，「只记录」就能造出服务端必拒的记录。
  func testObserveStillNeedsPositiveFinitePrices() {
    for broken in [0.0, -1.0, Double.nan, Double.infinity] {
      var value = draft()
      value.rule.direction = .observe
      value.rule.invalidation = broken
      XCTAssertNotNil(ReviewContract.failure(value, now: now), "只记录也不许带 \(broken) 这样的价")
    }
  }

  func testClockSkewBeyondTheServerToleranceIsRefused() {
    var value = draft()
    value.created = now + ReviewContract.createdAheadMillis
    XCTAssertNil(ReviewContract.failure(value, now: now), "正好卡在容差上要放行")
    value.created = now + ReviewContract.createdAheadMillis + 1
    XCTAssertNotNil(ReviewContract.failure(value, now: now), "本机时钟快过头，服务端会拒，本地先说清楚")
    value.created = -1
    XCTAssertNotNil(ReviewContract.failure(value, now: now))
  }

  func testExpiryHorizon() {
    var value = long(draft())
    value.rule.expires = value.created + ReviewContract.horizonMaxMillis
    XCTAssertNil(ReviewContract.failure(value, now: now), "正好一年（366 天）是上限本身")
    value.rule.expires = value.created + ReviewContract.horizonMaxMillis + 1
    XCTAssertNotNil(ReviewContract.failure(value, now: now))
    value.rule.expires = value.created
    XCTAssertNotNil(ReviewContract.failure(value, now: now), "到期不能和记录时间同一刻")
  }

  func testDirectionalPriceRelations() {
    var value = long(draft())
    value.rule.target = 90; value.rule.invalidation = 110
    XCTAssertNotNil(ReviewContract.failure(value, now: now), "看多却把目标放在参考价下面")

    var short = long(draft())
    short.rule.direction = .short
    short.rule.target = 90; short.rule.invalidation = 110
    XCTAssertNil(ReviewContract.failure(short, now: now))
    short.rule.target = 110; short.rule.invalidation = 90
    XCTAssertNotNil(ReviewContract.failure(short, now: now))
  }
}
