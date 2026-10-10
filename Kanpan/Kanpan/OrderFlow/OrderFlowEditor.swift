import SwiftUI
import UIKit
import KanpanCore
import KanpanData
import KanpanNetwork

/// 「指标 › 主力订单流」那张表：当前这只币的过滤门槛（按产品各一格）与步长（挂问号）。
///
/// 门槛和步长是**按币**存的（`Prefs.orderFlowOverrides[base]`），随账号同步。原来表底还有「显示」一节
/// 四个开关（现货 / 合约 / 已成交 / 已撤销），2026-09-28 收掉（收设置项 D 组）：一律全画，
/// 现货与合约按颜色分、已成交满色、没吃到的淡一档。和别的指标参数表同一个规矩：按「保存」才一次性生效，取消 / 下滑都不存
/// （门槛边打边生效的话，把 5000000 改成 3000000 的路上会先按「3」把所有单都判成大单）。
///
/// 只摆这只币真的在订的产品：非币（美股、金银）只有 U 本位永续一格。
/// 数值一律手动输入框，没有加减（`kanpan-no-steppers-use-text-fields`）。
struct OrderFlowEditor: View {
  var store: PrefsStore
  /// 当前品种；nil 时（预览、品种信息还没到）表里是空的，只有「取消」「保存」。
  var link: OrderFlowLink?
  var symbol: String

  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  @FocusState private var focus: OrderFlowField?
  /// 正在打的字（按格记）；没打过的格显示当前生效的数。
  @State private var typing: [OrderFlowField: String] = [:]
  /// 打过、提交过的数（按格记）；只有这几格会写进改动表，别的格原样沿用。
  @State private var edited: [OrderFlowField: Double] = [:]
  @State private var resetting = false

  init(store: PrefsStore, link: OrderFlowLink?, symbol: String) {
    self.store = store; self.link = link; self.symbol = symbol
  }

  private var facts: OrderFlowFacts? { link?.currentFacts.flatMap { OrderFlowBase.isValid($0.overrideKey) ? $0 : nil } }
  /// 行情流算好的默认（按成交额分过档）；还没来就是 nil。
  private var feedDefaults: OrderFlowThresholds? { link?.feedDefaults(symbol: symbol) }
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
            row(.step, label: "步长", term: .orderFlowStep, value: effective.step, suffix: nil,
                identifier: "orderflow.step.field")
            if store.prefs.orderFlowOverrides[facts.overrideKey] != nil {
              // 同 `IndicatorEditor`：表单纸会在键盘起落时整张跳一下，按钮的按压跟踪扛不住，点击手势能。
              Text("恢复默认")
                .font(TypeScale.body)
                .foregroundStyle(t.amber)
                .frame(maxWidth: .infinity, minHeight: Inset.rowMin, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { Haptics.warning(); resetting = true; typing = [:]; edited = [:]; focus = nil }
                .accessibilityIdentifier("orderflow.reset")
                .accessibilityAddTraits(.isButton)
            }
          }
          .listRowBackground(t.raised)
        }
      }
      // 行至少 44（HIG 命中区，`Inset.rowMin`）；表里三级字：行名 / 输入 15、K·M 读数 12、分组标题 11。
      .environment(\.defaultMinListRowHeight, Inset.rowMin)
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
          Button("保存") { Haptics.step(); save(); dismiss() }
            .fontWeight(.semibold)
            .foregroundStyle(t.amber)
            .accessibilityIdentifier("orderflow.save")
        }
      }
    }
    .tint(t.amber)
    .presentationBackground(t.app)
  }

  /// 一行「名字 + 数字框 + 读数」。门槛框右边小字给 K / M / B 读法，免得数零。
  private func row(_ field: OrderFlowField, label: String, term: GlossaryTerm? = nil, value: Double?,
                   suffix: String?, identifier: String) -> some View {
    let shown = resetting ? defaultValue(field) ?? value : (edited[field] ?? value)
    let text = typing[field] ?? shown.map(Self.plain) ?? ""
    return HStack(spacing: Space.m) {
      HStack(spacing: 0) {
        Text(label)
        if let term { TermMark(term, theme: t) }
      }
      .font(TypeScale.body).foregroundStyle(t.ink)
      Spacer(minLength: Space.s)
      if suffix != nil, let amount = Double(Self.sanitize(text)), amount > 0 {
        Text(Self.compact(amount)).font(PanelFont.meta).monospacedDigit().foregroundStyle(t.ink3)
      }
      TextField("", text: Binding(get: { text }, set: { accept($0, field) }),
                prompt: Text("自动").foregroundStyle(t.ink3))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .font(TypeScale.body)
        .monospacedDigit()
        .foregroundStyle(t.ink)
        .frame(width: 112)
        .padding(.horizontal, Space.s)
        // 框本身（也就是能点进去打字的那块）44 高；垫的底上下各收 4，看上去 36，不贴着行的分隔线。
        .frame(minHeight: Hit.min)
        .background {
          RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(t.raised2).padding(.vertical, Space.xs)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { focus = field })
        .focused($focus, equals: field)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }
  }

  /// 默认的那一格（恢复默认后显示用）：行情流给的那份优先，还没来就按品种事实查表（成交额不知道，
  /// 可能低一档）。步长表里没有就是 nil，框里写「自动」。
  private func defaultValue(_ field: OrderFlowField) -> Double? {
    guard let defaults = feedDefaults ?? facts?.defaults else { return nil }
    switch field {
    case .threshold(let product): return defaults[product]
    case .step: return defaults.step
    }
  }

  /// 框里打进来的字：过滤后和原样一样就直接收；不一样就先收原样、下一轮主循环再换成过滤后的。
  /// 在同一次编辑里改写绑定值，TextField 不刷新显示（压测 2026-09-28：打「1..5」存的是 1.5，框里却一直是「1..5」）。
  /// 下一轮换之前又打了字就不换，交给那一次。
  ///
  /// 只改绑定值还不够稳：编辑中的 TextField 对绑定值的改写时灵时不灵（2026-10-10 两台空机各撞一次——
  /// 粘「300万」框里留着「300万」、粘全角「１２０００００」框里留着全角，`typing` 里明明已经是归一化后的数）。
  /// 所以换值的同时直接把正在编辑的那个 UITextField 的文字换掉，再发一次 `editingChanged` 让 SwiftUI
  /// 走正常的「用户改了字」那条路把绑定值对齐（归一化是幂等的，再过一遍 `sanitize` 不会变）。
  /// 和 `selectAll` 一样走第一响应者，不碰别的框：只认文字还是原样的那一个。
  private func accept(_ raw: String, _ field: OrderFlowField) {
    let clean = Self.sanitize(raw)
    typing[field] = raw
    guard clean != raw else { return }
    DispatchQueue.main.async {
      guard typing[field] == raw else { return }
      typing[field] = clean
      if let editing = Self.editingTextField(), editing.text == raw {
        editing.text = clean
        editing.sendActions(for: .editingChanged)
      }
    }
  }

  /// 此刻正在编辑（第一响应者）的那个系统输入框：SwiftUI 的 `TextField` 底下就是一个 `UITextField`。
  @MainActor private static func editingTextField() -> UITextField? {
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      for window in scene.windows {
        if let field = firstResponderTextField(in: window) { return field }
      }
    }
    return nil
  }

  private static func firstResponderTextField(in view: UIView) -> UITextField? {
    if let field = view as? UITextField, field.isFirstResponder { return field }
    for sub in view.subviews {
      if let field = firstResponderTextField(in: sub) { return field }
    }
    return nil
  }

  /// 一格打完：空的、不是数的当没改；越界的夹回边上（框里显示什么就存什么）。
  private func commit(_ field: OrderFlowField) {
    guard let raw = typing.removeValue(forKey: field), let value = Double(Self.sanitize(raw)), value > 0 else { return }
    edited[field] = Self.clamp(value, field)
  }

  /// 框里只留 ASCII 数字和一个小数点（至多 14 位）。数字键盘打不出别的，要防的是粘贴：
  /// 全角数字 / 全角句点 / 中文句号先转半角（原来 `isNumber` 把「５」「五」这类也放进来，`Double` 解析失败，
  /// 保存时那一格被静默丢掉）；千分位逗号、空格、「美元」这类字丢掉；第二个小数点起丢掉（原来「3..5」整格作废）；
  /// 数字后面跟着的「万 / 亿 / K / M / B」按倍数展开（原来粘「500万」只剩「500」，再被夹到门槛下限 1000）。
  /// 科学计数法（「1e9」「2.5E6」「1e-6」）整串先按数认：原来逐字过滤把 e 丢掉，粘「1e9」框里剩「19」（压测 2026-09-28）。
  /// 只放行数字、小数点、e/E、正负号，免得「0xE」这类十六进制串被 `Double` 当成 14 认进来。
  nonisolated static func sanitize(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.contains(where: { $0 == "e" || $0 == "E" }), trimmed.allSatisfy({ "0123456789.eE+-".contains($0) }),
       let value = Double(trimmed), value.isFinite, value > 0, value < 1e14 {
      return plain(value)
    }
    var digits = "", dot = false, scale = 1.0
    for ch in raw {
      var c = ch
      if ch.unicodeScalars.count == 1, let v = ch.unicodeScalars.first?.value {
        switch v {
        case 0xFF10...0xFF19: c = Character(UnicodeScalar(v - 0xFF10 + 0x30)!)
        case 0xFF0E, 0x3002: c = "."
        default: break
        }
      }
      if c.isASCII, c.isNumber {
        guard scale == 1, digits.count < 14 else { continue }
        digits.append(c)
      } else if c == "." {
        guard !dot, scale == 1, digits.count < 14 else { continue }
        dot = true; digits.append(c)
      } else if scale == 1, digits.contains(where: \.isNumber),
                let unit = ["万": 1e4, "亿": 1e8, "k": 1e3, "K": 1e3, "m": 1e6, "M": 1e6, "b": 1e9, "B": 1e9][c] {
        scale = unit
      }
    }
    guard scale != 1, let value = Double(digits) else { return digits }
    let scaled = value * scale
    return scaled.isFinite && scaled < 1e14 ? plain(scaled) : digits
  }

  static func clamp(_ value: Double, _ field: OrderFlowField) -> Double {
    let range = field == .step ? OrderFlowOverride.stepRange : OrderFlowOverride.thresholdRange
    return min(range.upperBound, max(range.lowerBound, value))
  }

  /// 落盘：门槛 / 步长只写打过的那几格，和默认一样的那格从改动表里拿掉。
  private func save() {
    for field in typing.keys { commit(field) }
    guard let facts else { return }
    let base = facts.overrideKey
    let override = Self.override(defaults: feedDefaults, existing: resetting ? nil : store.prefs.orderFlowOverrides[base],
                                 edited: edited)
    store.update { $0.setOrderFlowOverride(override, for: base) }
  }

  /// 保存时写进改动表的那一份（纯函数，`OrderFlowPrefsTests` 测它）：在原来那份上改打过的那几格；
  /// 和默认一样的格拿掉（跟着默认走，默认换档时它也跟着换）。
  ///
  /// `defaults` 只认行情流给的那份（`OrderFlowSnapshot.defaults`）：app 自己查表不知道成交额，
  /// 只会落到第三档——拿它比，用户照着真实默认打的数不会被存，打一个恰好等于第三档的数反倒被当成
  /// 「和默认一样」丢掉（审查第 30 项）。所以还没拿到时一格都不拿掉，打了什么存什么。
  nonisolated static func override(defaults: OrderFlowThresholds?, existing: OrderFlowOverride?,
                       edited: [OrderFlowField: Double]) -> OrderFlowOverride {
    var override = existing ?? OrderFlowOverride()
    for (field, value) in edited {
      switch field {
      case .threshold(let product):
        override[product] = defaults.map { value == $0[product] } == true ? nil : value
      case .step:
        override.step = defaults.map { value == $0.step } == true ? nil : value
      }
    }
    return override
  }

  /// 框里的数：整数不带小数点，小数去掉尾零。
  nonisolated static func plain(_ value: Double) -> String {
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
