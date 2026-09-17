import Foundation
import KanpanCore

/// 配色两套：青苔（冷）与陶土（暖）。出厂是青苔。
///
/// 这一层只决定**颜色**。K 线底座的形状、尺寸，以及指标那几行读数的排布，
/// 一个字都不经过这里——换配色换的只有 `PaletteSeed` 里那十几个色值。
enum ThemeSkin: String, Sendable, Codable, CaseIterable, Hashable {
  case sage
  case terra

  var display: String {
    switch self {
    case .sage: "青苔"
    case .terra: "陶土"
    }
  }

  /// 卡片上那行小字。只说冷暖和主色，不写使用说明。
  var note: String {
    switch self {
    case .sage: "冷 · 墨绿"
    case .terra: "暖 · 赤陶"
    }
  }

  func seed(dark: Bool) -> PaletteSeed {
    switch self {
    case .sage: dark ? Palette.sageNightSeed : Palette.sageSeed
    case .terra: dark ? Palette.terraNightSeed : Palette.terraSeed
    }
  }

  static let fallback: ThemeSkin = .sage
}

/// 深浅三档（A6.3）。存档里的字面量照抄原型，不自己换词。
///
/// 配色和深浅是两根独立的轴：选了陶土照样可以跟随系统深浅，这是原来
/// 「护眼 / 夜读」那种把配色和深浅焊在一起的写法给不了的。
enum ThemeChoice: String, Sendable, Codable, CaseIterable, Hashable {
  case system = "auto"
  case light
  case dark

  var display: String {
    switch self {
    case .system: "跟随系统"
    case .light: "浅色"
    case .dark: "深色"
    }
  }

  func seed(skin: ThemeSkin, systemDark: Bool) -> PaletteSeed {
    switch self {
    case .system: skin.seed(dark: systemDark)
    case .light: skin.seed(dark: false)
    case .dark: skin.seed(dark: true)
    }
  }

  static let fallback: ThemeChoice = .system
}

/// 副图高度三档（任务书 A6.4 / §10.6「每个副图有 小 / 中 / 大 三档高度」）。
///
/// 原型没有这一项——它的副图高度完全由风格表的 `subH` 定死。所以这里只加一个
/// **倍率**：中档就是风格给的那个数，小 / 大在它上下各让一档，风格换了跟着换。
/// 下限 44pt 来自 §10.6「最小 44pt」。
enum SubPaneHeight: String, Sendable, Codable, CaseIterable, Hashable {
  case small, medium, large

  var display: String {
    switch self {
    case .small: "小"
    case .medium: "中"
    case .large: "大"
    }
  }

  var scale: Double {
    switch self {
    case .small: 0.75
    case .medium: 1.0
    case .large: 1.3
    }
  }

  /// 某款风格下这一档实际多高。`base` 传 `CandleStyle.subH`。
  func points(base: Double) -> Double { max(44, (base * scale).rounded()) }

  static let fallback: SubPaneHeight = .medium
}
