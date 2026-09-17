import SwiftUI

/// 底栏保留常用去处；外观与横屏统一在周期行。
///
/// 「自选」进的是带加密 / 美股分类的那张完整自选页（`FavoritesView`），不是顶栏
/// 品种名开的那个半屏弹层。两者分工：弹层是「快速换一个」，这一格是「去管我的表」——
/// 分类、分组、排序、历史都在那页上，弹层里塞不下。
///
/// 这儿没有「横屏」那一格：横屏不是一个单独要去的地方，需要它的其实只有画线。
/// 所以点周期行上的「画线」就直接横过去（见 `MainScreen.onChange(of: draw.active)`），
/// 画完自己转回来，底栏不必为它留一格。
struct BottomBar: View {
  var theme: PanelTheme
  /// 哪个亮着。面板开着时对应那个是琥珀色（原型 `syncTools()`）。
  var active: Panel?
  var onPanel: (Panel) -> Void
  var onReview: () -> Void
  var reviewCount: Int
  var onFavorites: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      item(VectorIcon.chart, "复盘", on: false, action: onReview)
        .accessibilityIdentifier("bottom.review")
        .overlay(alignment: .top) {
          if reviewCount > 0 {
            Text("\(min(reviewCount, 99))")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(theme.badgeInk)
              .padding(.horizontal, 4).padding(.vertical, 1.5)
              .background(theme.amber, in: Capsule())
              .offset(x: 19, y: 1)
          }
        }
      tool(.indicator, VectorIcon.indicator, "指标") { onPanel(.indicator) }
        .accessibilityIdentifier("bottom.indicator")
      item(VectorIcon.star(), "自选", on: false, action: onFavorites)
        .accessibilityIdentifier("bottom.favorites")
      tool(.settings, VectorIcon.settings, "设置") { onPanel(.settings) }
        .accessibilityIdentifier("bottom.settings")
    }
    .padding(.top, 6)
    .padding(.bottom, 2)
  }

  private func tool(
    _ which: Panel, _ icon: VectorIcon, _ title: String, action: @escaping () -> Void
  ) -> some View {
    item(icon, title, on: active == which, action: action)
  }

  /// 一格：18pt 的线性图标坐在一颗 42×27 的胶囊里，下面 10pt 的名字（原型 `.tabs`）。
  /// 亮着的那格不是只把字染色——胶囊垫一层 15% 的强调底，四格并排时一眼看得出在哪儿。
  private func item(
    _ icon: VectorIcon, _ title: String, on: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        icon.sized(18)
          .frame(width: 42, height: 27)
          .background(on ? theme.amberSoft : .clear, in: Capsule())
        Text(title).font(.system(size: 10, weight: on ? .semibold : .medium))
      }
      .foregroundStyle(on ? theme.amber : theme.ink3)
      .padding(.top, 4)
      .padding(.bottom, 6)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? [.isSelected] : [])
  }
}

/// 一句话提示（原型 `.toast`）。
///
/// 没有「撤销」时 1.6 秒自己消失；带「撤销」时停 5 秒——按钮得给人反应过来的时间，
/// 1.6 秒够不上「看清楚 + 决定 + 抬手点」。停多久由外面的 `say(_:undo:)` 定，
/// 这儿只管画。
///
/// 全屏同一时刻只有这一层：新的一句直接顶掉旧的，不叠不排队。
struct Toast: View {
  var theme: PanelTheme
  var text: String
  /// 右边那颗按钮上的字。绝大多数带动作的提示都是「撤销」，所以它是默认值；
  /// 「已记下 · 查看」那种「去看看刚才那条」也走同一条通道（§2F2），
  /// 免得为一颗按钮再养一套 toast。
  var actionTitle = "撤销"
  /// 右边那颗按钮。nil 就是一条普通提示，不画按钮。
  var undo: (() -> Void)?

  var body: some View {
    HStack(spacing: 10) {
      Text(text)
      if let undo {
        // 中间点一个间隔点，别让文案和按钮糊成一句话。
        Text("·").foregroundStyle(theme.ink3)
        Button(actionTitle, action: undo)
          .buttonStyle(.plain)
          .foregroundStyle(theme.amber)
          .accessibilityIdentifier(actionTitle == "撤销" ? "toast.undo" : "toast.action")
      }
    }
      .font(.system(size: 12.5))
      .foregroundStyle(theme.ink)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 20).fill(theme.raised)
          .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.line, lineWidth: 1)))
      .shadow(color: .black.opacity(theme.dark ? 0.5 : 0.12), radius: 12, y: 4)
      .transition(.opacity)
  }
}
