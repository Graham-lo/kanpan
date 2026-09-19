import Foundation
import Testing
@testable import KanpanData
import KanpanCore

/// `merge` 是所有「REST 回包和手上的序列合在一起」的入口：它先按 `time(at:)` 把
/// 手上的每一根建成字典，再 `keys.sorted()` 重建整条。所以手上那条序列只要有一根
/// 的时间是推出来的错值，错的就不只是显示——错时间会被当成真键写进字典，下一次
/// 补洞回来时，正确时间的新根和错位的旧根混在一起，序列被永久污染。
@Suite("空洞序列的合并与落盘")
struct SeriesGapMergeTests {
  private static let t0: Int64 = 1_700_000_000_000
  private static let step: Int64 = Interval.m1.stepMs

  private func slot(_ k: Int64) -> Bar {
    let v = Double(k)
    return Bar(openTime: Self.t0 + k * Self.step, open: v, high: v + 1, low: v - 1,
               close: v + 0.5, volume: v * 10)
  }
  private func composer(_ slots: [Int64]) -> FeedComposer {
    FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1, bars: slots.map { slot($0) }))
  }

  @Test("抽掉中间一根喂进 merge，末根的时间不能早一根")
  func mergedSeriesWithAHoleKeepsTheRealTail() {
    var c = composer([])
    c.merge([0, 1, 2, 4, 5].map { slot($0) })       // 第 3 格缺
    #expect(c.series.count == 5)
    #expect(c.series.lastTime == Self.t0 + 5 * Self.step)
    #expect(c.lastOpen == Self.t0 + 5 * Self.step)
  }

  @Test("旧快照接最新窗口，中间的两根空洞不能把后段整体平移")
  func snapshotPlusLatestWindowDoesNotShift() {
    var c = composer([0, 1, 2])                     // 旧快照
    c.merge([5, 6, 7].map { slot($0) })             // 最新窗口，第 3、4 格没人给
    #expect(c.series.count == 6)
    #expect(c.series.lastTime == Self.t0 + 7 * Self.step)
    for (i, k) in [0, 1, 2, 5, 6, 7].enumerated() {
      #expect(c.series.time(at: i) == Self.t0 + Int64(k) * Self.step, "第 \(i) 根应是第 \(k) 格")
    }
  }

  @Test("空洞被 REST 补上之后，整段一根不多一根不少")
  func fillingTheHoleRepairsTheSeriesCompletely() {
    var c = composer([0, 1, 2])
    c.merge([5, 6, 7].map { slot($0) })
    c.merge([3, 4].map { slot($0) })                // 洞由后到的 REST 补上
    #expect(c.series.count == 8, "补完应当正好 8 根，实际 \(c.series.count)")
    #expect(c.series.openTime.isEmpty, "整段重新严格等距，列该省掉")
    for k in 0..<8 {
      #expect(c.series.time(at: k) == Self.t0 + Int64(k) * Self.step)
      #expect(c.series.close[k] == Double(k) + 0.5, "第 \(k) 格的值串了")
    }
  }

  @Test("带洞的序列写进快照再读回来，每一根的时间都不变")
  func snapshotRoundTripPreservesHoles() throws {
    let slots: [Int64] = [0, 1, 2, 6, 7]
    let s = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: slots.map { slot($0) })
    let back = try #require(Snapshot.decode(Snapshot.encode(s)))
    #expect(back.count == slots.count)
    for (i, k) in slots.enumerated() {
      #expect(back.time(at: i) == Self.t0 + k * Self.step, "第 \(i) 根应是第 \(k) 格")
    }
    #expect(back.lastTime == s.lastTime)
  }

  @Test("空洞序列进内存缓存被截头之后，剩下那段的时间还是真时间")
  func trimmedSeriesKeepsRealTimes() async throws {
    let cache = BarCache(perKeyCap: 4)
    let slots: [Int64] = [0, 1, 2, 6, 7, 8]
    await cache.put(BarSeries(symbol: "BTCUSDT", interval: .m1, bars: slots.map { slot($0) }))
    let got = try #require(await cache.get(SeriesKey("BTCUSDT", .m1)))
    #expect(got.count == 4)
    for (i, k) in [2, 6, 7, 8].enumerated() {
      #expect(got.time(at: i) == Self.t0 + Int64(k) * Self.step, "第 \(i) 根应是第 \(k) 格")
    }
  }
}
