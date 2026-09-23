import Foundation
import Testing
import KanpanCore
import KanpanNetwork
@testable import KanpanMain

// 顶栏右侧六格（仓 / 额 · 市值 / 费率 · 结算 / 振幅）的取值规则。除了「仓」以外都会**过期**，
// 而过期的数和真的数在屏上长得一模一样——只能靠用例守。

@Suite("B-T10 / A-T20 顶栏六格只显示能负责的数")
struct HeaderStatsTests {
  @Test("涨跌额和价格采用相同的千位分隔")
  func groupedChange() {
    #expect(HeaderStats.priceChangeText(change: 3849.7, percent: 4.5, decimals: 1) == "+3,849.7  +4.50%")
    #expect(HeaderStats.priceChangeText(change: -12345.67, percent: -2, decimals: 2) == "−12,345.67  −2.00%")
  }

  @Test("头部涨跌额按品种精度、涨跌幅两位，缺数不编造")
  func changeLinePrecision() {
    let sndk = SymbolInfo(symbol: "SNDKUSDT", base: "SNDK", pricePrecision: 5, tickSize: 0.01)
    let btc = SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1)
    #expect(HeaderStats.priceChangeText(change: -19.73, percent: -1.1, decimals: sndk.priceDecimals) == "−19.73  −1.10%")
    #expect(HeaderStats.priceChangeText(change: 123.4, percent: 0.64, decimals: btc.priceDecimals) == "+123.4  +0.64%")
    #expect(HeaderStats.priceChangeText(change: 6.72, percent: 0.64, decimals: 2) == "+6.72  +0.64%")
    #expect(HeaderStats.priceChangeText(change: -0.00000001, percent: -0.08, decimals: 8) == "−0.00000001  −0.08%")
    #expect(HeaderStats.priceChangeText(change: nil, percent: 1, decimals: 2) == "—")
    #expect(HeaderStats.priceChangeText(change: .nan, percent: 1, decimals: 2) == "—")
  }

  @Test("带箭头的涨跌幅只写绝对值，缺数写破折号")
  func arrowPercent() {
    #expect(HeaderStats.arrowPercentText(-2.74) == "2.74%")
    #expect(HeaderStats.arrowPercentText(1.5) == "1.50%")
    #expect(HeaderStats.arrowPercentText(0) == "0.00%")
    #expect(HeaderStats.arrowPercentText(nil) == "—")
    #expect(HeaderStats.arrowPercentText(.nan) == "—")
  }

  private func stat(value: Double?, qty: Double?) -> OpenInterestStat {
    OpenInterestStat(symbol: "BTCUSDT", openInterest: qty, openInterestValue: value,
                     timeMs: 1_700_000_000_000)
  }

  // ---------------------------------------------------------------- B-T10

  @Test("没有美元名义持仓量，「仓」那一格就是 --")
  func openInterestWithoutNotionalShowsDashes() {
    #expect(HeaderStats.openInterestText(value: nil, unit: nil) == nil)
    #expect(HeaderStats.openInterestText(value: .nan, unit: nil) == nil)
    #expect(HeaderStats.openInterestText(value: 0, unit: nil) == nil)
    #expect(HeaderStats.openInterestText(value: -1, unit: nil) == nil)
  }

  @Test("有名义就按钉住的单位显示，没钉住才现认")
  func openInterestUsesPinnedUnit() {
    #expect(HeaderStats.openInterestText(value: 1_234_000_000, unit: nil) == "1.23B")
    // 单位按品种钉住：数字跌回百万档也还是 B，不会当着用户的面换单位。
    #expect(HeaderStats.openInterestText(value: 12_300_000, unit: .b) == "0.01B")
  }

  @Test("币本位数量永远进不了头部")
  func quantityNeverReachesTheHeader() {
    // 后端只给了数量：名义是 nil，那一格必须空着，而不是把 42000 个币当成 42000 美元。
    let next = MarketStatsClient.notionalOpenInterest(stat(value: nil, qty: 42_000), previous: nil)
    #expect(next == nil)
    #expect(HeaderStats.openInterestText(value: next, unit: nil) == nil)
  }

  // ---------------------------------------------------------------- A-T20

  @Test("先来一帧带名义、再来一帧只有数量，头部要变回 --")
  func staleNotionalIsClearedByANotionalLessFrame() {
    var shown = MarketStatsClient.notionalOpenInterest(stat(value: 9_000_000_000, qty: 120_000),
                                                       previous: nil)
    #expect(shown == 9_000_000_000)
    #expect(HeaderStats.openInterestText(value: shown, unit: nil) == "9.00B")

    // 同一个品种的下一轮：后端这次给不出名义了。旧的 9B 不能留在屏上。
    shown = MarketStatsClient.notionalOpenInterest(stat(value: nil, qty: 120_000), previous: shown)
    #expect(shown == nil)
    #expect(HeaderStats.openInterestText(value: shown, unit: nil) == nil)
  }

  @Test("整个请求没回来才沿用上一口值")
  func requestFailureKeepsThePreviousValue() {
    #expect(MarketStatsClient.notionalOpenInterest(nil, previous: 9_000_000_000) == 9_000_000_000)
    #expect(MarketStatsClient.notionalOpenInterest(nil, previous: nil) == nil)
  }

  // ---------------------------------------------------------------- B.8 展示寿命

  @Test("价不新鲜时，额 / 市值 / 费率一起 --")
  func staleQuoteBlanksTheDerivedCells() {
    #expect(HeaderStats.turnoverText(quoteVolume: 5_000_000, unit: nil, fresh: true) == "5.00M")
    #expect(HeaderStats.turnoverText(quoteVolume: 5_000_000, unit: nil, fresh: false) == nil)
    #expect(HeaderStats.marketCapText(totalSupply: 21_000_000, price: 100_000, fresh: true) == "2.10T")
    #expect(HeaderStats.marketCapText(totalSupply: 21_000_000, price: 100_000, fresh: false) == nil)
    #expect(HeaderStats.fundingText(rate: 0.0001, fresh: true) == "+0.0100%")
    #expect(HeaderStats.fundingText(rate: 0.0001, fresh: false) == nil)
  }

  @Test("成交额 0 和供应量 0 都是缺数，不是真的 0")
  func zeroIsMissingNotZero() {
    #expect(HeaderStats.turnoverText(quoteVolume: 0, unit: nil, fresh: true) == nil)
    #expect(HeaderStats.turnoverText(quoteVolume: .nan, unit: nil, fresh: true) == nil)
    #expect(HeaderStats.marketCapText(totalSupply: 0, price: 100, fresh: true) == nil)
    #expect(HeaderStats.marketCapText(totalSupply: 100, price: 0, fresh: true) == nil)
  }

  @Test("markPrice 帧超过一小时，费率就过期")
  func fundingFrameHasALifetime() {
    let now = Date(timeIntervalSince1970: 1_700_003_600)
    let fresh = Int64((now.timeIntervalSince1970 - 59 * 60) * 1000)
    let old = Int64((now.timeIntervalSince1970 - 61 * 60) * 1000)
    #expect(!HeaderStats.expired(frameMs: fresh, now: now, maxAge: HeaderStats.fundingMaxAge))
    #expect(HeaderStats.expired(frameMs: old, now: now, maxAge: HeaderStats.fundingMaxAge))
    // 一帧都没收到过：那时候费率本来就是 nil，不该被算成「过期」。
    #expect(!HeaderStats.expired(frameMs: 0, now: now, maxAge: HeaderStats.fundingMaxAge))
  }

  // ---------------------------------------------------------------- 距结算

  @Test("跟在费率后面那一小段只说还有多久结算，单位是中文的时和分")
  func fundingCountdownCountsDown() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let at = { (seconds: Double) in Int64((now.timeIntervalSince1970 + seconds) * 1000) }
    #expect(HeaderStats.fundingCountdownText(nextFundingTimeMs: at(4_320), now: now) == "1时12分")
    #expect(HeaderStats.fundingCountdownText(nextFundingTimeMs: at(720), now: now) == "12分")
    // 不足一分钟写「即将结算」，不写「还有零分钟」。
    #expect(HeaderStats.fundingCountdownText(nextFundingTimeMs: at(30), now: now) == "<1分")
  }

  @Test("没有结算时刻就一个字不写")
  func fundingCountdownStaysSilentWithoutData() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(HeaderStats.fundingCountdownText(nextFundingTimeMs: nil, now: now) == nil)
    #expect(HeaderStats.fundingCountdownText(nextFundingTimeMs: 0, now: now) == nil)
  }

  @Test("结算时刻过去之后自动滚到下一期")
  func fundingCountdownRollsOver() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // 刚刚结算完（10 秒前），下一帧还没到：写的是下一期，不是一个已经过去的时刻。
    let justPassed = Int64((now.timeIntervalSince1970 - 10) * 1000)
    #expect(HeaderStats.fundingCountdownText(nextFundingTimeMs: justPassed, now: now) == "7时59分")
  }

  // ---------------------------------------------------------------- 振幅

  @Test("振幅按最低价算 24h 的高低差")
  func amplitudeUsesLowAsDenominator() {
    #expect(HeaderStats.amplitudeText(high: 110, low: 100, fresh: true) == "10.00%")
    #expect(HeaderStats.amplitudeText(high: 100, low: 100, fresh: true) == "0.00%")
    #expect(HeaderStats.amplitudeText(high: 0.000_012, low: 0.000_010, fresh: true) == "20.00%")
  }

  @Test("高低价缺一个、或者价已经不新鲜，振幅就是 --")
  func amplitudeStaysDashesWithoutTrustworthyData() {
    #expect(HeaderStats.amplitudeText(high: 110, low: 100, fresh: false) == nil)
    #expect(HeaderStats.amplitudeText(high: nil, low: 100, fresh: true) == nil)
    #expect(HeaderStats.amplitudeText(high: 110, low: nil, fresh: true) == nil)
    #expect(HeaderStats.amplitudeText(high: .nan, low: 100, fresh: true) == nil)
    #expect(HeaderStats.amplitudeText(high: 110, low: 0, fresh: true) == nil)
    // 高比低还小只可能是拼错的两帧，宁可空着也不给一个负数。
    #expect(HeaderStats.amplitudeText(high: 90, low: 100, fresh: true) == nil)
  }

  /// 下架 / 交割的合约没有「现在的价」，顶栏不给它实时的样子（审查 B-06）。
  @MainActor
  @Test("品种不在交易时，这口价就不算新鲜")
  func untradableSymbolIsNeverFresh() {
    let model = MarketModel(symbol: "BTCUSDT")
    #expect(model.priceFresh)
    // 走产品自己那条路：交易所答不出这个代号时 `QuoteBook` 就是这么通知的
    // （审查 C-05——原来这儿用的是一个 `#if DEBUG` 的注入钩子，Release 下不存在，
    // 整个测试包因此在 Release 配置下编不过）。
    model.noteSymbolRejected("BTCUSDT")
    #expect(!model.priceFresh)
  }
}
