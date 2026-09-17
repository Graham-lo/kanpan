import Testing

@testable import KanpanCore

/// A1.10：风格表和两套配色的每个颜色，都要和定版原型一模一样。
///
/// 原来这儿逐字段比对的是原型带来的十一款风格（`Fx.styles`）。2026-09-15 风格表收成
/// AICoin 一套（见 `CandleStyle`），那一批对照就没有对象了；配色那几条一个都没动，
/// 它们和风格无关。
@Suite("风格表与配色")
struct StyleTableTests {
  @Test("只有 AICoin 一套")
  func tableShape() {
    #expect(CandleStyle.all.count == 1, "风格表又长出别的款了")
    #expect(CandleStyle.default.id == "aicoin")
    #expect(CandleStyle.default.name == "AICoin")
    #expect(CandleStyle.style(id: "没这个").id == "aicoin", "认不出的 id 要落回这一套")
    #expect(CandleStyle.style(id: "stout").id == "aicoin", "旧存档里的老风格 id 也一样")
  }

  /// AICoin 这一套本身：平头影线、不压影线颜色、直角实心、不画风格自带网格。
  @Test("AICoin 的字段")
  func aicoinFields() {
    let st = CandleStyle.aicoin
    #expect(st.wickCap == .butt)
    #expect(st.wickTint == 1)
    #expect(st.shape == .solid)
    #expect(st.radius == 0)
    #expect(st.grid == .none)
  }

  /// 字段本身得在合理范围里——写错一位小数比对不上原型也看得出来。
  @Test("字段范围合理", arguments: CandleStyle.all)
  func sane(_ st: CandleStyle) {
    #expect(st.wickTint >= 0 && st.wickTint <= 1)
    #expect(st.radius >= 0 && st.radius.isFinite)

  }

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
    let canvas = seed.dark ? Palette.nightCanvas : Palette.dayCanvas
    #expect(c.bg == canvas.bg)
    #expect(c.grid == canvas.grid)
    #expect(c.axis == canvas.axis)
    #expect(c.text == canvas.text)
    #expect(c.dim == canvas.dim)
    #expect(c.ink == canvas.ink)
    #expect(c.cross == canvas.cross)
    #expect(c.bg != seed.chart || seed.chart == canvas.bg, "画布不许再跟着皮肤染")
    #expect(c.amber == seed.amber, "图上那支暖色不跟界面强调色走")
    #expect(c.up == seed.up && c.down == seed.down)
    #expect(c.hair == seed.hair)
    #expect(c.palette == seed.palette)
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

  /// `mixHex` 两端与中点。原型用 JS `toString(16)`，出来是小写。
  @Test("mixHex")
  func mix() {
    #expect(mixHex("#000000", "#FFFFFF", 0).value == "#000000")
    #expect(mixHex("#000000", "#FFFFFF", 1).value == "#ffffff")
    #expect(mixHex("#000000", "#FFFFFF", 0.5).value == "#808080")
    #expect(mixHex("#DE2E57", "#0E9E78", 0).value == "#de2e57")
    #expect(mixHex("#DE2E57", "#0E9E78", 1).value == "#0e9e78")
    // 半透明色混色只看前三个通道，和原型 slice(1, 7) 一致。
    #expect(mixHex("#DE2E5780", "#0E9E7840", 0).value == "#de2e57")
  }
}
