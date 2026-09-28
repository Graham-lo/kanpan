import SwiftUI
import UIKit

/// 屏幕正中的术语解释卡：标题、两三行正文、一条发丝线、强调色「知道了」。
///
/// 宽 280、圆角 18（和系统居中弹窗同一档，比 `Radius.l` 的抽屉再圆一点），`raised` 的底；
/// 后面一层遮罩，点遮罩或「知道了」都关，进出都是 0.2 秒的淡入淡出。
/// 不直接摆在调用处的视图树里——它由 `GlossaryPresenter` 弹在最顶层的控制器上。
struct GlossaryCard: View {
  let term: GlossaryTerm
  let theme: PanelTheme
  /// 淡出完了之后由宿主把控制器收掉。
  let onDismissed: () -> Void

  @State private var shown = false
  @Environment(\.displayScale) private var displayScale

  static let width: CGFloat = 280
  static let corner: CGFloat = 18
  static let fade: Double = 0.2

  var body: some View {
    ZStack {
      Color.black.opacity(theme.dark ? 0.5 : 0.32)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .accessibilityHidden(true)
        .accessibilityIdentifier("glossary.scrim")

      card
    }
    .opacity(shown ? 1 : 0)
    .onAppear { withAnimation(.easeOut(duration: Self.fade)) { shown = true } }
    .environment(\.panelTheme, theme)
  }

  private var card: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: Space.s) {
        Text(term.title)
          .font(TypeScale.heading)
          .foregroundStyle(theme.ink)
          .accessibilityIdentifier("glossary.title")
        Text(term.body)
          .font(ScaledFont(14, .regular, relativeTo: .subheadline))
          .foregroundStyle(theme.ink2)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("glossary.body")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Space.xl)
      .padding(.top, Space.xl)
      .padding(.bottom, Space.l)

      Rectangle().fill(theme.line).frame(height: 1 / displayScale)

      Button(action: close) {
        Text("知道了")
          .font(TypeScale.bodyEmph)
          .foregroundStyle(theme.amber)
          .frame(maxWidth: .infinity, minHeight: Hit.min)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("glossary.ok")
    }
    .frame(width: Self.width)
    .background(theme.raised, in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
    .shadow(color: .black.opacity(theme.dark ? 0.4 : 0.14), radius: 24, y: 8)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("glossary.card")
    .accessibilityAddTraits(.isModal)
  }

  private func close() {
    withAnimation(.easeIn(duration: Self.fade)) { shown = false } completion: { onDismissed() }
  }
}

/// 把 `GlossaryCard` 弹到**最上层**。
///
/// 卡片不能用 SwiftUI 的 `.overlay` / `.fullScreenCover` 挂在调用处：问号可能长在半屏面板
/// （`PanelSheet`）、系统 sheet、横屏画线台的侧栏里，挂在哪儿就只能盖住哪儿，
/// 而且 sheet 上再叠一层 SwiftUI 弹层，和它自己的 detent、下拉手势纠缠不清。
///
/// 所以这儿直接走 UIKit：从前台窗口的根控制器一路顺着 `presentedViewController` 找到最顶上
/// 那一层，在它上面 present 一个透明的 `overFullScreen` 宿主（淡入淡出由卡片自己做，
/// 控制器本身无动画进出，等效 `crossDissolve` 但时长可控在 0.2 秒）。
/// 最顶上那一层是谁它都不在乎——半屏 sheet、全屏 sheet、横屏台都一样盖得住。
@MainActor
enum GlossaryPresenter {
  static func present(_ term: GlossaryTerm, theme: PanelTheme) {
    guard let top = topController() else { return }
    // 同一刻只弹一张：连点两下不叠两层。
    if top is GlossaryHostController { return }
    let host = GlossaryHostController()
    host.rootView = AnyView(GlossaryCard(term: term, theme: theme) { [weak host] in
      host?.dismiss(animated: false)
    })
    host.modalPresentationStyle = .overFullScreen
    host.modalTransitionStyle = .crossDissolve
    host.view.backgroundColor = .clear
    top.present(host, animated: false)
  }

  private static func topController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    var top = window?.rootViewController
    while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
    return top
  }
}

/// 透明底的宿主。单独成一个类型，好让 `GlossaryPresenter` 认出「已经弹着一张了」。
final class GlossaryHostController: UIHostingController<AnyView> {
  init() { super.init(rootView: AnyView(EmptyView())) }
  @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) 不用") }
}
