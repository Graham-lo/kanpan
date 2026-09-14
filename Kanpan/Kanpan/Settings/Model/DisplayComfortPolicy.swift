import Foundation

/// Screen brightness is a proxy, not a measurement of ambient light.
struct BrightnessThemePolicy: Sendable {
  private(set) var current: ThemeChoice?
  private var switchedAt: Double?

  mutating func resolve(enabled: Bool, brightness: Double, now: Double, manual: ThemeChoice, systemDark: Bool) -> ThemeChoice {
    guard enabled else { current = nil; switchedAt = nil; return manual }
    guard brightness.isFinite, now.isFinite else { return current ?? manual }
    let proposed: ThemeChoice? = brightness < 0.32 ? .night : (brightness > 0.45 ? .paper : nil)
    guard let old = current else {
      let first = proposed ?? (manual.seed(systemDark: systemDark).dark ? .night : .paper)
      current = first; switchedAt = now; return first
    }
    if let proposed, proposed != old, now - (switchedAt ?? now) >= 90 {
      current = proposed; switchedAt = now
    }
    return current ?? old
  }
}
