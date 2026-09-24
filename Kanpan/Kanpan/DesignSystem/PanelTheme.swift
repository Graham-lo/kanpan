import SwiftUI
import KanpanCore

/// 面板用色。两套配色（青苔 / 陶土）各有浅深两版，令牌名与原型 `styles.js` 一一对应。
///
/// 面板里**不许直接写颜色**，一律从这儿取——和图表共用同一份 `PaletteSeed`，
/// 换配色只换种子，面板和图表一起跟着换；涨跌对调只影响涨跌那两支
/// （`up` / `down` / `badgeFill`），别的地方一概不受它牵连。
struct PanelTheme: Sendable, Equatable {
  var seed: PaletteSeed
  var chart: ChartColors
  /// 图外文字上的涨跌色（`Palette.inkUp` / `inkDown`），已按 `redUp` 对调。
  private var inkUpHex: Hex
  private var inkDownHex: Hex

  init(seed: PaletteSeed, redUp: Bool = false) {
    self.seed = seed
    chart = Palette.chart(seed, redUp: redUp)
    inkUpHex = Palette.inkUp(seed, redUp: redUp)
    inkDownHex = Palette.inkDown(seed, redUp: redUp)
  }
  init(dark: Bool, redUp: Bool = false) {
    self.init(seed: dark ? Palette.darkSeed : Palette.lightSeed, redUp: redUp)
  }

  var dark: Bool { seed.dark }

  // 底 / 面
  /// 图区**以外**那张大底：面板、列表、底栏、头部全站在它上面，跟着皮肤走。
  ///
  /// 这儿原来取的是 `chart.bg`——那会儿种子里 `app` 和 `chart` 本来就是同一个值，
  /// 取哪个都一样，还顺带保证了「上下不出拼缝」。2026-09-17 画布改成固定的 AICoin 之后
  /// 这条捷径就反了：整屏会跟着画布一起变成纯白 / 深蓝，皮肤等于没换。
  /// 所以改回从种子取，画布归画布（`chartBG`），图区外归皮肤。
  var app: Color { Color(hex: seed.app) }
  var raised: Color { Color(hex: seed.raised) }
  var raised2: Color { Color(hex: seed.raised2) }
  /// 画布本身：固定的 AICoin 底，不跟皮肤走（见 `Palette.dayCanvas` / `nightCanvas`）。
  var chartBG: Color { Color(hex: chart.bg) }

  // 线
  var line: Color { Color(hex: seed.line) }
  /// 比 `line` 更轻的行分隔（原型 `--hair`）。
  var hair: Color { Color(hex: chart.hair) }

  // 字
  var ink: Color { Color(hex: seed.ink) }
  var ink2: Color { Color(hex: seed.ink2) }
  var ink3: Color { Color(hex: Palette.secondaryInk(seed)) }

  // 强调：当前项、动作字、选中态。名字还叫 `amber` 是因为全 app 几百处都这么写着，
  // 换名字的收益抵不上一次全量改动的风险；它取的是配色自己的强调色（青苔的墨绿、
  // 陶土的赤陶），不是画在图上那支暖色（那支仍叫 `chart.amber`）。
  var amber: Color { Color(hex: seed.accent) }
  var amberSoft: Color { Color(hex: seed.accent.alpha(dark ? "24" : "1A")) }
  var amberLine: Color { Color(hex: seed.accent.alpha("66")) }

  /// 图外**文字**上的涨 / 跌，已按 `redUp` 对调。
  ///
  /// 浅色下比蜡烛色深一档（`Palette.inkDayUp` / `inkDayDown`），为的是小字对页面底够 4.5:1；
  /// 图上画的东西、以及「这是图上那支颜色」的预览（蜡烛缩略、指标色标、徽章底）
  /// 一律取 `chart.up` / `chart.down`，不要拿这两支去画。
  var up: Color { Color(hex: inkUpHex) }
  var down: Color { Color(hex: inkDownHex) }

  /// 警示：删除、注销、报错这类「不可逆 / 出事了」的动作字（见 `PaletteSeed.danger`）。
  ///
  /// **别拿 `down` 当它使。** 出厂是红涨绿跌（`Prefs.redUp` 默认 `true`），跌色是绿的，
  /// 于是「删除」会变成一个绿按钮，读起来像「确认」；而且它还跟着一个跟删除毫无关系的
  /// 设置翻来翻去。`up` 同理——它碰巧是红的，但语义仍然是「涨」。
  /// 这一支是从种子直接取的，不经过 `Palette.chart` 的 `redUp` 对调。
  var danger: Color { Color(hex: seed.danger) }

  /// 分段控件选中那一格的底（原型 `--seg-on`）。
  var badgeInk: Color { Color(hex: pillInk) }
  private var pillInk: Hex { dark ? seed.ground : "#FFFFFF" }
  func badgeFill(up: Bool) -> Color {
    let base = up ? chart.up : chart.down
    let amount = Palette.isWarm(seed) ? 0.9 : (dark ? 1 : 0.92)
    let fill = Palette.mix(base, dark ? Hex("#000000") : seed.ink, amount: amount)
    return Color(hex: Palette.readable(fill, on: [pillInk], toward: seed.ink))
  }
  var segOn: Color { Color(hex: seed.raised) }
  /// 开关关着时的槽（`--sw-off`）。
  var switchOff: Color { controlLine }
  /// 开关的圆钮（原型 `.sw:after`）：开关两态都是白的，靠槽的颜色区分开关，
  /// 不靠钮的颜色——钮换色时那一小片白在深色里会整个消失，看着像钮没了。
  var switchKnob: Color { .white }
  /// 开关开着时的槽（原型 `.sw.on { background: var(--accBg) }`）。
  ///
  /// 这儿原来取的是涨色，于是把「红涨绿跌」一打开，设置页上十几个开关全变成红的，
  /// 像一排警告。开关跟涨跌没有关系，它表达的是「这一项当前生效」，
  /// 和周期药丸、底栏选中格是同一件事，所以一律用配色自己的强调色。
  var switchOn: Color { amber }

  /// 指标色标：持仓量与布林带自己一色，超级趋势/抛物线转向按多空换色所以取涨那一支，
  /// 其余取自己在调色板上的起始那一支（`IndicatorID.paletteOffset`，和图上第一条线同色）。
  func swatch(_ id: IndicatorID) -> Color {
    switch id {
    case .oi: Color(hex: chart.oi)
    case .boll: Color(hex: chart.band)
    case .supertrend, .sar, .orderFlow: Color(hex: chart.up)
    default: Color(hex: chart.palette[id.paletteOffset % chart.palette.count])
    }
  }
}

// MARK: - 字

/// 跟随系统「文字大小」的设计字号（P2.13）。
///
/// 界面上的字号都是照原型 CSS 一个 pt 一个 pt 抄的（14、11.5、10.5…），系统的语义档
/// （`.subheadline` = 15、`.caption` = 12…）对不上，换过去默认档下整页都会变样。所以
/// 设计字号照旧写死，只是不再是死数：交给 `@ScaledMetric` 按最接近的那一档语义字号的
/// 曲线放大缩小——默认档（`.large`）下一个 pt 都不变，调大调小时和系统自家的字一起走。
///
/// `Font.system(size:)` 没有 `relativeTo:`（只有 `Font.custom` 有），`@ScaledMetric`
/// 又只能待在视图里，所以这儿是一份「字号说明」，由 `View.font(_:)` 的重载在视图里兑现。
/// 调用处写 `.font(.scaled(13, .semibold))`、`.font(PanelFont.name)`，和原来一样读。
///
/// 放大到哪一档为止不在这儿管：整个 app 在根上封顶 `.xxxLarge`（`KanpanApp`），
/// 行情页头部那一行更低、封顶 `MarketChrome.typeCap`（`.large`，见 `MainHeaderView`）。
struct ScaledFont: Equatable {
  var size: CGFloat
  var weight: Font.Weight = .regular
  var design: Font.Design = .default
  /// 跟着哪一档语义字号的曲线走。不给就按字号挑最接近的那一档。
  var style: Font.TextStyle

  init(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default,
       relativeTo style: Font.TextStyle? = nil) {
    self.size = size
    self.weight = weight
    self.design = design
    self.style = style ?? Self.nearestStyle(size)
  }

  static func scaled(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default,
                     relativeTo style: Font.TextStyle? = nil) -> ScaledFont {
    ScaledFont(size, weight, design: design, relativeTo: style)
  }

  /// 各语义档在默认档下的字号：caption2 11 · caption 12 · footnote 13 · subheadline 15 ·
  /// callout 16 · body 17 · title3 20 · title2 22 · title 28。
  static func nearestStyle(_ size: CGFloat) -> Font.TextStyle {
    switch size {
    case ..<11.5: .caption2
    case ..<12.5: .caption
    case ..<14: .footnote
    case ..<15.5: .subheadline
    case ..<16.5: .callout
    case ..<18.5: .body
    case ..<21: .title3
    case ..<25: .title2
    default: .title
    }
  }
}

private struct ScaledFontModifier: ViewModifier {
  @ScaledMetric private var size: CGFloat
  private let spec: ScaledFont

  init(_ spec: ScaledFont) {
    self.spec = spec
    _size = ScaledMetric(wrappedValue: spec.size, relativeTo: spec.style)
  }

  func body(content: Content) -> some View {
    content.font(.system(size: size, weight: spec.weight, design: spec.design))
  }
}

extension View {
  /// 设计字号 + 跟随系统文字大小。见 `ScaledFont`。
  func font(_ spec: ScaledFont) -> some View {
    modifier(ScaledFontModifier(spec))
  }
}

/// 面板的字号字重。原来照原型 CSS 抄（`.row .name` 是 500 14px、`.meta` 是 400 11px…），
/// 2026-09-24 UI 审查后改为指向 `TypeScale` 的阶梯（14 → 15、11 → 12、12.5 → 13 …），
/// 名字保留，调用处不用动。
enum PanelFont {
  static let name = TypeScale.body            // 14 medium → 15 regular
  static let meta = TypeScale.caption         // 11 → 12
  static let title = TypeScale.title          // 15 semibold → 17 semibold
  static let sub = TypeScale.caption          // 11 → 12
  static let group = TypeScale.caption2Emph   // 11 medium → 11 medium（下限）
  static let seg = TypeScale.control          // 12 medium → 13 medium
  static let note = TypeScale.caption         // 11.5 → 12
  static let cardName = TypeScale.bodyEmph    // 14 semibold → 15 medium
  /// 数字一律等宽，免得步进时左右跳。
  static let number = TypeScale.number        // 11 → 12 等宽
}

/// 面板留白：横向 16（sheet 自带边距），行竖向 12，行距 12；行最小高 `Inset.rowMin` 44。
enum PanelMetrics {
  static let hPad: CGFloat = Inset.card
  static let vPad: CGFloat = Inset.rowV
  static let rowGap: CGFloat = Space.m
}

// MARK: - 环境

private struct PanelThemeKey: EnvironmentKey {
  static let defaultValue = PanelTheme(dark: false)
}

extension EnvironmentValues {
  /// 面板树里随手可取的一份主题。`PrefsPanel` 会按当前深浅和 `redUp` 灌进去。
  var panelTheme: PanelTheme {
    get { self[PanelThemeKey.self] }
    set { self[PanelThemeKey.self] = newValue }
  }
}

// MARK: - Hex → Color

extension Color {
  /// `Hex` → SwiftUI `Color`。
  ///
  /// 原先住在 `LaunchScreen.swift` 里，注释写着「Theme 层做好之前先放这儿」；
  /// Theme 层就是这个文件，那张 M0 的空壳首屏早已没人用（真正的启动屏是系统按
  /// `Info.plist` 里 `UILaunchScreen` 画的），所以随文件一起搬到了这儿。
  init(hex: Hex) {
    let c = hex.rgba
    self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
  }
}
