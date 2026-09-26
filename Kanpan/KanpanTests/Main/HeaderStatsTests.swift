import Foundation
import Testing
import KanpanCore
import KanpanNetwork
@testable import Kanpan

// 顶栏右侧六格（仓 / 额 · 市值 / 费率 · 结算 / 估值）的取值规则。除了「仓」以外都会**过期**，
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

  /// 涨跌幅那半截走 KanpanCore 那把 `changePercentText`（审查 U9），
  /// 用例在 `FormatTests`；这儿只守顶栏涨跌额取整成 0 时不写「−0.00」。
  @Test("涨跌额取整成 0 时不带负号")
  func flatChangeHasNoMinus() {
    #expect(HeaderStats.priceChangeText(change: -0.001, percent: -0.001, decimals: 2) == "+0.00  +0.00%")
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

  @Test("第六格：币给 OI/MC，就是「仓」÷「市值」")
  func cryptoOpenInterestToCap() {
    // 供应量 1 亿 × 价 10 = 市值 10 亿；持仓 2,500 万 → 2.50%。
    let cell = HeaderStats.valuationCell(asset: .crypto, openInterest: 25e6, totalSupply: 1e8, price: 10,
                                         forwardEarnings: nil, revenue: nil, fresh: true)
    #expect(cell?.label == "OI/MC")
    #expect(cell?.value == "2.50%")
    // 量级跟着位数走：BTC 那种零点几、山寨几十。
    #expect(HeaderStats.valuationCell(asset: .crypto, openInterest: 4.3e9, totalSupply: 1e10, price: 100,
                                      forwardEarnings: nil, revenue: nil, fresh: true)?.value == "0.43%")
    #expect(HeaderStats.valuationCell(asset: .crypto, openInterest: 3.47e8, totalSupply: 1e8, price: 10,
                                      forwardEarnings: nil, revenue: nil, fresh: true)?.value == "34.7%")
    // 缺持仓、缺供应量、价不新鲜：格子还在，值是破折号。
    for (oi, supply, fresh) in [(nil, 1e8, true), (25e6, nil, true), (25e6, 1e8, false)] as [(Double?, Double?, Bool)] {
      let blank = HeaderStats.valuationCell(asset: .crypto, openInterest: oi, totalSupply: supply, price: 10,
                                            forwardEarnings: nil, revenue: nil, fresh: fresh)
      #expect(blank?.label == "OI/MC")
      #expect(blank?.value == nil)
    }
  }

  @Test("第六格：股票给 Fwd PE，预期亏损的给 P/S，按正在显示的那口价现除")
  func equityValuation() {
    // NVDA 形状：市值 5.42T、远期利润 = 5.42T / 18.72。价涨一成，远期市盈率跟着涨一成。
    let earnings = 5.42e12 / 18.72
    let supply = 5.42e12 / 180
    let at = { (price: Double) in
      HeaderStats.valuationCell(asset: .equity, openInterest: 9e9, totalSupply: supply, price: price,
                                forwardEarnings: earnings, revenue: 302.97e9, fresh: true)
    }
    #expect(at(180)?.label == "Fwd PE")
    #expect(at(180)?.value == "18.7")
    #expect(at(198)?.value == "20.6")
    // RIVN 形状：没有远期利润，只剩营收 → P/S。
    let loss = HeaderStats.valuationCell(asset: .equity, openInterest: nil, totalSupply: 22.14e9 / 15, price: 15,
                                         forwardEarnings: nil, revenue: 5.88e9, fresh: true)
    #expect(loss?.label == "P/S")
    #expect(loss?.value == "3.77")
    // 两项都没有（ETF 这类）：格子仍叫 Fwd PE，值是破折号；股票不会显示 OI/MC。
    let none = HeaderStats.valuationCell(asset: .equity, openInterest: 9e9, totalSupply: supply, price: 180,
                                         forwardEarnings: nil, revenue: nil, fresh: true)
    #expect(none?.label == "Fwd PE")
    #expect(none?.value == nil)
    // 价不新鲜：同一套规矩。
    #expect(HeaderStats.valuationCell(asset: .equity, openInterest: nil, totalSupply: supply, price: 180,
                                      forwardEarnings: earnings, revenue: nil, fresh: false)?.value == nil)
  }

  @Test("第六格：金属、指数、未上市、不知道的都没有这一格")
  func noValuationCellForOtherAssets() {
    for asset in [SymbolClassification.Asset.preciousMetal, .commodity, .index, .preMarket, .other] {
      #expect(HeaderStats.valuationCell(asset: asset, openInterest: 1e9, totalSupply: 1e8, price: 10,
                                        forwardEarnings: 1e9, revenue: 1e9, fresh: true) == nil)
    }
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

  /// 下架 / 交割的合约没有「现在的价」，顶栏不给它实时的样子（审查 B-06）。
  @MainActor
  @Test("品种不在交易时，这口价就不算新鲜")
  func untradableSymbolIsNeverFresh() {
    let model = MarketModel(symbol: "BTCUSDT", endpoints: .default)
    #expect(model.priceFresh)
    // 走产品自己那条路：交易所答不出这个代号时 `QuoteBook` 就是这么通知的
    // （审查 C-05——原来这儿用的是一个 `#if DEBUG` 的注入钩子，Release 下不存在，
    // 整个测试包因此在 Release 配置下编不过）。
    model.noteSymbolRejected("BTCUSDT")
    #expect(!model.priceFresh)
  }

  /// 断网 / 弱网：推送连接不在 `.live` 超过宽限，顶栏那口价就不再当实时价摆（整机压测 2026-09-26）。
  @MainActor
  @Test("推送连接断了超过宽限，顶栏的价就不算新鲜；闪断看不见，后台不算")
  func droppedLinkMakesThePriceStale() {
    let model = MarketModel(symbol: "BTCUSDT", endpoints: .default)
    let grace = MarketModel.linkGrace
    let t0 = Date()
    model.noteFeedStatus(.live, now: t0)
    #expect(model.priceFresh)
    // 闪断：宽限之内接上，一下都不灰。
    model.noteFeedStatus(.reconnecting, now: t0)
    model.sweepDisplayLifetimes(now: t0.addingTimeInterval(1))
    #expect(model.priceFresh, "闪断一秒顶栏就灰了一下")
    model.noteFeedStatus(.live, now: t0.addingTimeInterval(1.5))
    model.sweepDisplayLifetimes(now: t0.addingTimeInterval(60))
    #expect(model.priceFresh)
    // 真断了：一路 offline → reconnecting（中途换档不重新起算），过了宽限就灰。
    let t1 = t0.addingTimeInterval(100)
    model.noteFeedStatus(.offline, now: t1)
    model.noteFeedStatus(.reconnecting, now: t1.addingTimeInterval(grace - 1))
    model.sweepDisplayLifetimes(now: t1.addingTimeInterval(grace + 0.1))
    #expect(!model.priceFresh, "断线之后顶栏那口价还是全彩，看起来就是实时价")
    model.noteFeedStatus(.live, now: t1.addingTimeInterval(grace + 2))
    #expect(model.priceFresh, "重新连上了还灰着")
    // 后台里断开不算；回前台还没连上，从回来那一刻重新起算。
    model.enterBackground()
    let t2 = t1.addingTimeInterval(200)
    model.noteFeedStatus(.offline, now: t2)
    model.sweepDisplayLifetimes(now: t2.addingTimeInterval(600))
    #expect(model.priceFresh)
    model.enterForeground()
    let back = Date()
    model.sweepDisplayLifetimes(now: back.addingTimeInterval(1))
    #expect(model.priceFresh, "回前台那一下就灰了：后台断开的时长被算了进来")
    model.sweepDisplayLifetimes(now: back.addingTimeInterval(grace + 1))
    #expect(!model.priceFresh)
    model.stop()
  }

  /// 统计轮询要有一台 kanpan-api 主机才会开（`.default` 是空表，`startStats` 直接收手）。
  /// 给一个本机必然拒连的地址：轮询真的挂上，但一口请求也出不了这台机器。
  static let statsEndpoints = MarketEndpoints(gateways: [], api: ["127.0.0.1:9"])

  /// 进了后台，持仓量轮询不许被换品种 / 换线路重新拉起来（整机压测 2026-09-26）。
  @MainActor
  @Test("后台里冷切换不重开持仓量轮询，回前台再开")
  func backgroundColdSwitchDoesNotRestartStatsPolling() {
    let model = MarketModel(symbol: "BTCUSDT", endpoints: Self.statsEndpoints)
    // 前提：前台冷切换确实会开轮询——否则下面那句断言什么都证明不了。
    model.switchTo(symbol: "ETHUSDT")
    #expect(model.isPollingStats, "前台冷切换没开轮询，这条用例验不到东西")
    model.enterBackground()
    #expect(!model.isPollingStats)
    model.switchTo(symbol: "SOLUSDT")
    #expect(!model.isPollingStats, "后台里换品种把 45 秒一轮的持仓量轮询又拉起来了")
    model.stop()
  }

  /// 跨交易所冷换品种：`.provider` 报到之前，持仓量按新品种自己那家取（整机压测 2026-09-26）。
  @MainActor
  @Test("冷换到另一家交易所的品种，持仓量来源立刻跟着新品种走")
  func coldCrossVenueSwitchUsesNewSymbolsStatsSource() {
    let model = MarketModel(symbol: "coinbase/spot/BTC-USD", endpoints: Self.statsEndpoints)
    let coinbase = model.capabilities
    #expect(coinbase.openInterestSource == nil, "前提：Coinbase 现货没有持仓量")
    model.switchTo(symbol: "BTCUSDT")
    // 离线单测里 `.provider` 不会到：`capabilities` 仍是 Coinbase 那份，统计口径不能跟着它。
    #expect(model.capabilities == coinbase, "前提：.provider 还没到")
    #expect(model.statsCapabilities.openInterestSource == "binance")
    #expect(model.isPollingStats)
    #expect(model.pollingStatsSource == "binance", "轮询还按上一只（Coinbase）的口径取，持仓量那格会一直是「—」")
    model.switchTo(symbol: "coinbase/spot/ETH-USD")
    #expect(model.statsCapabilities.openInterestSource == nil)
    model.stop()
  }

  /// 「创建提醒」的现价先取最后一笔成交：换品种之后上一只的那笔不能留着。
  @MainActor
  @Test("换品种之后，上一只的最后一笔成交不再算这一只的")
  func coldSwitchDropsTheLastTrade() {
    let model = MarketModel(symbol: "BTCUSDT", endpoints: .default)
    model.acceptTrade(TradeQuote(symbol: "BTCUSDT", price: 65_000, timeMs: 1_700_000_000_000, tradeID: 1))
    #expect(model.tradeQuote?.price == 65_000)
    // 晚到的别家成交不收。
    model.acceptTrade(TradeQuote(symbol: "ETHUSDT", price: 3_000, timeMs: 1_700_000_000_100, tradeID: 2))
    #expect(model.tradeQuote?.price == 65_000)
    model.switchTo(symbol: "ETHUSDT")
    #expect(model.tradeQuote == nil)
    // 只换周期不是冷切换，这一只自己的成交留着。
    model.acceptTrade(TradeQuote(symbol: "ETHUSDT", price: 3_000, timeMs: 1_700_000_000_200, tradeID: 3))
    model.switchTo(interval: .h4)
    #expect(model.tradeQuote?.price == 3_000)
    model.stop()
  }
}
