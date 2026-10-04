import SwiftUI

/// 只在竖屏露面的那种表单：横屏时同一份内容改由别处画（贴边卡片），状态是同一个开关。
///
/// 画线工具面板、发给朋友那张选人表都是这样：竖屏一张 `.sheet`，横屏是 `drawToolsLayer`
/// 那块贴边卡片，两边都由同一个开关（`draw.picker` / `showFriendPicker`）驱动。
///
/// 原来直接把 `.sheet` 绑在 `Binding(get: { 开关 && !landscape }, set: …)` 上。竖屏开着表
/// 转到横屏，`get` 变 false，系统收表时会回写一次 false——这一下不是人关的，可它照样把开关
/// 清掉了，横屏那块卡片也就跟着不出来：转一下屏，面板就没了。只在 `set` 里加
/// `if !landscape` 挡不住：系统回写用的那份绑定闭包是哪一趟 body 留下的说不准，
/// 里面读到的 `landscape` 可能还是转屏之前的。
///
/// 这里把「表在不在场」拆成自己的状态：开关 + 方向决定它；表被收起来时，只有在**此刻**
/// 仍是竖屏、开关仍开着（也就是人自己往下划掉的）才回头关开关。`onChange` 的动作取的是
/// 这一刻的值，不吃旧闭包。一个修饰符顶原来一个 `.sheet`，`MainScreen` 那条链不变长。
struct PortraitOnlySheet<Sheet: View>: ViewModifier {
  /// 外面那个开关此刻开着没有。
  let wanted: Bool
  let landscape: Bool
  /// 人在竖屏把表划掉了：把外面的开关关上。
  let onUserDismiss: () -> Void
  let sheet: () -> Sheet

  @State private var shown = false

  init(wanted: Bool, landscape: Bool, onUserDismiss: @escaping () -> Void,
       @ViewBuilder sheet: @escaping () -> Sheet) {
    self.wanted = wanted
    self.landscape = landscape
    self.onUserDismiss = onUserDismiss
    self.sheet = sheet
  }

  func body(content: Content) -> some View {
    content
      .sheet(isPresented: $shown) { sheet() }
      .onChange(of: wanted && !landscape, initial: true) { _, on in
        if shown != on { shown = on }
      }
      .onChange(of: shown) { _, on in
        if !on, wanted, !landscape { onUserDismiss() }
      }
  }
}
