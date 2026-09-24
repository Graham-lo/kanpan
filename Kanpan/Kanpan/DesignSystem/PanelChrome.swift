import SwiftUI
import KanpanCore

/// 四个面板共用的零件：半屏壳、行、分段、开关、分组标题、步进器、脚注、toast。
/// 字号、间距、圆角、命中区一律取 `DesignTokens`（2026-09-24 HIG 整改 P0b），改这里就是改所有面板。

// MARK: - 壳

/// 半屏面板的外壳：「‹」 + 标题 + 副标题 + 可滚动的正文（原型 `.sheet / .sheeth / .sheetb`）。
///
/// 左上角那颗「‹」不是装饰：面板被拉到全屏之后，下拉指示条还在，但整页占满屏幕，
/// 「往下拽」这件事在一个全是滚动内容的页面上不成立——实测在图表面板里拉到全屏就出不来了，
/// 只能杀进程。所以每个面板都常驻一个明确的出口。
///
/// 它原来是标题右边的文字「完成」。用户 2026-09-15 指出「很多页面左上方都没有返回按钮，
/// 你看 aicoin」——手机 AICoin 的每一层都在左上角摆一颗「‹」，出口永远在同一个位置，
/// 不用每进一页先找一遍。所以这里把出口搬到左上角，并和自选页（`favorites.back`）、
/// 品种页（`symbols.back`）统一成同一个手势。标识符仍叫 `panel.done`，UI 测试沿用。
///
/// 2026-09-18 加了 `asPage`：底栏换成常驻标签栏之后，「设置」不再是半屏叫出来的
/// 一张面板，而是标签栏上的一整页。整页没有「返回哪儿」可言（返回就是换一格标签），
/// 所以那颗「‹」只在半屏／侧栏模式下画；底色也从浮起来的 `raised` 换成页面的 `app`，
/// 免得一整页浮在一整页上面，读成两块拼接的材料。
struct PanelSheet<Content: View>: View {
  var title: String
  var subtitle: String?
  /// 当作标签栏上的一整页来画：不画左上角的「‹」，底色用页面底色。
  var asPage: Bool = false
  /// 标题行右端那一个字按钮（如提醒总表的「新建」）。一页最多一个。
  var action: PanelSheetAction? = nil
  /// 面板里推进去的下一层（「图表设置 › 指标」）：左上角的「‹」回上一层，不关面板。
  var onBack: (() -> Void)? = nil
  @ViewBuilder var content: () -> Content

  @Environment(\.panelTheme) private var t
  /// 横屏侧栏没有系统 `dismiss`，走主界面递进来的这一条（见 `PanelCloser`）。
  @Environment(\.panelDismiss) private var sideDismiss
  @Environment(\.dismiss) private var dismiss
  @Environment(\.panelHPad) private var hPad

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 0) {
        if !asPage {
          Button { if let onBack { onBack() } else { PanelCloser(side: sideDismiss, sheet: dismiss)() } } label: {
            Image(systemName: "chevron.left")
              .font(TypeScale.title)
              // 箭头的笔画左对齐到正文的 `hPad`，点击区从屏幕边一直撑到 44 以外，画面不动。
              .padding(.leading, hPad)
              .frame(minWidth: Hit.min + Space.xs, minHeight: Hit.min, alignment: .leading)
              .contentShape(Rectangle())
          }
          .foregroundStyle(t.amber)
          .buttonStyle(.plain)
          .accessibilityLabel("返回")
          .accessibilityIdentifier("panel.done")
        }

        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
          Text(title).font(PanelFont.title).foregroundStyle(t.ink)
            .accessibilityIdentifier("panel.header")
          if let subtitle {
            Text(subtitle).font(PanelFont.sub).foregroundStyle(t.ink3)
          }
        }
        Spacer(minLength: 0)
        if let action {
          Button(action: action.run) {
            Text(action.title).font(PanelFont.title).foregroundStyle(t.amber)
              .hitTarget()
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier(action.id)
        }
      }
      // 「‹」自己带着 `hPad` 的左留白（点击区要贴到屏幕边）；整页模式下没有它，
      // 标题直接用 `hPad`。标题行至少 44 高，有没有「‹」都一样高。
      .frame(minHeight: Hit.min)
      .padding(.leading, asPage ? hPad : 0)
      .padding(.trailing, hPad)
      .padding(.vertical, Space.xs)
      .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }

      ScrollView {
        VStack(spacing: 0) { content() }
          .padding(.top, Space.xs)
          .padding(.bottom, Space.l)
      }
      .scrollBounceBehavior(.basedOnSize)
      .accessibilityIdentifier("panel.content")
    }
    .background(asPage ? t.app : t.raised)
    .accessibilityLabel(title)
  }
}

/// `PanelSheet` 标题行右端的字按钮。
struct PanelSheetAction {
  var title: String
  var id: String
  var run: () -> Void
}

// MARK: - 行

/// 一行：左边名字（可带一行灰字），右边随便塞个控件。底下一条发丝线。
struct PanelRow<Trailing: View>: View {
  var name: String
  var meta: String?
  /// 名字前面的小色块（指标面板用）。
  var swatch: Color?
  /// 当前项用琥珀色标出来（周期面板用）。
  var highlighted: Bool = false
  var divider: Bool = true
  var onTap: (() -> Void)?
  /// 长按（§10.6 的「长按加入 / 移出常用行」）。
  var onLongPress: (() -> Void)?
  @ViewBuilder var trailing: () -> Trailing

  @Environment(\.panelTheme) private var t
  /// 外面 `.disabled(...)` 了这一行（如对比满三只时的「添加对比品种」），名字换成禁用色阶。
  @Environment(\.isEnabled) private var enabled
  /// 半屏里 16；拼到整页上时跟页面外边距走（`panelPageInset()`）。
  @Environment(\.panelHPad) private var hPad

  var body: some View {
    let row = HStack(spacing: PanelMetrics.rowGap) {
      VStack(alignment: .leading, spacing: Space.xxs) {
        HStack(spacing: Space.xs) {
          if let swatch { PanelSwatch(color: swatch) }
          Text(name)
            .font(PanelFont.name)
            .foregroundStyle(!enabled ? PanelDisabled.ink(t) : highlighted ? t.amber : t.ink)
        }
        if let meta {
          Text(meta).font(PanelFont.meta).foregroundStyle(t.ink3)
        }
      }
      Spacer(minLength: 0)
      trailing()
    }
    .padding(.horizontal, hPad)
    .padding(.vertical, PanelMetrics.vPad)
    .frame(minHeight: Inset.rowMin)
    .contentShape(Rectangle())
    .overlay(alignment: .bottom) {
      if divider { Rectangle().fill(t.hair).frame(height: 1) }
    }

    if let onTap {
      Button(action: onTap) { row }
        .buttonStyle(.plain)
        .modifier(LongPress(action: onLongPress))
    } else {
      row.modifier(LongPress(action: onLongPress))
    }
  }
}

extension PanelRow where Trailing == EmptyView {
  init(name: String, meta: String? = nil, swatch: Color? = nil,
       highlighted: Bool = false, divider: Bool = true,
       onTap: (() -> Void)? = nil, onLongPress: (() -> Void)? = nil) {
    self.init(name: name, meta: meta, swatch: swatch, highlighted: highlighted,
              divider: divider, onTap: onTap, onLongPress: onLongPress,
              trailing: { EmptyView() })
  }
}

/// 名字前面那颗指标色块（行里、「正在用」列表里同一个尺寸）。
struct PanelSwatch: View {
  var color: Color
  var body: some View {
    RoundedRectangle(cornerRadius: Space.xxs, style: .continuous)
      .fill(color)
      .frame(width: Space.s, height: Space.s)
  }
}

extension View {
  /// 行尾控件（字按钮、开关、分段）的命中区：撑到 44×44——正好一整行高——但只向布局报告
  /// 行里正文那么高，所以行不会因此变高。只用在 `PanelRow` 的 trailing 里（它上下各留 `vPad`）。
  func rowHitTarget() -> some View {
    hitTarget().padding(.vertical, -PanelMetrics.vPad)
  }
}

/// 面板里禁用态的颜色。
///
/// 审查量过：「加提醒」「分享卡」「清空全部画线」原来是整块 `opacity(0.4)`，文字与底色只剩
/// 1.05–1.6:1，看上去像没画出来。现在字一律不靠透明度淡化：禁用的字换成 `ink3`（三套皮肤、
/// 深浅色下对 `raised`／`raised2` 最差 3.5:1），强调色的底换成中性的 `raised2`，
/// 只有纯装饰（图标、色块）才乘 `ControlMetrics.disabledOpacity`。
enum PanelDisabled {
  /// 主按钮（琥珀底）禁用时的底色与字色。
  static func fill(_ t: PanelTheme) -> Color { t.raised2 }
  static func ink(_ t: PanelTheme) -> Color { t.ink3 }
}

/// 有就挂上，没有就什么都不做——省得每处写一遍 `if let`。
private struct LongPress: ViewModifier {
  var action: (() -> Void)?

  func body(content: Content) -> some View {
    if let action {
      content.onLongPressGesture(minimumDuration: 0.32, perform: action)
    } else {
      content
    }
  }
}

// MARK: - 分段

/// 原型 `.seg`：两到三格，选中那格底色抬起来。
struct PanelSegment<Value: Hashable>: View {
  var options: [(String, Value)]
  var selection: Value
  /// 给每一档挂 `<前缀>.<档位文字>` 的标识（比如 `chart.bodyChoice.空心`）。
  ///
  /// 分段这一排必须走这里，不能像开关那样把标识挂在 `PanelRow` 上：挂在行上的标识会
  /// **原样传给行里每一个无障碍元素**，开关那种一行只有一个元素的没事，分段却会让两三颗
  /// 按钮顶着同一个标识，`app.buttons["chart.bodyChoice"]` 拿到的是一团分不开的东西，
  /// 用例只能退回按坐标猜。所以分段行一律把行上的标识撤掉，改从这里逐档下发。
  var id: String? = nil
  /// 槽的底色。缺省 `raised2`（整页铺在 `raised` 上的设置行）；放进本身就是 `raised2` 的
  /// 分组卡片里时（创建提醒页），槽会化进卡片，由调用方换成页面那一层的底。
  var track: Color? = nil
  var pick: (Value) -> Void

  @Environment(\.panelTheme) private var t

  var body: some View {
    // 画面上是一条 32 高的槽（28 的档 + 上下各 2），但每一档的点击区是 44 高、撑满整行；
    // 多出来的那截用负边距还给布局，行高仍是 44。
    HStack(spacing: Space.xxs) {
      ForEach(options, id: \.1) { text, value in
        let on = value == selection
        Button { pick(value) } label: {
          Text(text)
            .font(PanelFont.seg)
            .foregroundStyle(on ? t.ink : t.ink2)
            .padding(.horizontal, Space.m)
            .frame(minHeight: ControlMetrics.pillHeight)
            .background {
              if on {
                RoundedRectangle(cornerRadius: Radius.concentric(outer: Radius.s, padding: Space.xxs),
                                 style: .continuous)
                  .fill(t.segOn)
                  .shadow(color: .black.opacity(0.09), radius: 1, y: 1)
              }
            }
            .frame(minHeight: Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id.map { "\($0).\(text)" } ?? "")
        .accessibilityAddTraits(on ? [.isSelected] : [])
      }
    }
    .padding(.horizontal, Space.xxs)
    .background {
      RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        .fill(track ?? t.raised2)
        .padding(.vertical, (Hit.min - ControlMetrics.pillHeight) / 2 - Space.xxs)
    }
    .padding(.vertical, -PanelMetrics.vPad)
  }
}

// MARK: - 控件边界

extension PanelTheme {
  /// 控件的边界色：开关关着时的槽、没选中的配色卡描边。对页面底（`app`）和浮层底（`raised`）
  /// 都 ≥ 3:1（WCAG 1.4.11 非文字对比，UI 审查 2026-09-24）。
  ///
  /// 原来槽取的是 `line`（深色取 `raised2`），六套种子实测只有 1.1–1.5:1，关着的开关
  /// 在青苔深上几乎看不出槽（`整改/P1b/设置整页-底部-青苔深.png`）。`line` 当分隔线够，
  /// 当控件边界不够，所以从 `line` 往 `ink` 一档一档调深，调到两块底都够 3:1 为止——
  /// 和 `Palette.readable` 同一个做法，只是门槛是非文字的 3:1。六套种子的结果：
  /// 青苔 #839088 / #5E6A64、陶土 #998D81 / #716459、经典 #909693 / #686E72（浅 / 深）。
  var controlLine: Color {
    let surfaces = [seed.app, seed.raised]
    for step in 0...100 {
      let candidate = Palette.mix(seed.line, seed.ink, amount: 1 - Double(step) / 100)
      if surfaces.allSatisfy({ Palette.contrast(candidate, $0) >= 3 }) { return Color(hex: candidate) }
    }
    return ink3
  }
}

// MARK: - 开关

/// 原型 `.sw`：44 × 26，开着填强调色。不用系统 `Toggle`，因为系统的绿不在配色里。
struct PanelSwitch: View {
  var isOn: Bool
  var toggle: () -> Void

  @Environment(\.panelTheme) private var t

  var body: some View {
    Button(action: toggle) {
      ZStack(alignment: isOn ? .trailing : .leading) {
        // 关着的槽取 `controlLine`（≥ 3:1），不再是几乎和底一样的 `switchOff`。
        Capsule().fill(isOn ? t.switchOn : t.controlLine)
        Circle()
          .fill(t.switchKnob)
          .frame(width: 20, height: 20)
          .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
          .padding(3)
      }
      .frame(width: 44, height: 26)
      .animation(.easeOut(duration: 0.18), value: isOn)
      .rowHitTarget()
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isButton)
    .accessibilityValue(isOn ? "开" : "关")
  }
}

// MARK: - 分组标题 / 脚注

/// 原型 `.groupt`：小号、加字距的灰标题。
struct PanelGroupTitle: View {
  var text: String
  @Environment(\.panelTheme) private var t
  @Environment(\.panelHPad) private var hPad

  var body: some View {
    Text(text)
      .font(PanelFont.group)
      .tracking(1)
      .foregroundStyle(t.ink3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, hPad)
      .padding(.top, Space.xl)
      .padding(.bottom, Space.s)
  }
}

/// 系统 `Form` / `List` 里那一行分节标题。
///
/// 和上面那个 `PanelGroupTitle` 是同一支笔（`PanelFont.group` + `tracking(1)` + `ink3`），
/// 只是不自带内边距——`Section` 的 header 由表自己缩进，再加一层就会比行文更往里一格。
/// 内建的 `Section("字面量")` 不能用：那一行是系统的 secondary label 灰，三套皮肤下
/// 一模一样，压在已经跟着皮肤走的表上是这一屏唯一不换肤的字。
/// 定义只此一份，`IndicatorEditor` 与 `DrawingStyleEditor` 都用它。
struct PanelFormSectionTitle: View {
  var text: String
  @Environment(\.panelTheme) private var t

  var body: some View {
    Text(text).font(PanelFont.group).tracking(1).foregroundStyle(t.ink3)
  }
}

// MARK: - toast

// 面板从前自己养一条 `PanelToast`（主界面那条被半屏面板盖住了）。P2.7 起全 app 只有一条
// 提示 `ToastCenter`，画在所有面板之上；面板里 `store.note(...)` 说的话由宿主
// （`MainScreen` 的 `onStoreNotice`）转过去，这里不再画任何东西。
