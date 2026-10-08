import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

/// 2026-10-08 这一批压测（限速器、推送、模糊、翻页、交叉）挂在同一个串行的父套件下：彼此一个接一个跑，
/// 不和整包里按真实时间缩放（`FastPacer`）的那些用例一起把 CPU 挤满，免得把它们饿到超时。
@Suite("压测 · 交易所框架（串行）", .serialized)
enum StressVenueSerial {}

// 压测（2026-10-08）：交易所通用限速器 `VenueRateLimiter`。
//
// 几百个并发 `acquire` 挂在一把手拨的钟（`ManualPacer`）上：钟只在「每一笔要么放行了、要么睡着了」时才拨，
// 拨到下一个醒点。于是每一笔的放行时刻是确定的虚拟时刻，判据全是计数与窗口和，不看墙钟。

/// 记下每一笔放行的虚拟时刻与权重。
private actor Ledger {
  struct Grant { var id: Int; var atMs: Double; var weight: Double }
  private(set) var grants: [Grant] = []
  private(set) var failures = 0
  private(set) var finished = 0
  func granted(_ id: Int, at ms: Double, weight: Double) { grants.append(Grant(id: id, atMs: ms, weight: weight)); finished += 1 }
  func failed() { failures += 1; finished += 1 }
  func grant(_ id: Int) -> Grant? { grants.first { $0.id == id } }
}

/// 一组并发取号的人 + 拨钟的人。
private struct Rig {
  let pacer = ManualPacer()
  let ledger = Ledger()
  let limiter: VenueRateLimiter
  private let spawned = Counter()

  init(perSecond: Double) { limiter = VenueRateLimiter(perSecond: perSecond, pacer: pacer) }
  init(weightPerMinute: Double) { limiter = VenueRateLimiter(weightPerMinute: weightPerMinute, pacer: pacer) }

  /// 起一笔：放行那一刻按虚拟钟记下来。
  @discardableResult
  func spawn(_ id: Int, weight: Double = 1) -> Task<Void, Never> {
    _ = spawned.bump()
    let limiter = self.limiter, pacer = self.pacer, ledger = self.ledger
    return Task {
      do {
        try await limiter.acquire(weight: weight)
        await ledger.granted(id, at: await pacer.nowMs(), weight: weight)
      } catch {
        await ledger.failed()
      }
    }
  }

  /// 等到每一笔要么结束了、要么睡在钟上。
  func quiesce() async -> Bool {
    await waitUntil(10) {
      let finished = await ledger.finished
      let sleeping = await pacer.sleeping
      return finished + sleeping >= spawned.value
    }
  }

  /// 把钟往前拨 `ms`，途中每个醒点都停一下，让醒来的人按那一刻的钟放行。
  func advance(_ ms: Double) async {
    var left = ms
    while left > 0 {
      #expect(await quiesce())
      let step = min(left, max(0, await pacer.nextWakeIn ?? left))
      await pacer.advance(step)
      left -= step
    }
    #expect(await quiesce())
  }

  /// 一直拨到所有人都结束（`maxMs` 封顶）。
  func runToEnd(maxMs: Double) async {
    var spent = 0.0
    while spent < maxMs {
      #expect(await quiesce())
      if await ledger.finished >= spawned.value { return }
      guard let next = await pacer.nextWakeIn else { return }
      await pacer.advance(next)
      spent += next
    }
  }
}

/// 任意 `windowMs` 长的半开窗口 [t, t + windowMs) 里放行的权重之和的最大值（窗口起点取每一笔的放行时刻就够了）。
private func peakWindow(_ grants: [Ledger.Grant], windowMs: Double) -> Double {
  let sorted = grants.sorted { $0.atMs < $1.atMs }
  var best = 0.0
  var j = 0
  var sum = 0.0
  for i in sorted.indices {
    while j < sorted.count, sorted[j].atMs < sorted[i].atMs + windowMs { sum += sorted[j].weight; j += 1 }
    best = max(best, sum)
    sum -= sorted[i].weight
  }
  return best
}

extension StressVenueSerial {
  @Suite("压测 · 交易所限速器", .timeLimit(.minutes(3)))
  struct StressVenueLimiterTests {

    @Test("按次数：300 个并发 acquire，任意 1 秒最多 8 笔，相邻两笔间隔 ≥ 125ms，全部放行、总耗时 ≈ 299 格")
    func countModeBurst() async throws {
      let rig = Rig(perSecond: 8)
      let n = 300
      for i in 0..<n { rig.spawn(i) }
      await rig.runToEnd(maxMs: 3_600_000)
      let grants = await rig.ledger.grants
      #expect(grants.count == n)
      let times = grants.map(\.atMs).sorted()
      let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
      #expect(gaps.allSatisfy { $0 >= 125 - 1e-6 }, "最小间隔 \(gaps.min() ?? 0)")
      #expect(peakWindow(grants, windowMs: 1000) <= 8)
      #expect(peakWindow(grants.map { var g = $0; g.weight = 1; return g }, windowMs: 60_000) <= 8 * 60)
      // 不比该等的多等：最后一笔恰好在第 299 格放行。
      #expect((times.last ?? 0) - (times.first ?? 0) <= Double(n - 1) * 125 + 1)
      await rig.pacer.drain()
    }

    @Test("按权重：400 个并发、权重 2 / 20 / 104 混着，任意 60 秒放行权重 ≤ 1000，全部放行")
    func weightModeBurst() async throws {
      let rig = Rig(weightPerMinute: 1000)
      let weights: [Double] = [2, 20, 104, 20, 2, 25]
      let n = 400
      for i in 0..<n { rig.spawn(i, weight: weights[i % weights.count]) }
      await rig.runToEnd(maxMs: 6 * 3_600_000)
      let grants = await rig.ledger.grants
      #expect(grants.count == n)
      let peak = peakWindow(grants, windowMs: 60_000)
      #expect(peak <= 1000, "60 秒窗口峰值 \(peak)")
      // 总权重 / 每分钟预算 ≈ 至少要这么多分钟；不应慢于两倍。
      let total = grants.reduce(0) { $0 + $1.weight }
      let span = (grants.map(\.atMs).max() ?? 0) - (grants.map(\.atMs).min() ?? 0)
      #expect(span <= (total / 1000 + 2) * 60_000 * 2, "跨度 \(span)ms，总权重 \(total)")
      await rig.pacer.drain()
    }

    /// 原来：轻的一笔只要挤得进剩下的预算就放，重的那笔要等「够它一整笔」的空位——
    /// 可每空出 20 就被排在后面的轻请求抢走，重的那笔永远等不到（Hyperliquid 上一页 5000 根的 K 线 ≈ 104 权重，
    /// 被 `allMids` / `meta` 这种轻查询饿死）。
    @Test("按权重：轻请求川流不息（每秒一笔 20、预算一直满着）时，中途来的一笔 500 不被饿死")
    func heavyIsNotStarvedByLightStream() async throws {
      let rig = Rig(weightPerMinute: 1000)
      for second in 0..<400 {
        rig.spawn(second, weight: 20)
        if second == 90 { rig.spawn(10_000, weight: 500) }
        await rig.advance(1000)
      }
      let grants = await rig.ledger.grants
      #expect(peakWindow(grants, windowMs: 60_000) <= 1000)
      let heavyGrant = try #require(await rig.ledger.grant(10_000), "那一笔 500 一直没放行")
      // 它来的时候预算是满的：至多再过一个窗口（60 秒）加一点排队就该轮到它。
      let arrived = 1_000_000 + 90_000.0
      #expect(heavyGrant.atMs - arrived <= 125_000, "等了 \(heavyGrant.atMs - arrived)ms")
      await rig.pacer.drain()
    }

    @Test("按权重：比整个预算还重的一笔在川流不息的轻请求里也有尽头（空窗口就放，之后的轻请求让它）")
    func oversizedIsNotStarved() async throws {
      let rig = Rig(weightPerMinute: 1000)
      for second in 0..<300 {
        rig.spawn(second, weight: 20)
        if second == 30 { rig.spawn(10_000, weight: 1500) }
        await rig.advance(1000)
      }
      let big = try #require(await rig.ledger.grant(10_000), "那一笔 1500 一直没放行")
      #expect(big.atMs - (1_000_000 + 30_000) <= 125_000, "等了 \(big.atMs - 1_030_000)ms")
      // 放它的时候窗口是空的；它之后 60 秒里谁也不许再放（它一笔就超了预算）。
      let grants = await rig.ledger.grants
      #expect(!grants.contains { $0.id != 10_000 && $0.atMs > big.atMs - 60_000 && $0.atMs < big.atMs })
      #expect(!grants.contains { $0.id != 10_000 && $0.atMs >= big.atMs && $0.atMs < big.atMs + 60_000 })
      await rig.pacer.drain()
    }

    @Test("中途 429 罚停：罚停期间没有一笔抢跑；罚完照常按间隔放")
    func penaltyMidBurst() async throws {
      let rig = Rig(perSecond: 10)
      for i in 0..<100 { rig.spawn(i) }
      await rig.advance(1_000)
      let before = await rig.ledger.grants.count
      #expect(before >= 10 && before <= 11)
      let penalizedAt = await rig.pacer.nowMs()
      await rig.limiter.penalize(seconds: 3)
      await rig.runToEnd(maxMs: 3_600_000)
      let grants = await rig.ledger.grants
      #expect(grants.count == 100)
      #expect(!grants.contains { $0.atMs > penalizedAt && $0.atMs < penalizedAt + 3000 },
              "罚停期间放行了 \(grants.filter { $0.atMs > penalizedAt && $0.atMs < penalizedAt + 3000 }.count) 笔")
      let after = grants.map(\.atMs).filter { $0 >= penalizedAt + 3000 }.sorted()
      #expect(zip(after.dropFirst(), after).allSatisfy { $0 - $1 >= 100 - 1e-6 })
      await rig.pacer.drain()
    }

    @Test("按权重：中途罚停同样谁都不抢跑")
    func penaltyMidWeightBurst() async throws {
      let rig = Rig(weightPerMinute: 1000)
      for i in 0..<200 { rig.spawn(i, weight: 20) }
      await rig.advance(30_000)
      let penalizedAt = await rig.pacer.nowMs()
      await rig.limiter.penalize(seconds: 5)
      await rig.runToEnd(maxMs: 3_600_000)
      let grants = await rig.ledger.grants
      #expect(grants.count == 200)
      #expect(!grants.contains { $0.atMs > penalizedAt && $0.atMs < penalizedAt + 5000 })
      #expect(peakWindow(grants, windowMs: 60_000) <= 1000)
      await rig.pacer.drain()
    }

    @Test("撤掉 50 笔睡着的：不留下占位，下一笔按「上一笔真出站 + 一格」放（按次数）")
    func cancelledCountWaitersLeaveNothing() async throws {
      let rig = Rig(perSecond: 10)
      rig.spawn(0)
      #expect(await rig.quiesce())
      let doomed = (1...50).map { rig.spawn($0) }
      #expect(await rig.quiesce())
      doomed.forEach { $0.cancel() }
      for t in doomed { await t.value }
      #expect(await rig.ledger.failures == 50)
      let first = try #require(await rig.ledger.grant(0))
      await rig.advance(100)
      rig.spawn(99)
      await rig.advance(1)
      let next = try #require(await rig.ledger.grant(99), "撤掉的 50 笔把下一笔挡住了")
      #expect(next.atMs - first.atMs <= 101)
      await rig.pacer.drain()
    }

    @Test("撤掉排在前面的重请求：后面的不替它们等（按权重）")
    func cancelledWeightWaitersLeaveNothing() async throws {
      let rig = Rig(weightPerMinute: 100)
      rig.spawn(0, weight: 100)
      #expect(await rig.quiesce())
      let doomed = (1...30).map { rig.spawn($0, weight: 90) }
      #expect(await rig.quiesce())
      let light = rig.spawn(500, weight: 10)
      #expect(await rig.quiesce())
      doomed.forEach { $0.cancel() }
      for t in doomed { await t.value }
      // 窗口滑过去（60 秒）那一刻，轻的那笔就该放行，不替撤掉的 30 笔排队。
      await rig.advance(61_000)
      await light.value
      let g = try #require(await rig.ledger.grant(500))
      #expect(g.atMs <= 1_000_000 + 61_000)
      await rig.pacer.drain()
    }

    @Test("按权重：一笔比整个预算还重，窗口空着当场放；窗口不空等它清空就放，不永远挂着")
    func oversizedNeverHangs() async throws {
      let rig = Rig(weightPerMinute: 100)
      rig.spawn(0, weight: 5000)
      #expect(await rig.quiesce())
      #expect(await rig.ledger.grant(0)?.atMs == 1_000_000)
      rig.spawn(1, weight: 5000)
      await rig.runToEnd(maxMs: 120_000)
      let second = try #require(await rig.ledger.grant(1), "第二笔超重请求挂死了")
      #expect(second.atMs == 1_000_000 + 60_000)
      await rig.pacer.drain()
    }
  }
}
