import SwiftUI

/// 术语标签后面那颗小问号：12pt 的细圈里一个「?」，点了在屏幕正中弹 `GlossaryCard`。
///
/// 用法——紧跟在短标签后面，放进同一个 `HStack(spacing: 0)`（问号自己带 3pt 的左距）：
///
/// ```swift
/// HStack(spacing: 0) {
///   Text("仓").font(TypeScale.caption2).foregroundStyle(theme.ink3)
///   TermMark(.openInterest)          // 面板 / sheet 里：皮肤从环境里读
///   // TermMark(.openInterest, theme: theme)  // 没注入 panelTheme 的页面手递一份
/// }
/// ```
///
/// - **颜色跟着所在的文字**：用的是当前的 `foregroundStyle`，再压到 55% 不透明度——
///   它是标签的一个附注，不该比标签本身更抢眼。
/// - **命中区 ≥ 32×32，但不撑大排版**：画出来 12pt，点击框用 `contentShape` 撑到 32，
///   外面再用负边距把版面收回 12，所在那一行一个 pt 都不变高、不变宽。
/// - **点按不吞横滑**：用的是 `onTapGesture` 而不是 `Button`。父视图上的
///   `DragGesture(minimumDistance: 20)`（行情页价格区的横滑扫图）在手指一动就接手，
///   从问号上起手横划照样换品种。
/// - 无障碍标识是 `term.<id>`，读屏念「<标题> 说明」。
/// - 卡片怎么弹到最上层见 `GlossaryPresenter`：半屏面板、系统 sheet、横屏画线台里都一样。
struct TermMark: View {
  let term: GlossaryTerm
  /// 卡片用哪套皮肤。不给就读环境里的 `panelTheme`（面板、sheet 里都注入了）；
  /// 行情页头部这类自己手递 `theme` 的地方把它传进来。
  private let explicitTheme: PanelTheme?
  @Environment(\.panelTheme) private var envTheme
  private var theme: PanelTheme { explicitTheme ?? envTheme }

  init(_ term: GlossaryTerm, theme: PanelTheme? = nil) {
    self.term = term
    self.explicitTheme = theme
  }

  /// 画出来的圈多大。
  static let size: CGFloat = 12
  /// 手指够得着的方框。
  static let hit: CGFloat = 32
  /// 和前面标签的间距。
  static let gap: CGFloat = 3

  var body: some View {
    ZStack {
      Circle().strokeBorder(lineWidth: 1)
      Text("?")
        .font(.system(size: 8.5, weight: .bold, design: .rounded))
        .baselineOffset(0.5)
    }
    .frame(width: Self.size, height: Self.size)
    .opacity(0.55)
    // 点击框撑到 32×32，再用负边距把版面收回 12×12。
    .frame(width: Self.hit, height: Self.hit)
    .contentShape(Rectangle())
    .onTapGesture { GlossaryPresenter.present(term, theme: theme) }
    .padding(-(Self.hit - Self.size) / 2)
    .padding(.leading, Self.gap)
    .accessibilityElement()
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(term.title + " 说明")
    .accessibilityIdentifier("term." + term.id)
    .accessibilityAction { GlossaryPresenter.present(term, theme: theme) }
  }
}
