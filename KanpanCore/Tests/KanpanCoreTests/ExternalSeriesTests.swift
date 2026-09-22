import Foundation
import Testing
@testable import KanpanCore

@Suite("外部指标：对齐、缓存与实时桶")
struct ExternalSeriesTests {
  @Test("全部周期的稀疏对齐与持仓量逐位相同", arguments: Interval.allCases)
  func alignment(_ interval: Interval) {
    let day = Aggregator.utcMs(year: 2025, month: 1, day: 1)
    let bars = (0..<160).map { i in
      Bar(openTime: day + Int64(i) * interval.stepMs, open: 100, high: 101, low: 99, close: 100, volume: 10)
    }
    let series = BarSeries(symbol: "TEST", interval: interval, bars: bars)
    for sparse in [false, true] {
      let points = (0..<100).filter { !sparse || $0 % 7 != 0 }.map {
        OIPoint(time: day + Int64($0) * max(300_000, interval.stepMs), value: Double($0) * 1.234)
      }
      let oi = OISeries(points: points, step: max(300_000, interval.stepMs), bucketInterval: interval)
      let external = ExternalSeries(oi: oi)
      #expect(external.revision == oi.revision)
      #expect(external.aligned(to: series)[0].map(\.bitPattern) == oi.aligned(to: series).map(\.bitPattern))
    }
  }

  @Test("只改外部序列也刷新缓存；没有当前桶就留空")
  func cache() {
    let series = BarSeries(symbol: "TEST", interval: .m5, bars: [
      Bar(openTime: 300_000, open: 10, high: 11, low: 9, close: 10, volume: 1),
      Bar(openTime: 600_000, open: 10, high: 11, low: 9, close: 10, volume: 1)])
    var engine = IndicatorEngine()
    var input = ExternalSeries(t0: 300_000, step: 300_000, columns: [[1]], timestamps: [300_000], bucketInterval: .m5)
    engine.ensure(series: series, wanted: [.lsr], params: [:], external: [.lsr: input])
    #expect(engine[.lsr]?.lines[0][0] == 1)
    #expect(engine[.lsr]?.lines[0][1].isNaN == true)
    input.columns = [[2]]
    engine.ensure(series: series, wanted: [.lsr], params: [:], external: [.lsr: input])
    #expect(engine[.lsr]?.lines[0][0] == 2)
  }

  @Test("逐笔去重、乱序丢弃、跨桶归零，分母零不伪造比率")
  func taker() {
    var bucket = TakerBucket()
    bucket.add(time: 300_010, quantity: 6, buyer: true, id: 10, interval: .m1)
    #expect(bucket.point == nil)
    bucket.add(time: 300_020, quantity: 2, buyer: false, id: 11, interval: .m1)
    #expect(bucket.point == OIPoint(time: 300_000, value: 3))
    bucket.add(time: 300_020, quantity: 2, buyer: false, id: 11, interval: .m1)
    bucket.add(time: 300_015, quantity: 999, buyer: false, id: 9, interval: .m1)
    #expect(bucket.point?.value == 3)
    bucket.add(time: 600_010, quantity: 4, buyer: false, id: 12, interval: .m1)
    #expect(bucket.point == OIPoint(time: 600_000, value: 0))
    bucket = TakerBucket()
    #expect(bucket.point == nil)
  }

  @Test("中途连接和重连不把半桶显示为全桶")
  func partialBucket() {
    var bucket = TakerBucket(startedAt: 300_010)
    bucket.add(time: 300_020, quantity: 6, buyer: true, id: 1, interval: .m5)
    bucket.add(time: 300_030, quantity: 2, buyer: false, id: 2, interval: .m5)
    #expect(bucket.point == nil)
    bucket.add(time: 600_010, quantity: 6, buyer: true, id: 3, interval: .m5)
    bucket.add(time: 600_020, quantity: 2, buyer: false, id: 4, interval: .m5)
    #expect(bucket.point?.value == 3)
  }

  @Test("盘口只保留有效五档并按买降卖升排序")
  func book() {
    let levels = (1...8).map { OrderBook.Level(price: Double($0), quantity: 1) }
      + [.init(price: .nan, quantity: 2), .init(price: 9, quantity: 0)]
    let book = OrderBook(symbol: "TEST", time: 1, bids: levels, asks: levels)
    #expect(book.bids.map(\.price) == [8, 7, 6, 5, 4])
    #expect(book.asks.map(\.price) == [1, 2, 3, 4, 5])
  }
}
