import Foundation
import Observation
import UIKit

/// 主线程心跳（只在 `KANPAN_LOG=1` 时跑）。
///
/// 「行情不跳」有两种完全不同的原因：帧没到，或者帧到了而主线程正忙着——后者
/// 整屏都冻着，图和自选列表一起停，跟网络没有半点关系。这段每秒醒一次，报的是
/// 实际间隔比一秒多出多少：稳定在几十毫秒内说明主线程是空的，动不动几百上千
/// 毫秒就是被什么活儿堵住了。
@MainActor
enum MainThreadHeartbeat {
  private static var task: Task<Void, Never>?

  /// **只在 DEBUG 构建里起得来**（审查 C-02）：正式包不该被一个环境变量拉起一条
  /// 每秒醒一次的后台任务。
  static func startIfRequested() {
    #if DEBUG
    MainThreadHangLog.startIfRequested()
    guard ProcessInfo.processInfo.environment["KANPAN_LOG"] == "1", task == nil else { return }
    task = Task { @MainActor in
      var worst = 0
      var report = Date()
      while !Task.isCancelled {
        let before = Date()
        try? await Task.sleep(for: .seconds(1))
        let late = Int(Date().timeIntervalSince(before) * 1000) - 1000
        worst = max(worst, late)
        let now = Date()
        if now.timeIntervalSince(report) >= 5 {
          print("主线程心跳 最大滞后 \(worst)ms")
          worst = 0; report = now
        }
      }
    }
    #endif
  }
}

#if DEBUG
/// 主线程卡顿账（整机压测 2026-09-26 起；只在 DEBUG + `KANPAN_CHART_DIAGNOSTICS=1` 时跑）。
///
/// 每 50 ms 醒一次，醒晚了多少就是主线程被堵了多久；晚过 100 ms 记一笔。
/// UI 用例从诊断浮层的 `main.hangs` 读这本账：压测前后各读一次，差出来的那几笔
/// 就是这一轮操作里的卡顿。1 秒一跳的 `MainThreadHeartbeat` 分辨不出 100 ms 级的卡，
/// 而且只往 stdout 打，用例看不见。
@MainActor @Observable
final class MainThreadHangLog {
  static let shared = MainThreadHangLog()
  static let threshold = 100
  /// 晚过门槛的次数。
  private(set) var count = 0
  /// 最近 50 笔的滞后（ms），老的在前。
  private(set) var recent: [Int] = []
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var epoch = 0

  static func startIfRequested() {
    guard ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1", shared.task == nil else { return }
    // 退到后台、下拉通知中心这类「不在前台」的那一段，醒来当然晚——那是被挂起，不是卡。
    // 前后台一有进出就换一代，跨了代的那一跳不记。
    for name in [UIApplication.willResignActiveNotification, UIApplication.didBecomeActiveNotification] {
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { shared.epoch &+= 1 }
      }
    }
    shared.task = Task { @MainActor in
      let clock = ContinuousClock()
      while !Task.isCancelled {
        let before = clock.now, epoch = shared.epoch
        try? await Task.sleep(for: .milliseconds(50))
        let late = Int((clock.now - before) / .milliseconds(1)) - 50
        guard late > threshold, epoch == shared.epoch,
              UIApplication.shared.applicationState == .active else { continue }
        shared.count += 1
        shared.recent = Array((shared.recent + [late]).suffix(50))
      }
    }
  }

  var summary: String { "count=\(count);recent=\(recent.map(String.init).joined(separator: ","))" }
}
#endif
