import SwiftUI
import KanpanCore

/// 指标选择即时生效；参数与输出在独立草稿中保存或取消。
struct IndicatorPanel: View {
  var store: PrefsStore
  @State private var editing: IndicatorID?
  @Environment(\.panelTheme) private var t

  private var prefs: Prefs { store.prefs }

  var body: some View {
    PanelSheet(title: "指标", subtitle: "副图默认 VOL + OI + MACD") {
      PanelGroupTitle(text: "主图叠加")
      ForEach([IndicatorID.ma, .ema, .boll], id: \.self) { id in
        row(id)
      }

      PanelGroupTitle(text: "副图")
      ForEach([IndicatorID.vol, .macd, .rsi, .kdj, .srsi, .atr, .oi], id: \.self) { id in
        row(id)
      }

      if prefs.subs.count > 1 {
        PanelGroupTitle(text: "副图顺序")
        SubOrderList(store: store)
      }

      PanelNote(markdown:
        "副图按打开的先后从上往下排，更多副图可上下滚动查看；拖动副图下边界可调整高度。"
        + "**持仓量**用的是币安 openInterestHist，交易所只保留最近 30 天、最细 5 分钟——"
        + "超出这个范围会直说没有，不画假线。")
    }
    .sheet(item: $editing) { id in IndicatorEditor(store: store, id: id) }
    .panelToast(store)
  }

  @ViewBuilder
  private func row(_ id: IndicatorID) -> some View {
    let on = prefs.isOn(id)
    PanelRow(name: id.name, meta: IndicatorPanel.hint(id), swatch: t.swatch(id)) {
      PanelSwitch(isOn: on) {
        store.attempt { $0.toggle(id) }
      }
      .accessibilityIdentifier("indicator.switch.\(id.rawValue)")
    }
    if on, !id.paramLabels.isEmpty || id.placement == .sub {
      detail(id)
    }
  }

  /// 开着的指标底下这一块：参数步进器 +（副图才有的）高度三档。
  @ViewBuilder
  private func detail(_ id: IndicatorID) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Button("参数与输出设置") { editing = id }
        .font(PanelFont.meta).foregroundStyle(t.ink)
        .accessibilityIdentifier("indicator.edit.\(id.rawValue)")
      if id.placement == .sub {
        HStack(spacing: PanelMetrics.rowGap) {
          Text(prefs.subHeightOverrides[id] == nil ? "高度" : "高度 · 已手调").font(PanelFont.meta).foregroundStyle(t.ink3)
          Spacer(minLength: 0)
          PanelSegment(options: SubPaneHeight.options, selection: prefs.height(for: id)) { h in
            store.update { $0.subHeights[id] = h; $0.subHeightOverrides[id] = nil }
          }
        }
      }
    }
    .padding(.horizontal, PanelMetrics.hPad)
    .padding(.bottom, PanelMetrics.vPad)
    .overlay(alignment: .bottom) { Rectangle().fill(t.hair).frame(height: 1) }
  }

  /// 原型 `hintFor`，逐字。
  static func hint(_ id: IndicatorID) -> String {
    switch id {
    case .ma: "收盘价的简单均线"
    case .ema: "指数加权，比 MA 跟得紧"
    case .boll: "中轨加减标准差"
    case .vol: "成交量柱 + 均量线"
    case .macd: "快慢均线的差与它的均线"
    case .rsi: "涨跌力量的比值"
    case .kdj: "随机指标"
    case .srsi: "RSI 自己的随机指标，更灵敏"
    case .atr: "真实波幅，拿来量止损距离"
    case .oi: "未平仓合约张数 · 币安只给近 30 天"
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
  @Environment(\.dismiss) private var dismiss
  init(store: PrefsStore, id: IndicatorID) {
    self.store = store; _draft = State(initialValue: IndicatorDraft(id: id, prefs: store.prefs))
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("参数") {
          ForEach(Array(draft.params.indices), id: \.self) { index in
            Stepper("\(parameterLabel(index))：\(draft.params[index])", value: $draft.params[index], in: 1...400)
              .accessibilityIdentifier("indicator.param.\(index)")
          }
          if draft.id == .rsi {
            Stepper("上限：\(Int(draft.upper))", value: $draft.upper, in: (draft.lower + 1)...100)
            Stepper("下限：\(Int(draft.lower))", value: $draft.lower, in: 0...(draft.upper - 1))
          }
        }
        Section("输出") {
          ForEach(Array(draft.outputs.enumerated()), id: \.offset) { index, name in
            Toggle(name, isOn: Binding(get: { !draft.hidden.contains(index) }, set: { on in
              if on { draft.hidden.remove(index) } else { draft.hidden.insert(index) }
            })).accessibilityIdentifier("indicator.output.\(index)")
          }
        }
      }
      .navigationTitle(draft.id.name)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") { store.update { draft.save(into: &$0) }; dismiss() }
        }
      }
    }
  }
  private func parameterLabel(_ index: Int) -> String {
    if [.ma, .ema, .vol].contains(draft.id) { return "周期\(index + 1)" }
    return draft.id.paramLabels[index]
  }
}
