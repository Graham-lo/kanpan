import Foundation
import KanpanAccount

/// 找相似任务的轮询节奏（审查 P2-2）。
///
/// 原来是死循环里固定睡 2 秒：服务端那边任务卡住（排队排不上、跑到一半没人管），
/// 这台手机就每 2 秒敲一次、永远敲下去，查找页一直转圈。现在：
/// - **指数退避**：从 `base` 起翻倍，封顶 `ceiling`（30 秒）；
/// - **有进展就回到基准节奏**：`checked` 变了说明任务在跑，进度条该勤快地刷；
/// - **总时长封顶**：`budget`（10 分钟）用完返回 nil，调用方停下、撤掉服务端任务、
///   以「可重试」收尾（`search_timeout`，查找页上是一颗「重试」），不是判失败。
public struct ReviewPollSchedule: Sendable, Equatable {
  public static let timeoutCode = "search_timeout"
  public let base: Double
  public let ceiling: Double
  public let budget: Double
  private var delay: Double
  private var lastChecked: Int?

  public init(base: Double = 2, ceiling: Double = 30, budget: Double = 600) {
    self.base = base; self.ceiling = ceiling; self.budget = budget
    self.delay = base
  }

  /// 看完一次状态之后，下一次隔多久再看。`elapsed` 是从发起查找到现在的秒数（含请求耗时）。
  /// 返回 nil：总时长用完，该停了。
  public mutating func next(checked: Int?, elapsed: Double) -> Double? {
    guard elapsed < budget else { return nil }
    if let checked {
      if let lastChecked, checked != lastChecked { delay = base }
      lastChecked = checked
    }
    let wait = min(delay, budget - elapsed)
    delay = min(delay * 2, ceiling)
    return wait
  }

  /// 问一次状态失败了，要不要接着按退避节奏问：断网、超时、服务端 5xx / 429 是「等一等」，
  /// 接着问；凭证失效、被顶下线、4xx 是「问多少次都一样」，立刻停。
  public static func keepsPolling(after error: any Error) -> Bool {
    if error is CancellationError { return false }
    if error is URLError { return true }
    if let account = error as? AccountError {
      switch account {
      case .unavailable, .invalidResponse, .credentialsUnavailable: return true
      case .http(let status, _): return status == 429 || status >= 500
      default: return false
      }
    }
    guard let status = (error as? any ReviewFailureStatus)?.reviewStatusCode else { return false }
    return status == 429 || status >= 500
  }

  /// 总时长用完时抛的那个错：504 + `search_timeout`，文案是「请稍后重试」，查找页给「重试」。
  public static var timedOut: ScorebookError { .http(504, timeoutCode) }
}
