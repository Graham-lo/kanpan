import SwiftUI
import UIKit

// ============================================================ 左划／右划的那几块砖
//
// **全 app 的划出动作只有这一份实现。** 提醒总表（`AlertListPage`）、画线管理
// （`DrawingBar` 里的 `DrawingSheet`）、自选分类页（`FavoritesView`）、品种整页的
// 自选段（`SymbolPickerView`）都从这儿取，不许任何一处再自己画一套
// （`kanpan-one-feature-one-module`）。
//
// ------------------------------------------------------------ 为什么不用 `.swipeActions`
//
// 2026-09-22 在 iPhone 15 / 青苔深上量过：`.swipeActions` 里的
// `Text("删除").foregroundStyle(theme.badgeInk)`，字**根本没染上**。
// 砖底确实是 `theme.danger`（`#F08A80`，`.tint` 是生效的），但砖上那两个字的
// 像素直方图里 `#FFFFFF` 218 个、`#060A08` 一个都没有，对比度 2.43:1。
//
// 机制不是「`foregroundStyle` 被别的样式盖过去」，是**那个 `Text` 压根没被画出来**：
// 无障碍树里那颗按钮是**叶子**，里头没有任何 StaticText 节点（`delete.staticTexts`
// 空的）。SwiftUI 只是把 label 里的字符串取走，塞进 `UIContextualAction.title`，
// 剩下的 SwiftUI 修饰符（`foregroundStyle` / `font` / `.environment`）全部丢弃；
// 真正画字的是 UIKit，而 `UIContextualAction` 不提供标题颜色，一律白字。
// 同理，`Label` 换 `labelStyle`、`.environment(\.colorScheme)`、`UIView.appearance`
// 都够不着它——它们都作用在 SwiftUI 那棵早就被丢掉的子树上。
// 唯一还剩的路子是把「删除」两个字渲成位图当 `Image` 递过去，那等于把一句中文
// 钉死成一张图：动态字号、本地化、无障碍标签全丢，比手搓还糟。
//
// 而且这件事**不能只修一半**：给 destructive 那颗补一句 `.tint(theme.danger)`，
// 底是跟着皮肤走了，可字仍旧是 UIKit 画的白——白压在青苔深的 `#F08A80` 上是
// 2.43:1，比系统红 `#FF3B30` 的 3.55:1 还差。所以颜色这件事在 `.swipeActions`
// 上没有干净的解法，这一套自己画：底和字一起自己上。
//
// ------------------------------------------------------------ 自己画就得把系统那两样补回来
//
// 换掉原生的代价是两样东西，都在这儿补齐了，没有丢：
//
// 1. **滑到底直接触发**（full swipe）：拖过行宽的 60%（且至少 140pt）松手就触发那一边
//    的第一颗，过程中砖块跟着手指一路铺满整行，和系统一个样。调用方可以关掉它
//    （`fullSwipe: false`），对应原来的 `allowsFullSwipe: false`。
// 2. **VoiceOver 的破坏性语义 + 删除行的收拢动画**：砖上那颗按钮仍是
//    `Button(role: .destructive)`；砖没划开时它不在无障碍树里，所以另外给行挂了
//    一条同名的 `accessibilityAction`，VoiceOver 从「操作」转子里直接够得到，
//    不必先学会左划。破坏性那一下裹在 `withAnimation` 里，行的收拢交给
//    `List` / `ForEach` 自己做。
//
// 还补了一样原生有、上一版手搓没有的：**同一时刻只许一行划开着**。开关状态住在
// 调用方（`@State private var openSwipe: String?`），不摆全局单例。
//
// ------------------------------------------------------------ 砖块怎么排
//
// 砖块画在 `.background(alignment:)` 里，宽度 = 行被推走的距离。
// 行往哪边推多少，那一边的砖就露多少，两者严丝合缝——所以**行本身不需要垫一层
// 不透明的底**（上一版 `AlertRow` 那句 `.background(t.raised)` 就是为了挡砖，
// 现在没必要了）。`.offset` 不改布局框，`.background` 落在原地，砖不会跟着行一起跑。
//
// 一边挂多颗时，那一边露出来的宽度平分给它们，顺序和系统 `.swipeActions` 一致：
// **先写的那颗贴着屏幕那条边**（左划时最靠右，右划时最靠左）。

/// 划开之后露出来的一颗按钮。
///
/// 字色**不在这儿**：全 app 压在彩色块上的字统一走 `theme.badgeInk`（深皮肤下近黑的
/// `ground`、浅皮肤下白），由组件自己从环境里取，调用方给不了别的值——这是规矩，
/// 不是选项。这儿只给底色，因为底色是语义（删除 = `theme.danger`，其余 = `theme.amber`）。
struct SwipeAction: Identifiable {
  /// 无障碍记号后缀：按钮是 `swipe.<id>`，砖上那几个字是 `swipe.<id>.text`。
  /// 删除那颗的 id 就叫 `delete`，所以记号照旧是 `swipe.delete`（见 `SwipeDeleteIDs`）。
  var id: String
  var title: String
  /// 砖底。删除一律 `theme.danger`（`884c802` 定的那支警示色），不许再出现系统红。
  var fill: Color
  /// 不可逆的那种。只影响两件事：按钮的 `role`（VoiceOver 会念「破坏性」）、
  /// 以及触发时裹不裹行收拢动画。
  var destructive: Bool = false
  var run: () -> Void

  /// 删除砖。全 app 的删除都从这儿开，省得哪天有人又手写一支颜色。
  static func delete(_ t: PanelTheme, title: String = "删除",
                     id: String = "delete",
                     run: @escaping () -> Void) -> SwipeAction {
    SwipeAction(id: id, title: title, fill: t.danger, destructive: true, run: run)
  }
}

/// 砖块长什么样。只有两种，按这一行住在什么容器里定，**不是给用户的选项**。
enum SwipeDeleteBrick {
  /// 贴边方砖：行与行首尾相连、自己没有圆角的表（`PanelSheet` 里的 `PanelRow`）。
  case flush
  /// 圆角药丸，四周留一圈：成组 `List` 的行。方角会戳出行背景那个圆角，
  /// 而且 iOS 26 自带的 `swipeActions` 在成组表里画的本来就是一颗离开行的药丸。
  case pill
}

/// 递给行内容的一只手：这一行现在划开着吗、怎么把它收回去。
///
/// 划开的时候点行里任何东西都该先收回去，而不是当成一次正常的点击——
/// 不接这只手，用户划开之后想反悔只能再划一次。
struct SwipeDeleteProxy {
  var isOpen: Bool
  var close: () -> Void
}

struct SwipeToDelete<Content: View>: View {
  /// 这一行的身份，和 `open` 比对。
  var id: String
  /// 当前划开的是哪一行，住在调用方。
  @Binding var open: String?
  var brick: SwipeDeleteBrick = .flush
  /// 右划（从左沿拉出来）露的那几颗。空数组 = 这一行右划不出东西。
  var leading: [SwipeAction] = []
  /// 左划（从右沿拉出来）露的那几颗。
  var trailing: [SwipeAction]
  /// 滑到底直接触发那一边的第一颗。对应原来的 `allowsFullSwipe`。
  var fullSwipe: Bool = true
  @ViewBuilder var content: (SwipeDeleteProxy) -> Content

  @Environment(\.panelTheme) private var t
  /// 这一行当前被推走了多少（左划为负、右划为正）。吸附位和 `open` 保持一致，
  /// 拖的过程中自己走。
  @State private var offset: CGFloat = 0
  @State private var rowWidth: CGFloat = 0
  /// 吸附住的是哪一边。`open == id` 时才有意义。
  @State private var side: Edge = .trailing

  /// 一颗砖吸附住的时候露出多宽。药丸要把四周那一圈留白也算进去。
  private var unit: CGFloat { brick == .pill ? 92 : 76 }
  private var pad: CGFloat { brick == .pill ? 8 : 0 }
  private var corner: CGFloat { brick == .pill ? 14 : 0 }
  private var trailingReveal: CGFloat { unit * CGFloat(trailing.count) }
  private var leadingReveal: CGFloat { unit * CGFloat(leading.count) }
  /// 滑到底的门槛：行宽的 60%，短行也至少要 140pt。
  private var fullSwipeThreshold: CGFloat { max(140, rowWidth * 0.6) }

  var body: some View {
    content(SwipeDeleteProxy(isOpen: open == id, close: close))
      // VoiceOver 的入口。砖块没划开时不在树上，光靠它够不着。
      .accessibilityActions {
        ForEach(leading + trailing) { action in
          Button(action.title) { fire(action) }
        }
      }
      .offset(x: offset)
      // 认手势的是一颗 **UIKit 的 `UIPanGestureRecognizer`**，不是 SwiftUI 的
      // `DragGesture`。这不是口味问题，是 2026-09-22 在 iPhone 15 上量出来的：
      // 行上挂 `.simultaneousGesture(DragGesture(minimumDistance: 12))` 之后，
      // 自选分类页**纵向滚不动了**——`FavoritesScrollAnchorUITests`
      // 里那条 `testFavoritesKeepsTheScrollPositionAcrossTabs` 从 29.6 秒过
      // 变成「滚了 12 下还没把 APTUSDT 滚出来」，把这一句注释掉又立刻恢复。
      // 「`simultaneousGesture` 不会抢滚动」这句话在 `List` 的行里不成立：
      // SwiftUI 的 drag 一旦起手就把这趟触摸认走了，表的 pan 再也拿不到。
      // 而 `onChanged` 里那道横纵锁来得太晚——它是**起手之后**才判的。
      //
      // UIKit 这一颗则是在**起手之前**判：手指挪过 8 点时先看方向，是纵的就
      // 当场把自己判死（`.failed`），整趟触摸原封不动留给表去滚。
      //
      // 两边都没挂东西的行（品种整页里非自选段那几百行）连认都不认：
      // 手势关掉，横着划什么都不会发生，和改之前一样。
      .gesture(HorizontalPan(enabled: !(leading.isEmpty && trailing.isEmpty),
                             onChanged: { dx in pan(dx) },
                             onEnded: { dx in panEnded(dx) }))
      .background(alignment: .trailing) { bricks(trailing.reversed(), max(0, -offset)) }
      .background(alignment: .leading) { bricks(leading, max(0, offset)) }
      .clipped()
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
      .onChange(of: open) { _, now in
        guard now != id, offset != 0 else { return }
        withAnimation(.easeOut(duration: 0.16)) { offset = 0 }
      }
  }

  // ------------------------------------------------------------ 手势

  /// 拖的过程中：把手指的横向位移换成行的位移，夹在这一行真拉得动的范围里。
  private func pan(_ dx: CGFloat) {
    let want = anchor + dx
    // 那一边没挂东西就拉不动；有东西时最远能拉到整行宽（滑到底那一下）。
    // 关掉滑到底的（`fullSwipe: false`）就拉到吸附位为止，再拽也不动——
    // 拉得出去却什么都不会发生，是在骗手指。
    let far = max(rowWidth, 1)
    let low = trailing.isEmpty ? 0 : -(fullSwipe ? far : trailingReveal)
    let high = leading.isEmpty ? 0 : (fullSwipe ? far : leadingReveal)
    offset = min(high, max(low, want))
  }

  /// 手指抬起来：要么滑到底直接触发，要么吸附到砖宽，要么弹回去。
  private func panEnded(_ dx: CGFloat) {
    var end = anchor + dx
    // 那一边没挂东西，这一趟就当没往那边走过。
    if trailing.isEmpty { end = max(end, 0) }
    if leading.isEmpty { end = min(end, 0) }
    if fullSwipe, end < -fullSwipeThreshold, let first = trailing.first { fire(first); return }
    if fullSwipe, end > fullSwipeThreshold, let first = leading.first { fire(first); return }
    withAnimation(.easeOut(duration: 0.16)) {
      if end < -36, !trailing.isEmpty {
        offset = -trailingReveal
        side = .trailing
        open = id
      } else if end > 36, !leading.isEmpty {
        offset = leadingReveal
        side = .leading
        open = id
      } else {
        offset = 0
        if open == id { open = nil }
      }
    }
  }

  /// 这一趟起手时行停在哪儿。
  private var anchor: CGFloat {
    guard open == id else { return 0 }
    return side == .leading ? leadingReveal : -trailingReveal
  }

  private func close() {
    withAnimation(.easeOut(duration: 0.16)) { offset = 0 }
    if open == id { open = nil }
  }

  /// 真触发。破坏性那一下的收拢动画交给外面那层 `ForEach` —— 把动作裹进
  /// `withAnimation` 就行，不必自己把行推出屏幕再等。
  private func fire(_ action: SwipeAction) {
    if open == id { open = nil }
    if action.destructive {
      offset = 0
      withAnimation(.easeOut(duration: 0.2)) { action.run() }
    } else {
      // 这一颗不删行（「移到分类」开的是一张表），行得自己滑回去。
      withAnimation(.easeOut(duration: 0.16)) { offset = 0 }
      action.run()
    }
  }

  // ------------------------------------------------------------ 砖块

  /// 一边的一组砖，总宽 `w` 平分。
  ///
  /// **没划开的时候整组砖不建出来**（不是画成透明）。`opacity(0)` 只是不画，
  /// 节点照样在无障碍树里：上一版那颗按钮闭合状态下还报得出一个 23pt 宽的 frame
  /// （`.frame(width: 0)` 夹不住里头 `fixedSize` 的两个字），用例据此判「砖已经开着」，
  /// 于是一下都没划就去采色，量到的是行底 `#131C18`。`if` 掉才是真的不在。
  @ViewBuilder private func bricks(_ actions: [SwipeAction], _ w: CGFloat) -> some View {
    if w > 1, !actions.isEmpty {
      HStack(spacing: 0) {
        ForEach(actions) { one($0, w / CGFloat(actions.count)) }
      }
      .frame(width: w)
      .frame(maxHeight: .infinity)
      .clipped()
    }
  }

  private func one(_ action: SwipeAction, _ w: CGFloat) -> some View {
    ZStack {
      // 按钮的 label 只有那块底色，**那几个字摆在它外面**：`Button` 会把 label 里的
      // 子元素并成一颗叶子，字就没有自己的 frame 了（上一版的 `delete.staticTexts`
      // 一直是空的，用例只能靠在图上数像素找那两个字）。摆成兄弟节点之后，
      // 它在无障碍树里是一颗独立的 StaticText，带自己的记号。
      Button(role: action.destructive ? ButtonRole.destructive : nil) { fire(action) } label: {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .fill(action.fill)
          .padding(pad)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(action.title)
      .accessibilityIdentifier(SwipeDeleteIDs.button(action.id))

      Text(action.title)
        .font(PanelFont.seg)
        // 压在彩色砖上的字，全 app 同一支笔。
        .foregroundStyle(t.badgeInk)
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityIdentifier(SwipeDeleteIDs.text(action.id))
    }
    .frame(width: w)
    .clipped()
  }
}

/// 无障碍记号。同一时刻只有一行划得开，所以各处共用同一套后缀，不会撞。
///
/// 后缀就是 `SwipeAction.id`：按钮 `swipe.<id>`、砖上那几个字 `swipe.<id>.text`。
/// 删除那颗的 id 是 `delete`，所以它的记号和上一版一字不差（`swipe.delete`）。
enum SwipeDeleteIDs {
  static func button(_ id: String) -> String { "swipe." + id }
  /// 砖上那几个字自己的记号。用例直接量它的 frame 去采样，
  /// 不用再在整张图上找那两撇（上一版它在树里根本没有 frame）。
  static func text(_ id: String) -> String { button(id) + ".text" }

  // 各处的后缀写在这儿，实现和用例共用同一份字面量。
  /// `SwipeAction.delete` 默认的那颗。
  static let delete = "delete"
  /// 自选分类页右划：「取消自选」。
  static let favoritesRemove = "favorites.remove"
  /// 自选分类页左划：「移到分类」。
  static let favoritesMove = "favorites.move"
  /// 品种整页自选段左划：「取消自选」。
  static let favoritesUnstar = "favorites.unstar"
}


// ============================================================ 只认横着那一趟的 pan

/// 一颗只在**横向**起手的 `UIPanGestureRecognizer`。
///
/// 关键在 `touchesMoved` 里：`super` 一旦把状态推到 `.began`，这一趟触摸就归它了，
/// 外面那张 `List` 的滚动再也拿不到。所以在调 `super` **之前**先自己看方向，
/// 纵的直接判死。判死的手势不吃触摸，表照旧滚。
///
/// 8 点这道门槛比系统 pan 的 10 点略小，保证方向在 `super` 起手之前就判完。
private final class HorizontalPanRecognizer: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
  private var origin: CGPoint?

  override init(target: Any?, action: Selector?) {
    super.init(target: target, action: action)
    // 和表自己那颗 pan 并存。表横着本来也滚不动，两边互不挡道；
    // 不放开的话谁先认下谁就把对方挤掉，全看识别顺序。
    // （SwiftUI 要是把 `delegate` 抢回去，也只是退回默认的互斥，
    //   `touchesMoved` 里那道方向判死照旧管用。）
    delegate = self
  }

  func gestureRecognizer(_ g: UIGestureRecognizer,
                         shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    origin = touches.first?.location(in: view)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    if state == .possible, let from = origin, let now = touches.first?.location(in: view) {
      let dx = now.x - from.x
      let dy = now.y - from.y
      if max(abs(dx), abs(dy)) > 8, abs(dy) >= abs(dx) {
        state = .failed
        return
      }
    }
    super.touchesMoved(touches, with: event)
  }

  override func reset() {
    super.reset()
    origin = nil
  }
}

/// 把上面那颗接到 SwiftUI 上。位移只报 x，纵向的那一趟根本走不到这儿。
///
/// `UIGestureRecognizerRepresentable` 只有 `gesture(_:)` 这一个入口、没有
/// `isEnabled:`，所以开关做在 `updateUIGestureRecognizer` 里：两边都没挂东西的行
/// （品种整页里非自选段那几百行）直接把这颗关掉，横着划什么都不会发生。
private struct HorizontalPan: UIGestureRecognizerRepresentable {
  var enabled: Bool
  var onChanged: (CGFloat) -> Void
  var onEnded: (CGFloat) -> Void

  func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
    HorizontalPanRecognizer()
  }

  func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
    recognizer.isEnabled = enabled
  }

  func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
    let dx = recognizer.translation(in: recognizer.view).x
    switch recognizer.state {
    case .changed: onChanged(dx)
    case .ended, .cancelled, .failed: onEnded(dx)
    default: break
    }
  }
}
