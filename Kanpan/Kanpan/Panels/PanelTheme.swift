import SwiftUI
import KanpanCore

/// 面板用色。只有「靛」这一套，浅深各一版（§6），令牌名与原型 `styles.js` 一一对应。
///
/// 面板里**不许直接写颜色**，一律从这儿取——和图表共用 `Palette`，
/// 所以「涨跌对调」只要改 `redUp`，开关的绿、胶囊的红就一起跟着换（A6.7）。
struct PanelTheme: Sendable, Equatable {
  var seed: PaletteSeed
  var chart: ChartColors

  init(dark: Bool, redUp: Bool = false) {
    seed = dark ? Palette.darkSeed : Palette.lightSeed
    chart = Palette.chart(dark: dark, redUp: redUp)
  }

  var dark: Bool { seed.dark }

  // 底 / 面
  var app: Color { Color(hex: chart.bg) }
  var raised: Color { Color(hex: seed.raised) }
  var raised2: Color { Color(hex: seed.raised2) }
  var chartBG: Color { Color(hex: seed.chart) }

  // 线
  var line: Color { Color(hex: seed.line) }
  /// 比 `line` 更轻的行分隔（原型 `--hair`）。
  var hair: Color { Color(hex: chart.hair) }

  // 字
  var ink: Color { Color(hex: seed.ink) }
  var ink2: Color { Color(hex: seed.ink2) }
  var ink3: Color { Color(hex: seed.ink3) }

  // 琥珀：当前项、强调
  var amber: Color { Color(hex: seed.amber) }
  var amberSoft: Color { Color(hex: chart.amberSoft) }
  var amberLine: Color { Color(hex: chart.amberLine) }

  /// 涨 / 跌，已按 `redUp` 对调。
  var up: Color { Color(hex: chart.up) }
  var down: Color { Color(hex: chart.down) }

  /// 分段控件选中那一格的底（原型 `--seg-on`）。
  var badgeInk: Color { dark ? app : .white }
  var segOn: Color { seed.dark ? Color(hex: seed.raised) : .white }
  /// 开关关着时的槽（`--sw-off`）。
  var switchOff: Color { seed.dark ? Color(hex: seed.raised2) : Color(hex: seed.line) }
  /// 开关的圆钮（`--sw-knob`）。
  var switchKnob: Color { seed.dark ? Color(hex: seed.ink3) : .white }
  /// 开关开着时的槽：涨色 42% 透明（原型 `color-mix(… var(--up) 42%)`）。
  var switchOn: Color { up.opacity(0.42) }

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
