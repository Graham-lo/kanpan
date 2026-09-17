import Foundation

/// Screen brightness is a proxy, not a measurement of ambient light.
struct BrightnessThemePolicy: Sendable {
  private(set) var current: ThemeChoice?
  private var switchedAt: Double?

  /// 配色（青苔 / 陶土）归用户，这里只动深浅：屏幕暗下去换深色，亮起来换浅色。
  /// 原来这儿换的是「夜读 / 护眼」两套独立配色，等于把用户选的那一套悄悄换掉。
  mutating func resolve(enabled: Bool, brightness: Double, now: Double, manual: ThemeChoice, manualDark: Bool) -> ThemeChoice {
    guard enabled else { current = nil; switchedAt = nil; return manual }
    guard brightness.isFinite, now.isFinite else { return current ?? manual }
    let proposed: ThemeChoice? = brightness < 0.32 ? .dark : (brightness > 0.45 ? .light : nil)
    guard let old = current else {
      let first = proposed ?? (manualDark ? .dark : .light)
      current = first; switchedAt = now; return first
    }
    if let proposed, proposed != old, now - (switchedAt ?? now) >= 90 {
      current = proposed; switchedAt = now
    }
    return current ?? old
  }
}
