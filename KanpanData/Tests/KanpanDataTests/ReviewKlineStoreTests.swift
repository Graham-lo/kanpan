import Foundation
import Testing
@testable import KanpanData
import KanpanCore

/// 复盘历史 K 线的盘上缓存与并行取数（体感优化 2026-10-07）。
@Suite("复盘 K 线缓存")
struct ReviewKlineStoreTests {
  let symbol = "BTCUSDT"
  let step = Interval.m5.stepMs
  let base: Int64 = 1_700_000_100_000 - (1_700_000_100_000 % Interval.m5.stepMs)

  func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("rkl-\(UUID().uuidString)", isDirectory: true)
  }

  func bars(_ from: Int64, count: Int, step: Int64) -> [Bar] {
    (0..<count).map { i in
      let t = from + Int64(i) * step
      return Bar(openTime: t, open: 100 + Double(i), high: 101 + Double(i), low: 99 + Double(i),
                 close: 100.5 + Double(i), volume: 10, takerBuy: i % 2 == 0 ? .nan : 4)
    }
  }

  /// 假交易所：`[start, endInclusive]` 里每一步一根，记下每次问了什么、同时有几页在路上。
  final class Exchange: @unchecked Sendable {
    let lock = NSLock()
    var calls: [(Int64, Int64)] = []
    var inFlight = 0
    var peak = 0
    let step: Int64
    let firstBar: Int64
    let lastBar: Int64
    let delay: UInt64
    init(step: Int64, firstBar: Int64, lastBar: Int64, delayNs: UInt64 = 0) {
      self.step = step; self.firstBar = firstBar; self.lastBar = lastBar; self.delay = delayNs
    }
    func fetch(_ s: Int64, _ e: Int64, _ limit: Int) async throws -> [Bar] {
      lock.withLock { calls.append((s, e)); inFlight += 1; peak = max(peak, inFlight) }
      if delay > 0 { try await Task.sleep(nanoseconds: delay) }
      defer { lock.withLock { inFlight -= 1 } }
      var t = max(s, firstBar)
      if (t - firstBar) % step != 0 { t += step - (t - firstBar) % step }
      var out: [Bar] = []
      while t <= min(e, lastBar), out.count < limit {
        out.append(Bar(openTime: t, open: 1, high: 2, low: 0.5, close: 1.5, volume: 3, takerBuy: .nan))
        t += step
      }
      return out
    }
    var callCount: Int { lock.withLock { calls.count } }
  }

  @Test("写进去的已收盘 K 线能原样读回来（含 NaN 主动买量），重开 store 也在")
  func roundTrip() async {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ReviewKlineStore(directory: dir)
    let input = bars(base, count: 50, step: step)
    let end = base + 50 * step
    await store.record(symbol: symbol, interval: .m5, from: base, to: end, bars: input, now: end + 10 * step)
    let reopened = ReviewKlineStore(directory: dir)
    let hit = await reopened.lookup(symbol: symbol, interval: .m5, from: base, to: end)
    #expect(hit.isComplete)
    #expect(hit.bars.count == 50)
    #expect(hit.bars.first?.takerBuy.isNaN == true)
    #expect(hit.bars[1].takerBuy == 4)
    #expect(hit.bars.map(\.openTime) == input.map(\.openTime))
  }

  @Test("缺的那几段算得对：只问没存过的部分")
  func missingRanges() async {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ReviewKlineStore(directory: dir)
    let far = base + 1000 * step
    await store.record(symbol: symbol, interval: .m5, from: base + 10 * step, to: base + 20 * step,
                       bars: bars(base + 10 * step, count: 10, step: step), now: far)
    let hit = await store.lookup(symbol: symbol, interval: .m5, from: base, to: base + 30 * step)
    #expect(hit.bars.count == 10)
    #expect(hit.missing == [base..<(base + 10 * step), (base + 20 * step)..<(base + 30 * step)])
  }

  @Test("还在走的那一根和「现在」附近不进缓存，下次照样去取")
  func formingBarNotCached() async {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ReviewKlineStore(directory: dir)
    // now 落在第 10 根中间：第 10 根还在走。
    let now = base + 10 * step + step / 2
    await store.record(symbol: symbol, interval: .m5, from: base, to: base + 20 * step,
                       bars: bars(base, count: 11, step: step), now: now)
    let hit = await store.lookup(symbol: symbol, interval: .m5, from: base, to: base + 20 * step)
    #expect(hit.bars.count == 10)
    #expect(hit.missing == [(base + 10 * step)..<(base + 20 * step)])
  }

  @Test("交易所什么都没给的一次不记")
  func emptyNotRecorded() async {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ReviewKlineStore(directory: dir)
    await store.record(symbol: symbol, interval: .m5, from: base, to: base + 20 * step, bars: [], now: base + 999 * step)
    let hit = await store.lookup(symbol: symbol, interval: .m5, from: base, to: base + 20 * step)
    #expect(hit.missing == [base..<(base + 20 * step)])
  }

  @Test("相邻、相交的段并成一段；同一根以新取的为准")
  func mergeAdjacent() {
    typealias S = ReviewKlineStore.Segment
    let a = S(from: 0, to: 10, bars: [Bar(openTime: 5, open: 1, high: 1, low: 1, close: 1, volume: 1)])
    let b = S(from: 20, to: 30, bars: [])
    let fresh = S(from: 10, to: 20, bars: [Bar(openTime: 5, open: 9, high: 9, low: 9, close: 9, volume: 9),
                                            Bar(openTime: 15, open: 2, high: 2, low: 2, close: 2, volume: 2)])
    let merged = ReviewKlineStore.merge([a, b], with: fresh)
    #expect(merged.count == 1)
    #expect(merged[0].from == 0 && merged[0].to == 30)
    #expect(merged[0].bars.map(\.openTime) == [5, 15])
    #expect(merged[0].bars[0].close == 9)
  }

  @Test("单个文件超条数上限：先丢离这次写入最远的段，一段装不下从远端截")
  func perSlotCap() async {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ReviewKlineStore(directory: dir, maxBarsPerSlot: 30)
    let far = base + 100_000 * step
    await store.record(symbol: symbol, interval: .m5, from: base, to: base + 20 * step,
                       bars: bars(base, count: 20, step: step), now: far)
    let later = base + 1000 * step
    await store.record(symbol: symbol, interval: .m5, from: later, to: later + 20 * step,
                       bars: bars(later, count: 20, step: step), now: far)
    let old = await store.lookup(symbol: symbol, interval: .m5, from: base, to: base + 20 * step)
    let new = await store.lookup(symbol: symbol, interval: .m5, from: later, to: later + 20 * step)
    #expect(old.bars.isEmpty)
    #expect(new.isComplete && new.bars.count == 20)

    // 一段 50 根，上限 30：写入在尾部，截掉头部 20 根。
    let x = base + 5000 * step
    await store.record(symbol: symbol, interval: .m5, from: x, to: x + 50 * step,
                       bars: bars(x, count: 50, step: step), now: far)
    let all = await store.lookup(symbol: symbol, interval: .m5, from: x, to: x + 50 * step)
    #expect(all.bars.count == 30)
    #expect(all.missing == [x..<(x + 20 * step)])
  }

  @Test("整棵目录超总量：按最近使用从最久没用的删，刚写的那份留着")
  func totalCapEvictsLRU() async throws {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    // 每份 100 根 ≈ 5.6 KB，总量 16 KB（删到 3/4 即 12 KB）：写第三份时删掉最久没用的那一份正好够。
    let store = ReviewKlineStore(directory: dir, maxBytes: 16_000)
    let far = base + 100_000 * step
    let input = bars(base, count: 100, step: step)
    let end = base + 100 * step
    await store.record(symbol: "AAAUSDT", interval: .m5, from: base, to: end, bars: input, now: far)
    try await Task.sleep(nanoseconds: 20_000_000)
    await store.record(symbol: "BBBUSDT", interval: .m5, from: base, to: end, bars: input, now: far)
    try await Task.sleep(nanoseconds: 20_000_000)
    // 读一下 A，它就成了最近用过的。
    _ = await store.lookup(symbol: "AAAUSDT", interval: .m5, from: base, to: end)
    try await Task.sleep(nanoseconds: 20_000_000)
    await store.record(symbol: "CCCUSDT", interval: .m5, from: base, to: end, bars: input, now: far)
    #expect(await store.totalBytes() <= 16_000)
    let fresh = ReviewKlineStore(directory: dir, maxBytes: 16_000)
    #expect(await fresh.lookup(symbol: "BBBUSDT", interval: .m5, from: base, to: end).bars.isEmpty)
    #expect(await fresh.lookup(symbol: "AAAUSDT", interval: .m5, from: base, to: end).isComplete)
    #expect(await fresh.lookup(symbol: "CCCUSDT", interval: .m5, from: base, to: end).isComplete)
  }

  @Test("分钟与月份文件名不撞，行情源分区分开放")
  func slotsDistinct() async {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let m1 = ReviewKlineStore.url(symbol: symbol, interval: .m1, namespace: nil, in: dir)
    let mo1 = ReviewKlineStore.url(symbol: symbol, interval: .mo1, namespace: nil, in: dir)
    let ns = ReviewKlineStore.url(symbol: symbol, interval: .m1, namespace: "relay", in: dir)
    #expect(m1 != nil && m1?.lastPathComponent.lowercased() != mo1?.lastPathComponent.lowercased())
    #expect(ns != m1)
    #expect(ReviewKlineStore.url(symbol: "../../etc", interval: .m1, namespace: nil, in: dir) == nil)
  }

  @Test("第二次打开同一段一页都不取，秒出")
  func loaderSecondOpenHitsDisk() async throws {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ReviewKlineStore(directory: dir)
    let end = base + 3000 * step
    let ex = Exchange(step: step, firstBar: base - 100 * step, lastBar: end + 100 * step)
    let now = end + 50 * step
    let first = try await ReviewKlineLoader.load(symbol: symbol, interval: .m5, start: base, end: end,
                                                 pageLimit: 1000, maxBars: 6000, overflow: .fail, now: now,
                                                 store: store) { try await ex.fetch($0, $1, $2) }
    #expect(first.count == 3000)
    let calls = ex.callCount
    #expect(calls == 3)
    let second = try await ReviewKlineLoader.load(symbol: symbol, interval: .m5, start: base, end: end,
                                                  pageLimit: 1000, maxBars: 6000, overflow: .fail, now: now,
                                                  store: store) { try await ex.fetch($0, $1, $2) }
    #expect(second == first)
    #expect(ex.callCount == calls)
  }

  @Test("缺的部分切成整页并行取，同时在路上的不超过上限，拼回来连续不重")
  func loaderParallelPages() async throws {
    let end = base + 5000 * step
    let ex = Exchange(step: step, firstBar: base, lastBar: end, delayNs: 30_000_000)
    let out = try await ReviewKlineLoader.load(symbol: symbol, interval: .m5, start: base, end: end,
                                               pageLimit: 500, maxBars: 6000, overflow: .fail, now: end * 2,
                                               store: nil, maxConcurrent: 3) { try await ex.fetch($0, $1, $2) }
    #expect(out.count == 5000)
    #expect(zip(out, out.dropFirst()).allSatisfy { $1.openTime - $0.openTime == step })
    #expect(ex.peak > 1 && ex.peak <= 3)
    #expect(ex.callCount == 10)
  }

  @Test("超上限：回放直接报错，缩略图只取开头那一截")
  func loaderOverflow() async throws {
    let end = base + 10_000 * step
    let ex = Exchange(step: step, firstBar: base, lastBar: end)
    await #expect(throws: ReviewKlineLoader.TooLarge.self) {
      _ = try await ReviewKlineLoader.load(symbol: symbol, interval: .m5, start: base, end: end,
                                           pageLimit: 1500, maxBars: 6000, overflow: .fail, now: end * 2,
                                           store: nil) { try await ex.fetch($0, $1, $2) }
    }
    let thumb = try await ReviewKlineLoader.load(symbol: symbol, interval: .m5, start: base, end: end,
                                                 pageLimit: 1500, maxBars: 1500, overflow: .truncate, now: end * 2,
                                                 store: nil) { try await ex.fetch($0, $1, $2) }
    #expect(thumb.count == 1500)
    #expect(thumb.first?.openTime == base)
  }

  @Test("一半在盘上：只去取另一半，拼起来完整")
  func loaderPartialHit() async throws {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ReviewKlineStore(directory: dir)
    let end = base + 400 * step
    let now = end + 10 * step
    await store.record(symbol: symbol, interval: .m5, from: base, to: base + 200 * step,
                       bars: bars(base, count: 200, step: step), now: now)
    let ex = Exchange(step: step, firstBar: base, lastBar: end)
    let out = try await ReviewKlineLoader.load(symbol: symbol, interval: .m5, start: base, end: end,
                                               pageLimit: 1500, maxBars: 6000, overflow: .fail, now: now,
                                               store: store) { try await ex.fetch($0, $1, $2) }
    #expect(out.count == 400)
    #expect(ex.calls.allSatisfy { $0.0 >= base + 200 * step })
  }

  @Test("清缓存与用量把复盘 K 线、复盘本缩略图都算进去")
  func clearCoversReviewCaches() async throws {
    let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
    let paths = Paths(root: root)
    try paths.ensure(paths.reviewKlines); try paths.ensure(paths.tradeImages)
    try Data(repeating: 1, count: 4096).write(to: paths.reviewKlines.appendingPathComponent("a.rkl"))
    try Data(repeating: 1, count: 4096).write(to: paths.tradeImages.appendingPathComponent("b.jpg"))
    let cache = DiskMarketCache(paths: paths)
    let before = await cache.footprint()
    #expect(before.snapshotBytes >= 4096 && before.derivedBytes >= 4096)
    await cache.clear()
    #expect(!FileManager.default.fileExists(atPath: paths.reviewKlines.path))
    #expect(!FileManager.default.fileExists(atPath: paths.tradeImages.path))
  }
}
