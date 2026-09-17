import SwiftUI
import Observation

@Observable @MainActor
final class DisplayComfort {
  private var brightnessPolicy = BrightnessThemePolicy()
  private(set) var automaticTheme: ThemeChoice?

  func tick(prefs: Prefs, active: Bool, brightness: Double, systemDark: Bool, animated: Bool) {
    guard active else { return }
    let next = brightnessPolicy.resolve(enabled: prefs.ambientTheme, brightness: brightness,
      now: ProcessInfo.processInfo.systemUptime, manual: prefs.theme,
      manualDark: prefs.seed(systemDark: systemDark).dark)
    if next != automaticTheme {
      withAnimation(animated ? .easeInOut(duration: 0.35) : nil) { automaticTheme = next }
    }
  }
}
