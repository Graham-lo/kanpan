import XCTest
import ReviewDomain

/// 重温（回放）那两件纯算术的事：这段行情该用几位小数（审查 B-04），推进一根之后
/// 视野落在哪（审查 B-05）。
///
/// 这两条本来长在 `ReviewChartBridge` 里，而桥住在 app target 里、这个包的测试够不着。
/// 现在它们搬进了 `ReviewDomain`，桥只剩「取数、喂给图」的接线——所以这一组测试锁的
/// 就是报告 B.5 里「ReviewIntegration」那两行的判据。
final class ReviewReplayPolicyTests: XCTestCase {

  // MARK: - B-04：精度跟着**被回放的那个品种**走

  /// 在一位小数的图（比如 BTCUSDT）上打开一条 0.00001234 的记录。
  ///
  /// 从前回放直接沿用当前图的 `decimals`，于是轴、十字线、画线标签把每一口价都写成
  /// `0.0`——整段回放变成一条平的直线，人看不出任何东西。
  func testPrecisionComesFromTheReplayedBarsNotTheLiveChart() throws {
    let prices = [0.00001234, 0.00001240, 0.00001199, 0.00001233]
    let decimals = try XCTUnwrap(ReviewPricePrecision.decimals(of: prices))
    XCTAssertEqual(decimals, 8)
    XCTAssertEqual(ReviewPricePrecision.tickSize(decimals: decimals), 0.00000001, accuracy: 1e-12)

    XCTAssertEqual(String(format: "%.\(decimals)f", prices[0]), "0.00001234")
    // 反证：拿实时图那一位小数去写，这一段整个塌成 0.0。
    XCTAssertEqual(String(format: "%.1f", prices[0]), "0.0")
  }

  func testPrecisionOfOrdinaryAndIntegerSeries() {
    XCTAssertEqual(ReviewPricePrecision.decimals(of: [76800.5, 76801.0, 76799.5]), 1)
    XCTAssertEqual(ReviewPricePrecision.decimals(of: [3421.25, 3420.10]), 2)
    XCTAssertNil(ReviewPricePrecision.decimals(of: [100, 200, 300]),
                 "整数报价问不出小数位，该由调用方拿品种目录里那一口价兜底，而不是当成 0 位硬写")
    XCTAssertEqual(ReviewPricePrecision.decimals(of: [0.000000001234]), ReviewPricePrecision.maxDecimals,
                   "比 8 位还细的，只能顶到 8 位——币安 USDⓈ-M 的 pricePrecision 不超过 8")
  }

  func testTickSizeIsClamped() {
    XCTAssertEqual(ReviewPricePrecision.tickSize(decimals: 0), 1, accuracy: 1e-12)
    XCTAssertEqual(ReviewPricePrecision.tickSize(decimals: 2), 0.01, accuracy: 1e-12)
    XCTAssertEqual(ReviewPricePrecision.tickSize(decimals: 99), 0.00000001, accuracy: 1e-12)
    XCTAssertEqual(ReviewPricePrecision.tickSize(decimals: -3), 1, accuracy: 1e-12)
  }

  // MARK: - B-05：每推进一根，不许把人的视野拨回默认

  private let step: Int64 = 3_600_000
  private let first: Int64 = 1_700_000_000_000

  /// 第一次进回放：没有个人视野，按默认 80 根 + 右边留白铺开。
  func testOpeningAReplayUsesTheDefaultWindow() {
    let window = ReviewReplayViewport.next(current: nil, previousLastTime: nil, lastTime: first, step: step, reset: true)
    XCTAssertEqual(window.span, Double(step) * ReviewReplayViewport.defaultBars)
    XCTAssertEqual(window.to, Double(first + step * Int64(ReviewReplayViewport.rightPadBars)))
  }

  /// **人捏成 40 根之后，连按 10 下「下一根」，还是 40 根。**
  ///
  /// 这是审查 B-05 的现场：每一拍都写死 `span = 80 根`，那颗按钮等于一次次把人的手拨开。
  func testSteppingKeepsTheUserZoom() {
    let span = Double(step) * 40
    var last = first
    var window = ReviewReplayWindow(to: Double(last + step * 6), span: span)
    for _ in 0..<10 {
      let next = last + step
      window = ReviewReplayViewport.next(current: window, previousLastTime: last, lastTime: next, step: step, reset: false)
      last = next
      XCTAssertEqual(window.span, span, "推进一根不该动窗宽")
      XCTAssertEqual(window.to, Double(last + step * Int64(ReviewReplayViewport.rightPadBars)),
                     "人还跟着播放头，右缘就跟着新根走")
    }
    // 停下来（不再推进）之后也没有任何一处把它拨回 80 根。
    XCTAssertNotEqual(window.span, Double(step) * ReviewReplayViewport.defaultBars)
  }

  /// 人已经拖到历史段去看了：新根在视野外面长，视野一动不动。
  func testScrolledBackIntoHistoryTheViewportStaysPut() {
    let window = ReviewReplayWindow(to: Double(first - step * 200), span: Double(step) * 40)
    let next = ReviewReplayViewport.next(current: window, previousLastTime: first,
                                         lastTime: first + step, step: step, reset: false)
    XCTAssertEqual(next, window, "人在看三百根之前的那一段，播放头前进不该把他拽回去")
  }

  /// 边界：最新那根的开盘时刻正好贴在右缘上，仍然算「跟着播放头」。
  func testTheNewestBarExactlyAtTheRightEdgeStillFollows() {
    let window = ReviewReplayWindow(to: Double(first), span: Double(step) * 40)
    let next = ReviewReplayViewport.next(current: window, previousLastTime: first,
                                         lastTime: first + step, step: step, reset: false)
    XCTAssertEqual(next.to, Double(first + step + step * Int64(ReviewReplayViewport.rightPadBars)))
    XCTAssertEqual(next.span, window.span)
  }

  /// 只有**明确的跳转**（重新打开、跳到判断处）才重新铺视野；窗宽也一起回默认。
  func testOnlyAnExplicitJumpResetsTheViewport() {
    let window = ReviewReplayWindow(to: Double(first - step * 200), span: Double(step) * 40)
    let jumped = ReviewReplayViewport.next(current: window, previousLastTime: first,
                                           lastTime: first + step, step: step, reset: true)
    XCTAssertEqual(jumped.span, Double(step) * ReviewReplayViewport.defaultBars)
    XCTAssertEqual(jumped.to, Double(first + step + step * Int64(ReviewReplayViewport.rightPadBars)))
  }

  /// 拿不到上一拍的播放头（刚从别处接上来）时，保住窗宽、右缘跟到最新——
  /// 这时候没有证据说人拖走过，不能拿默认 80 根去盖掉他捏出来的宽度。
  func testWithoutAPreviousHeadTheSpanIsStillKept() {
    let window = ReviewReplayWindow(to: Double(first), span: Double(step) * 40)
    let next = ReviewReplayViewport.next(current: window, previousLastTime: nil,
                                         lastTime: first + step, step: step, reset: false)
    XCTAssertEqual(next.span, window.span)
    XCTAssertEqual(next.to, Double(first + step + step * Int64(ReviewReplayViewport.rightPadBars)))
  }

  /// 视野里存着 NaN / 0 宽这种坏值时退回默认，别把坏值算进去让图整个画不出来。
  func testBrokenViewportFallsBackToTheDefault() {
    for broken in [ReviewReplayWindow(to: .nan, span: Double(step) * 40),
                   ReviewReplayWindow(to: Double(first), span: 0),
                   ReviewReplayWindow(to: Double(first), span: .infinity)] {
      let next = ReviewReplayViewport.next(current: broken, previousLastTime: first,
                                           lastTime: first + step, step: step, reset: false)
      XCTAssertEqual(next.span, Double(step) * ReviewReplayViewport.defaultBars)
    }
  }

  // MARK: - 草稿只在**完全同一个上下文**里接着写

  /// 在 BTC 的 1 小时上圈了一段写了两句，切到 ETH（或切到 4 小时、切到别家交易所）
  /// 再点「记录」，接着写的不能还是 BTC 那条。三样全同才算同一个上下文。
  func testDraftIsReusedOnlyInTheExactSameContext() {
    let draft = ReviewDraft(range: ReviewRange(symbol: "BTCUSDT", interval: "1h",
                                               start: 0, end: 172_800_000, bars: 48),
                            reference: 100, high: 110, low: 90, now: 172_800_000)
    XCTAssertTrue(draft.reusable(venue: "binance", symbol: "BTCUSDT", interval: "1h"))
    XCTAssertFalse(draft.reusable(venue: "binance", symbol: "ETHUSDT", interval: "1h"), "换了品种")
    XCTAssertFalse(draft.reusable(venue: "binance", symbol: "BTCUSDT", interval: "4h"), "换了周期")
    XCTAssertFalse(draft.reusable(venue: "okx", symbol: "BTCUSDT", interval: "1h"), "换了交易所")
  }
}
