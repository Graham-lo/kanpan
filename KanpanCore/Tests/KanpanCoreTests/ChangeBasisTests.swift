import Testing
@testable import KanpanCore

@Suite("统一涨跌幅开盘基准")
struct ChangeBasisTests {
  @Test("国际0点等于上海8点，上海0点前后使用不同UTC日期")
  func boundary() {
    let utc = Aggregator.utcMs(year: 2026, month: 9, day: 15)
    #expect(ChangeBasis.utcMidnight.boundary(now: utc + 1) == utc)
    #expect(ChangeBasis.utcMidnight.boundary(now: utc - 1) == utc - 86_400_000)
    #expect(ChangeBasis.shanghaiMidnight.boundary(now: utc + 1) == utc - 28_800_000)
    #expect(ChangeBasis.shanghaiMidnight.boundary(now: utc - 28_800_001) == utc - 28_800_000 - 86_400_000)
    #expect(ChangeBasis.rolling24h.boundary(now: utc) == nil)
  }

  @Test("滚动24小时保持交易所口径，日基准随最新价更新，缺开盘价留空")
  func dynamicPercent() {
    #expect(ChangeBasis.rolling24h.percent(last: 110, rolling: -2, open: 100) == -2)
    #expect(abs(ChangeBasis.utcMidnight.percent(last: 110, rolling: -2, open: 100) - 10) < 1e-10)
    #expect(abs(ChangeBasis.utcMidnight.percent(last: 90, rolling: -2, open: 100) + 10) < 1e-10)
    #expect(ChangeBasis.shanghaiMidnight.percent(last: 110, rolling: 5, open: nil).isNaN)
    #expect(ChangeBasis.shanghaiMidnight.percent(last: 110, rolling: 5, open: 0).isNaN)
  }
  @Test("振幅按24h开盘，切换涨跌基准不能改变振幅，缺开盘不伪造")
  func amplitude() {
    var ticker = Ticker(symbol: "BTCUSDT", last: 110, changePercent: 10,
      high: 120, low: 90, quoteVolume: 1000, open24h: 100)
    #expect(ticker.amplitude24h == 30)
    ticker.changePercent = -5
    #expect(ticker.amplitude24h == 30)
    ticker.open24h = nil
    #expect(ticker.amplitude24h == nil)
  }

}
