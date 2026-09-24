import Testing
import KanpanCore
@testable import KanpanPresentation

/// A1.10：配色令牌的接线。原在 KanpanCore 的 `StyleTableTests`，随 `Palette` 搬到这里（审查 24）。
@Suite("配色接线")
struct PaletteWiringTests {
  /// 配色不再对着原型那张表逐字比。2026-09-16 换成青苔 / 陶土两套（见 `Palette`），
  /// 旧 `styles.json` 里的浅 / 深两行说的是上一版的蓝白配色，留着比只会比出旧值。
  /// 现在守的是**接线**：每个令牌有没有接到该接的地方，四套配色一视同仁。
  ///
  /// 2026-09-17 又分成两半：画布那几样（底、网格、轴线、轴文字、次要读数、主文字、十字线）
  /// 固定用 AICoin 的日 / 夜两套，只认 `seed.dark`；跟着皮肤走的只剩涨跌色、`amber`
  /// 和 MA 那组 `palette`——它们在头部和自选列表里也出现，图里图外得是同一个红、同一个绿。
  @Test("令牌接线正确", arguments: [Palette.sageSeed, Palette.sageNightSeed,
                                    Palette.terraSeed, Palette.terraNightSeed,
                                    Palette.classicSeed, Palette.classicNightSeed])
  func tokensWireThrough(_ seed: PaletteSeed) {
    let c = Palette.chart(seed)
    let canvas = Palette.canvas(seed)
    #expect(c.bg == canvas.bg)
    #expect(c.grid == canvas.grid)
    #expect(c.axis == canvas.axis)
    #expect(c.text == canvas.text)
    #expect(c.dim == canvas.dim)
    #expect(c.ink == canvas.ink)
    #expect(c.cross == canvas.cross)
    #expect(c.bg == seed.chart, "图区的底就是皮肤自己的底；经典那支正好等于 AICoin 的白 / 深蓝")
    #expect(c.amber == seed.amber, "图上那支暖色不跟界面强调色走")
    #expect(c.up == seed.up && c.down == seed.down)
    #expect(c.hair == seed.hair)
    #expect(c.palette == seed.palette)
    #expect(c.sub == seed.sub)
    #expect(c.band == seed.palette[4] && c.oi == seed.palette[5])
    #expect(c.panel == seed.app)
    #expect(c.chip == (seed.dark ? seed.ground : seed.app))
    #expect(c.amberSoft.value.hasPrefix(seed.amber.value))
    #expect(c.amberLine.value == seed.amber.value + "55")
  }

  /// 红涨绿跌只换 up/down 两个，别的一个都不许动。
  @Test("redUp 只翻转涨跌两色", arguments: [Palette.sageSeed, Palette.sageNightSeed,
                                           Palette.terraSeed, Palette.terraNightSeed,
                                    Palette.classicSeed, Palette.classicNightSeed])
  func redUpSwapsOnlyUpDown(_ seed: PaletteSeed) {
    let a = Palette.chart(seed)
    let b = Palette.chart(seed, redUp: true)
    #expect(b.up == a.down && b.down == a.up, "没换过来")
    var c = b
    c.up = a.up
    c.down = a.down
    #expect(c == a, "除了涨跌色还动了别的")
  }

  /// 颜色都得是能解析的十六进制。
  @Test("颜色格式合法", arguments: [Palette.sageSeed, Palette.sageNightSeed,
                                           Palette.terraSeed, Palette.terraNightSeed,
                                    Palette.classicSeed, Palette.classicNightSeed])
  func hexParses(_ seed: PaletteSeed) {
    let c = Palette.chart(seed)
    for h in [c.bg, c.grid, c.axis, c.text, c.dim, c.ink, c.amber, c.cross, c.band, c.oi,
              c.oiFill, c.chip, c.panel, c.crossBg, c.crossInk, c.hair, c.amberSoft,
              c.amberLine, c.up, c.down] + c.palette {
      #expect(h.value.hasPrefix("#"), "\(h.value) 不是十六进制")
      #expect([7, 9].contains(h.value.count), "\(h.value) 长度不对")
      let p = h.rgba
      #expect(p.r >= 0 && p.r <= 1 && p.g >= 0 && p.g <= 1 && p.b >= 0 && p.b <= 1 && p.a >= 0 && p.a <= 1,
              "\(h.value) 解析成 \(p)")
    }
    #expect(Palette.veil(seed).value.count == 9, "遮罩要带透明度")
    #expect(Palette.scrim(seed).value.count == 9, "幕布要带透明度")
  }
}
