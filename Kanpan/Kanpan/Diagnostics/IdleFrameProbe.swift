// 「静置看盘」那一段的帧与 body 采集（审查 21 的验收口径）。只在 DEBUG 包里有。
#if DEBUG

  import Foundation

  /// 启动环境带 `KANPAN_FRAME_PROBE_IDLE=<秒>` 时，等行情第一次推到 live，再静置 2 秒，
  /// 然后让 `FrameProbe` 采那么多秒——手不碰屏幕，这一段里的重算全是行情推送带来的。
  ///
  /// 报告和手势那条同一个格式、同一个目录（`Diagnostics/frames/`），标签是「静置行情」。
  /// 报告里的 `bodies` 就是这一分钟里 `MainScreen`、图表宿主各被求值了几次。
  @MainActor
  enum IdleFrameProbe {
    static let label = "静置行情"

    static var seconds: Double? {
      ProcessInfo.processInfo.environment["KANPAN_FRAME_PROBE_IDLE"].flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
    }

    static func run(live: @escaping @MainActor () -> Bool) async {
      guard let seconds else { return }
      while !live() {
        try? await Task.sleep(for: .milliseconds(200))
        if Task.isCancelled { return }
      }
      try? await Task.sleep(for: .seconds(2))
      if Task.isCancelled { return }
      FrameProbe.shared.record(label: label, seconds: seconds)
    }
  }
#endif
