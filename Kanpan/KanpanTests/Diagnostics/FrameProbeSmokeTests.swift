import Foundation
import Testing

@testable import Kanpan

// `FrameProbe` 的算术在 FrameStatsTests 里已经测死了，这里测的是**采集本身**：
// CADisplayLink 真的回调了吗？两个 CFRunLoopObserver 真的夹住了一帧吗？
// 这两件事只能跑在 iOS 模拟器上（`make diag-ios-test`；diag-test 里也单独跑一趟，
// 不和几百条 @MainActor 用例挤在一起，否则主线程被占满、一秒钟量不出十帧）。
//
// 注意模拟器上的 hitch 数字**没有取证价值**：它量的是 mac 的合成节奏，
// 而且测试宿主没有真实的绘制负载。这里只验「管子是通的」。

@Suite("帧探针（仅 iOS 模拟器）", .serialized)
struct FrameProbeSmokeTests {

  @Test("跑一秒钟，能采到帧、能出报告、能落盘")
  @MainActor
  func collectsRealFrames() async throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("kanpan-probe-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let probe = FrameProbe(store: FrameReportStore(directory: dir))
    probe.start(label: "冒烟")
    #expect(probe.isRunning)
    // await 让出主线程，主 runloop 才转得起来，DisplayLink 才有机会回调。
    try await Task.sleep(for: .seconds(1))
    let report = try #require(probe.stop())

    #expect(!probe.isRunning)
    #expect(report.label == "冒烟")
    // 1 秒钟至少也该有十几帧。一帧都没有 = 观察者或 DisplayLink 没挂上。
    #expect(report.frameCount > 10)
    #expect(report.durationMs > 500)
    let hz = try #require(report.measuredHz)
    #expect(hz > 20)
    #expect(report.work != nil)

    // 落盘那一份必须和返回的这一份一模一样。
    #expect(probe.reportStore.reports() == [report])

    // 把这次实测的数打出来。取证时直接抄这一行，不用再翻沙盒。
    print(
      """
      [FrameProbe] \(FrameProbe.deviceTag()) \
      帧数=\(report.frameCount) 时长=\(String(format: "%.0f", report.durationMs))ms \
      实测Hz=\(report.measuredHz.map { String(format: "%.1f", $0) } ?? "—") \
      hitch占比=\(String(format: "%.3f%%", report.hitchRatio * 100)) \
      最长hitch=\(String(format: "%.2f", report.worstHitchMs))ms \
      绘制p50=\(report.work.map { String(format: "%.3f", $0.p50) } ?? "—")ms \
      绘制p99=\(report.work.map { String(format: "%.3f", $0.p99) } ?? "—")ms
      """)
  }

  @Test("record(label:seconds:) 到点自动停")
  @MainActor
  func autoStops() async throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("kanpan-probe-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let probe = FrameProbe(store: FrameReportStore(directory: dir))
    probe.record(label: "定时", seconds: 0.5)
    #expect(probe.isRunning)
    try await Task.sleep(for: .seconds(1.2))
    #expect(!probe.isRunning)
    #expect(probe.reportStore.reports().first?.label == "定时")
  }

  @Test("重复 start / 没 start 就 stop 都不炸")
  @MainActor
  func idempotent() async throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("kanpan-probe-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let probe = FrameProbe(store: FrameReportStore(directory: dir))
    #expect(probe.stop() == nil)
    probe.start(label: "a")
    probe.start(label: "b")  // 第二次应该被忽略，不能换掉标签
    #expect(probe.label == "a")
    try await Task.sleep(for: .milliseconds(300))
    _ = probe.stop()
    #expect(probe.stop() == nil)
  }

  @Test("设备标记里带得出机型和刷新率")
  @MainActor
  func deviceTag() {
    let tag = FrameProbe.deviceTag()
    #expect(tag.contains("iOS"))
    #expect(tag.contains("Hz"))
  }
}
