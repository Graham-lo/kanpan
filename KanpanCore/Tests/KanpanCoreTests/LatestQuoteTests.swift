import Testing
@testable import KanpanCore

@Suite("Latest quote identity and ordering")
struct LatestQuoteTests {
  func quote(_ price: Double = 100, time: Int64? = 1000, id: Int64? = 1, symbol: String = "BTCUSDT") -> Ticker {
    Ticker(symbol: symbol, last: price, changePercent: 1, high: 120, low: 90, quoteVolume: 1000, timeMs: time, lastTradeID: id)
  }
  @Test func staleAndDuplicate() {
    let latest = quote(time: 2000, id: 20)
    #expect(!LatestQuote.accepts(quote(1, time: 1000, id: 10), after: latest))
    #expect(!LatestQuote.accepts(latest, after: latest))
    #expect(!LatestQuote.accepts(quote(1, time: 3000, id: 10), after: latest))
    #expect(!LatestQuote.accepts(quote(999, time: 2000, id: 20), after: latest))
    #expect(LatestQuote.accepts(quote(101, time: 2000, id: 21), after: latest))
    #expect(LatestQuote.accepts(quote(102, time: 2001, id: 22), after: latest))
  }
  @Test func identityAndValidity() {
    #expect(!LatestQuote.accepts(quote(symbol: "ETHUSDT"), after: quote()))
    for bad in [Double.nan, .infinity, -1, 0] { #expect(!LatestQuote.accepts(quote(bad), after: nil)) }
    #expect(!LatestQuote.accepts(quote(500, time: nil), after: quote()))
    #expect(LatestQuote.newest(quote(), nil, symbol: "ETHUSDT") == nil)
  }
  @Test func samePriceNewClockDoesNotInvalidateDisplay() {
    #expect(LatestQuote.sameDisplay(quote(), quote(time: 2000, id: 2)))
    #expect(!LatestQuote.sameDisplay(quote(), quote(101)))
  }
  @Test func arbitraryArrivalOrderConverges() {
    let updates = [quote(1, time: 1), quote(2, time: 2), quote(3, time: 3)]
    for order in [[0,1,2,1,0], [2,1,0,2], [1,0,2,1], [2,2,2]] {
      var current: Ticker?
      for index in order where LatestQuote.accepts(updates[index], after: current) { current = updates[index] }
      #expect(current?.last == 3)
    }
  }
}

@Suite("Independent live price and rolling statistics")
struct QuoteStateTests {
  @Test("较晚统计保留交易所涨跌额，较新成交只补价格差")
  func priceChangeFollowsLatestTrade() {
    var state = QuoteState()
    var first = ticker(105, time: 1900, id: 19)
    first.priceChange = 4.75
    state.receive(first)
    #expect(state.value?.priceChange == 4.75)
    state.receive(trade(106))
    #expect(state.value?.priceChange == 5.75)
    var different = first; different.priceChange = 4.5
    #expect(!LatestQuote.sameDisplay(first, different))
  }
  func ticker(_ price: Double, time: Int64, id: Int64, open: Double = 100) -> Ticker {
    Ticker(symbol: "BTCUSDT", last: price, changePercent: 0, high: 110, low: 90,
      quoteVolume: 1000, open24h: open, timeMs: time, lastTradeID: id)
  }
  func trade(_ price: Double, time: Int64 = 2000, id: Int64 = 20) -> TradeQuote {
    TradeQuote(symbol: "BTCUSDT", price: price, timeMs: time, tradeID: id)
  }
  @Test func delayedStatisticsCannotOverwriteLivePrice() {
    var state = QuoteState()
    #expect({ state.receive(trade(120)) }())
    #expect(state.value?.quoteVolume.isNaN == true)
    #expect({ state.receive(ticker(105, time: 1900, id: 19)) }())
    #expect(state.value?.last == 120)
    #expect(state.value?.changePercent == 20)
    #expect(state.value?.quoteVolume == 1000)
    #expect(state.value?.high == 120)
    #expect(state.value?.timeMs == 2000)
    #expect({ !state.receive(trade(1, time: 9000, id: 18)) }())
    #expect({ !state.receive(trade(999, time: 9001)) }())
    #expect(state.value?.last == 120)
  }
  @Test func sameMillisecondAndPeriodSwitchConverge() {
    var state = QuoteState()
    state.receive(ticker(100, time: 2000, id: 20))
    #expect({ state.receive(trade(101, id: 21)) }())
    #expect({ !state.receive(trade(80, time: 3000, id: 10)) }())
    state.receive(ticker(100, time: 2100, id: 20, open: 80))
    #expect(state.value?.last == 101)
    #expect(state.value?.changePercent == 26.25)
    #expect({ state.receive(trade(102, time: 2050, id: 22)) }())
    #expect(state.value?.timeMs == 2100)
    #expect(state.value?.last == 102)
  }
  @Test func identityAndInvalidTrade() {
    var state = QuoteState()
    state.receive(trade(100))
    #expect({ !state.receive(TradeQuote(symbol: "ETHUSDT", price: 1, timeMs: 9000, tradeID: 99)) }())
    for price in [Double.nan, .infinity, 0, -1] { #expect({ !state.receive(trade(price, id: 30)) }()) }
    #expect(state.value?.last == 100)
  }
}

@Suite("成交额自己一条时钟（推送帧不带成交额的线路）")
struct TurnoverCarryTests {
  func frame(_ price: Double, time: Int64, turnover: Double = .nan, symbol: String = "BTCUSDT") -> Ticker {
    Ticker(symbol: symbol, last: price, changePercent: 1, high: 110, low: 90,
      quoteVolume: turnover, open24h: 100, timeMs: time)
  }

  @Test("推送帧不带成交额时沿用 REST 补来的那份")
  func streamWithoutTurnoverKeepsKnownValue() {
    var state = QuoteState()
    state.receive(frame(101, time: 1000, turnover: 5_000))
    state.receive(frame(102, time: 2000))
    #expect(state.value?.last == 102)
    #expect(state.value?.quoteVolume == 5_000)
    #expect(state.turnoverTimeMs == 1000)
  }

  @Test("整帧已旧的 REST 回包，成交额仍收下，价不回退")
  func staleRestFrameStillDeliversTurnover() {
    var state = QuoteState()
    state.receive(frame(102, time: 2000))
    #expect(state.value?.quoteVolume.isNaN == true)
    let r1 = state.receive(frame(101, time: 1500, turnover: 7_000))
    #expect(r1)
    #expect(state.value?.last == 102)
    #expect(state.value?.quoteVolume == 7_000)
    // 比已知成交额更旧的那份不收。
    let r2 = state.receive(frame(100, time: 1200, turnover: 6_000))
    #expect(!r2)
    #expect(state.value?.quoteVolume == 7_000)
  }

  @Test("只收成交额的入口不动价和会话")
  func turnoverOnlyEntry() {
    var state = QuoteState()
    let r3 = state.receiveTurnover(frame(99, time: 500, turnover: 1))
    #expect(!r3)  // 还没有值：记下但不出值
    state.receive(frame(102, time: 2000))
    #expect(state.value?.quoteVolume == 1)
    let r4 = state.receiveTurnover(frame(99, time: 1800, turnover: 8_000))
    #expect(r4)
    #expect(state.value?.last == 102)
    #expect(state.value?.quoteVolume == 8_000)
    let r5 = state.receiveTurnover(frame(99, time: 1800, turnover: 8_000))
    #expect(!r5)
  }

  @Test("换品种不借上一只的成交额")
  func carryDoesNotCrossSymbols() {
    var carry = TurnoverCarry()
    carry.note(frame(1, time: 1000, turnover: 9_000))
    #expect(carry.apply(frame(2, time: 2000, symbol: "ETHUSDT")).quoteVolume.isNaN)
    #expect(carry.apply(frame(2, time: 2000)).quoteVolume == 9_000)
    carry.note(frame(3, time: 500, turnover: 10, symbol: "ETHUSDT"))
    #expect(carry.symbol == InstrumentID.canonical("ETHUSDT"))
    #expect(carry.apply(frame(2, time: 2000)).quoteVolume.isNaN)
  }

  @Test("带成交额的帧照旧以帧里的为准")
  func frameValueWins() {
    var carry = TurnoverCarry()
    carry.note(frame(1, time: 1000, turnover: 9_000))
    #expect(carry.apply(frame(2, time: 900, turnover: 3)).quoteVolume == 3)
  }
}
