import Foundation
import KanpanChart
import QuartzCore

/// 从外面观察 `ChartView` 那条 `CADisplayLink` 的状态。
///
/// `ChartView.link` 是 `private`，**取证不该为了看一眼就把它开放成 API**——
/// 生产代码不欠取证任何东西。所以这里用 `Mirror` 读存储属性：
/// `ChartView` 是 Swift 类，`Mirror` 能列出它自己声明的存储属性，包括 private 的。
/// `KanpanChart/Sources/` 下一个字都不用改。
///
/// 两个观测量：
/// - `isPaused`：`CADisplayLink` 的公开属性，直接就是 A3.12 前半句要的答案；
/// - `timestamp`：**只在回调真的发生时**才被 CoreAnimation 更新。30 秒里它一动不动，
///   就等于这条 link 一帧都没跑——比 `isPaused` 更硬，因为它是「结果」不是「意图」。
@MainActor
enum DisplayLinkProbe {
  static func link(of chart: ChartView) -> CADisplayLink? {
    for child in Mirror(reflecting: chart).children where child.label == "link" {
      return child.value as? CADisplayLink
    }
    return nil
  }

  /// 一次采样。
  struct Sample {
    let t: Double
    let phase: String
    /// `nil` = 这一刻压根没有 link 对象（`didMoveToWindow` 里 invalidate 过，或还没建）。
    let paused: Bool?
    let timestamp: Double?

    var line: String {
      let p = paused.map { $0 ? "paused" : "RUNNING" } ?? "no-link"
      let ts = timestamp.map { String(format: "%.6f", $0) } ?? "-"
      let pad = { (s: String, n: Int) in s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
      return String(format: "%7.3f", t) + "  " + pad(phase, 10) + "  " + pad(p, 8) + "  " + ts
    }
  }

  static func sample(_ chart: ChartView, phase: String, t: Double) -> Sample {
    let l = link(of: chart)
    return Sample(t: t, phase: phase, paused: l?.isPaused, timestamp: l?.timestamp)
  }
}
