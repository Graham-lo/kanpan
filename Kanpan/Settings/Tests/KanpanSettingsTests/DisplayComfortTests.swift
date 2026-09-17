import Testing
import Foundation
import KanpanCore
@testable import KanpanSettings

@Suite("护眼选择与屏幕亮度防抖")
struct DisplayComfortTests {
  @Test func allThemesRoundTripWithoutNewArchiveVersion() {
    for theme in ThemeChoice.allCases {
      for skin in ThemeSkin.allCases {
        var prefs = Prefs(); prefs.theme = theme; prefs.skin = skin; prefs.ambientTheme = true
        #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)) == prefs)
      }
    }
    let old = Data(#"{"v":2,"theme":"dark","subs":["VOL","OI"]}"#.utf8)
    let decoded = PrefsCodec.decode(old)
    #expect(decoded.theme == .dark && !decoded.ambientTheme)
    #expect(decoded.subs == [.vol, .oi])
    // 老存档里那两档「护眼 / 夜读」已经没了：认不出来就退回出厂的青苔 + 跟随系统，
    // 别的键照旧读出来（不用为了删两个枚举值把整档作废）。
    let retired = PrefsCodec.decode(Data(#"{"v":2,"theme":"paper","skin":"sepia","redUp":true}"#.utf8))
    #expect(retired.theme == .system && retired.skin == .sage && retired.redUp)
  }
  @Test func hysteresisAndDwell() {
    var p = BrightnessThemePolicy()
    #expect(p.resolve(enabled: true, brightness: 0.2, now: 0, manual: .dark, manualDark: true) == .dark)
    #expect(p.resolve(enabled: true, brightness: 0.8, now: 89, manual: .dark, manualDark: true) == .dark)
    #expect(p.resolve(enabled: true, brightness: 0.4, now: 90, manual: .dark, manualDark: true) == .dark)
    #expect(p.resolve(enabled: true, brightness: 0.8, now: 91, manual: .dark, manualDark: true) == .light)
    #expect(p.resolve(enabled: true, brightness: 0.2, now: 92, manual: .dark, manualDark: true) == .light)
    #expect(p.resolve(enabled: false, brightness: 0.2, now: 93, manual: .dark, manualDark: true) == .dark)
    #expect(p.current == nil)
  }
  @Test func invalidBrightnessDoesNotChangeChoice() {
    var p = BrightnessThemePolicy()
    #expect(p.resolve(enabled: true, brightness: .nan, now: 0, manual: .light, manualDark: false) == .light)
    #expect(p.resolve(enabled: true, brightness: 0.4, now: 0, manual: .system, manualDark: true) == .dark)
    #expect(p.resolve(enabled: true, brightness: .infinity, now: 100, manual: .dark, manualDark: true) == .dark)
  }
  /// 配色和深浅是两根独立的轴：手动选了浅 / 深，系统怎么样都不改；
  /// 选了哪一套配色，深浅两边都得还是那一套。
  @Test func seedResolutionIsIndependentOfSystemForManualChoice() {
    for systemDark in [false, true] {
      #expect(ThemeChoice.light.seed(skin: .sage, systemDark: systemDark) == Palette.sageSeed)
      #expect(ThemeChoice.dark.seed(skin: .sage, systemDark: systemDark) == Palette.sageNightSeed)
      #expect(ThemeChoice.light.seed(skin: .terra, systemDark: systemDark) == Palette.terraSeed)
      #expect(ThemeChoice.dark.seed(skin: .terra, systemDark: systemDark) == Palette.terraNightSeed)
      for skin in ThemeSkin.allCases {
        #expect(ThemeChoice.system.seed(skin: skin, systemDark: systemDark) == skin.seed(dark: systemDark))
      }
    }
    #expect(Prefs.defaults.skin == .sage, "出厂是青苔")
    #expect(Prefs.defaults.theme == .system)
  }
}
