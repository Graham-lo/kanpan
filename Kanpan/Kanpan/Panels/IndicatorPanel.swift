import SwiftUI
import UIKit
import KanpanCore

/// 「分析」面板：周期条行尾「分析」直达（`Panel.indicators`），半屏面板里的一整页。
/// 四节：**画线 · 指标 · 对比 · 主力订单流**（2026-09-28 起；之前这一页和行尾那格都叫「指标」）。
///
/// 2026-09-18 指标并进「图表设置」时，是十三个开关连同每个开着的指标底下那块「参数与颜色」
/// 一股脑铺在那一页上的——再往下还有一段「副图顺序」。开得越多，这一页越长，坐标轴、
/// 网格那几行被推到三四屏之后。2026-09-23 用户的话是「新加的指标全部堆积在图表里，
/// 应该在图表中增加一个指标，点击指标跳到专门的指标设置页面」，于是有了这一页：
///
/// - 最上面「正在用」一段只列开着的指标，参数直接写在行上，点一行进参数表，
///   副图那几行右端的把手拖动就是换顺序——原来单独那段「副图顺序」并进来了；
/// - 下面两段只有开关，不再夹参数块。
///
/// 2026-09-27（方案「我的 · 自动复盘 · 周期分组指标」§1.3）：这一页分三节——
/// **指标 · 对比 · 主力订单流**。「对比」整节从「图表设置」搬了过来，主力订单流也从「主图叠加」
/// 那排开关里拎出来单成一节（开关 + 门槛）。三样都是「往图上叠一层东西」，一个入口开关完；
/// 「图表设置」里那一行「指标」同一天撤了，这一页从此只有周期条这一条路进来，没有上一层可回，
/// 左上角那颗就是关面板。
///
/// 2026-09-28 画线和指标并列归到一个大类「分析」（用户：「周期条中的画线和指标能不能归到一个大类，
/// 只放三个，更多，原来是指标，设置，不然布局会有问题」）：周期条行尾四件挤得命中区互相叠，
/// 画线那颗记号挪进这一页、排在最上面单成一节，行尾回到「更多 ▾ · 分析 · 图表设置」三件，
/// 这一页的标题跟着行尾改叫「分析」，「指标」只作第二节的节名。
///
/// 参数编辑那层 sheet 和面板提示仍挂在这一层自己身上。
struct IndicatorPage: View {
  var store: PrefsStore
  /// 主力订单流的胶水与当前品种（它那张表要显示这只币此刻生效的门槛）。
  var orderFlow: OrderFlowLink? = nil
  var symbol: String = ""
  /// 「添加对比品种」：关面板、开品种搜索。此刻不能对比（复盘回放、横屏画线台）时调用方传 nil，
  /// 「对比」这一节整节不排。
  var onAddCompare: (() -> Void)? = nil
  /// 对比品种键 → 显示名（主界面按品种表算好递进来，这儿不查表）。
  var compareNames: [String: String] = [:]
  /// 「画线」：关面板、把这张图横过来进画线工作台。复盘回放、已经在画时调用方传 nil，
  /// 「画线」这一节整节不排（和对比那节同一个判法）。
  var onDraw: (() -> Void)? = nil
  /// 对比期间画不了线：那一行置灰、点不动（原来周期条那颗记号的 `drawEnabled`）。
  var drawEnabled = true
  @State private var editing: IndicatorID?
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 横屏侧栏没有系统 `dismiss`，走主界面递进来的这一条（见 `PanelCloser`）。
  @Environment(\.panelDismiss) private var sideDismiss

  private var prefs: Prefs { store.prefs }
  /// 对比那几个动作要先收面板再做（搜索页、看得见图），竖屏 sheet / 横屏侧栏一律走这里。
  private var close: PanelCloser { PanelCloser(side: sideDismiss, sheet: dismiss) }
  /// 主图叠加那排开关里不再有主力订单流——它单成了一节。
  private static let overlayPalette = IndicatorID.mainPalette.filter { $0 != .orderFlow }

  var body: some View {
    PanelSheet(title: Panel.indicators.title, subtitle: nil) {
      drawSection

      // 「指标」这一节：节名压在开着的那几项上（原来这里叫「正在用」），下面是两段开关。
      // 一项都没开时不让两行节名叠在一起，节名并进第一段的标题里。
      let inUse = !prefs.overlays.isEmpty || !prefs.subs.isEmpty
      if inUse {
        PanelGroupTitle(text: "指标")
        InUseList(store: store, onEdit: { editing = $0 })
      }

      PanelGroupTitle(text: inUse ? "主图叠加" : "指标 · 主图叠加")
      ForEach(Self.overlayPalette, id: \.self) { id in
        row(id, last: id == Self.overlayPalette.last)
      }

      // 上限写在标题里：满了再点第四个是「换一个」而不是「点不动」，先把规矩摆出来。
      PanelGroupTitle(text: "副图 · 最多三个")
      ForEach(IndicatorID.subPalette, id: \.self) { id in
        row(id, last: id == IndicatorID.subPalette.last)
      }

      compareSection
      orderFlowSection

      // 指标按周期分组记忆（2026-09-27）唯一的管理入口：当前周期所在那一组回到出厂，别的组不动。
      // 已经是出厂那份时点不动（`PanelRow` 在禁用时自己换禁用色阶）。
      PanelRow(name: "恢复这一组的默认", divider: false, onTap: {
        store.resetIndicatorLayoutForCurrentGroup()
        Haptics.warning()
      })
      .padding(.top, Space.xl)
      .disabled(prefs.indicatorLayout == .factory)
      .accessibilityIdentifier("indicator.resetGroup")
    }
    .sheet(item: $editing) { id in
      if id == .orderFlow {
        OrderFlowEditor(store: store, link: orderFlow, symbol: symbol).environment(\.panelTheme, t)
      } else {
        IndicatorEditor(store: store, id: id).environment(\.panelTheme, t)
      }
    }
  }

  /// 画线：一行，行尾是原来周期条上那颗 24pt 记号（`IntervalDrawGlyph`）。点它先收面板，
  /// 再做原来周期条上那颗做的事（`MainScreen.startDrawing`：横屏进画线工作台，画完自动转回）。
  /// 横屏侧栏里开的这一页（`sideDismiss` 那条路）不排——侧栏在，要么已经在画，要么手边就有
  /// `ToolRail` 那一格「画线」。
  @ViewBuilder private var drawSection: some View {
    if let onDraw, sideDismiss == nil {
      PanelGroupTitle(text: "画线")
      // 行名不重复「画线」：分组标题已经念过一遍（2026-09-24 审查 U4，和主力订单流那节同一条规矩）。
      PanelRow(name: "开始画线", divider: false, onTap: { close(); onDraw() }) {
        IntervalDrawGlyph(theme: t, size: 24)
          .opacity(drawEnabled ? 1 : ControlMetrics.disabledOpacity)
          .accessibilityHidden(true)
      }
      .disabled(!drawEnabled)
      .accessibilityIdentifier("indicator.draw")
    }
  }

  /// 对比 K 线（`Kanpan/Kanpan/Compare/`）：最多三只，颜色跟皮肤色板走，不给选。
  /// 原样搬自「图表设置」（2026-09-27），标识不变：`compare.add` / `compare.remove.<键>` / `compare.clear`。
  @ViewBuilder private var compareSection: some View {
    if let onAddCompare {
      PanelGroupTitle(text: "对比")
      // 满三只时这一行点不动；`PanelRow` 在禁用时自己把字换成禁用色阶。
      PanelRow(name: "添加对比品种", divider: !prefs.compareSymbols.isEmpty, onTap: { close(); onAddCompare() })
        .disabled(prefs.compareSymbols.count >= 3)
        .accessibilityIdentifier("compare.add")
      ForEach(prefs.compareSymbols, id: \.self) { key in
        PanelRow(name: compareNames[key] ?? String(key.split(separator: "/").last ?? "")) {
          Button { store.updateByHand { $0.compareSymbols.removeAll { $0 == key } }; close() } label: {
            Text("移除").font(PanelFont.seg).foregroundStyle(t.ink2).rowHitTarget()
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("compare.remove." + key)
        }
      }
      if !prefs.compareSymbols.isEmpty {
        PanelRow(name: "清除对比", divider: false, onTap: { store.updateByHand { $0.compareSymbols = [] }; close() })
          .accessibilityIdentifier("compare.clear")
      }
    }
  }

  /// 主力订单流：一颗开关，开着时底下多一行「门槛」进它那张表（原来在「正在用」里点它那一行进）。
  /// 行右写这只币的门槛动没动过。标识沿用 `indicator.switch.ORDERFLOW` / `indicator.edit.ORDERFLOW`。
  @ViewBuilder private var orderFlowSection: some View {
    PanelGroupTitle(text: IndicatorID.orderFlow.name)
    // 行名不再重复「主力订单流」：分组标题已经念过一遍（2026-09-24 审查 U4 同一条规矩）。
    PanelRow(name: "在图上显示", swatch: t.swatch(.orderFlow), divider: prefs.orderFlow) {
      PanelSwitch(isOn: prefs.orderFlow) { store.byHand { $0.toggleIndicator(.orderFlow) } }
        .accessibilityIdentifier("indicator.switch.\(IndicatorID.orderFlow.rawValue)")
    }
    if prefs.orderFlow {
      let base = orderFlow?.currentFacts?.overrideKey
      let meta = base.map { "\($0) · " + (prefs.orderFlowOverrides[$0] == nil ? "默认门槛" : "已改门槛") } ?? ""
      PanelRow(name: "门槛", divider: false, onTap: { editing = .orderFlow }) {
        HStack(spacing: Space.s) {
          if !meta.isEmpty {
            Text(meta).monospacedDigit().font(PanelFont.meta).foregroundStyle(t.ink3).lineLimit(1)
          }
          VectorIcon.chevron(ControlMetrics.chevron, w: 1.7).rotationEffect(.degrees(-90)).foregroundStyle(t.ink3)
        }
      }
      .accessibilityLabel(meta.isEmpty ? "门槛" : "门槛，\(meta)")
      .accessibilityIdentifier("indicator.edit.\(IndicatorID.orderFlow.rawValue)")
    }
  }

  private func row(_ id: IndicatorID, last: Bool) -> some View {
    let on = prefs.isOn(id)
    return PanelRow(name: id.name, swatch: t.swatch(id), divider: !last) {
      PanelSwitch(isOn: on) { store.byHand { $0.toggleIndicator(id) } }
        .accessibilityIdentifier("indicator.switch.\(id.rawValue)")
    }
  }
}

// MARK: - 正在用

/// 开着的指标，一行一个：名字、参数、「›」。副图那几行右端多一个把手，拖它换顺序。
///
/// 拖法沿用原来「副图顺序」那一段（§10.6）：行高固定，位移除以行高就是挪几格，松手就定。
/// 主图叠加不排序——几条均线叠在同一张图上，谁先谁后看不出来。
/// 主力订单流 2026-09-27 起不在这一段：它单成一节，门槛从那一节的「门槛」行进。
private struct InUseList: View {
  var store: PrefsStore
  var onEdit: (IndicatorID) -> Void
  @Environment(\.panelTheme) private var t

  @State private var dragging: IndicatorID?
  @State private var offset: CGFloat = 0

  /// 和 `PanelRow` 同一个行高，同一张表节奏一致。
  private static let rowH: CGFloat = Inset.rowMin

  private var prefs: Prefs { store.prefs }
  /// 这一段里有没有带把手的行（副图）。有的话，没把手的行（主图叠加）在同一个位置
  /// 垫一块同宽的空位，参数和「›」才落在同一条竖线上（UI 整改 P2）。
  private var hasHandles: Bool { !prefs.subs.isEmpty }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(prefs.overlays.filter { $0.placement == .main }, id: \.self) { id in
        line(id, index: nil)
      }
      ForEach(Array(prefs.subs.enumerated()), id: \.element) { index, id in
        line(id, index: index)
          .background(dragging == id ? t.raised2 : .clear)
          .offset(y: dragging == id ? offset : 0)
          .zIndex(dragging == id ? 1 : 0)
      }
    }
    .animation(.easeOut(duration: 0.15), value: prefs.subs)
    .overlay(alignment: .bottom) { Rectangle().fill(t.hair).frame(height: 1) }
  }

  private func line(_ id: IndicatorID, index: Int?) -> some View {
    let params = prefs.params(for: id).map(String.init).joined(separator: " · ")
    let resized = id.placement == .sub && prefs.subHeightOverrides[id] != nil
    return HStack(spacing: 0) {
      Button { onEdit(id) } label: {
        HStack(spacing: PanelMetrics.rowGap) {
          HStack(spacing: Space.xs) {
            PanelSwatch(color: t.swatch(id))
            Text(id.name).font(PanelFont.name).foregroundStyle(t.ink).lineLimit(1)
          }
          Spacer(minLength: 0)
          if !params.isEmpty {
            Text(params).monospacedDigit().font(PanelFont.meta).foregroundStyle(t.ink3).lineLimit(1)
          }
          VectorIcon.chevron(ControlMetrics.chevron, w: 1.7).rotationEffect(.degrees(-90)).foregroundStyle(t.ink3)
        }
        .padding(.leading, PanelMetrics.hPad)
        .padding(.trailing, hasHandles ? Space.xs : PanelMetrics.hPad)
        .frame(height: Self.rowH)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(params.isEmpty ? id.name : "\(id.name)，\(params)")
      .accessibilityIdentifier("indicator.edit.\(id.rawValue)")

      // 在图上拖过副图高度才出现的那条退路（高度只在图上拖，这儿不给档位）。
      if resized {
        Button { store.updateByHand { $0.subHeightOverrides[id] = nil } } label: {
          Text("还原高度").font(PanelFont.seg).foregroundStyle(t.amber)
            .frame(height: Self.rowH)
            .hitTarget()
        }
          .buttonStyle(.plain)
          .padding(.leading, Space.s)
          .accessibilityIdentifier("indicator.height.reset.\(id.rawValue)")
      }

      if index == nil, hasHandles {
        // 把手那一格的空位：同宽、同样借进边距，只占地方不画东西。
        Color.clear
          .frame(width: Hit.min, height: Self.rowH)
          .padding(.trailing, PanelMetrics.hPad - Space.m)
          .accessibilityHidden(true)
      }
      if let index {
        Image(systemName: "line.3.horizontal")
          .font(TypeScale.bodyEmph)
          .foregroundStyle(t.ink3)
          .frame(width: Hit.min, height: Self.rowH)
          .contentShape(Rectangle())
          .gesture(drag(id: id, index: index))
          // 把手的图形大致落在正文右缘 `hPad` 上：44 宽的点击区里图形居中，多出来的那截借进边距。
          .padding(.trailing, PanelMetrics.hPad - Space.m)
          .accessibilityElement()
          .accessibilityLabel("\(id.name)，第 \(index + 1) 个副图")
          .accessibilityIdentifier("indicator.order.\(id.rawValue)")
          .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: store.updateByHand { $0.moveSub(from: index, to: index + 1) }
            case .decrement: store.updateByHand { $0.moveSub(from: index, to: index - 1) }
            default: break
            }
          }
      }
    }
  }

  private func drag(id: IndicatorID, index: Int) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { g in
        dragging = id
        offset = g.translation.height
      }
      .onEnded { g in
        let steps = Int((g.translation.height / Self.rowH).rounded())
        dragging = nil
        offset = 0
        guard steps != 0 else { return }
        store.updateByHand { $0.moveSub(from: index, to: index + steps) }
      }
  }
}

#if DEBUG
#Preview("指标") {
  PanelPreviewHost { store in IndicatorPage(store: store, onAddCompare: {}) }
}
#endif

/// 指标参数编辑：全 app **唯一**一处「要按『保存』才生效」的设置，是**已知且有意的例外**。
///
/// 别处的开关一律即时生效（用户定的规矩：改过的东西要立刻跟上）。这一张不行——
/// 一组指标参数是要一起改的几个数（周期、快慢线、上下轨），逐字符生效意味着把
/// 「20」改成「60」的路上图会先按「6」重算一次，画面当场乱跳；而且删到空的那一瞬
/// 参数是非法的。所以这儿拿一份 `draft`，按「保存」才一次性落进 `Prefs`。
///
/// 独立的 draft 生命周期同时让「返回 / 取消 / 下滑关掉」三种退出方式结果一致——
/// 都是不保存。下一个人看到这儿别当 bug 修掉。
extension IndicatorID: @retroactive Identifiable { public var id: String { rawValue } }
private struct IndicatorEditor: View {
  var store: PrefsStore
  @State private var draft: IndicatorDraft
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 正在打字的是哪一格。数字键盘没有回车键，收键盘只有「下滑」和右上角「保存」两条路，
  /// 所以焦点得由这儿统一管——「保存」要先把手上这一格提交掉，再关面板。
  @FocusState private var focus: ParamFocus?
  /// 正在打字那几格的字面值（一般只有一格）。提交或离开就抹掉，那一格回去显示 draft 里的数。
  /// 放在这张表身上而不是各格自己身上，是为了「保存」能在同一个调用栈里把它算进去，
  /// 不用先点别处失焦。
  ///
  /// 这一份接手了审查 C-07 原来那个 `pendingText`：那条账是「手指落在保存上的那一刻，
  /// SwiftUI 先跑按钮动作还是先跑失焦回调没有保证，框里显示 999 存进去的是 9」。
  /// 现在「保存」走 `committed()`——在同一个调用栈里把手上这几格算进去再落盘，
  /// 一样不依赖失焦时序。
  @State private var typing: [ParamFocus: String] = [:]
  init(store: PrefsStore, id: IndicatorID) {
    self.store = store; _draft = State(initialValue: IndicatorDraft(id: id, prefs: store.prefs))
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          // 均线那几个指标「几条线」由用户定，能左滑删；MACD、KDJ 的参数个数是算法
          // 定死的，那儿连划都不该划得动，所以整条 ForEach 分两种写法。
          if variablePeriods {
            ForEach(Array(draft.params.indices), id: \.self) { paramRow($0) }
              .onDelete(perform: removePeriods)
            if draft.params.count < IndicatorDraft.maxPeriods {
              // 这一行不能用 `Button`：小尺寸 iPad 上数字键盘一起来，系统会把整张
              // 表单纸重新居中（实测抬高 170pt）；手指落下时焦点丢了、键盘收了、纸又
              // 落回去，`Button` 的按压跟踪就被这一跳判成「手指移出去了」而取消，
              // 用户的第一下只用来收键盘。点击手势不跟着视图跑，所以这一下能活下来。
              Text("添加周期")
                .foregroundStyle(t.amber)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { addPeriod() }
                .accessibilityIdentifier("indicator.param.add")
                .accessibilityAddTraits(.isButton)
            }
          } else {
            ForEach(Array(draft.params.indices), id: \.self) { paramRow($0) }
          }
          // RSI 的超买 / 超卖线 2026-09-28 起定在 70 / 30（收设置项 C 组），不再给上下限两格。
        } header: {
          PanelFormSectionTitle(text: "参数")
        }
        .listRowBackground(t.raised)

        // 「输出」一节（逐条线的显示开关）2026-09-28 收掉（收设置项 C 组）：线一律全画，
        // 不想要哪条均线就在上面左滑删掉那个周期。

        if draft.id == .ma || draft.id == .ema || draft.id == .vwap {
          Section {
            ForEach(Array(draft.outputs.enumerated()), id: \.offset) { index, name in
              DrawingColorControl(title: name, identifierPrefix: "indicator.color.\(index)", color: Binding(get: {
                let palette = store.prefs.chartColors(dark: colorScheme == .dark).palette
                return draft.colors[index] ?? palette[(index + draft.id.paletteOffset) % palette.count]
              }, set: { draft.colors[index] = $0 }))
            }
            // 同上：表单纸会在键盘起落时整张跳一下，按钮的按压跟踪扛不住，点击手势能。
            Text("恢复默认颜色")
              .foregroundStyle(t.amber)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
              .onTapGesture { Haptics.warning(); draft.colors = [:] }
              .accessibilityIdentifier("indicator.colors.reset")
              .accessibilityAddTraits(.isButton)
          } header: {
            PanelFormSectionTitle(text: "线条颜色")
          }
          .listRowBackground(t.raised)
        }
      }
      // 行文 15 regular，和面板行同一档（系统 `Form` 默认 17，在这里比标题还大）。
      .font(TypeScale.body)
      // 这张表是系统 `Form`，但配色得跟着皮肤走：底换成 `app`、行换成 `raised`、
      // 强调色（「添加周期」、开关、光标）走 `tint`。留着 `Form` 是因为分节、左滑删除
      // 和键盘避让都是它给的，自己搭一套只会把这几样做丢。
      //
      // 导航栏和表底同取 `app`。原来这儿给的是 `raised`：青苔浅色下 `raised` 是
      // `#FFFFFF`、表底 `app` 是 `#F3F7F4`，亮度比 1.08，导航栏下沿会横出一道
      // 看得见的台阶；六套皮肤里五套都有这道边（经典浅色两支同为 `#FFFFFF` 才碰巧无缝）。
      // 整屏要读成一块连续的材料，所以栏与表同色，`raised` 只留给**行**。
      .scrollContentBackground(.hidden)
      .background(t.app)
      .navigationTitle(draft.id.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(t.app, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      // 数字键盘没有回车键：下滑把它划走，或者直接按右上角「保存」，不用再多一颗「完成」。
      // （原来这儿写「输进去的数字是边打边生效的」，和这张表的 draft 模型对不上——
      //   它就是要按「保存」才生效的那一张，见上面 `IndicatorEditor` 的说明。）
      .scrollDismissesKeyboard(.interactively)
      // 焦点一挪：上一格提交，新一格把原值整段选上（验收 a）。
      .onChange(of: focus) { old, now in
        if let old { commit(old) }
        if now != nil { selectAllInFocusedField() }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .foregroundStyle(t.ink2)
            .accessibilityIdentifier("indicator.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          // 手指还停在某一格里也能直接按：`committed()` 把那格的字算进去之后才落盘
          // （验收 b，也是审查 C-07 那条账的现在这一版做法）。
          Button("保存") { save() }
            .fontWeight(.semibold)
            .foregroundStyle(t.amber)
            .accessibilityIdentifier("indicator.save")
        }
      }
    }
    .tint(t.amber)
    .presentationBackground(t.app)
  }

  /// 「保存」：先把手上还在打的那格算进去，再落盘、关面板。
  private func save() {
    let final = committed()
    store.updateByHand { final.save(into: &$0) }
    dismiss()
  }

  private func parameterLabel(_ index: Int) -> String {
    if [.ma, .ema, .vol].contains(draft.id) { return "周期\(index + 1)" }
    return draft.id.paramLabels[index]
  }

  /// 一格参数：只有输入框，没有加减。
  ///
  /// 2026-09-20 用户的话是「ma 参数一律改成手动输入框，不再搞那种加减，那个都没用」。
  /// 均线周期常常是 5 → 120 这种跨度，±1 的键按 115 下不是人干的事；点进去原值全选，
  /// 改一个数就只需要打那个数。
  private func paramRow(_ index: Int) -> some View {
    // 行上不能再挂一个 id：容器上的无障碍修饰会往下传给里面的输入框，把
    // `indicator.param.N.field` 盖成 `indicator.param.N`，用例就再也找不着这一格了。
    // 原来那个行 id 是给步进器用的，步进器没了，它也就没有主人。
    numberRow(.param(index), label: parameterLabel(index), value: draft.params[index],
              identifier: "indicator.param.\(index).field")
  }

  /// 一行「名字 + 数字框」。框里显示的是「正在打的字」，没在打就是 draft 里的数。
  private func numberRow(_ field: ParamFocus, label: String, value: Int, identifier: String) -> some View {
    ParamField(label: label,
               text: Binding(get: { typing[field] ?? String(value) },
                             set: { text in typing[field] = String(text.filter(\.isNumber).prefix(3)) }),
               field: field,
               focus: $focus,
               theme: t,
               identifier: identifier)
  }

  /// 把一格打完的字落进 draft。
  ///
  /// 空的、根本不是数字的**当没改过**——那一格回到原来的数，不清零（审查 C-07 第三段）。
  /// 越界的**夹回最近的那个边界**，不是丢掉：框里明明显示着 999，存进去却还是 10，
  /// 用户没有任何办法知道自己那一下没生效（C-07 的原话是「保存的必须是规范化之后的
  /// 那个数」，`PresenterAndStateUITests` 盯着它）。
  private func apply(_ field: ParamFocus, _ text: String, to draft: inout IndicatorDraft) {
    guard let n = Int(text) else { return }
    switch field {
    case .param(let index):
      guard draft.params.indices.contains(index) else { return }
      draft.params[index] = IndicatorParamRule.clamp(n)
    }
  }

  /// 把还在打字的那几格算进去之后的 draft。「保存」拿它落盘，
  /// 不依赖「先改 @State 再读回来」这种时序。
  private func committed() -> IndicatorDraft {
    var out = draft
    for (field, text) in typing { apply(field, text, to: &out) }
    return out
  }

  private func commit(_ field: ParamFocus) {
    guard let text = typing.removeValue(forKey: field) else { return }
    var out = draft
    apply(field, text, to: &out)
    draft = out
  }

  private func commitAll() {
    draft = committed()
    typing.removeAll()
  }

  /// 点进一格先把原值整段选上：直接打就是替换，不用先删。
  /// （原来是「点进来先清空」——清空之后那一格看着像空的，不知道自己刚才是几。）
  private func selectAllInFocusedField() {
    Task { @MainActor in
      UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
    }
  }

  /// 均线这类「几条线」由用户定；MACD、KDJ 那种参数个数是算法定死的，不能加也不能删。
  private var variablePeriods: Bool { [.ma, .ema, .vol].contains(draft.id) }

  private func addPeriod() {
    commitAll(); focus = nil
    let next = IndicatorParamRule.clamp((draft.params.last ?? 5) * 2)
    draft.params.append(next)
  }

  /// 删一条线时，线条颜色按位置存着，得跟着往前挪一格，否则颜色串到隔壁去了。
  /// 删一条之前先把手上那格提交掉、把「正在打的字」全抹掉：那几个字面值是按行号存的，
  /// 行一挪就串到隔壁去了。
  private func removePeriods(_ offsets: IndexSet) {
    guard draft.params.count - offsets.count >= 1 else { return }
    Haptics.warning()
    commitAll(); focus = nil
    for index in offsets.sorted(by: >) {
      draft.params.remove(at: index)
      draft.colors = Dictionary(uniqueKeysWithValues: draft.colors.compactMap { key, value in
        key == index ? nil : (key > index ? (key - 1, value) : (key, value))
      })
    }
  }
}

/// 这张表上要打字的那几格：参数逐格一个。
enum ParamFocus: Hashable {
  case param(Int)
}

/// 一格能直接打字的数。
///
/// 它只管显示和拿焦点：只收数字、最多三位（参数上限 400），
/// 打字途中不夹也不回写——图按中间值重算一次画面就乱跳，而且删到空的那一瞬是非法的。
/// 值什么时候落进 draft、非法了怎么办，全在 `IndicatorEditor` 那边一处说了算。
private struct ParamField: View {
  var label: String
  @Binding var text: String
  var field: ParamFocus
  var focus: FocusState<ParamFocus?>.Binding
  var theme: PanelTheme
  var identifier: String

  var body: some View {
    HStack(spacing: Space.m) {
      Text(label).foregroundStyle(theme.ink)
      Spacer(minLength: Space.s)
      // 一格能打字的数字，底垫一层 `raised2`：不垫的话它和左边的名字长得一模一样，
      // 谁也不会想到那儿能点进去打字。
      TextField("", text: $text)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.trailing)
        .font(TypeScale.body)
        .monospacedDigit()
        .foregroundStyle(theme.ink)
        .frame(width: Hit.min + Space.m)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.s)
        .background(theme.raised2, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .focused(focus, equals: field)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }
  }
}
