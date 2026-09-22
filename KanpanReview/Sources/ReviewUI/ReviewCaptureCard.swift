import SwiftUI
import KanpanCore
import ReviewDomain

public struct ReviewCaptureCard: View {
  @Bindable var feature: ReviewFeature
  @Environment(\.reviewTheme) private var t
  public var onSave: () -> Void
  public var onClose: () -> Void
  public init(feature: ReviewFeature, onSave: @escaping () -> Void, onClose: @escaping () -> Void) {
    self.feature = feature; self.onSave = onSave; self.onClose = onClose
  }
  public var body: some View {
    if let draft = feature.draft {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("记一笔").font(.headline).foregroundStyle(t.ink)
            Text("\(draft.range.bars) 根 · \(draft.range.interval)").font(.caption).foregroundStyle(t.ink3)
            Spacer()
            Button("收起", action: onClose).foregroundStyle(t.ink2)
          }
          Picker("方向", selection: binding(\.rule.direction, fallback: .observe)) {
            ForEach(ReviewDirection.allCases, id: \.self) { Text($0.title).tag($0) }
          }.pickerStyle(.segmented)
          if draft.rule.direction != .observe {
            HStack {
              priceField("目标", key: \.rule.target, flag: \.rule.targetEdited)
              priceField("失效", key: \.rule.invalidation, flag: \.rule.invalidationEdited)
            }
            HStack {
              // 参考价按品种自己的小数位写（审查 B-07）：原来「最多 8 位、能省就省」，
              // 同一张卡上参考价 `76800`、目标价框里 `76800.5`，看着像两个量级。
              Text("参考价 " + feature.price(draft.rule.reference, symbol: draft.range.symbol))
                .font(.caption).foregroundStyle(t.ink3)
              Spacer()
              Button("按方向重置") {
                guard var value = feature.draft else { return }
                let a = max(value.rule.target, value.rule.invalidation, value.rule.reference * 1.01)
                let b = min(value.rule.target, value.rule.invalidation, value.rule.reference * 0.99)
                value.rule.target = value.rule.direction == .long ? a : b
                value.rule.invalidation = value.rule.direction == .long ? b : a
                value.rule.targetEdited = false; value.rule.invalidationEdited = false
                feature.draft = value; feature.saveDraft()
              }.font(.caption)
            }
            Picker("判定", selection: binding(\.rule.confirmation, fallback: .barClose)) {
              ForEach(ReviewConfirmation.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            DatePicker("到期", selection: Binding(get: { Date(timeIntervalSince1970: Double(feature.draft?.rule.expires ?? ReviewClock.now) / 1000) }, set: {
              feature.draft?.rule.expires = Int64($0.timeIntervalSince1970 * 1000); feature.draft?.rule.expiryEdited = true; feature.saveDraft()
            }), in: Date()..., displayedComponents: [.date, .hourAndMinute]).font(.subheadline)
              // 挑到期时刻用的时区 = 复盘本里写这个时刻用的时区（审查 B-08）。
              // 不灌的话这颗原生轮盘认设备时区：在「交易所」档上设 20:00，
              // 记录详情里会写成 12:00。
              .environment(\.timeZone, feature.tzOffset.timeZone)
          }
          HStack {
            Text("把握").font(.subheadline).foregroundStyle(t.ink2)
            Picker("把握", selection: binding(\.confidence, fallback: nil)) {
              Text("未填写").tag(Int?.none)
              ForEach([50, 60, 70, 80, 90], id: \.self) { Text("\($0)%").tag(Optional($0)) }
            }.pickerStyle(.menu)
            Spacer()
            Picker("来源", selection: binding(\.origin, fallback: .chartFirst)) {
              ForEach(ReviewOrigin.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
          }
          TextField("一句话（可选）", text: binding(\.text, fallback: ""), axis: .vertical)
            .textFieldStyle(.roundedBorder).lineLimit(1...3)
          HStack {
            Button("找相似") { feature.search(draft.range, cutoff: ReviewClock.now, scope: "history") }.frame(minHeight: 44)
            Spacer()
            Button("记下", action: onSave).buttonStyle(.borderedProminent).tint(t.accent).frame(minHeight: 44)
          }
        }.padding()
      }.scrollDismissesKeyboard(.interactively)
        .tint(t.accent)
        .background(t.raised)
        .onChange(of: feature.draft?.rule.direction) { _, direction in
          guard let direction, var value = feature.draft, direction != .observe else { return }
          let high = max(value.rule.target, value.rule.invalidation), low = min(value.rule.target, value.rule.invalidation)
          if !value.rule.targetEdited { value.rule.target = direction == .long ? high : low }
          if !value.rule.invalidationEdited { value.rule.invalidation = direction == .long ? low : high }
          feature.draft = value; feature.saveDraft()
        }
        .sheet(isPresented: $feature.searchOpen) { ReviewSearchView(feature: feature, range: draft.range, cutoff: feature.searchCutoff) }
    }
  }
  private func binding<T>(_ key: WritableKeyPath<ReviewDraft, T>, fallback: T) -> Binding<T> {
    Binding(get: { feature.draft?[keyPath: key] ?? fallback }, set: { feature.draft?[keyPath: key] = $0; feature.saveDraft() })
  }
  private func priceField(_ title: String, key: WritableKeyPath<ReviewDraft, Double>, flag: WritableKeyPath<ReviewDraft, Bool>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption).foregroundStyle(t.ink3)
      TextField(title, value: Binding(get: { feature.draft?[keyPath: key] ?? 0 }, set: {
        feature.draft?[keyPath: key] = $0; feature.draft?[keyPath: flag] = true; feature.saveDraft()
      }), format: .number.precision(.fractionLength(0...decimals))).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
    }
  }

  /// 这张卡上所有口价的小数位：品种自己说（`SymbolInfo.priceDecimals`，宿主注入到
  /// `feature.priceDecimals`），问不到才按参考价猜。写死 8 位会把 76800 显示成
  /// 一个能填到 `76800.00000001` 的框，也会让摆出来的口价和 K 线价格轴不是一个写法。
  private var decimals: Int {
    guard let draft = feature.draft else { return 2 }
    return feature.priceDecimals(draft.range.symbol) ?? priceDecimalsFallback(draft.rule.reference)
  }
}
