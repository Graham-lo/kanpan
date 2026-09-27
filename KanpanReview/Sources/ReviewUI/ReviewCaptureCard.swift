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
      VStack(spacing: 0) {
        // 抬头钉在顶上、不跟着滚：「收起」随时够得着。
        HStack(alignment: .center, spacing: ReviewSpace.s) {
          Text("记一笔").font(ReviewType.title).foregroundStyle(t.ink)
          Text(Interval.shortLabel(raw: draft.range.interval))
            .font(ReviewType.caption).foregroundStyle(t.ink3)
          Spacer()
          Button("收起", action: onClose).font(ReviewType.control).foregroundStyle(t.ink2).hitTarget()
        }
        .padding(.horizontal, ReviewInset.card)
        ScrollView {
          VStack(alignment: .leading, spacing: ReviewSpace.m) {
            rangeLine(draft)
            ReviewSegment(options: ReviewDirection.allCases.map { ($0.title, $0) },
                          selection: binding(\.rule.direction, fallback: .observe), id: "review.capture.direction")
            if draft.rule.direction != .observe {
              HStack(spacing: ReviewSpace.m) {
                priceField("目标", key: \.rule.target, flag: \.rule.targetEdited)
                priceField("失效", key: \.rule.invalidation, flag: \.rule.invalidationEdited)
              }
              HStack {
                // 参考价按品种自己的小数位写（审查 B-07）：原来「最多 8 位、能省就省」，
                // 同一张卡上参考价 `76800`、目标价框里 `76800.5`，看着像两个量级。
                Text("参考价 " + feature.price(draft.rule.reference, symbol: draft.range.key))
                  .font(ReviewType.caption).monospacedDigit().foregroundStyle(t.ink3)
                Spacer()
                Button("按方向重置") {
                  guard var value = feature.draft else { return }
                  let a = max(value.rule.target, value.rule.invalidation, value.rule.reference * 1.01)
                  let b = min(value.rule.target, value.rule.invalidation, value.rule.reference * 0.99)
                  value.rule.target = value.rule.direction == .long ? a : b
                  value.rule.invalidation = value.rule.direction == .long ? b : a
                  value.rule.targetEdited = false; value.rule.invalidationEdited = false
                  feature.draft = value; feature.saveDraft()
                }
                .font(ReviewType.control)
                // 字只有 13，点按区撑到 44；多出来的那截用负边距还给布局，这一行不被撑高。
                .hitTarget()
                .padding(.vertical, -ReviewSpace.m)
              }
              ReviewSegment(options: ReviewConfirmation.allCases.map { ($0.title, $0) },
                            selection: binding(\.rule.confirmation, fallback: .barClose), id: "review.capture.confirmation")
            }
            TextField("一句话（可选）", text: binding(\.text, fallback: ""), axis: .vertical)
              .lineLimit(1...3)
              .reviewField()
            menuRow("来源") {
              Picker("来源", selection: binding(\.origin, fallback: .chartFirst)) {
                ForEach(ReviewOrigin.allCases, id: \.self) { Text($0.title).tag($0) }
              }
            }
          }
          .padding(.horizontal, ReviewInset.card)
          .padding(.bottom, ReviewSpace.xs)
        }.scrollDismissesKeyboard(.interactively)
        // 「记下」钉在卡片底边、不跟着滚。卡片竖屏只给 280pt（横屏 150pt），连「只记录」
        // 这一档的内容都比它高，按钮原来排在滚动区最末尾——一打开就在可视区外，得先往下
        // 滑才点得到（ReviewFlowUITests 两条就卡在这儿：点下去落在卡片外面）。
        HStack {
          Button("找相似") { feature.search(draft.range, cutoff: ReviewClock.now, scope: "history") }
            .font(ReviewType.bodyEmph).hitTarget()
          Spacer()
          Button("记下", action: onSave).buttonStyle(ReviewPrimaryButtonStyle())
        }
        .padding(.horizontal, ReviewInset.card)
        .padding(.vertical, ReviewSpace.s)
      }
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
  /// 圈的是哪一段（收设置项 2026-09-28）：就是图上看得见的那一段，从最左一根到最右一根
  /// 已收盘的 K 线（`ReviewChartBridge.followViewport`）。原来这儿是起、止两颗时间钮，
  /// 现在只读一行——想圈哪段就拖图、捏图，这一行跟着变。时刻写法和复盘本、找相似列表
  /// 同一个纯函数（`ReviewLabels.range`），同一档时区。
  private func rangeLine(_ draft: ReviewDraft) -> some View {
    Text(ReviewLabels.range(bars: draft.range.bars, start: draft.range.start, end: draft.range.end,
                            offsetMinutes: feature.tzOffset))
      .font(ReviewType.body).monospacedDigit().foregroundStyle(t.ink2)
      .lineLimit(1).minimumScaleFactor(0.8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityIdentifier("review.capture.range")
  }
  private func menuRow<P: View>(_ title: String, @ViewBuilder picker: () -> P) -> some View {
    HStack {
      Text(title).font(ReviewType.body).foregroundStyle(t.ink2)
      Spacer()
      picker().pickerStyle(.menu).font(ReviewType.body)
    }
    .frame(minHeight: ReviewControl.hit)
  }
  private func binding<T>(_ key: WritableKeyPath<ReviewDraft, T>, fallback: T) -> Binding<T> {
    Binding(get: { feature.draft?[keyPath: key] ?? fallback }, set: { feature.draft?[keyPath: key] = $0; feature.saveDraft() })
  }
  private func priceField(_ title: String, key: WritableKeyPath<ReviewDraft, Double>, flag: WritableKeyPath<ReviewDraft, Bool>) -> some View {
    VStack(alignment: .leading, spacing: ReviewSpace.xs) {
      Text(title).font(ReviewType.caption).foregroundStyle(t.ink3)
      TextField(title, value: Binding(get: { feature.draft?[keyPath: key] ?? 0 }, set: {
        feature.draft?[keyPath: key] = $0; feature.draft?[keyPath: flag] = true; feature.saveDraft()
      }), format: .number.grouping(.never).precision(.fractionLength(0...decimals)))
        .keyboardType(.decimalPad).monospacedDigit()
        .reviewField()
    }
  }

  /// 这张卡上所有口价的小数位：品种自己说（`SymbolInfo.priceDecimals`，宿主注入到
  /// `feature.priceDecimals`），问不到才按参考价猜。写死 8 位会把 76800 显示成
  /// 一个能填到 `76800.00000001` 的框，也会让摆出来的口价和 K 线价格轴不是一个写法。
  private var decimals: Int {
    guard let draft = feature.draft else { return 2 }
    return feature.priceDecimals(draft.range.key) ?? priceDecimalsFallback(draft.rule.reference)
  }
}
