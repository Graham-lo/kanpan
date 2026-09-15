import Foundation

public enum MarketRoutingState: Sendable, Equatable {
  case idle, switching, switched
}

/// Independent of chart selection: opening charts cannot reset or trigger recovery probes.
struct MarketRecoverySchedule: Sendable {
  private(set) var nextAttempt: Date
  private(set) var lastAttempt = Date.distantPast
  private(set) var confirming = false
  private var failures = 0
  init(now: Date = Date()) { nextAttempt = now.addingTimeInterval(300) }
  func isDue(at now: Date) -> Bool { now >= nextAttempt }
  mutating func record(healthy: Bool, at now: Date) -> Bool {
    lastAttempt = now
    if healthy {
      let confirmed = confirming
      confirming = true
      nextAttempt = now.addingTimeInterval(10)
      return confirmed
    }
    confirming = false
    failures = min(failures + 1, 3)
    nextAttempt = now.addingTimeInterval(Double(failures) * 300)
    return false
  }
  mutating func networkRestored(at now: Date) {
    // Ignore flapping connectivity; a real offline→online transition can bring the probe forward.
    if now.timeIntervalSince(lastAttempt) >= 60 { nextAttempt = now; confirming = false }
  }
}
