import SwiftUI

/// 底栏那四格。
///
/// 2026-09-18 它从「几个入口按钮」改成了常驻标签栏。用户的话是「大部分 app 把常用的
/// 大分页都固定在底部，比如 tv 和推特都是，底部是固定的，切换页面下面还是那样」——
/// 以前「自选」是全屏 cover、「设置」是半屏 sheet、「复盘」是另一层 cover，一层盖一层，
/// 人不知道自己在第几层，只能一路退回去。现在四格各是一张整页，底栏永远在，
/// 换页就是换一格。
///
/// 顺序是用户定死的：**画线 · 图表 · 自选 · 设置**。他的话是「本来行情 app 这个
/// 就很重要」——画线值一格；「复盘放到图表里」，所以复盘不在底栏上（它挪到了行情页
/// 顶栏那颗带角标的按钮），「指标」也不在（并进了「图表设置」）。
enum Tab: String, CaseIterable, Sendable {
  case draw, chart, favorites, settings

  var title: String {
    switch self {
    case .draw: "画线"
    case .chart: "图表"
    case .favorites: "自选"
    case .settings: "设置"
    }
  }

  var icon: VectorIcon {
    switch self {
    case .draw: VectorIcon.draw
    case .chart: VectorIcon.chart
    case .favorites: VectorIcon.star()
    case .settings: VectorIcon.settings
    }
  }

  /// 能不能停在这一格。
  ///
  /// 「画线」是个动作不是去处：点它是「把当前这张图横过来画」，画完自动转回行情页
  /// （见 `kanpan-landscape-is-for-drawing`）。所以它永远不是那个「回来之后还停在
  /// 这儿」的格子，选中态只在真的在画的时候亮。
  var isRestingPlace: Bool { self != .draw }
}

/// 常驻标签栏：四格等宽，谁亮着谁是当前页。
struct TabBar: View {
  var theme: PanelTheme
  /// 停在哪一页。`draw` 不会是它——见 `Tab.isRestingPlace`。
  var current: Tab
  /// 正在画线。这时候亮的是最左边那格，而不是身下那张行情页。
  var drawing: Bool
  var onPick: (Tab) -> Void

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Tab.allCases, id: \.self) { tab in
        item(tab).accessibilityIdentifier("bottom.\(tab.rawValue)")
      }
    }
    .padding(.top, 6)
    .padding(.bottom, 2)
  }

  private func on(_ tab: Tab) -> Bool {
    drawing ? tab == .draw : tab == current
  }

  /// 一格：18pt 的线性图标坐在一颗 42×27 的胶囊里，下面 10pt 的名字（原型 `.tabs`）。
  /// 亮着的那格不是只把字染色——胶囊垫一层 15% 的强调底，四格并排时一眼看得出在哪儿。
  private func item(_ tab: Tab) -> some View {
    let on = on(tab)
    return Button { onPick(tab) } label: {
      VStack(spacing: 3) {
        tab.icon.sized(18)
          .frame(width: 42, height: 27)
          .background(on ? theme.amberSoft : .clear, in: Capsule())
        Text(tab.title).font(.system(size: 10, weight: on ? .semibold : .medium))
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
