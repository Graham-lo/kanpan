import SwiftUI

// 全 app 共用的设计令牌（2026-09-24 UI 对照苹果 HIG 审查后定的，见
// docs/acceptance/UI审查-2026-09-24/汇总.md）。以后界面上的字号、间距、圆角、命中区
// 一律从这儿取，不再各处手写数字——审查前全 app 有 21 个字号值、14 个圆角值，
// 一半 padding 不在 4pt 网格上，设计师看一眼就说「怪」。
//
// 这里只管图区**以外**的界面。K 线画布里的刻度字、指标标签是复刻 AICoin 的，不归它管。

// MARK: - 字号阶梯

/// 只用 HIG Dynamic Type 的档：22 / 17 / 16 / 15 / 13 / 12 / 11。默认档（.large）下就是这些数，
/// 调系统文字大小时跟着显式指定的语义档走（不靠 `nearestStyle` 猜）。
/// 字重只用 regular / medium / semibold，不用 bold；同一块内容里最多两种。
enum TypeScale {
  /// 22 · 行情页最新价，全 app 唯一一处 22。数字调用处加 `.monospacedDigit()`。
  static let price = ScaledFont(22, .medium, relativeTo: .title2)
  /// 17 semibold · 整页 / 面板标题（与系统行内导航标题同级）。
  static let title = ScaledFont(17, .semibold, relativeTo: .headline)
  /// 16 semibold · 区块标题：行情页品种名、卡片标题（设计师说的「主标题 16」）。
  static let heading = ScaledFont(16, .semibold, relativeTo: .callout)
  /// 15 · 列表行名、输入框、正文。原来的 14 medium 一律并到这里，字重降成 regular 抵掉那 1pt。
  static let body = ScaledFont(15, .regular, relativeTo: .subheadline)
  static let bodyEmph = ScaledFont(15, .medium, relativeTo: .subheadline)
  /// 13 · 控件字：周期条、分段、药丸、Toast、动作按钮（原 12.5 / 12 medium 并到这里）。
  static let control = ScaledFont(13, .medium, relativeTo: .footnote)
  static let controlOn = ScaledFont(13, .semibold, relativeTo: .footnote)
  /// 13 · 次级数字与次级信息：涨跌小字、行内次要信息。
  static let footnote = ScaledFont(13, .regular, relativeTo: .footnote)
  static let footnoteEmph = ScaledFont(13, .medium, relativeTo: .footnote)
  /// 12 · 说明、计价币、六格的值（设计师说的「副标题 12」）。
  static let caption = ScaledFont(12, .regular, relativeTo: .caption)
  static let captionEmph = ScaledFont(12, .medium, relativeTo: .caption)
  /// 11 · 下限：六格标签、分组标题、角标。**不许再小。**
  static let caption2 = ScaledFont(11, .regular, relativeTo: .caption2)
  static let caption2Emph = ScaledFont(11, .medium, relativeTo: .caption2)
  /// 12 等宽 · 面板里会步进的数字（原 `PanelFont.number`）。
  static let number = ScaledFont(12, .medium, design: .monospaced, relativeTo: .caption)
}

// MARK: - 间距（4pt 网格）

enum Space {
  /// 一组里的两行（价格 ↔ 涨跌）。
  static let xxs: CGFloat = 2
  static let xs: CGFloat = 4
  static let s: CGFloat = 8
  static let m: CGFloat = 12
  static let l: CGFloat = 16
  static let xl: CGFloat = 20
  static let xxl: CGFloat = 24
  static let section: CGFloat = 32
}

// MARK: - 内边距（外容器 / 内容器）

enum Inset {
  /// 页面外边距：iPhone 16 Pro（402pt）16，iPhone 17 Pro Max（440pt）20。
  /// 设计师说的「外容器 20」落在大屏上；系统自己的布局边距也是这样分的。
  static func page(_ width: CGFloat) -> CGFloat { width >= 428 ? 20 : 16 }
  /// 卡片 / 浮层内边距（「内容器 16」）。
  static let card: CGFloat = 16
  /// 紧凑卡片：详情卡、Toast、提示条。
  static let cardCompact: CGFloat = 12
  /// 行的竖向内边距。
  static let rowV: CGFloat = 12
  /// 行最小高度（= 命中区）。
  static let rowMin: CGFloat = 44
}

// MARK: - 圆角（四档 + 胶囊；嵌套时同心）

enum Radius {
  /// 标签、角标、色块。
  static let xs: CGFloat = 4
  /// 输入框、缩略图、卡片里的小格。
  static let s: CGFloat = 8
  /// 卡片、浮层、网格格子。
  static let m: CGFloat = 12
  /// 抽屉、弹层、分享面板。
  static let l: CGFloat = 16
  /// 内圆角 = 外圆角 − 内边距（WWDC25「Build a SwiftUI app with the new design」），最低 4。
  static func concentric(outer: CGFloat, padding: CGFloat) -> CGFloat { max(outer - padding, xs) }
}
// 药丸、按钮一律 `Capsule()`；sheet 的圆角交给系统，不再 `presentationCornerRadius`。

// MARK: - 命中区

enum Hit {
  static let min: CGFloat = 44
}

extension View {
  /// 画面不变，把可点区撑到 44×44（顶栏 iconButton 原来就是这种写法）。
  func hitTarget(_ side: CGFloat = Hit.min) -> some View {
    frame(minWidth: side, minHeight: side).contentShape(Rectangle())
  }
}

// MARK: - 控件尺寸

enum ControlMetrics {
  /// 周期档位、动作药丸（iOS 26 small 控件高）。
  static let pillHeight: CGFloat = 28
  /// 顶栏圆托底（32 + 间距 12 = 步距 44）。
  static let iconDisc: CGFloat = 32
  /// 头部品种徽章。
  static let badge: CGFloat = 28
  /// 列表行徽章（自选「琉璃」行的 33 是用户定稿，例外保留）。
  static let listBadge: CGFloat = 32
  /// 列表箭头统一一个尺寸（原来 9 / 10 / 11 三种）。
  static let chevron: CGFloat = 12
  /// 禁用态不透明度（原来 0.35 / 0.4 / 0.45 三种）。
  static let disabledOpacity: Double = 0.4
  /// 空态那一枚图标（UI 审查 2026-09-24：空态 = 36 图标 + 15 字，不写解释句）。
  static let emptyGlyph: CGFloat = 36
}
