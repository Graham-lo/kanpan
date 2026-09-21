import SwiftUI

// ============================================================ 左划删除
//
// **全 app 的左划删除只有这一份实现。** 提醒总表（`AlertListPage`）和画线管理
// （`DrawingBar` 里的 `DrawingSheet`）都从这儿取，不许任何一处再自己画一套
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
// 所以颜色这件事在 `.swipeActions` 上没有干净的解法，这一套自己画。
//
// ------------------------------------------------------------ 自己画就得把系统那两样补回来
//
// 换掉原生的代价是两样东西，都在这儿补齐了，没有丢：
//
// 1. **滑到底直接触发**（full swipe）：拖过行宽的 60%（且至少 140pt）松手就删，
//    过程中砖块跟着手指一路铺满整行，和系统一个样。
// 2. **VoiceOver 的破坏性语义 + 删除行的收拢动画**：砖上那颗按钮仍是
//    `Button(role: .destructive)`；砖没划开时它 `opacity` 为 0、不在无障碍树里，
//    所以另外给行挂了一条 `accessibilityAction(named: "删除")`，VoiceOver 从
//    「操作」转子里直接够得到，不必先学会左划。删除那一下裹在 `withAnimation` 里，
//    行的收拢交给 `List` / `ForEach` 自己做。
//
// 还补了一样原生有、上一版手搓没有的：**同一时刻只许一行划开着**。开关状态住在
// 调用方（`@State private var openSwipe: String?`），不摆全局单例。
//
// ------------------------------------------------------------ 砖块怎么排
//
// 砖块画在 `.background(alignment: .trailing)` 里，宽度 = 行被推走的距离。
// 行往左推多少，砖就露多少，两者严丝合缝——所以**行本身不需要垫一层不透明的底**
// （上一版 `AlertRow` 那句 `.background(t.raised)` 就是为了挡砖，现在没必要了）。
// `.offset` 不改布局框，`.background` 落在原地，砖不会跟着行一起跑。

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
  var onDelete: () -> Void
  @ViewBuilder var content: (SwipeDeleteProxy) -> Content

  @Environment(\.panelTheme) private var t
  /// 这一行当前被推走了多少（负数）。吸附位和 `open` 保持一致，拖的过程中自己走。
  @State private var offset: CGFloat = 0
  @State private var rowWidth: CGFloat = 0
  /// 这一趟手势是横的还是纵的，**第一次判完就锁住**。
  /// 每帧重判的话，一次先纵后横的滚动会在半路把行也拽出去。
  @State private var axis: Axis?

  /// 砖块吸附住的时候露出多宽。药丸要把四周那一圈留白也算进去。
  private var reveal: CGFloat { brick == .pill ? 92 : 76 }
  private var pad: CGFloat { brick == .pill ? 8 : 0 }
  private var corner: CGFloat { brick == .pill ? 14 : 0 }
  /// 滑到底的门槛：行宽的 60%，短行也至少要 140pt。
  private var fullSwipe: CGFloat { max(140, rowWidth * 0.6) }

  var body: some View {
    content(SwipeDeleteProxy(isOpen: open == id, close: close))
      // VoiceOver 的入口。砖块没划开时不在树上，光靠它够不着。
      .accessibilityAction(named: Text("删除")) { fire() }
      .offset(x: offset)
      // `simultaneousGesture` 而不是 `gesture`：这一份要塞进 `List` 的行里，
      // 独占的手势会把列表的纵向滚动一起吃掉。横纵由 `axis` 那道锁分流。
      .simultaneousGesture(swipe)
      .background(alignment: .trailing) { brickView(max(0, -offset)) }
      .clipped()
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
      .onChange(of: open) { _, now in
        guard now != id, offset != 0 else { return }
        withAnimation(.easeOut(duration: 0.16)) { offset = 0 }
      }
  }

  // ------------------------------------------------------------ 手势

  private var swipe: some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { g in
        if axis == nil {
          axis = abs(g.translation.width) > abs(g.translation.height) ? .horizontal : .vertical
        }
        guard axis == .horizontal else { return }
        offset = min(0, max(-max(rowWidth, 1), anchor + g.translation.width))
      }
      .onEnded { g in
        let horizontal = axis == .horizontal
        axis = nil
        guard horizontal else { return }
        let end = anchor + g.translation.width
        if end < -fullSwipe { fire(); return }
        withAnimation(.easeOut(duration: 0.16)) {
          if end < -36 {
            offset = -reveal
            open = id
          } else {
            offset = 0
            if open == id { open = nil }
          }
        }
      }
  }

  /// 这一趟起手时行停在哪儿。
  private var anchor: CGFloat { open == id ? -reveal : 0 }

  private func close() {
    withAnimation(.easeOut(duration: 0.16)) { offset = 0 }
    if open == id { open = nil }
  }

  /// 真删。收拢动画交给外面那层 `ForEach` —— 把 `onDelete` 裹进 `withAnimation`
  /// 就行，不必自己把行推出屏幕再等。
  private func fire() {
    if open == id { open = nil }
    offset = 0
    withAnimation(.easeOut(duration: 0.2)) { onDelete() }
  }

  // ------------------------------------------------------------ 砖块

  ///
  /// **没划开的时候整块砖不建出来**（不是画成透明）。`opacity(0)` 只是不画，
  /// 节点照样在无障碍树里：上一版那颗按钮闭合状态下还报得出一个 23pt 宽的 frame
  /// （`.frame(width: 0)` 夹不住里头 `fixedSize` 的两个字），用例据此判「砖已经开着」，
  /// 于是一下都没划就去采色，量到的是行底 `#131C18`。`if` 掉才是真的不在。
  @ViewBuilder private func brickView(_ w: CGFloat) -> some View {
    if w > 1 {
      ZStack {
        // 按钮的 label 只有那块底色，**「删除」两个字摆在它外面**：`Button` 会把
        // label 里的子元素并成一颗叶子，字就没有自己的 frame 了（上一版的
        // `delete.staticTexts` 一直是空的，用例只能靠在图上数像素找那两个字）。
        // 摆成兄弟节点之后，它在无障碍树里是一颗独立的 StaticText，带自己的记号。
        Button(role: .destructive) { fire() } label: {
          RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(t.danger)
            .padding(pad)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("删除")
        .accessibilityIdentifier(SwipeDeleteIDs.button)

        Text("删除")
          .font(PanelFont.seg)
          .foregroundStyle(t.badgeInk)
          .fixedSize()
          .allowsHitTesting(false)
          .accessibilityIdentifier(SwipeDeleteIDs.text)
      }
      .frame(width: w)
      .frame(maxHeight: .infinity)
      .clipped()
    }
  }
}

/// 无障碍记号。两处共用同一套——同一时刻只有一行划得开，不会撞。
enum SwipeDeleteIDs {
  static let button = "swipe.delete"
  /// 砖上「删除」两个字自己的记号。用例直接量它的 frame 去采样，
  /// 不用再在整张图上找那两撇（上一版它在树里根本没有 frame）。
  static let text = "swipe.delete.text"
}
