#if DEBUG

  import Foundation
  import QuartzCore

  // ============================================================ 收到行情事件 → 画进图层
  //
  // M5 A5.2 要的数：「接收事件到绘制的时间，P99 < 16 毫秒」。只在 DEBUG 包里、
  // 且启动环境带 `KANPAN_EVENT_DRAW_PROBE=1` 时才采，平时一行不跑。
  //
  // 一个样本三段，全在主线程上记：
  //   1. `received`：行情泵从 feed 的事件流里拿到这一帧的时刻（离开 feed actor、还没跳到主线程
  //      之前记下，跳主线程排队的那段也算在里面），由 `MarketModel.apply` 把末根事件真正并进
  //      序列之后交进来。
  //   2. `adopted`：图表视图收下了含这一帧的新状态。这一次没置脏位（末根没变）就不会重画，
  //      这些事件记作「无需重画」，不当成延迟样本。
  //   3. `rendered`：蜡烛层或最新价层真的画完一次。收下过的事件全部结算：样本 = 此刻 − 收到。
  //
  // 量不到的：WebSocket 字节进 feed actor 之前的解码排队，以及 CA 提交到渲染服务、上屏那一段
  // （那是另一个进程，要看只能 Instruments）。
  //
  // 每 10 秒往控制台打一行汇总（`simctl launch --console-pty` 能看到），同时把全部样本写到
  // `tmp/event-draw.json`，取证时用 `simctl get_app_container … data` 捞。
  @MainActor
  final class EventDrawProbe {
    static let shared = EventDrawProbe()
    static let enabled = ProcessInfo.processInfo.environment["KANPAN_EVENT_DRAW_PROBE"] == "1"

    private var pending: [CFTimeInterval] = []
    private var adopted: [CFTimeInterval] = []
    private var samples: [Double] = []
    private var skipped = 0
    private var lastReport = CACurrentMediaTime()

    func received(at t0: CFTimeInterval) {
      guard Self.enabled else { return }
      pending.append(t0)
    }

    func adopted(dirty: Bool) {
      guard Self.enabled, !pending.isEmpty else { return }
      if dirty { adopted += pending } else { skipped += pending.count }
      pending.removeAll(keepingCapacity: true)
    }

    func rendered() {
      guard Self.enabled else { return }
      let now = CACurrentMediaTime()
      if !adopted.isEmpty {
        for t in adopted { samples.append((now - t) * 1000) }
        adopted.removeAll(keepingCapacity: true)
      }
      if now - lastReport >= 10 { report(now) }
    }

    private func report(_ now: CFTimeInterval) {
      lastReport = now
      guard let q = FrameQuantiles.of(samples.sorted()) else { return }
      let line = String(
        format: "事件到画完 样本%d 无需重画%d p50=%.2fms p90=%.2fms p99=%.2fms max=%.2fms",
        q.count, skipped, q.p50, q.p90, q.p99, q.max)
      print(line)
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("event-draw.json")
      let body: [String: Any] = [
        "samplesMs": samples, "skippedNoRedraw": skipped,
        "p50": q.p50, "p90": q.p90, "p99": q.p99, "max": q.max, "mean": q.mean,
      ]
      if let data = try? JSONSerialization.data(withJSONObject: body) { try? data.write(to: url) }
    }
  }

#endif
