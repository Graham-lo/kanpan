import SwiftUI
import UIKit
import KanpanCore
import KanpanData
import KanpanNetwork

/// 「指标 › 主力订单流」那张表：当前这只币的过滤门槛（按产品各一格）、价格步长，以及四个显示开关。
///
/// 门槛和步长是**按币**存的（`Prefs.orderFlowOverrides[base]`），显示开关全品种共用一份；
/// 两样都随账号同步。和别的指标参数表同一个规矩：按「保存」才一次性生效，取消 / 下滑都不存
/// （门槛边打边生效的话，把 5000000 改成 3000000 的路上会先按「3」把所有单都判成大单）。
///
/// 只摆这只币真的在订的产品：非币（美股、金银）只有 U 本位永续一格。
/// 数值一律手动输入框，没有加减（`kanpan-no-steppers-use-text-fields`）。
struct OrderFlowEditor: View {
  var store: PrefsStore
  /// 当前品种；nil 时（预览、品种信息还没到）只摆显示开关。
  var link: OrderFlowLink?
  var symbol: String

  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  @FocusState private var focus: OrderFlowField?
  /// 正在打的字（按格记）；没打过的格显示当前生效的数。
  @State private var typing: [OrderFlowField: String] = [:]
  /// 打过、提交过的数（按格记）；只有这几格会写进改动表，别的格原样沿用。
  @State private var edited: [OrderFlowField: Double] = [:]
  @State private var display: OrderFlowDisplay
  @State private var resetting = false

  init(store: PrefsStore, link: OrderFlowLink?, symbol: String) {
    self.store = store; self.link = link; self.symbol = symbol
    _display = State(initialValue: store.prefs.orderFlowDisplay)
  }

  private var facts: OrderFlowFacts? { link?.currentFacts.flatMap { OrderFlowBase.isValid($0.overrideKey) ? $0 : nil } }
  private var effective: OrderFlowThresholds? { link?.effectiveThresholds(symbol: symbol) }
  private var products: [OrderFlowProduct] { OrderFlowProduct.allCases.filter { effective?[$0] != nil } }

  var body: some View {
    NavigationStack {
      Form {
        if let facts, let effective {
          Section {
            ForEach(products, id: \.self) { product in
              row(.threshold(product), label: product.label, value: effective[product],
                  suffix: "美元", identifier: "orderflow.threshold.\(product.rawValue).field")
            }
          } header: {
            PanelFormSectionTitle(text: "\(facts.overrideKey) · 过滤门槛")
          }
          .listRowBackground(t.raised)

          Section {
            // 表里没有步长、前一日收盘还没到时步长还在推：框留空、写「自动」，不显示一个假的 0。
            row(.step, label: "价格步长", value: effective.step, suffix: nil,
                identifier: "orderflow.step.field")
            if store.prefs.orderFlowOverrides[facts.overrideKey] != nil {
              // 同 `IndicatorEditor`：表单纸会在键盘起落时整张跳一下，按钮的按压跟踪扛不住，点击手势能。
              Text("恢复默认")
                .foregroundStyle(t.amber)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { Haptics.warning(); resetting = true; typing = [:]; edited = [:]; focus = nil }
                .accessibilityIdentifier("orderflow.reset")
                .accessibilityAddTraits(.isButton)
            }
          }
          .listRowBackground(t.raised)
        }

        Section {
          toggle("现货", \.spot, "spot")
          toggle("合约", \.contract, "contract")
          toggle("已成交", \.filled, "filled")
          toggle("已撤销", \.cancelled, "cancelled")
        } header: {
          PanelFormSectionTitle(text: "显示")
        }
        .listRowBackground(t.raised)
      }
      .scrollContentBackground(.hidden)
      .background(t.app)
      .navigationTitle(IndicatorID.orderFlow.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(t.app, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: focus) { old, now in
        if let old { commit(old) }
        if now != nil {
          Task { @MainActor in
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .foregroundStyle(t.ink2)
            .accessibilityIdentifier("orderflow.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") { save(); dismiss() }
            .fontWeight(.semibold)
            .foregroundStyle(t.amber)
            .accessibilityIdentifier("orderflow.save")
        }
      }
    }
    .tint(t.amber)
    .presentationBackground(t.app)
  }

  private func toggle(_ name: String, _ key: WritableKeyPath<OrderFlowDisplay, Bool>, _ id: String) -> some View {
    Toggle(name, isOn: Binding(get: { display[keyPath: key] }, set: { display[keyPath: key] = $0 }))
      .foregroundStyle(t.ink)
      .accessibilityIdentifier("orderflow.show.\(id)")
  }

  /// 一行「名字 + 数字框 + 读数」。门槛框右边小字给 K / M / B 读法，免得数零。
  private func row(_ field: OrderFlowField, label: String, value: Double?, suffix: String?,
                   identifier: String) -> some View {
    let shown = resetting ? defaultValue(field) ?? value : (edited[field] ?? value)
    let text = typing[field] ?? shown.map(Self.plain) ?? ""
    return HStack(spacing: 10) {
      Text(label).foregroundStyle(t.ink)
      Spacer(minLength: 8)
      if suffix != nil, let amount = Double(text), amount > 0 {
        Text(Self.compact(amount)).font(PanelFont.meta).monospacedDigit().foregroundStyle(t.ink3)
      }
      TextField("", text: Binding(get: { text }, set: { typing[field] = String($0.filter { $0.isNumber || $0 == "." }.prefix(14)) }),
                prompt: Text("自动").foregroundStyle(t.ink3))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .font(.body.monospacedDigit())
        .foregroundStyle(t.ink)
        .frame(width: 112)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(t.raised2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .focused($focus, equals: field)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }
  }

  /// 默认表里这一格的数（恢复默认后显示用）。步长默认按收盘推，表里没有就沿用此刻生效的那个。
  private func defaultValue(_ field: OrderFlowField) -> Double? {
    guard let facts else { return nil }
    switch field {
    case .threshold(let product): return facts.defaults[product]
    case .step: return facts.defaults.step
    }
  }

  /// 一格打完：空的、不是数的当没改；越界的夹回边上（框里显示什么就存什么）。
  private func commit(_ field: OrderFlowField) {
    guard let text = typing.removeValue(forKey: field), let value = Double(text), value > 0 else { return }
    edited[field] = Self.clamp(value, field)
  }

  static func clamp(_ value: Double, _ field: OrderFlowField) -> Double {
    let range = field == .step ? OrderFlowOverride.stepRange : OrderFlowOverride.thresholdRange
    return min(range.upperBound, max(range.lowerBound, value))
  }

  /// 落盘：显示开关整组写；门槛 / 步长只写打过的那几格，和默认一样的那格从改动表里拿掉。
  private func save() {
    for field in typing.keys { commit(field) }
    let next = display
    guard let facts else { store.update { $0.orderFlowDisplay = next }; return }
    let base = facts.overrideKey, defaults = facts.defaults
    var override = resetting ? OrderFlowOverride() : (store.prefs.orderFlowOverrides[base] ?? OrderFlowOverride())
    for (field, value) in edited {
      switch field {
      case .threshold(let product): override[product] = value == defaults[product] ? nil : value
      case .step: override.step = value == defaults.step ? nil : value
      }
    }
    store.update {
      $0.orderFlowDisplay = next
      $0.setOrderFlowOverride(override, for: base)
    }
  }

  /// 框里的数：整数不带小数点，小数去掉尾零。
  static func plain(_ value: Double) -> String {
    if value >= 1, value == value.rounded() { return String(Int64(value)) }
    var s = String(format: "%.8f", value)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
  }

  /// K / M / B 读法。
  static func compact(_ value: Double) -> String {
    func fmt(_ v: Double, _ unit: String) -> String {
      let s = v == v.rounded() ? String(Int64(v)) : String(format: "%.2f", v).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
      return s + unit
    }
    if value >= 1e9 { return fmt(value / 1e9, "B") }
    if value >= 1e6 { return fmt(value / 1e6, "M") }
    if value >= 1e3 { return fmt(value / 1e3, "K") }
    return plain(value)
  }
}

/// 这张表上要打字的那几格。
enum OrderFlowField: Hashable {
  case threshold(OrderFlowProduct)
  case step
}
