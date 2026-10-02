import Testing
import Foundation
import KanpanCore
@testable import Kanpan

@Suite("深浅与配色")
struct DisplayComfortTests {
  @Test func allThemesRoundTripWithoutNewArchiveVersion() {
    for theme in ThemeChoice.allCases {
      for skin in ThemeSkin.allCases {
        var prefs = Prefs(); prefs.theme = theme; prefs.skin = skin
        #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)) == prefs)
      }
    }
    let old = Data(#"{"v":2,"theme":"dark","subs":["VOL","OI"]}"#.utf8)
    let decoded = PrefsCodec.decode(old)
    #expect(decoded.theme == .dark)
    #expect(decoded.subs == [.vol, .oi])
    // 老存档里那两档「护眼 / 夜读」已经没了：认不出来就退回出厂的青苔 + 跟随系统，
    // 别的键照旧读出来（不用为了删两个枚举值把整档作废）。
    let retired = PrefsCodec.decode(Data(#"{"v":2,"theme":"paper","skin":"sepia","redUp":true}"#.utf8))
    // redUp 是第 4 版之前的档，按「一律绿涨红跌」迁成了 false（PrefsCodec.migrate）。
    #expect(retired.theme == .system && retired.skin == .sage && !retired.redUp)
  }
  /// 「按屏幕亮度切换深浅」2026-09-28 收掉：老存档里那一键认不出来就忽略，别的键照旧。
  @Test func retiredAmbientKeyIsIgnored() {
    let old = PrefsCodec.decode(Data(#"{"v":2,"theme":"light","ambientTheme":true,"redUp":true}"#.utf8))
    #expect(old.theme == .light && !old.redUp)   // 第 4 版之前的档一律迁成绿涨
  }
  /// 配色和深浅是两根独立的轴：手动选了浅 / 深，系统怎么样都不改；
  /// 选了哪一套配色，深浅两边都得还是那一套。
  @Test func seedResolutionIsIndependentOfSystemForManualChoice() {
    for systemDark in [false, true] {
      #expect(ThemeChoice.light.seed(skin: .sage, systemDark: systemDark) == Palette.sageSeed)
      #expect(ThemeChoice.dark.seed(skin: .sage, systemDark: systemDark) == Palette.sageNightSeed)
      #expect(ThemeChoice.light.seed(skin: .terra, systemDark: systemDark) == Palette.terraSeed)
      #expect(ThemeChoice.dark.seed(skin: .terra, systemDark: systemDark) == Palette.terraNightSeed)
      #expect(ThemeChoice.light.seed(skin: .classic, systemDark: systemDark) == Palette.classicSeed)
      #expect(ThemeChoice.dark.seed(skin: .classic, systemDark: systemDark) == Palette.classicNightSeed)
      for skin in ThemeSkin.allCases {
        #expect(ThemeChoice.system.seed(skin: skin, systemDark: systemDark) == skin.seed(dark: systemDark))
      }
    }
    #expect(Prefs.defaults.skin == .sage, "出厂是青苔")
    #expect(Prefs.defaults.theme == .system)
  }
}
