import Testing
import Foundation
import KanpanCore
@testable import KanpanSettings

@Suite("护眼选择与屏幕亮度防抖")
struct DisplayComfortTests {
  @Test func allThemesRoundTripWithoutNewArchiveVersion() {
    for theme in ThemeChoice.allCases {
      var prefs = Prefs(); prefs.theme = theme; prefs.ambientTheme = true
      #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)) == prefs)
    }
    let old = Data(#"{"v":2,"theme":"dark","subs":["VOL","OI"]}"#.utf8)
    let decoded = PrefsCodec.decode(old)
    #expect(decoded.theme == .dark && !decoded.ambientTheme)
    #expect(decoded.subs == [.vol, .oi])
  }
  @Test func hysteresisAndDwell() {
    var p = BrightnessThemePolicy()
    #expect(p.resolve(enabled: true, brightness: 0.2, now: 0, manual: .dark, systemDark: false) == .night)
    #expect(p.resolve(enabled: true, brightness: 0.8, now: 89, manual: .dark, systemDark: false) == .night)
    #expect(p.resolve(enabled: true, brightness: 0.4, now: 90, manual: .dark, systemDark: false) == .night)
    #expect(p.resolve(enabled: true, brightness: 0.8, now: 91, manual: .dark, systemDark: false) == .paper)
    #expect(p.resolve(enabled: true, brightness: 0.2, now: 92, manual: .dark, systemDark: false) == .paper)
    #expect(p.resolve(enabled: false, brightness: 0.2, now: 93, manual: .dark, systemDark: false) == .dark)
    #expect(p.current == nil)
  }
  @Test func invalidBrightnessDoesNotChangeChoice() {
    var p = BrightnessThemePolicy()
    #expect(p.resolve(enabled: true, brightness: .nan, now: 0, manual: .paper, systemDark: false) == .paper)
    #expect(p.resolve(enabled: true, brightness: 0.4, now: 0, manual: .system, systemDark: true) == .night)
    #expect(p.resolve(enabled: true, brightness: .infinity, now: 100, manual: .dark, systemDark: false) == .night)
  }
  @Test func seedResolutionIsIndependentOfSystemForManualChoice() {
    for systemDark in [false, true] {
      #expect(ThemeChoice.paper.seed(systemDark: systemDark) == Palette.paperSeed)
      #expect(ThemeChoice.night.seed(systemDark: systemDark) == Palette.nightSeed)
    }
  }
}
