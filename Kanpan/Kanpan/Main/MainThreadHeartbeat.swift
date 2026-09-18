import Foundation

/// 主线程心跳（只在 `KANPAN_LOG=1` 时跑）。
///
/// 「行情不跳」有两种完全不同的原因：帧没到，或者帧到了而主线程正忙着——后者
/// 整屏都冻着，图和自选列表一起停，跟网络没有半点关系。这段每秒醒一次，报的是
/// 实际间隔比一秒多出多少：稳定在几十毫秒内说明主线程是空的，动不动几百上千
/// 毫秒就是被什么活儿堵住了。
@MainActor
enum MainThreadHeartbeat {
  private static var task: Task<Void, Never>?

  static func startIfRequested() {
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
  }
}
