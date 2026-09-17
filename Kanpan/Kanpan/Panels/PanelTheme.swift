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

  init(seed: PaletteSeed, redUp: Bool = false) {
    self.seed = seed
    chart = Palette.chart(seed, redUp: redUp)
  }
  init(dark: Bool, redUp: Bool = false) {
    self.init(seed: dark ? Palette.darkSeed : Palette.lightSeed, redUp: redUp)
  }

  var dark: Bool { seed.dark }

  // 底 / 面
  var app: Color { Color(hex: chart.bg) }
  var raised: Color { Color(hex: seed.raised) }
  var raised2: Color { Color(hex: seed.raised2) }
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

  /// 涨 / 跌，已按 `redUp` 对调。
  var up: Color { Color(hex: chart.up) }
  var down: Color { Color(hex: chart.down) }

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
  var switchOff: Color { seed.dark ? Color(hex: seed.raised2) : Color(hex: seed.line) }
  /// 开关的圆钮（原型 `.sw:after`）：开关两态都是白的，靠槽的颜色区分开关，
  /// 不靠钮的颜色——钮换色时那一小片白在深色里会整个消失，看着像钮没了。
  var switchKnob: Color { .white }
  /// 开关开着时的槽（原型 `.sw.on { background: var(--accBg) }`）。
  ///
  /// 这儿原来取的是涨色，于是把「红涨绿跌」一打开，设置页上十几个开关全变成红的，
  /// 像一排警告。开关跟涨跌没有关系，它表达的是「这一项当前生效」，
  /// 和周期药丸、底栏选中格是同一件事，所以一律用配色自己的强调色。
  var switchOn: Color { amber }

  /// 指标色标：OI 与 BOLL 自己一色，其余取调色板第一支（原型 `swatch`）。
  func swatch(_ id: IndicatorID) -> Color {
    switch id {
    case .oi: Color(hex: chart.oi)
    case .boll: Color(hex: chart.band)
    default: Color(hex: chart.palette[0])
    }
  }
}

// MARK: - 字

/// 面板的字号字重，照原型 CSS 抄的（`.row .name` 是 500 14px，`.meta` 是 400 11px…）。
enum PanelFont {
  static let name = Font.system(size: 14, weight: .medium)
  static let meta = Font.system(size: 11)
  static let title = Font.system(size: 15, weight: .semibold)
  static let sub = Font.system(size: 11)
  static let group = Font.system(size: 11, weight: .medium)
  static let seg = Font.system(size: 12, weight: .medium)
  static let note = Font.system(size: 11.5)
  static let cardName = Font.system(size: 14, weight: .semibold)
  static let cardOne = Font.system(size: 10.5)
  static let cardBet = Font.system(size: 11)
  /// 数字一律等宽，免得步进时左右跳。
  static let number = Font.system(size: 11, weight: .medium, design: .monospaced)
}


/// 面板横向留白，原型 `.row { padding: 11px 16px }`。
enum PanelMetrics {
  static let hPad: CGFloat = 16
  static let vPad: CGFloat = 11
  static let rowGap: CGFloat = 10
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
