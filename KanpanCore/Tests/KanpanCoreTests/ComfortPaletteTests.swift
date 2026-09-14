import Testing
@testable import KanpanCore

@Suite("护眼配色实际表面对比度")
struct ComfortPaletteTests {
  @Test func luminanceFormula() {
    #expect(abs(Palette.contrast("#FFFFFF", "#000000") - 21) < 0.00001)
    #expect(Palette.contrast("#888888", "#888888") == 1)
  }
  @Test(arguments: [Palette.paperSeed, Palette.nightSeed])
  func resolvedSmallText(_ seed: PaletteSeed) {
    let colors = Palette.chart(seed)
    #expect(colors.bg == seed.app)
    for surface in [seed.app, seed.raised] {
      for ink in [seed.ink, seed.ink2, colors.dim, colors.amber, colors.up, colors.down] {
        #expect(Palette.contrast(ink, surface) >= 4.5)
      }
    }
    #expect(Palette.contrast(colors.dim, seed.raised2) >= 4.5)
    for ink in colors.palette { #expect(Palette.contrast(ink, colors.bg) >= 4.5) }
    let reversed = Palette.chart(seed, redUp: true)
    #expect(reversed.up == colors.down && reversed.down == colors.up)
    #expect(reversed.bg == colors.bg && reversed.palette == colors.palette)
  }
  @Test func retainSeedsAndExposePrototypeGap() {
    #expect(Palette.paperSeed.ink3 == "#736D5D")
    #expect(Palette.nightSeed.ink3 == "#887F6A")
    #expect(Palette.contrast(Palette.nightSeed.ink3, Palette.nightSeed.raised) < 4.5)
    #expect(Palette.chart(Palette.nightSeed).dim != Palette.nightSeed.ink3)
    #expect(Palette.chart(Palette.lightSeed).hair == "#12163A0F")
    #expect(Palette.chart(Palette.darkSeed).hair == "#FFFFFF0A")
  }
}
