import SwiftUI
import UIKit
import KanpanCore

/// 「分析」面板：周期条行尾「分析」直达（`Panel.indicators`），半屏面板里的一整页。
/// 四节：**画线 · 指标 · 对比 · 主力订单流**（2026-09-28 起；10-05 曾收成三节、10-06 恢复，
/// 见下；再往前这一页和行尾那格都叫「指标」）。
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
/// 2026-10-05 照 TradingView 手机版把「添加对比」搬到顶栏（当时是一颗加号圆片；2026-10-08 起收进顶栏「⋯」菜单，菜单项 `top.compare`），
/// 点开是搜索页的对比模式（`CompareSearchMode`），这一节当时撤了；10-06 用户要求两处并存
/// （「分析里的对比要留」），分析面板恢复四节：这一节的「添加对比」开的就是顶栏「⋯ › 添加对比」那张
/// 对比模式搜索页，两处入口共用同一页、同一份 `Prefs.compareSymbols`。
///
/// 参数编辑那层 sheet 和面板提示仍挂在这一层自己身上。
struct IndicatorPage: View {
  var store: PrefsStore
  /// 主力订单流的胶水与当前品种（它那张表要显示这只币此刻生效的门槛）。
  var orderFlow: OrderFlowLink? = nil
  var symbol: String = ""
  /// 「添加对比」：关面板、开顶栏「⋯ › 添加对比」那张对比模式搜索页。此刻不能对比（复盘回放、横屏画线台、
  /// 看朋友分享的线）时调用方传 nil，「对比」这一节整节不排。
  var onAddCompare: (() -> Void)? = nil
  /// 对比品种键 → 显示名（主界面按品种表算好递进来，这儿不查表）。
  var compareNames: [String: String] = [:]
  /// 「画线」：关面板、把这张图横过来进画线工作台。复盘回放、已经在画时调用方传 nil，
  /// 「画线」这一节整节不排（和对比那节同一个判法）。
  var onDraw: (() -> Void)? = nil
  /// 对比期间画不了线：那一行置灰、点不动（原来周期条那颗记号的 `drawEnabled`）。
  var drawEnabled = true
  /// 横屏画线台顶行「主图˅」开的这一页（2026-10-05）：画线台不画副图、不画主力订单流，
  /// 那几段在这儿点了图上看不出任何变化，所以只摆主图那几段——开着的主图指标（点进参数）
  /// 和主图叠加那排开关；「恢复默认指标」会连副图一起动，也不摆。标题改叫「主图指标」。
  /// 改的仍是同一份指标布局，退出画线回竖屏原样带着走。
  var mainOnly = false
  @State private var editing: IndicatorID?
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 横屏侧栏没有系统 `dismiss`，走主界面递进来的这一条（见 `PanelCloser`）。
  @Environment(\.panelDismiss) private var sideDismiss

  private var prefs: Prefs { store.prefs }
  /// 「开始画线」与对比那几个动作要先收面板再做（搜索页、看得见图），竖屏 sheet / 横屏侧栏一律走这里。
  private var close: PanelCloser { PanelCloser(side: sideDismiss, sheet: dismiss) }
  /// 主图叠加那排开关里不再有主力订单流——它单成了一节。
  private static let overlayPalette = IndicatorID.mainPalette.filter { $0 != .orderFlow }

  var body: some View {
    PanelSheet(title: mainOnly ? "主图指标" : Panel.indicators.title, subtitle: nil) {
      if mainOnly { mainOnlyBody } else { fullBody }
    }
    .sheet(item: $editing) { id in
      if id == .orderFlow {
        OrderFlowEditor(store: store, link: orderFlow, symbol: symbol).environment(\.panelTheme, t)
      } else {
        IndicatorEditor(store: store, id: id).environment(\.panelTheme, t)
      }
    }
  }

  /// 画线台那一版：开着的主图指标（点进参数），下面一排主图叠加开关。
  @ViewBuilder private var mainOnlyBody: some View {
    let inUse = prefs.overlays.contains { $0.placement == .main }
    if inUse {
      PanelCardGroup(title: "使用中") {
        InUseList(store: store, onEdit: { editing = $0 }, mainOnly: true)
      }
    }
    PanelCardGroup(title: "主图叠加") {
      ForEach(Self.overlayPalette, id: \.self) { id in
        row(id, last: id == Self.overlayPalette.last)
      }
    }
  }

  @ViewBuilder private var fullBody: some View {
    drawSection

    // 「指标」这一节：节名压在开着的那几项上（原来这里叫「正在用」），下面是两段开关。
    // 一项都没开时不让两行节名叠在一起，节名并进第一段的标题里。
    let inUse = !prefs.overlays.isEmpty || !prefs.subs.isEmpty
    // 每节一张琉璃玻璃卡（2026-10-08），节名与卡里行文对齐。
    if inUse {
      PanelCardGroup(title: "指标") {
        InUseList(store: store, onEdit: { editing = $0 })
      }
    }

    PanelCardGroup(title: inUse ? "主图叠加" : "指标 · 主图叠加") {
      ForEach(Self.overlayPalette, id: \.self) { id in
        row(id, last: id == Self.overlayPalette.last)
      }
    }

    // 上限写在标题里：满了再点第四个是「换一个」而不是「点不动」，先把规矩摆出来。
    // 成交量不占名额（`Prefs.maxSubs`，与网页版同一口径），标题上一并说清。
    PanelCardGroup(title: "副图 · 最多三个 · 成交量不占") {
      ForEach(IndicatorID.subPalette, id: \.self) { id in
        row(id, last: id == IndicatorID.subPalette.last)
      }
    }

    compareSection
    orderFlowSection

    // 指标布局回到出厂（一人一份、不分周期，2026-10-03）。
    // 已经是出厂那份时点不动（`PanelRow` 在禁用时自己换禁用色阶）。
    PanelCard {
      PanelRow(name: "恢复默认指标", divider: false, onTap: {
        store.resetIndicatorLayout()
        Haptics.warning()
      })
      .disabled(prefs.indicatorLayout == .factory)
      .accessibilityIdentifier("indicator.reset")
    }
    .padding(.top, Space.xl)
  }

  /// 画线：一行，行尾是原来周期条上那颗 24pt 记号（`IntervalDrawGlyph`）。点它先收面板，
  /// 再做原来周期条上那颗做的事（`MainScreen.startDrawing`：横屏进画线工作台，画完自动转回）。
  /// 横屏侧栏里开的这一页（`sideDismiss` 那条路）不排——侧栏在，要么已经在画，要么手边就有
  /// `ToolRail` 那一格「画线」。
  ///
  /// 底下一行「隐藏画线」（2026-10-06）：看行情时把画线整片藏起来、提醒照常盯盘，信号线照常画
  /// （`Prefs.drawingsHidden`，跟账号同步）。它不靠 `onDraw`，复盘回放里也摆；横屏侧栏不摆——
  /// 画线台永远显示画线。
  @ViewBuilder private var drawSection: some View {
    if sideDismiss == nil {
      PanelCardGroup(title: "画线") {
        if let onDraw {
          // 行名不重复「画线」：分组标题已经念过一遍（2026-09-24 审查 U4，和主力订单流那节同一条规矩）。
          PanelRow(name: "开始画线", onTap: { close(); onDraw() }) {
            IntervalDrawGlyph(theme: t, size: 24)
              .opacity(drawEnabled ? 1 : ControlMetrics.disabledOpacity)
              .accessibilityHidden(true)
          }
          .disabled(!drawEnabled)
          .accessibilityIdentifier("indicator.draw")
        }
        PanelRow(name: "隐藏画线", divider: false) {
          PanelSwitch(isOn: prefs.drawingsHidden) { store.updateByHand { $0.drawingsHidden.toggle() } }
            .accessibilityIdentifier("drawing.hide")
        }
      }
    }
  }

  /// 对比 K 线（`Kanpan/Kanpan/Compare/`）：最多三只，颜色跟皮肤色板走，不给选。
  /// 标识不变：`compare.add` / `compare.remove.<键>` / `compare.clear`。
  /// 「添加对比」开的是顶栏「⋯ › 添加对比」那张对比模式搜索页（10-06 起，两处入口共用）。
  @ViewBuilder private var compareSection: some View {
    if let onAddCompare {
      PanelCardGroup(title: "对比") {
        // 满三只时这一行点不动；`PanelRow` 在禁用时自己把字换成禁用色阶。
        PanelRow(name: "添加对比", divider: !prefs.compareSymbols.isEmpty, onTap: { close(); onAddCompare() })
          .disabled(prefs.compareSymbols.count >= 3)
          .accessibilityIdentifier("compare.add")
        ForEach(prefs.compareSymbols, id: \.self) { key in
          PanelRow(name: compareNames[key] ?? String(key.split(separator: "/").last ?? "")) {
            Button { store.updateByHand { $0.compareSymbols.removeAll { $0 == key } }; close() } label: {
              Text("移除").font(PanelFont.seg).foregroundStyle(t.ink2).rowHitTarget()
            }
            .buttonStyle(PanelPlainButtonStyle())
            .accessibilityIdentifier("compare.remove." + key)
          }
        }
        if !prefs.compareSymbols.isEmpty {
          PanelRow(name: "清除对比", divider: false, onTap: { store.updateByHand { $0.compareSymbols = [] }; close() })
            .accessibilityIdentifier("compare.clear")
        }
      }
    }
  }

  /// 主力订单流：一颗开关，开着时底下多一行「门槛」进它那张表（原来在「正在用」里点它那一行进）。
  /// 行右写这只币的门槛动没动过。标识沿用 `indicator.switch.ORDERFLOW` / `indicator.edit.ORDERFLOW`。
  @ViewBuilder private var orderFlowSection: some View {
    PanelCardGroup(title: IndicatorID.orderFlow.name) {
      // 行名不再重复「主力订单流」：分组标题已经念过一遍（2026-09-24 审查 U4 同一条规矩）。
      // 「门槛」那一行只在这只币的品种信息到了之后才出：那张表里只剩门槛与步长两节
      // （显示开关 2026-09-28 收设置项 D 组收掉），没有品种信息时点进去是一张空表。
      // 「图上大单签」（2026-10-08）和挂单墙互不依赖：墙关着签照出，门槛那一行两样开着任一样就排（签也按门槛算）。
      let base = prefs.orderFlow || prefs.bigTradeSigns ? orderFlow?.currentFacts?.overrideKey : nil
      PanelRow(name: "显示", swatch: t.swatch(.orderFlow), divider: true) {
        PanelSwitch(isOn: prefs.orderFlow) { store.byHand { $0.toggleIndicator(.orderFlow) } }
          .accessibilityIdentifier("indicator.switch.\(IndicatorID.orderFlow.rawValue)")
      }
      PanelRow(name: "图上大单签", divider: base != nil) {
        PanelSwitch(isOn: prefs.bigTradeSigns) { store.updateByHand { $0.bigTradeSigns.toggle() } }
          .accessibilityIdentifier("orderflow.bigTradeSigns")
      }
      if let base {
        let meta = "\(base) · " + (prefs.orderFlowOverrides[base] == nil ? "默认门槛" : "已改门槛")
        PanelRow(name: "门槛", term: .orderFlowThreshold, divider: false, onTap: { editing = .orderFlow },
                 buttonID: "indicator.edit.\(IndicatorID.orderFlow.rawValue)", buttonLabel: "门槛，\(meta)") {
          HStack(spacing: Space.s) {
            Text(meta).monospacedDigit().font(PanelFont.meta).foregroundStyle(t.ink3).lineLimit(1)
            VectorIcon.chevron(ControlMetrics.chevron, w: 1.7).rotationEffect(.degrees(-90)).foregroundStyle(t.ink3)
          }
        }
      }
    }
  }

  private func row(_ id: IndicatorID, last: Bool) -> some View {
    let on = prefs.isOn(id)
    return PanelRow(name: id.name, term: .indicator(id), swatch: t.swatch(id), divider: !last) {
      PanelSwitch(isOn: on) {
        store.byHand {
          $0.toggleIndicator(id)
          // 画线台里眼睛关着时新开一个主图指标：用户是来看它的，眼睛跟着睁开，
          // 不然开了图上什么也不变，像没点上。
          if mainOnly, !on, $0.prefs.isOn(id), !$0.prefs.drawingOverlaysShown {
            $0.update { $0.drawingOverlaysShown = true }
          }
        }
      }
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
  /// 画线台「主图指标」那一版只列主图那几行，副图不摆（画线台不画副图）。
  var mainOnly = false
  @Environment(\.panelTheme) private var t

  @State private var dragging: IndicatorID?
  @State private var offset: CGFloat = 0

  /// 和 `PanelRow` 同一个行高，同一张表节奏一致。
  private static let rowH: CGFloat = Inset.rowMin

  private var prefs: Prefs { store.prefs }
  /// 这一段里有没有带把手的行（副图）。有的话，没把手的行（主图叠加）在同一个位置
  /// 垫一块同宽的空位，参数和「›」才落在同一条竖线上（UI 整改 P2）。
  private var hasHandles: Bool { !mainOnly && !prefs.subs.isEmpty }
  private var subs: [IndicatorID] { mainOnly ? [] : prefs.subs }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(prefs.overlays.filter { $0.placement == .main }, id: \.self) { id in
        line(id, index: nil)
      }
      ForEach(Array(subs.enumerated()), id: \.element) { index, id in
        line(id, index: index)
          .background(dragging == id ? LiuliMaterial(t).well : .clear)
          .offset(y: dragging == id ? offset : 0)
          .zIndex(dragging == id ? 1 : 0)
      }
    }
    .animation(.easeOut(duration: 0.15), value: prefs.subs)
    // 整段装在一张玻璃卡里（`PanelCardGroup`，2026-10-08）：原来底下那条分隔线不要了，
    // 拖着的那一行的底按卡的圆角裁。
    .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
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
      .buttonStyle(PanelPlainButtonStyle())
      .accessibilityLabel(params.isEmpty ? id.name : "\(id.name)，\(params)")
      .accessibilityIdentifier("indicator.edit.\(id.rawValue)")

      // 在图上拖过副图高度才出现的那条退路（高度只在图上拖，这儿不给档位）。
      if resized {
        Button { store.updateByHand { $0.subHeightOverrides[id] = nil } } label: {
          Text("还原高度").font(PanelFont.seg).foregroundStyle(t.amber)
            .frame(height: Self.rowH)
            .hitTarget()
        }
          .buttonStyle(PanelPlainButtonStyle())
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
        .listRowBackground(LiuliMaterial(t).glass)

        // 「输出」一节（逐条线的显示开关）2026-09-28 收掉（收设置项 C 组）：线一律全画，
        // 不想要哪条均线就在上面左滑删掉那个周期。

        if draft.id == .ma || draft.id == .ema || draft.id == .vwap {
          Section {
            ForEach(Array(draft.outputs.enumerated()), id: \.offset) { index, name in
              let seed = store.prefs.seed(systemDark: colorScheme == .dark)
              let palette = store.prefs.chartColors(dark: colorScheme == .dark).palette
              let fallback = palette[(index + draft.id.paletteOffset) % palette.count]
              IndicatorColorControl(
                title: name, identifierPrefix: "indicator.color.\(index)",
                swatches: Palette.lineSwatchOptions(default: fallback, seed: seed, redUp: store.prefs.redUp),
                picked: draft.colors[index],
                pick: { draft.colors[index] = $0 })
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
          .listRowBackground(LiuliMaterial(t).glass)
        }
      }
      // 行文 15 regular，和面板行同一档（系统 `Form` 默认 17，在这里比标题还大）。
      .font(TypeScale.body)
      // 这张表是系统 `Form`，但配色得跟着皮肤走：底是琉璃底（不带光斑）、行是琉璃玻璃、
      // 分隔线是材质细线，强调色（「添加周期」、开关、光标）走 `tint`。留着 `Form` 是因为
      // 分节、左滑删除和键盘避让都是它给的，自己搭一套只会把这几样做丢。
      //
      // 导航栏不另上底色：整屏要读成一块连续的材料（原来栏取 `raised`、表取 `app`，
      // 栏下沿会横出一道台阶），所以栏透明、让同一块琉璃底从它身后透上来。
      .scrollContentBackground(.hidden)
      .listRowSeparatorTint(LiuliMaterial(t).rule)
      .background { LiuliBackdrop(material: LiuliMaterial(t), lobes: false) }
      .navigationTitle(draft.id.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
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
    .presentationBackground { LiuliBackdrop(material: LiuliMaterial(t), lobes: false) }
  }

  /// 「保存」：先把手上还在打的那格算进去，再落盘、关面板。
  private func save() {
    let final = committed()
    store.updateByHand { final.save(into: &$0) }
    dismiss()
  }

  private func parameterLabel(_ index: Int) -> String {
    if draft.id.hasVariablePeriods { return "周期\(index + 1)" }
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
  private var variablePeriods: Bool { draft.id.hasVariablePeriods }

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

// MARK: - 线条颜色

/// 指标参数表里一条线的颜色（2026-10-08）：这条线的出厂色排第一、底下标「默认」，
/// 后面几支全从皮肤派生（`Palette.lineSwatches`：强调色、提亮的强调色、涨、跌、墨），
/// 不再摆一排跟皮肤无关的通用色；行尾仍留系统取色器给真想要别的颜色的人。
///
/// 点「默认」是把这条线的自定义色清掉（`nil`），之后跟着皮肤走，换皮肤也对；
/// 点别的就记成那一支此刻的色值。标识按角色：`<前缀>.default` / `.accent` / `.accentLift` /
/// `.up` / `.down` / `.ink`（色值随皮肤变，角色不变；和画线色板 `color.<角色>` 同一个办法）。
struct IndicatorColorControl: View {
  var title: String
  var identifierPrefix: String
  /// 第一支是出厂色。
  var swatches: [LineSwatch]
  /// 用户改过的颜色；nil 就是出厂色。
  var picked: Hex?
  var pick: (Hex?) -> Void
  @Environment(\.panelTheme) private var theme

  private var current: Hex { picked ?? swatches.first?.hex ?? "#000000" }

  var body: some View {
    VStack(alignment: .leading, spacing: Space.s) {
      ColorPicker(title, selection: Binding(get: { Color(hex: current) },
                                            set: { pick(Self.hex($0)) }), supportsOpacity: false)
      HStack(alignment: .top, spacing: Space.m) {
        ForEach(Array(swatches.enumerated()), id: \.offset) { index, swatch in
          let hex = swatch.hex
          let isDefault = index == 0
          let on = isDefault ? picked == nil || picked == hex : picked == hex
          Button { pick(isDefault ? nil : hex) } label: {
            VStack(spacing: Space.xxs) {
              Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                // 选中圈走皮肤的墨色（同 `LineWidthPicker`）。
                .overlay(Circle().stroke(on ? theme.ink : .clear, lineWidth: 2).padding(-3))
              if isDefault {
                Text("默认").font(TypeScale.caption).foregroundStyle(theme.ink3)
              }
            }
            .frame(minWidth: Hit.min, minHeight: Hit.min, alignment: .top)
            .contentShape(Rectangle())
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(isDefault ? "默认" : Self.roleName(swatch.role))
          .accessibilityValue(hex.value)
          .accessibilityAddTraits(on ? [.isSelected] : [])
          .accessibilityIdentifier("\(identifierPrefix).\(swatch.role)")
        }
      }
    }
  }

  static func roleName(_ role: String) -> String {
    switch role {
    case "accent": "强调色"
    case "accentLift": "浅强调色"
    case "up": "涨色"
    case "down": "跌色"
    case "ink": "墨色"
    default: "默认"
    }
  }

  static func hex(_ color: Color) -> Hex {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return Hex(String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())))
  }
}
