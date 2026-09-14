import Foundation
import Testing

@testable import KanpanDiagnostics

// `FrameProbe` 那半边（CADisplayLink + runloop 观察者）只能在 iOS 上跑，
// 但它吐出来的每一个 `FrameSample` 都要经过这里的算术才变成结论。
// 所以这套件造假样本，把 P9.2 / P9.3 的判定逻辑在 mac 上全测死——
// 真机取证时要是数字看着不对，先怀疑采集，不用再怀疑算术。

private let hz120 = 1.0 / 120.0
private let hz60 = 1.0 / 60.0

/// 造一串帧。
/// - `interval`: 每一帧**系统认定**的帧间隔（秒），也就是 target − timestamp。
/// - `work`: 每帧主线程忙时（ms）。给一个就全程一样，给数组就逐帧取。
/// - `stalls`: `下标 → 这一帧之前额外卡了几秒`。
private func frames(
  count: Int,
  interval: Double = hz120,
  work: [Double] = [1.0],
  latencyMs: Double = 0.2,
  stalls: [Int: Double] = [:]
) -> [FrameSample] {
  var out: [FrameSample] = []
  var t = 1000.0
  for i in 0..<count {
    if i > 0 { t += interval + (stalls[i] ?? 0) }
    let w = work[i % work.count] / 1000
    let start = t + latencyMs / 1000
    out.append(
      FrameSample(
        timestamp: t, targetTimestamp: t + interval,
        callbackStart: start, callbackEnd: start + w))
  }
  return out
}

private func stats(_ samples: [FrameSample]) -> FrameStats {
  var s = FrameStats()
  for x in samples { s.add(x) }
  return s
}

@Suite("分位数")
struct FrameQuantilesTests {

  @Test("线性插值口径，和 numpy 默认一致")
  func interpolates() throws {
    let q = try #require(FrameQuantiles.of([1, 2, 3, 4]))
    #expect(q.count == 4)
    #expect(q.p50 == 2.5)  // pos = 0.5×3 = 1.5 → (2+3)/2
    #expect(q.max == 4)
    #expect(q.mean == 2.5)
  }

  @Test("只有一个样本时所有分位数都是它")
  func singleSample() throws {
    let q = try #require(FrameQuantiles.of([7]))
    #expect(q.p50 == 7 && q.p90 == 7 && q.p99 == 7 && q.max == 7)
  }

  @Test("空数组返回 nil")
  func empty() {
    #expect(FrameQuantiles.of([]) == nil)
  }
}

@Suite("帧统计")
struct FrameStatsTests {

  @Test("满帧 120Hz、每帧 1ms：hitch 为 0，三条预算全过")
  func perfect120() throws {
    let r = stats(frames(count: 240)).report(label: "拖动", device: "测试")
    #expect(r.frameCount == 240)
    #expect(r.hitchMs == 0)
    #expect(r.hitchRatio == 0)
    #expect(r.droppedFrames == 0)
    #expect(r.worstHitchMs == 0)

    let hz = try #require(r.measuredHz)
    #expect(abs(hz - 120) < 0.5)

    let work = try #require(r.work)
    #expect(abs(work.p50 - 1) < 1e-6)
    #expect(abs(work.p99 - 1) < 1e-6)

    #expect(r.verdict.hitchRatioUnder1Percent == true)
    #expect(r.verdict.frameP99Under3ms == true)
    #expect(r.verdict.frameMedianUnder3ms == true)
    #expect(r.verdict.allPassed == true)
  }

  @Test("±20% 的帧间隔抖动不算 hitch")
  func jitterIsNotHitch() {
    // CADisplayLink 的 timestamp 本身就抖。按「超一点点就算掉帧」去判，
    // 会得出「120Hz 机器占比 4%」这种和 Instruments 差一个数量级的假数。
    // 阈值是 1.5 倍，所以 1.2 倍必须是 0。
    let jitter = frames(count: 200, stalls: Dictionary(
      uniqueKeysWithValues: (1..<200).map { ($0, hz120 * 0.2) }))
    let r = stats(jitter).report(label: "抖动")
    #expect(r.hitchMs == 0)
    #expect(r.droppedFrames == 0)
  }

  @Test("卡一次 3 帧：hitch 时长、丢帧数、占比都对得上")
  func oneBigStall() throws {
    // 240 帧 @120Hz ≈ 2 秒，中间卡掉 3 帧（25ms）。
    let r = stats(frames(count: 240, stalls: [120: hz120 * 3])).report(label: "卡一次")

    #expect(abs(r.hitchMs - 25) < 0.1)
    #expect(r.droppedFrames == 3)
    #expect(abs(r.worstHitchMs - 25) < 0.1)
    // 总时长 = 239 个正常间隔 + 3 个额外间隔 = 242 × 8.333ms ≈ 2016.7ms
    #expect(abs(r.durationMs - 2016.7) < 1)
    // 25 / 2016.7 ≈ 1.24% > 1% → P9.2 不过
    #expect(r.hitchRatio > 0.01)
    #expect(r.verdict.hitchRatioUnder1Percent == false)
    #expect(r.verdict.allPassed == false)
  }

  @Test("占比达标但有一次长卡顿，worstHitch 要把它顶出来")
  func worstHitchIsReportedSeparately() throws {
    // 30 秒里只卡一次 120ms：占比 0.4%，P9.2 判过；但用户是能感觉到这一下的。
    // 所以 `worstHitchMs` 单独记一笔，证据表上要写。
    let r = stats(frames(count: 3600, stalls: [1800: 0.12])).report(label: "长卡一次")
    #expect(r.hitchRatio < 0.01)
    #expect(r.verdict.hitchRatioUnder1Percent == true)
    #expect(r.worstHitchMs > 100)
  }

  @Test("采集中途从 120Hz 降到 60Hz，不能把降频后每一帧都算成掉帧")
  func refreshRateChangeMidRun() {
    // 这是用「全局中位数当预期间隔」时必然踩的坑：低电量模式一开，
    // 后半段每帧 16.7ms 对上 8.3ms 的预期，占比直接冲到 50%，
    // 报告会说「掉帧一半」，而其实一帧没掉。
    var samples = frames(count: 120, interval: hz120)
    var t = samples[samples.count - 1].timestamp
    for _ in 0..<120 {
      t += hz60
      samples.append(
        FrameSample(
          timestamp: t, targetTimestamp: t + hz60,
          callbackStart: t + 0.0002, callbackEnd: t + 0.0012))
    }
    let r = stats(samples).report(label: "降频")
    #expect(r.hitchMs == 0)
    #expect(r.droppedFrames == 0)
    #expect(r.verdict.hitchRatioUnder1Percent == true)
  }

  @Test("每帧 4ms：P9.3 的 P99 < 3ms 判不过")
  func slowFramesFailBudget() throws {
    let r = stats(frames(count: 200, work: [4.0])).report(label: "画太慢")
    let work = try #require(r.work)
    #expect(abs(work.p50 - 4) < 1e-6)
    #expect(r.verdict.frameP99Under3ms == false)
    #expect(r.verdict.frameMedianUnder3ms == false)
    #expect(r.verdict.allPassed == false)
  }

  @Test("中位数过但长尾超：P99 判不过，中位数判过")
  func longTailOnly() {
    // 100 帧里 95 帧 1ms、5 帧 20ms。中位数 1ms 很好看，P99 会把慢的那几帧顶出来。
    // （只放 1 帧慢的不行：P99 是线性插值，100 个样本里第 99 分位落在
    // 下标 98.01，会被旁边的 1ms 插值拉回 1.19ms——这本身就是正确行为。）
    var work = Array(repeating: 1.0, count: 95)
    work.append(contentsOf: Array(repeating: 20.0, count: 5))
    let r = stats(frames(count: 100, work: work)).report(label: "长尾")
    #expect(r.verdict.frameMedianUnder3ms == true)
    #expect(r.verdict.frameP99Under3ms == false)
    #expect(r.verdict.allPassed == false)
  }

  @Test("排队延迟和绘制耗时分开记")
  func latencySeparateFromWork() throws {
    // 主线程被别人占着（网络回调、解码）导致的晚点，不该算在「绘制耗时」头上，
    // 否则优化方向会全错。
    let r = stats(frames(count: 100, work: [1.0], latencyMs: 5.0)).report(label: "被占")
    #expect(abs(try #require(r.work).p50 - 1) < 1e-6)
    #expect(abs(try #require(r.latency).p50 - 5) < 1e-6)
  }

  @Test("没采到帧 / 只采到一帧：不崩，也不谎报通过")
  func degenerateInputs() {
    var empty = FrameStats()
    #expect(empty.isEmpty)
    let r0 = empty.report(label: "空")
    #expect(r0.frameCount == 0)
    #expect(r0.durationMs == 0)
    #expect(r0.work == nil)
    #expect(r0.verdict.allPassed == nil)  // 「没测」≠「过了」

    let r1 = stats(frames(count: 1)).report(label: "一帧")
    #expect(r1.frameCount == 1)
    #expect(r1.interval == nil)
    #expect(r1.verdict.hitchRatioUnder1Percent == nil)
    #expect(r1.verdict.allPassed == nil)

    empty.reset()
    #expect(empty.isEmpty)
  }

  @Test("报告能 Codable 往返，allPassed 进得了 JSON")
  func codableRoundTrip() throws {
    let r = stats(frames(count: 200)).report(label: "拖动", device: "iPhone17,1")
    let data = try DiagnosticsStore.encoder.encode(r)
    #expect(String(decoding: data, as: UTF8.self).contains("allPassed"))
    let back = try DiagnosticsStore.decoder.decode(FrameReport.self, from: data)
    #expect(back == r)
  }
}

@Suite("帧报告落盘")
struct FrameReportStoreTests {

  private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("kanpan-frames-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test("存进去读出来是同一份")
  func saveAndRead() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = FrameReportStore(directory: dir)
    let r = stats(frames(count: 200)).report(label: "拖动")
    #expect(store.save(r) != nil)
    #expect(store.reports() == [r])
  }

  @Test("标签里的空格和斜杠不会变成路径")
  func sanitizesLabel() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = FrameReportStore(directory: dir)
    let url = try #require(
      store.save(stats(frames(count: 10)).report(label: "拖动 / 60s")))
    #expect(url.deletingLastPathComponent().path == dir.path)
    #expect(!url.lastPathComponent.contains("/"))
    #expect(store.reports().count == 1)
  }

  @Test("超上限删最旧的")
  func prunes() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = TestClock()
    let store = FrameReportStore(directory: dir, maxReports: 2, clock: clock.now)
    for i in 0..<5 {
      store.save(stats(frames(count: 10)).report(label: "第\(i)段"))
      clock.advance(60)
    }
    #expect(store.reports().map(\.label) == ["第3段", "第4段"])
  }

  @Test("整批导出：有一段没判定，整批就是 nil")
  func bundleVerdict() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = FrameReportStore(directory: dir)

    #expect(store.bundle().allPassed == nil)  // 一份都没有

    store.save(stats(frames(count: 200)).report(label: "好的一段"))
    #expect(store.bundle().allPassed == true)

    store.save(stats(frames(count: 1)).report(label: "没采到"))
    #expect(store.bundle().allPassed == nil)

    store.save(stats(frames(count: 200, work: [9.0])).report(label: "慢的一段"))
    #expect(store.bundle().allPassed == nil)

    let out = dir.appendingPathComponent("export/M9-frames.json")
    try store.writeExport(to: out)
    let back = try DiagnosticsStore.decoder.decode(
      FrameReportBundle.self, from: Data(contentsOf: out))
    #expect(back.reports.count == 3)

    store.removeAll()
    #expect(store.reports().isEmpty)
  }
}
