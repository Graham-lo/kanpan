import Testing

@testable import KanpanCore

/// A1.10：11 款风格的每个字段、两套配色的每个颜色，都要和定版原型一模一样。
@Suite("风格表与配色")
struct StyleTableTests {
  @Test("11 款风格、顺序与默认值")
  func tableShape() {
    #expect(CandleStyle.all.count == 11)
    #expect(CandleStyle.all.map(\.id) == Fx.styles.map { $0.s["id"]! }, "顺序和原型不一致")
    #expect(CandleStyle.default.id == "stout", "默认必须是「墩」")
    #expect(CandleStyle.default.name == "墩")
    #expect(Set(CandleStyle.all.map(\.id)).count == 11, "id 有重复")
    #expect(Set(CandleStyle.all.map(\.name)).count == 11, "名字有重复")
    #expect(CandleStyle.style(id: "没这个").id == "stout", "找不到要落回默认")
  }

  @Test("每个字段与原型逐一相等", arguments: CandleStyle.all.indices)
  func fieldsMatchPrototype(_ i: Int) {
    let st = CandleStyle.all[i]
    let fx = Fx.styles[i]
    #expect(st.id == fx.s["id"]!)
    #expect(st.name == fx.s["name"]!)
    #expect(st.one == fx.s["one"]!)
    #expect(st.wickCap.rawValue == fx.s["wickCap"]!, "\(st.id) wickCap")
    #expect(st.shape.rawValue == fx.s["shape"]!, "\(st.id) shape")
    #expect(st.grid.rawValue == fx.s["grid"]!, "\(st.id) grid")
    let nums: [(String, Double)] = [
      ("bodyR", st.bodyR), ("wick", st.wick), ("wickTint", st.wickTint), ("radius", st.radius),
      ("minBody", st.minBody), ("spacing", st.spacing), ("pad", st.pad), ("axisW", st.axisW),
      ("timeH", st.timeH), ("subH", st.subH), ("lastDash", st.lastDash ? 1 : 0),
    ]
    for (k, v) in nums {
      #expect(v == fx.n[k], "\(st.id).\(k)：原型 \(fx.n[k] ?? .nan)，这里 \(v)")
    }
    // 一句话和赌注文案都得有，图例和切换器要用。
    #expect(!st.one.isEmpty && !st.bet.isEmpty, "\(st.id) 缺文案")
  }

  /// 字段本身得在合理范围里——写错一位小数比对不上原型也看得出来。
  @Test("字段范围合理", arguments: CandleStyle.all)
  func sane(_ st: CandleStyle) {
    #expect(st.bodyR > 0 && st.bodyR <= 1, "\(st.id) bodyR=\(st.bodyR)")
    #expect(st.wick > 0 && st.wick <= 6, "\(st.id) wick=\(st.wick)")
    #expect(st.wickTint >= 0 && st.wickTint <= 1, "\(st.id) wickTint=\(st.wickTint)")
    #expect(st.spacing >= Chart.minBarSpacing && st.spacing <= Chart.maxBarSpacing, "\(st.id) spacing")
    #expect(st.pad >= 0 && st.pad < 0.5, "\(st.id) pad=\(st.pad)")
    #expect(st.axisW > 20 && st.timeH > 10 && st.subH > 30, "\(st.id) 版面尺寸")
  }

  @Test("浅色配色与原型逐一相等")
  func lightPalette() { Self.checkPalette(Palette.chart(Palette.lightSeed), Fx.light, "浅色") }

  @Test("深色配色与原型逐一相等")
  func darkPalette() { Self.checkPalette(Palette.chart(Palette.darkSeed), Fx.dark, "深色") }

  static func checkPalette(
    _ c: ChartColors, _ fx: PaletteRow, _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let fromChart: [(String, Hex)] = [
      ("bg", c.bg), ("grid", c.grid), ("axis", c.axis), ("text", c.text), ("dim", c.dim),
      ("ink", c.ink), ("amber", c.amber), ("cross", c.cross), ("band", c.band), ("oi", c.oi),
      ("oiFill", c.oiFill), ("chip", c.chip), ("panel", c.panel),
      ("crossBg", c.crossBg), ("crossInk", c.crossInk),
    ]
    for (k, v) in fromChart {
      #expect(v.value == fx.chart[k], "\(label) \(k)：原型 \(fx.chart[k] ?? "无")，这里 \(v.value)",
              sourceLocation: sourceLocation)
    }
    let fromCSS: [(String, Hex)] = [
      ("--up", c.up), ("--down", c.down), ("--hair", c.hair),
      ("--amber-soft", c.amberSoft), ("--amber-line", c.amberLine),
    ]
    for (k, v) in fromCSS {
      #expect(v.value == fx.css[k], "\(label) \(k)：原型 \(fx.css[k] ?? "无")，这里 \(v.value)",
              sourceLocation: sourceLocation)
    }
    #expect(c.palette.map(\.value) == fx.palette, "\(label) 指标配色", sourceLocation: sourceLocation)
    #expect(c.up.value == fx.green, "\(label) 涨色", sourceLocation: sourceLocation)
    #expect(c.down.value == fx.red, "\(label) 跌色", sourceLocation: sourceLocation)
  }

  /// 红涨绿跌只换 up/down 两个，别的一个都不许动。
  @Test("redUp 只翻转涨跌两色", arguments: [Palette.lightSeed, Palette.darkSeed])
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
  @Test("颜色格式合法", arguments: [Palette.lightSeed, Palette.darkSeed])
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
