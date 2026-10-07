import Testing
import KanpanCore
import KanpanPresentation
@testable import Kanpan

/// 琉璃材质（`LiuliMaterial`）三套皮肤的签名，和底栏上方那条提示（`Toast`）的对比度。
@Suite("琉璃材质与提示条对比度")
struct LiuliMaterialTests {
  private static let themes: [PanelTheme] = [false, true].flatMap { dark in
    Skin.allCases.map { PanelTheme(seed: Palette.seed($0, dark: dark)) }
  }

  @Test("提示条：墨色字、按钮字、间隔点在白图和黑图上都 ≥ 4.5:1")
  func toastContrast() {
    for theme in Self.themes {
      for surface in Toast.worstSurfaces(theme) {
        #expect(Palette.contrast(theme.seed.ink, surface) >= 4.5, "\(theme.seed.ink) on \(surface)")
        #expect(Palette.contrast(Toast.actionInk(theme), surface) >= 4.5)
        #expect(Palette.contrast(Toast.secondaryInk(theme), surface) >= 4.5)
      }
    }
  }

  @Test("提示条让位底栏实际高度")
  func toastClearsTabBar() {
    #expect(TabBar.height >= 44)
  }

  @Test("皮肤签名：经典与深色不画光斑，青苔 / 陶土各自的底色")
  func skinSignatures() {
    let sage = LiuliMaterial(theme: PanelTheme(seed: Palette.seed(.sage, dark: false)))
    let terra = LiuliMaterial(theme: PanelTheme(seed: Palette.seed(.terra, dark: false)))
    let classic = LiuliMaterial(theme: PanelTheme(seed: Palette.seed(.classic, dark: false)))
    #expect(sage.showsLobes && terra.showsLobes)
    #expect(!classic.showsLobes)
    #expect(sage.groundHex == "#E9F3F1")
    #expect(terra.groundHex == "#F4EFEA")
    #expect(terra.grainOpacity == 0.06)
    for skin in Skin.allCases {
      #expect(!LiuliMaterial(theme: PanelTheme(seed: Palette.seed(skin, dark: true))).showsLobes)
    }
  }

  @Test("玻璃上的正文墨色 ≥ 4.5:1（三套浅色皮肤）")
  func inkOnGlass() {
    for skin in Skin.allCases {
      let m = LiuliMaterial(theme: PanelTheme(seed: Palette.seed(skin, dark: false)))
      #expect(Palette.contrast(m.seed.ink, m.groundHex) >= 4.5)
      #expect(Palette.contrast(m.seed.ink3, m.groundHex) >= 4.5)
    }
  }
}
