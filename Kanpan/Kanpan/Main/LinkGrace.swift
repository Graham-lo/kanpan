import Foundation

/// 推送连接「断了多久」的那只表：从该连着却不在 `.live` 的那一刻起算，满 `seconds` 秒算断。
///
/// 顶栏（`MarketModel`，bfc1c816）和自选表（`QuoteBook`）用的是同一条规矩：
/// 平常的闪断（退避第一拍 1 秒、重连几百毫秒）在宽限之内接上，肉眼看不见灰一下；
/// 断满宽限那口价就不再当「现在的价」摆；一接上立刻复原。后台不算，回前台重新起算。
///
/// 只管计时，不管调度：「时间流过去」本身不是事件，断线之后也没有帧进来触发重算，
/// 所以由持有者在起算的那一刻挂一拍、到点来问 `isDown(now:)`。
struct LinkGrace: Equatable {
  /// 连接断了满这么多秒才算断。
  static let seconds: TimeInterval = 5

  /// 从哪一刻起该连着却不在 `.live`。nil = 连着，或者这时候根本不该有连接（后台、没人要）。
  private(set) var since: Date?

  /// 报一次现状。`waiting` = 此刻该连着、却不在 `.live`。
  /// 返回 true 表示刚刚开始起算——持有者该在 `seconds` 之后来扫一次。
  /// 中途换档（offline → reconnecting）不重新起算。
  @discardableResult
  mutating func track(waiting: Bool, now: Date) -> Bool {
    guard waiting else { since = nil; return false }
    guard since == nil else { return false }
    since = now
    return true
  }

  /// 此刻算不算断。
  func isDown(now: Date) -> Bool {
    since.map { now.timeIntervalSince($0) >= Self.seconds } ?? false
  }
}
