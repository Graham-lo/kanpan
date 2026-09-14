import Foundation
import KanpanCore

/// 外观三档（A6.3）。原型 `S.theme` 存的是 `'auto' | 'light' | 'dark'`，
/// 存档里的字面量照抄原型，不自己换词。
enum ThemeChoice: String, Sendable, Codable, CaseIterable, Hashable {
  case system = "auto"
  case light
  case dark
  case paper
  case night

  /// 面板上的三个字。原型 `renderSettings` / `renderStyleSheet` 里逐字如此。
  var display: String {
    switch self {
    case .system: "跟随系统"
    case .light: "浅色"
    case .dark: "深色"
    case .paper: "护眼"
    case .night: "夜读"
    }
  }

  func seed(systemDark: Bool) -> PaletteSeed {
    switch self {
    case .system: systemDark ? Palette.darkSeed : Palette.lightSeed
    case .light: Palette.lightSeed
    case .dark: Palette.darkSeed
    case .paper: Palette.paperSeed
    case .night: Palette.nightSeed
    }
  }

  static let fallback: ThemeChoice = .system

  /// 分段控件那三格，顺序与原型一致。
  static let options: [(String, ThemeChoice)] = allCases.map { ($0.display, $0) }
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

  static let options: [(String, SubPaneHeight)] = allCases.map { ($0.display, $0) }
}
