import SwiftUI
import KanpanCore

/// 指标选择即时生效；参数与输出在独立草稿中保存或取消。
struct IndicatorPanel: View {
  var store: PrefsStore
  @State private var editing: IndicatorID?
  @Environment(\.panelTheme) private var t

  private var prefs: Prefs { store.prefs }

  var body: some View {
    PanelSheet(title: "指标", subtitle: nil) {
      PanelGroupTitle(text: "主图叠加")
      ForEach([IndicatorID.ma, .ema, .boll], id: \.self) { id in
        row(id)
      }

      // 上限写在标题里：满了再点第四个是「换一个」而不是「点不动」，先把规矩摆出来。
      PanelGroupTitle(text: "副图 · 同时最多三个")
      ForEach([IndicatorID.vol, .macd, .rsi, .kdj, .srsi, .atr, .oi], id: \.self) { id in
        row(id)
      }

      if prefs.subs.count > 1 {
        PanelGroupTitle(text: "副图顺序")
        SubOrderList(store: store)
      }

    }
    .sheet(item: $editing) { id in IndicatorEditor(store: store, id: id).environment(\.panelTheme, t) }
    .panelToast(store)
  }

  @ViewBuilder
  private func row(_ id: IndicatorID) -> some View {
    let on = prefs.isOn(id)
    PanelRow(name: id.name, meta: IndicatorPanel.hint(id), swatch: t.swatch(id)) {
      PanelSwitch(isOn: on) {
        store.toggleIndicator(id)
      }
      .accessibilityIdentifier("indicator.switch.\(id.rawValue)")
    }
    if on, !id.paramLabels.isEmpty || id.placement == .sub {
      detail(id)
    }
  }

  /// 开着的指标底下这一块：参数步进器 +（手调过高度的副图才有的）一键还原。
  ///
  /// 原来这儿挂着「高度」三档。它和图上副图上沿那条把手是同一件事的两个入口，
  /// 两边还各说各话——拖过之后三档仍停在旧档位上，看着像没生效（第三批 16）。
  /// 现在设高度只有一个地方：在图上拖，边拖边看。这儿只留一条退路，
  /// 而且只在真的手调过之后才出现。
  @ViewBuilder
  private func detail(_ id: IndicatorID) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Button { editing = id } label: {
        HStack(spacing: 4) {
          Text(id == .ma || id == .ema ? "参数与颜色" : "参数与输出").font(PanelFont.seg)
          VectorIcon.chevron(9, w: 1.7).rotationEffect(.degrees(-90))
        }
        .foregroundStyle(t.amber)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(t.amberSoft, in: Capsule())
        .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("indicator.edit.\(id.rawValue)")
      if id.placement == .sub, prefs.subHeightOverrides[id] != nil {
        HStack(spacing: PanelMetrics.rowGap) {
          Text("高度 · 已手调").font(PanelFont.meta).foregroundStyle(t.ink3)
          Spacer(minLength: 0)
          Button("还原高度") { store.update { $0.subHeightOverrides[id] = nil } }
            .font(PanelFont.meta).foregroundStyle(t.amber)
            .accessibilityIdentifier("indicator.height.reset.\(id.rawValue)")
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, PanelMetrics.hPad)
    .padding(.bottom, PanelMetrics.vPad)
    .overlay(alignment: .bottom) { Rectangle().fill(t.hair).frame(height: 1) }
  }

  /// 保留指标中文名称与必要的数据范围。
  static func hint(_ id: IndicatorID) -> String {
    switch id {
    case .ma: "均线"
    case .ema: "指数均线"
    case .boll: "布林带"
    case .vol: "成交量"
    case .macd: "平滑异同均线"
    case .rsi: "相对强弱"
    case .kdj: "随机指标"
    case .srsi: "随机 RSI"
    case .atr: "平均真实波幅"
    case .oi: "持仓量 · 近 30 天，最细 5 分钟"
    }
  }
}

// MARK: - 副图顺序

/// §10.6 的拖柄：按住往上下拖，松手就定。行高固定，所以位移除以行高就是挪几格。
private struct SubOrderList: View {
  var store: PrefsStore
  @Environment(\.panelTheme) private var t

  @State private var dragging: IndicatorID?
  @State private var offset: CGFloat = 0

  private static let rowH: CGFloat = 44

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(store.prefs.subs.enumerated()), id: \.element) { index, id in
        HStack(spacing: PanelMetrics.rowGap) {
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(t.swatch(id)).frame(width: 9, height: 9)
          Text(id.name).font(PanelFont.name).foregroundStyle(t.ink)
          Spacer(minLength: 0)
          Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(t.ink3)
            .frame(width: 44, height: Self.rowH)
            .contentShape(Rectangle())
            .gesture(drag(id: id, index: index))
        }
        .padding(.leading, PanelMetrics.hPad)
        .padding(.trailing, PanelMetrics.hPad - 12)
        .frame(height: Self.rowH)
        .background(dragging == id ? t.raised2 : .clear)
        .offset(y: dragging == id ? offset : 0)
        .zIndex(dragging == id ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(id.name)，第 \(index + 1) 个副图")
        .accessibilityAdjustableAction { direction in
          switch direction {
          case .increment: store.update { $0.moveSub(from: index, to: index + 1) }
          case .decrement: store.update { $0.moveSub(from: index, to: index - 1) }
          default: break
          }
        }
      }
    }
    .animation(.easeOut(duration: 0.15), value: store.prefs.subs)
    .overlay(alignment: .bottom) { Rectangle().fill(t.hair).frame(height: 1) }
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
        store.update { $0.moveSub(from: index, to: index + steps) }
      }
  }
}

// MARK: - 参数排布

/// 一排步进器，塞不下就换行（原型 `.params { flex-wrap: wrap }`）。
struct FlowRow: SwiftUI.Layout {
  var spacing: CGFloat = 5

  func sizeThatFits(proposal: ProposedViewSize, subviews: SwiftUI.LayoutSubviews, cache: inout ()) -> CGSize {
    let maxW = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
    for v in subviews {
      let s = v.sizeThatFits(.unspecified)
      if x > 0, x + s.width > maxW { x = 0; y += lineH + spacing; lineH = 0 }
      x += s.width + spacing
      widest = max(widest, x - spacing)
      lineH = max(lineH, s.height)
    }
    return CGSize(width: min(widest, maxW), height: y + lineH)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                     subviews: SwiftUI.LayoutSubviews, cache: inout ()) {
    var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
    for v in subviews {
      let s = v.sizeThatFits(.unspecified)
      if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += lineH + spacing; lineH = 0 }
      v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
      x += s.width + spacing
      lineH = max(lineH, s.height)
    }
  }
}

#Preview("指标") {
  PanelPreviewHost { store in IndicatorPanel(store: store) }
}

// Separate draft lifetime makes Back/Cancel/swipe-to-dismiss equivalent.
extension IndicatorID: @retroactive Identifiable { public var id: String { rawValue } }
private struct IndicatorEditor: View {
  var store: PrefsStore
  @State private var draft: IndicatorDraft
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 正在打字的是第几格。数字键盘没有回车键，收键盘全靠工具条那颗「完成」，
  /// 而工具条只能挂在整张表上挂一次——所以焦点得由这儿统一管。
  @FocusState private var editingParam: Int?
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
              Button("添加周期") { addPeriod() }
                .accessibilityIdentifier("indicator.param.add")
            }
          } else {
            ForEach(Array(draft.params.indices), id: \.self) { paramRow($0) }
          }
          if draft.id == .rsi {
            Stepper("上限：\(Int(draft.upper))", value: $draft.upper, in: (draft.lower + 1)...100)
              .foregroundStyle(t.ink)
            Stepper("下限：\(Int(draft.lower))", value: $draft.lower, in: 0...(draft.upper - 1))
              .foregroundStyle(t.ink)
          }
        } header: {
          sectionTitle("参数")
        }
        .listRowBackground(t.raised)

        Section {
          ForEach(Array(draft.outputs.enumerated()), id: \.offset) { index, name in
            Toggle(name, isOn: Binding(get: { !draft.hidden.contains(index) }, set: { on in
              if on { draft.hidden.remove(index) } else { draft.hidden.insert(index) }
            }))
            .foregroundStyle(t.ink)
            .accessibilityIdentifier("indicator.output.\(index)")
          }
        } header: {
          sectionTitle("输出")
        }
        .listRowBackground(t.raised)

        if draft.id == .ma || draft.id == .ema {
          Section {
            ForEach(Array(draft.outputs.enumerated()), id: \.offset) { index, name in
              DrawingColorControl(title: name, identifierPrefix: "indicator.color.\(index)", color: Binding(get: {
                let palette = store.prefs.chartColors(dark: colorScheme == .dark).palette
                return draft.colors[index] ?? palette[(index + (draft.id == .ema ? 3 : 0)) % palette.count]
              }, set: { draft.colors[index] = $0 }))
            }
            Button("恢复默认颜色") { draft.colors = [:] }.accessibilityIdentifier("indicator.colors.reset")
          } header: {
            sectionTitle("线条颜色")
          }
          .listRowBackground(t.raised)
        }
      }
      // 这张表是系统 `Form`，但配色得跟着皮肤走：底换成 `app`、行换成 `raised`、
      // 强调色（「添加周期」、开关、光标）走 `tint`。留着 `Form` 是因为步进器和
      // 左滑删除都是它给的，自己搭一套只会把这两样做丢。
      .scrollContentBackground(.hidden)
      .background(t.app)
      .navigationTitle(draft.id.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(t.raised, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      // 数字键盘没有回车键：下滑把它划走，或者直接按右上角「保存」——
      // 输进去的数字是边打边生效的，不需要再多一颗「完成」。
      .scrollDismissesKeyboard(.interactively)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }.foregroundStyle(t.ink2)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") { store.update { draft.save(into: &$0) }; dismiss() }
            .fontWeight(.semibold)
            .foregroundStyle(t.amber)
        }
      }
    }
    .tint(t.amber)
    .presentationBackground(t.app)
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text).font(PanelFont.group).tracking(1).foregroundStyle(t.ink3)
  }

  private func parameterLabel(_ index: Int) -> String {
    if [.ma, .ema, .vol].contains(draft.id) { return "周期\(index + 1)" }
    return draft.id.paramLabels[index]
  }

  /// 一格参数：步进器管 ±1，数字本身可以直接打——均线周期常常是 5 → 120 这种跨度，
  /// 按 115 下 + 不是人干的事。两边共用一个值，谁改都立刻生效。
  private func paramRow(_ index: Int) -> some View {
    Stepper(value: $draft.params[index], in: IndicatorParamRule.range) {
      ParamField(label: parameterLabel(index),
                 value: $draft.params[index],
                 index: index,
                 focus: $editingParam,
                 theme: t,
                 identifier: "indicator.param.\(index).field")
    }.accessibilityIdentifier("indicator.param.\(index)")
  }

  /// 均线这类「几条线」由用户定；MACD、KDJ 那种参数个数是算法定死的，不能加也不能删。
  private var variablePeriods: Bool { [.ma, .ema, .vol].contains(draft.id) }

  private func addPeriod() {
    let next = IndicatorParamRule.clamp((draft.params.last ?? 5) * 2)
    draft.params.append(next)
  }

  /// 删一条线时，输出开关和线条颜色都按位置存着，得跟着往前挪一格，
  /// 否则关掉的是别人那条、颜色也串到隔壁去了。
  private func removePeriods(_ offsets: IndexSet) {
    guard draft.params.count - offsets.count >= 1 else { return }
    for index in offsets.sorted(by: >) {
      draft.params.remove(at: index)
      draft.hidden = Set(draft.hidden.compactMap { $0 == index ? nil : ($0 > index ? $0 - 1 : $0) })
      draft.colors = Dictionary(uniqueKeysWithValues: draft.colors.compactMap { key, value in
        key == index ? nil : (key > index ? (key - 1, value) : (key, value))
      })
    }
  }
}

/// 一格能直接打字的周期。
///
/// 只收数字、最多三位（上限 400），失焦时夹回合法区间——中途不夹，
/// 不然删到剩一位数就被顶成 1，再想输 120 得跟它打架。什么都没打就走开，
/// 原来那个值原样留着。
private struct ParamField: View {
  var label: String
  @Binding var value: Int
  var index: Int
  var focus: FocusState<Int?>.Binding
  var theme: PanelTheme
  var identifier: String

  @State private var text = ""

  var body: some View {
    HStack(spacing: 12) {
      Text(label).foregroundStyle(theme.ink)
      Spacer(minLength: 8)
      // 一格能打字的数字，底垫一层 `raised2`：不垫的话它和左边的名字长得一模一样，
      // 谁也不会想到那儿能点进去打字。
      TextField(String(value), text: $text)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.trailing)
        .font(.body.monospacedDigit())
        .foregroundStyle(theme.ink)
        .frame(width: 56)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(theme.raised2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .focused(focus, equals: index)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .onChange(of: text) { _, now in
          let digits = String(now.filter(\.isNumber).prefix(3))
          if digits != now { text = digits }
          if let n = Int(digits), IndicatorParamRule.isValid(n) { value = n }
        }
        // 点进来先清空，当前值退成灰底纹。不清的话光标停在数字中间，
        // 想把 10 改成 7 会打出 710——三位以内的周期，重打一遍比删两下快。
        .onChange(of: focus.wrappedValue) { _, now in
          if now == index { text = "" } else { commit() }
        }
        .onChange(of: value) { _, now in if focus.wrappedValue != index { text = String(now) } }
        .onAppear { text = String(value) }
    }
  }

  private func commit() {
    let clamped = IndicatorParamRule.clamp(Int(text) ?? value)
    value = clamped
    text = String(clamped)
  }
}
