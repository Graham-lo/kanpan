import Testing
@testable import KanpanCore

/// 三套配色（青苔 / 陶土 / 经典）六个版本在真实表面上的可读性。
///
/// 两条不同的线：**文字**按 WCAG AA 的 4.5:1 收，**画在图上的线**（均线、BOLL 中轴、
/// 那六支指标色）按图形元素的 3:1 收。均线要在同一张图上彼此分得开，一律压到 4.5
/// 只会把六支颜色全挤成深色，反而分不清哪根是哪根。
@Suite("配色在真实表面上的对比度")
struct SkinPaletteTests {
  static let seeds = [Palette.sageSeed, Palette.sageNightSeed, Palette.terraSeed, Palette.terraNightSeed,
                      Palette.classicSeed, Palette.classicNightSeed]

  @Test func luminanceFormula() {
    #expect(abs(Palette.contrast("#FFFFFF", "#000000") - 21) < 0.00001)
    #expect(Palette.contrast("#888888", "#888888") == 1)
  }

  @Test("文字在所有表面上都够黑（或够白）", arguments: seeds)
  func resolvedSmallText(_ seed: PaletteSeed) {
    let colors = Palette.chart(seed)
    // 画布是固定的 AICoin 那套，不跟皮肤走；它只按深浅二选一。
    #expect(colors.bg == (seed.dark ? Palette.nightCanvas.bg : Palette.dayCanvas.bg))
    for surface in [seed.app, seed.raised, seed.raised2] {
      for ink in [seed.ink, seed.ink2] {
        #expect(Palette.contrast(ink, surface) >= 4.5, "\(ink) 落在 \(surface) 上看不清")
      }
    }
    // 轴上的读数画在画布上，就按画布收，不再拿皮肤的面去量。
    // 轴文字这一支照 AICoin 的实测值 #7A8899 原样搬过来，落在白画布上是 3.6:1——
    // 够不上 AICoin AA 的 4.5，但它是刻度这类次要读数（跟网格线一个层级），按图形元素的
    // 3:1 收。把它压黑确实更「合规」，代价是整张图的层次全乱：刻度会比蜡烛还抢眼。
    // 十字线悬停时读的那行字走的是 `crossInk`，不吃这条线。
    #expect(Palette.contrast(colors.text, colors.bg) >= 3, "轴文字在画布上看不清")
    #expect(Palette.contrast(colors.ink, colors.bg) >= 4.5, "画布上的主文字看不清")
    // 涨跌两色要当数字读（最新价、涨跌幅），按文字收。
    // 「经典」照搬 AICoin 真机实测的涨跌色（#36B257 / #E64552，夜 #2F9347 / #CC3333），
    // 白底上只有 2.6–3.9:1，本来就够不上这条；它的目标是「跟 AICoin 一样」，不是合规，跳过。
    if !Palette.isClassic(seed) {
      for surface in [seed.app, seed.raised] {
        for ink in [colors.up, colors.down] {
          #expect(Palette.contrast(ink, surface) >= 4.5, "\(ink) 落在 \(surface) 上看不清")
        }
      }
    }
  }

  @Test("图上的线彼此分得开也看得见", arguments: seeds)
  func chartLines(_ seed: PaletteSeed) {
    let colors = Palette.chart(seed)
    // 「经典」的线色是 AICoin 真机上量出来的（#FFB400 在白底上只有 1.8:1），照抄不改，跳过淡不淡。
    if !Palette.isClassic(seed) {
      for line in colors.palette + colors.sub + [colors.amber] {
        #expect(Palette.contrast(line, colors.bg) >= 3, "\(line) 画在图上太淡")
      }
    }
    // 六支指标色两两之间也得分得开，否则同屏几根均线看着是一根。
    // 这里比的是色差而不是明暗对比：同一亮度的蓝和紫对比度只有 1.0，眼睛却分得清清楚楚，
    // 拿对比度当「像不像」的尺子会把一整排颜色误判成一样的。
    for (i, a) in colors.palette.enumerated() {
      for b in colors.palette[(i + 1)...] {
        let x = a.bytes, y = b.bytes
        let apart = abs(x.r - y.r) + abs(x.g - y.g) + abs(x.b - y.b)
        #expect(apart >= 40, "\(a) 和 \(b) 太像（色差 \(apart)）")
      }
    }
  }

  @Test("红涨绿跌只翻涨跌两色", arguments: seeds)
  func redUpSwapsOnlyUpDown(_ seed: PaletteSeed) {
    let colors = Palette.chart(seed)
    let reversed = Palette.chart(seed, redUp: true)
    #expect(reversed.up == colors.down && reversed.down == colors.up)
    #expect(reversed.bg == colors.bg && reversed.palette == colors.palette)
  }

  @Test("三套配色确实不是同一套")
  func skinsDiffer() {
    #expect(Palette.isWarm(Palette.terraSeed) && Palette.isWarm(Palette.terraNightSeed))
    #expect(!Palette.isWarm(Palette.sageSeed) && !Palette.isWarm(Palette.sageNightSeed))
    #expect(!Palette.isWarm(Palette.classicSeed) && !Palette.isWarm(Palette.classicNightSeed))
    #expect(Palette.isClassic(Palette.classicSeed) && Palette.isClassic(Palette.classicNightSeed))
    #expect(!Palette.isClassic(Palette.sageSeed) && !Palette.isClassic(Palette.terraSeed))
    #expect(Palette.lightSeed == Palette.sageSeed, "出厂是青苔")
    #expect(Palette.darkSeed == Palette.sageNightSeed)
    #expect(Palette.chart(Palette.sageSeed).hair == "#14211B0F")
    #expect(Palette.chart(Palette.sageNightSeed).hair == "#FFFFFF0A")
  }

  /// 经典只是青苔换了底：底、面、线是 AICoin 的白 / 深蓝，其余每一个令牌都和青苔相同。
  @Test("经典：字和强调色照青苔，底和 K 线色照 AICoin")
  func classicKeepsInkTakesAICoinKLine() {
    for (classic, sage) in [(Palette.classicSeed, Palette.sageSeed),
                            (Palette.classicNightSeed, Palette.sageNightSeed)] {
      #expect(classic.dark == sage.dark)
      #expect(classic.ink == sage.ink && classic.ink2 == sage.ink2 && classic.ink3 == sage.ink3)
      #expect(classic.accent == sage.accent && classic.hair == sage.hair)
      #expect(classic.app != sage.app && classic.raised2 != sage.raised2)
      // 涨跌、均线、副图线全都不再是青苔的
      #expect(classic.up != sage.up && classic.down != sage.down)
      #expect(classic.palette != sage.palette)
      #expect(classic.sub != classic.palette, "副图线按 AICoin 槽位色板，和主图均线不是一个顺序")
      #expect(classic.palette.count == 6 && classic.sub.count == 6)
      // 主图 MA10 / MA30 = 黄 / 紫；OI 青绿
      #expect(classic.palette[0] == "#FFB400" && classic.palette[1] == "#E849B9")
      #expect(classic.palette[5] == "#2FD2B2")
      // 副图 DIF / DEA = 青绿 / 黄
      #expect(classic.sub[0] == "#2FD2B2" && classic.sub[1] == "#FFB400")
    }
    // 浅色蜡烛是用户 iPhone 截图实测的众数；MA120 / MA256 浅色压深
    #expect(Palette.classicSeed.up == "#36B257" && Palette.classicSeed.down == "#E64552")
    #expect(Palette.classicSeed.palette[2] == "#6EBF26" && Palette.classicSeed.palette[3] == "#F55B58")
    #expect(Palette.classicNightSeed.up == "#2F9347" && Palette.classicNightSeed.down == "#CC3333")
    #expect(Palette.classicSeed.app == "#F7F9FF" && Palette.classicSeed.raised == "#FFFFFF")
    #expect(Palette.classicNightSeed.app == Palette.nightCanvas.bg, "夜里图里图外同一块深蓝")
    // 青苔、陶土没给副图色板，就跟主图同一组
    for seed in [Palette.sageSeed, Palette.sageNightSeed, Palette.terraSeed, Palette.terraNightSeed] {
      #expect(seed.sub == seed.palette)
    }
  }
}
