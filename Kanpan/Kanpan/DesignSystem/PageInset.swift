import SwiftUI
import UIKit

/// 页面左右外边距（`Inset.page`）的落地写法：量自己这一整行有多宽，按宽度给 16 / 20。
///
/// 行情页头部、周期条、十字线动作条、「更多」弹层要站在**同一条竖线**上（UI 审查 2026-09-24
/// §4.3 #1 / #23 / #27 / #28），各自挂这一句就行，不必从主屏一路把宽度传下来——
/// `MainScreen` 的 body 链有类型嵌套深度的上限，不能再往上面加修饰器。
///
/// 量的是**加过边距之后**的整行（也就是页面宽），所以不会「边距改了宽度、宽度又改边距」地来回跳。
/// 第一帧还没量到时按当前屏幕宽度先猜一个，17 Pro Max 上不会先画 16 再跳到 20。
private struct PageHorizontalInset: ViewModifier {
  @State private var width: CGFloat = PageHorizontalInset.screenWidth

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, Inset.page(width))
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
  }

  @MainActor private static var screenWidth: CGFloat {
    let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
    guard let bounds = scene?.screen.bounds else { return 0 }
    return min(bounds.width, bounds.height)
  }
}

extension View {
  /// 左右各留一份页面外边距（`Inset.page`：宽 ≥ 428 为 20，否则 16）。见 `PageHorizontalInset`。
  func pageHorizontalInset() -> some View {
    modifier(PageHorizontalInset())
  }
}

// MARK: - 面板零件在整页上的边距

/// `PanelRow`、`PanelGroupTitle`、`PanelSheet` 左右留多少。默认是面板那一份 `Inset.card`（16）：
/// 半屏面板自带边距，不跟页面宽走。
private struct PanelHPadKey: EnvironmentKey {
  static let defaultValue: CGFloat = Inset.card
}

extension EnvironmentValues {
  /// 面板零件的左右内边距。面板零件被拿去拼**整页**（设置页、提醒总表）时由 `panelPageInset()`
  /// 改成页面外边距，这样行文、分组标题、皮肤卡和页面上别的东西站在同一条竖线上。
  var panelHPad: CGFloat {
    get { self[PanelHPadKey.self] }
    set { self[PanelHPadKey.self] = newValue }
  }
}

/// 量这一整页有多宽，按 `Inset.page` 把 `panelHPad` 灌下去（16 / 20）。量法与 `PageHorizontalInset` 同。
private struct PanelPageInset: ViewModifier {
  @State private var width: CGFloat = PanelPageInset.screenWidth

  func body(content: Content) -> some View {
    content
      .environment(\.panelHPad, Inset.page(width))
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
  }

  @MainActor private static var screenWidth: CGFloat {
    let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
    guard let bounds = scene?.screen.bounds else { return 0 }
    return min(bounds.width, bounds.height)
  }
}

extension View {
  /// 这一整页里的面板零件（`PanelRow` 等）左右改用页面外边距（`Inset.page`）。整页用，半屏面板别用。
  func panelPageInset() -> some View {
    modifier(PanelPageInset())
  }
}
