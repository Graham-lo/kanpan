import Foundation

// ============================================================ 帧耗时统计（纯算术）
//
// 任务书 §13 M9 的 P9.2 / P9.3 和 §13 M4 的 G13 都要 Instruments：
//   P9.2 hitch 时长占比 < 1%（Animation Hitches 导出 csv）
//   P9.3 一帧绘制 P99 < 3ms；一屏 2000 根时 < 6ms（自埋计时 + Time Profiler）
//
// P9.3 那行写着「**自埋计时**」——就是这个文件。Instruments 要人插着线、点按钮、
// 手工导出，跑不进 CI，也没法在改一行代码之后立刻回归。进程内自测拿不到
// Instruments 那么细的归因，但它能给一条**可复现、可比对、能进证据文件**的数。
//
// 两者的关系：Instruments 是裁判，这个是每天的体温计。M9.md 里两份数都放，
// 打架时以 Instruments 为准。
//
// 这一层**只有算术，没有 CADisplayLink**：喂进来的是一串 `FrameSample`，
// 吐出来的是 `FrameReport`。所以在 mac 上 `swift test` 里造几十个假样本就能把
// 分位数、hitch 比例、丢帧数全测死，不需要开模拟器。真正接 DisplayLink 的
// 在 `FrameProbe.swift`。

/// 一帧的现场。四个时刻全部取自同一条时间轴（`CACurrentMediaTime()` / `CADisplayLink`）。
struct FrameSample: Sendable, Equatable, Codable {
  /// `CADisplayLink.timestamp`：这一帧**上一次**显示的时刻，系统给的。
  var timestamp: Double
  /// `CADisplayLink.targetTimestamp`：这一帧**将要**显示的时刻。
  /// `target - timestamp` 就是系统当前认定的帧间隔（120Hz ≈ 8.33ms，60Hz ≈ 16.67ms）。
  var targetTimestamp: Double
  /// 回调刚进来时的 `CACurrentMediaTime()`。
  var callbackStart: Double
  /// 这一帧的活干完之后的 `CACurrentMediaTime()`。
  var callbackEnd: Double

  /// 主线程在这一帧上花的时间（ms）。P9.3 的「一帧绘制」量的就是它。
  var workMs: Double { (callbackEnd - callbackStart) * 1000 }

  /// 系统说这一帧该显示的时刻，到主线程真的开始干活的时刻，差多少（ms）。
  /// 这一段是「runloop 被别人占着」的时间，不是我们自己画的时间——
  /// 它大说明主线程上有别的东西（网络回调、布局、解码）在抢，
  /// 和 `workMs` 分开记才知道该去优化谁。
  var latencyMs: Double { (callbackStart - timestamp) * 1000 }

  /// 系统当前的帧间隔（ms）。
  var expectedIntervalMs: Double { (targetTimestamp - timestamp) * 1000 }
}

/// 一组分位数。ms。
struct FrameQuantiles: Sendable, Equatable, Codable {
  var count: Int
  var p50: Double
  var p90: Double
  var p99: Double
  var max: Double
  var mean: Double

  /// 线性插值分位数（和 numpy 默认口径一致）。样本已排序。
  static func of(_ sorted: [Double]) -> FrameQuantiles? {
    guard !sorted.isEmpty else { return nil }
    func q(_ p: Double) -> Double {
      if sorted.count == 1 { return sorted[0] }
      let pos = p * Double(sorted.count - 1)
      let lo = Int(pos.rounded(.down))
      let hi = Swift.min(lo + 1, sorted.count - 1)
      let f = pos - Double(lo)
      return sorted[lo] * (1 - f) + sorted[hi] * f
    }
    return FrameQuantiles(
      count: sorted.count,
      p50: q(0.5), p90: q(0.9), p99: q(0.99),
      max: sorted[sorted.count - 1],
      mean: sorted.reduce(0, +) / Double(sorted.count))
  }
}

/// 一次采集的结论。直接 encode 成 JSON 落盘，`Tools/frame-report.sh` 读它。
struct FrameReport: Sendable, Equatable, Codable {
  var schema: Int = 1
  /// 采集标签，写清楚当时在干嘛：`"拖动"` / `"捏合"` / `"甩"` / `"静止"`。
  var label: String
  /// 机型 + 系统，人看证据时要知道是哪台。
  var device: String?
  /// 采到多少帧、跨了多少秒。
  var frameCount: Int
  var durationMs: Double

  /// 实测刷新率（Hz）。取帧间隔中位数的倒数，不是看机型标称——
  /// 低电量模式、系统降频、后台都会把它压到 60 甚至 30，
  /// 拿标称值算 hitch 会得出「120Hz 机器一直在丢帧」的假结论。
  var measuredHz: Double?
  /// 系统给的目标帧间隔中位数（ms）。
  var expectedIntervalMs: Double?

  /// P9.3：主线程每帧干活耗时。
  var work: FrameQuantiles?
  /// 排队延迟（见 `FrameSample.latencyMs`）。
  var latency: FrameQuantiles?
  /// 实际帧间隔。
  var interval: FrameQuantiles?

  /// P9.2：hitch 总时长（ms）与占比。
  var hitchMs: Double
  var hitchRatio: Double
  /// 掉了多少帧（按「这一帧比预期晚了几个帧间隔」累加）。
  var droppedFrames: Int
  /// 最长的一次 hitch（ms）。占比达标但有一次 300ms 的卡顿，用户照样骂人。
  var worstHitchMs: Double

  /// 对着任务书的预算逐条判。nil = 这项没数据，**不算过**。
  var verdict: Verdict

  struct Verdict: Sendable, Equatable, Codable {
    /// P9.2：hitch 占比 < 1%。
    var hitchRatioUnder1Percent: Bool?
    /// P9.3：一帧绘制 P99 < 3ms。
    var frameP99Under3ms: Bool?
    /// §11 性能预算：一帧绘制 < 3ms（这里看的是中位数，更宽松的一条）。
    var frameMedianUnder3ms: Bool?
    /// 三条都有数且都过，才是 true。有一条没数据就是 nil（**「没测」不等于「过了」**）。
    /// 存成字段而不是计算属性，是为了它能进 JSON——`Tools/frame-report.sh` 直接读这一项。
    var allPassed: Bool?

    /// 三条判完后回填 `allPassed`。
    mutating func seal() {
      let flags = [hitchRatioUnder1Percent, frameP99Under3ms, frameMedianUnder3ms]
      allPassed = flags.contains(where: { $0 == nil }) ? nil : flags.allSatisfy { $0 == true }
    }
  }
}

// ---------------------------------------------------------------- 统计器

/// 攒样本 + 出报告。不是线程安全的；`FrameProbe` 只在主线程用它。
struct FrameStats: Sendable {

  /// hitch 的判定阈值：实际帧间隔超过预期的多少倍才算掉帧。
  ///
  /// 为什么是 1.5 而不是 1.0：`CADisplayLink` 的 `timestamp` 本身有抖动
  /// （120Hz 下 ±0.3ms 很常见），按 1.0 判会把每一帧的抖动都记成 hitch，
  /// 得出「占比 4%」这种和 Instruments 差一个数量级的假数。1.5 倍 = 真的少画了
  /// 至少半帧，和 Animation Hitches 报的量级能对上（实测见 docs/acceptance/M9.md）。
  static let hitchThreshold = 1.5

  private(set) var samples: [FrameSample] = []

  mutating func add(_ s: FrameSample) { samples.append(s) }
  mutating func reset() { samples.removeAll(keepingCapacity: true) }

  var isEmpty: Bool { samples.isEmpty }

  func report(label: String, device: String? = nil) -> FrameReport {
    // 第一帧没有前一帧，算不出间隔，所以间隔序列比样本数少 1。
    var intervals: [Double] = []
    intervals.reserveCapacity(max(0, samples.count - 1))
    for i in 1..<max(samples.count, 1) {
      intervals.append((samples[i].timestamp - samples[i - 1].timestamp) * 1000)
    }

    let expected = median(samples.map(\.expectedIntervalMs))
    var hitchTotal = 0.0
    var worst = 0.0
    var dropped = 0

    // hitch 时长的口径抄 Apple：这一帧比「本该显示的时刻」晚了多久，就记多久。
    // 用每一帧**自己的** expectedInterval，不用全局中位数——采集中途系统降频
    // （120→60）时，全局中位数会把降频后的每一帧都算成掉帧。
    for i in 1..<max(samples.count, 1) {
      let exp = samples[i].expectedIntervalMs
      guard exp > 0 else { continue }
      let actual = intervals[i - 1]
      if actual > exp * Self.hitchThreshold {
        let over = actual - exp
        hitchTotal += over
        worst = Swift.max(worst, over)
        dropped += Int((actual / exp).rounded(.down)) - 1
      }
    }

    let duration = samples.count >= 2
      ? (samples[samples.count - 1].timestamp - samples[0].timestamp) * 1000 : 0
    let ratio = duration > 0 ? hitchTotal / duration : 0

    let work = FrameQuantiles.of(samples.map(\.workMs).sorted())
    let latency = FrameQuantiles.of(samples.map(\.latencyMs).sorted())
    let intervalQ = FrameQuantiles.of(intervals.sorted())

    var verdict = FrameReport.Verdict()
    if duration > 0 { verdict.hitchRatioUnder1Percent = ratio < 0.01 }
    if let work {
      verdict.frameP99Under3ms = work.p99 < 3
      verdict.frameMedianUnder3ms = work.p50 < 3
    }
    verdict.seal()

    return FrameReport(
      label: label,
      device: device,
      frameCount: samples.count,
      durationMs: duration,
      measuredHz: (median(intervals)).map { $0 > 0 ? 1000 / $0 : 0 },
      expectedIntervalMs: expected,
      work: work,
      latency: latency,
      interval: intervalQ,
      hitchMs: hitchTotal,
      hitchRatio: ratio,
      droppedFrames: dropped,
      worstHitchMs: worst,
      verdict: verdict)
  }

  private func median(_ xs: [Double]) -> Double? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted()
    let m = s.count / 2
    return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
  }
}
