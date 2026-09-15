import SwiftUI
import ReviewDomain

public struct ReviewCaptureCard: View {
  @Bindable var feature: ReviewFeature
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
            Text("记一笔").font(.headline)
            Text("\(draft.range.bars) 根 · \(draft.range.interval)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("收起", action: onClose)
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
              Text("参考价 \(draft.rule.reference.formatted(.number.precision(.fractionLength(0...8))))").font(.caption).foregroundStyle(.secondary)
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
          }
          HStack {
            Text("把握").font(.subheadline)
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
            Button("记下", action: onSave).buttonStyle(.borderedProminent).tint(.orange).frame(minHeight: 44)
          }
        }.padding()
      }.scrollDismissesKeyboard(.interactively)
        .background(.regularMaterial)
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
      Text(title).font(.caption).foregroundStyle(.secondary)
      TextField(title, value: Binding(get: { feature.draft?[keyPath: key] ?? 0 }, set: {
        feature.draft?[keyPath: key] = $0; feature.draft?[keyPath: flag] = true; feature.saveDraft()
      }), format: .number.precision(.fractionLength(0...8))).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
    }
  }
}
