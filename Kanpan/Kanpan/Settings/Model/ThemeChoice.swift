import Foundation
import KanpanCore

/// 配色三套：青苔（冷）、陶土（暖）与经典（白）。出厂是青苔。
///
/// 经典是青苔换了一张 AICoin 的白底（深色是 AICoin 夜间的深蓝底），文字、涨跌、
/// 强调色全和青苔一样——它存在的意义就是让图里图外同一张纸。
///
/// 这一层只决定**颜色**。K 线底座的形状、尺寸，以及指标那几行读数的排布，
/// 一个字都不经过这里——换配色换的只有 `PaletteSeed` 里那十几个色值。
enum ThemeSkin: String, Sendable, Codable, CaseIterable, Hashable {
  case sage
  case terra
  case classic

  var display: String {
    switch self {
    case .sage: "青苔"
    case .terra: "陶土"
    case .classic: "经典"
    }
  }

  /// 卡片上那行小字。只说冷暖和主色，不写使用说明。
  var note: String {
    switch self {
    case .sage: "冷 · 墨绿"
    case .terra: "暖 · 赤陶"
    case .classic: "白 · 墨绿"
    }
  }

  func seed(dark: Bool) -> PaletteSeed {
    switch self {
    case .sage: dark ? Palette.sageNightSeed : Palette.sageSeed
    case .terra: dark ? Palette.terraNightSeed : Palette.terraSeed
    case .classic: dark ? Palette.classicNightSeed : Palette.classicSeed
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

