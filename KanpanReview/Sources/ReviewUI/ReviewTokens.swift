import SwiftUI

// ============================================================ 复盘包里的设计令牌
//
// `ReviewUI` 是独立的包，看不到 app 里那份 `DesignSystem/DesignTokens.swift`（`TypeScale` /
// `Space` / `Inset` / `Radius` / `Hit` / `ControlMetrics`），所以在这儿**逐项抄一份同值的**，
// 每一项都注明对的是 app 那边哪一个。以后改令牌要两边一起改——这儿不许自己长出新数。
//
// 字号走系统语义档（默认档下与 `TypeScale` 同一个数，调系统文字大小时跟同一条曲线走，
// 等价于 app 那边 `ScaledFont(…, relativeTo:)`）。

/// 对应 `TypeScale`。
enum ReviewType {
  /// `TypeScale.title`：17 semibold（`.headline`）。
  static let title = Font.headline
  /// `TypeScale.heading`：16 semibold（`.callout`）。
  static let heading = Font.callout.weight(.semibold)
  /// `TypeScale.body`：15 regular（`.subheadline`）。
  static let body = Font.subheadline
  /// `TypeScale.bodyEmph`：15 medium。
  static let bodyEmph = Font.subheadline.weight(.medium)
  /// `TypeScale.control`：13 medium（`.footnote`）。
  static let control = Font.footnote.weight(.medium)
  /// `TypeScale.controlOn`：13 semibold。
  static let controlOn = Font.footnote.weight(.semibold)
  /// `TypeScale.footnote`：13 regular。
  static let footnote = Font.footnote
  /// `TypeScale.caption`：12 regular（`.caption`）。
  static let caption = Font.caption
  /// `TypeScale.captionEmph`：12 medium——分组标题用它。
  static let captionEmph = Font.caption.weight(.medium)
  /// `TypeScale.caption2`：11 regular（`.caption2`），全包最小的字。
  static let caption2 = Font.caption2
  /// 战绩摘要卡的三个数：17 semibold 等宽数字（`TypeScale.title` 加 `monospacedDigit`）。
  static let stat = Font.headline.monospacedDigit()
  /// 战绩页的胜率：20 semibold 等宽数字（`.title3`；HIG 字号阶梯里 17 之上那一档）。
  static let rate = Font.title3.weight(.semibold).monospacedDigit()
}

/// 对应 `Space`（4pt 网格）。
enum ReviewSpace {
  static let xxs: CGFloat = 2
  static let xs: CGFloat = 4
  static let s: CGFloat = 8
  static let m: CGFloat = 12
  static let l: CGFloat = 16
  static let xl: CGFloat = 20
  static let xxl: CGFloat = 24
}

/// 对应 `Inset`。
enum ReviewInset {
  /// `Inset.page`：页面左右外边距，宽 ≥ 428 为 20，否则 16。
  static func page(_ width: CGFloat) -> CGFloat { width >= 428 ? 20 : 16 }
  /// `Inset.card`：卡片内边距 16。
  static let card: CGFloat = 16
  /// `Inset.cardCompact`：紧凑卡片 12。
  static let cardCompact: CGFloat = 12
}

/// 对应 `Radius`。
enum ReviewRadius {
  static let xs: CGFloat = 4
  static let s: CGFloat = 8
  static let m: CGFloat = 12
  static let l: CGFloat = 16
  /// `Radius.concentric`：套在里面那一层的圆角 = 外圆角 − 间距，最小 `xs`。
  static func concentric(outer: CGFloat, padding: CGFloat) -> CGFloat { max(outer - padding, xs) }
}

/// 对应 `Hit` 与 `ControlMetrics`。
enum ReviewControl {
  /// `Hit.min`：HIG 最小点按区 44。
  static let hit: CGFloat = 44
  /// `ControlMetrics.pillHeight`：分段里一档 / 胶囊的视觉高 28。
  static let pillHeight: CGFloat = 28
  /// 分段那条槽的视觉高：一档 28 + 上下各 `Space.xxs`。
  static let segmentTrack: CGFloat = pillHeight + 2 * ReviewSpace.xxs
  /// 筛选胶囊的视觉高 32（`ControlMetrics.iconDisc` 那一档），点按区另撑到 44。
  static let chip: CGFloat = 32
  /// `ControlMetrics.chevron`：行尾箭头 12。
  static let chevron: CGFloat = 12
  /// `ControlMetrics.disabledOpacity`。
  static let disabledOpacity: Double = 0.4
  /// 主按钮：常规 44、大号 50（账号页那颗主按钮同一套）。
  static let primary: CGFloat = 44
  static let primaryLarge: CGFloat = 50
}

extension View {
  /// 对应 app 的 `hitTarget()`：视觉不变，点按区撑到至少 44×44。
  func hitTarget(_ side: CGFloat = ReviewControl.hit) -> some View {
    frame(minWidth: side, minHeight: side).contentShape(Rectangle())
  }

  /// 对应 app 的 `pageHorizontalInset()`：量这一整行多宽，左右各留 `Inset.page`（16 / 20）。
  func reviewPageInset() -> some View { modifier(ReviewPageInset()) }

  /// 皮肤输入框：抬高底（`raised2`）、圆角 `Radius.s`、高 ≥ 44，字 15。替掉系统 `.roundedBorder`
  /// ——那一圈灰描边在青苔、陶土上都像借来的。
  func reviewField() -> some View { modifier(ReviewFieldModifier()) }
}

private struct ReviewPageInset: ViewModifier {
  @State private var width: CGFloat = 0
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, ReviewInset.page(width))
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
  }
}

private struct ReviewFieldModifier: ViewModifier {
  @Environment(\.reviewTheme) private var t
  func body(content: Content) -> some View {
    content
      .font(ReviewType.body)
      .foregroundStyle(t.ink)
      .padding(.horizontal, ReviewSpace.m)
      .padding(.vertical, ReviewSpace.s)
      .frame(minHeight: ReviewControl.hit)
      .background(t.raised2, in: RoundedRectangle(cornerRadius: ReviewRadius.s, style: .continuous))
  }
}

// ============================================================ 皮肤零件

/// 分组标题：12 medium、`ink3`。替掉 `Section("…")` 的系统灰大写头。
struct ReviewSectionTitle: View {
  var title: String
  @Environment(\.reviewTheme) private var t
  init(_ title: String) { self.title = title }
  var body: some View {
    Text(title).font(ReviewType.captionEmph).foregroundStyle(t.ink3).textCase(nil)
  }
}

/// 皮肤分段：照 app 的 `PanelSegment` 抄——一条 32 高的槽（`raised2`、圆角 8），每档 28 高，
/// 选中那档垫 `segOn` 加一丝投影、字 `ink`，没选中字 `ink2`；每档点按区 44 高，多出来的那截
/// 用负边距还给布局，所以在版面里只占 32（和原来的系统分段一样高，卡片不会被撑高）。
///
/// 每档挂 `<id>.<档位文字>` 的标识和「已选中」特征，用例按档点。
struct ReviewSegment<Value: Hashable>: View {
  var options: [(String, Value)]
  @Binding var selection: Value
  var id: String? = nil
  /// 铺满整行、各档等宽（卡片里那几排）；否则按字宽排。
  var fill = true
  @Environment(\.reviewTheme) private var t

  var body: some View {
    HStack(spacing: ReviewSpace.xxs) {
      ForEach(options, id: \.1) { text, value in
        let on = value == selection
        Button { selection = value } label: {
          Text(text)
            .font(ReviewType.control)
            .foregroundStyle(on ? t.ink : t.ink2)
            .lineLimit(1)
            .padding(.horizontal, ReviewSpace.m)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: ReviewControl.pillHeight)
            .background {
              if on {
                RoundedRectangle(cornerRadius: ReviewRadius.concentric(outer: ReviewRadius.s, padding: ReviewSpace.xxs),
                                 style: .continuous)
                  .fill(t.segOn)
                  .shadow(color: .black.opacity(0.09), radius: 1, y: 1)
              }
            }
            .frame(minHeight: ReviewControl.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id.map { "\($0).\(text)" } ?? "")
        .accessibilityAddTraits(on ? [.isSelected] : [])
      }
    }
    .padding(.horizontal, ReviewSpace.xxs)
    .background {
      RoundedRectangle(cornerRadius: ReviewRadius.s, style: .continuous)
        .fill(t.raised2)
        .padding(.vertical, (ReviewControl.hit - ReviewControl.segmentTrack) / 2)
    }
    .padding(.vertical, -(ReviewControl.hit - ReviewControl.segmentTrack) / 2)
    .accessibilityElement(children: .contain)
  }
}

/// 皮肤主按钮：强调色胶囊、压在上面的字走 `onAccent`。常规 44 高（字 15 medium），
/// 大号 50 高（字 17 semibold）。替掉系统 `.borderedProminent`。
struct ReviewPrimaryButtonStyle: ButtonStyle {
  var large = false
  @Environment(\.reviewTheme) private var t
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(large ? ReviewType.title : ReviewType.bodyEmph)
      .foregroundStyle(t.onAccent)
      .padding(.horizontal, large ? ReviewSpace.xl : ReviewSpace.l)
      .frame(minHeight: large ? ReviewControl.primaryLarge : ReviewControl.primary)
      .background(t.accent, in: Capsule())
      .opacity(configuration.isPressed ? 0.8 : 1)
      .opacity(enabled ? 1 : ReviewControl.disabledOpacity)
      .contentShape(Capsule())
  }
}

// ============================================================ 左划

/// 左划露出来的一颗。底色按语义由 app 那边定：不可逆的走 `danger`，其余走强调色。
public struct ReviewSwipeAction: Identifiable {
  /// 无障碍记号后缀（app 那边是 `swipe.<id>`）。
  public var id: String
  public var title: String
  public var destructive: Bool
  public var run: () -> Void
  public init(id: String, title: String, destructive: Bool = false, run: @escaping () -> Void) {
    self.id = id; self.title = title; self.destructive = destructive; self.run = run
  }
}

/// 递给行内容的那只手：现在划开着吗、怎么收回去。划开时点行应先收回，不当成一次点击。
public struct ReviewSwipeState {
  public var isOpen: Bool
  public var close: () -> Void
  public init(isOpen: Bool, close: @escaping () -> Void) { self.isOpen = isOpen; self.close = close }
}

/// 一行可左划的行，交给 app 去画。
public struct ReviewSwipeRow {
  public var id: String
  public var open: Binding<String?>
  public var trailing: [ReviewSwipeAction]
  public var fullSwipe: Bool
  public var content: (ReviewSwipeState) -> AnyView
}

public typealias ReviewSwipeProvider = @MainActor @Sendable (ReviewSwipeRow) -> AnyView

/// 包里用的那一层：有 app 的实现就交给它，没有（`#Preview`）就退回系统 `.swipeActions`。
struct ReviewSwipe<Content: View>: View {
  var id: String
  @Binding var open: String?
  var trailing: [ReviewSwipeAction]
  var fullSwipe = true
  @ViewBuilder var content: (ReviewSwipeState) -> Content
  @Environment(\.reviewTheme) private var t

  var body: some View {
    if let swipe = t.swipe {
      swipe(ReviewSwipeRow(id: id, open: $open, trailing: trailing, fullSwipe: fullSwipe,
                           content: { AnyView(content($0)) }))
    } else {
      content(ReviewSwipeState(isOpen: false, close: {}))
        .swipeActions(edge: .trailing, allowsFullSwipe: fullSwipe) {
          ForEach(trailing) { action in
            Button(role: action.destructive ? .destructive : nil, action: action.run) { Text(action.title) }
              .tint(action.destructive ? t.danger : t.accent)
          }
        }
    }
  }
}
