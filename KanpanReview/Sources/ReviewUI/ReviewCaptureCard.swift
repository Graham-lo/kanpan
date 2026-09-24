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
  /// 「更多」展开没有。把握、来源、到期这三样不是每一笔都要动的（有默认值），
  /// 卡片竖屏只给 280pt，常开着会把「一句话」挤出第一屏（UI 整改 P3）。
  @State private var moreOpen = false
  private static let moreEnd = "review.capture.moreEnd"
  public var body: some View {
    if let draft = feature.draft {
      VStack(spacing: 0) {
        // 抬头钉在顶上、不跟着滚：「收起」随时够得着。
        HStack(alignment: .center, spacing: ReviewSpace.s) {
          Text("记一笔").font(ReviewType.title).foregroundStyle(t.ink)
          Text("\(draft.range.bars) 根 · \(Interval.shortLabel(raw: draft.range.interval))")
            .font(ReviewType.caption).monospacedDigit().foregroundStyle(t.ink3)
          Spacer()
          Button("收起", action: onClose).font(ReviewType.control).foregroundStyle(t.ink2).hitTarget()
        }
        .padding(.horizontal, ReviewInset.card)
        ScrollViewReader { reader in
        ScrollView {
          VStack(alignment: .leading, spacing: ReviewSpace.m) {
            rangePickers(draft)
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
            more(draft)
            Color.clear.frame(height: 0).id(Self.moreEnd)
          }
          .padding(.horizontal, ReviewInset.card)
          .padding(.bottom, ReviewSpace.xs)
        }.scrollDismissesKeyboard(.interactively)
        // 卡片只有 280pt 高：「更多」展开的那几行落在可视区下面，点开时顺手滚到它们露出来。
        .onChange(of: moreOpen) { _, open in
          // 等展开的那几行先排进布局（下一拍）再滚，不然滚到的是展开前的底。
          guard open else { return }
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(Self.moreEnd, anchor: .bottom) }
          }
        }
        }
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
  /// 起止两颗紧凑时间钮（P3.7）。时区和复盘本、选区标签同一档（`ReviewLabels.range` 用的
  /// `tzOffset`）；「止」写的是最后一根的开盘时刻——和图上那根蜡烛对得上，存下来的仍是收盘边界。
  /// 改完交给宿主吸附到整根 K 线，图上的选区跟着挪（`feature.editRange`）。
  private func rangePickers(_ draft: ReviewDraft) -> some View {
    let step = max(1, (draft.range.end - draft.range.start) / Int64(max(1, draft.range.bars)))
    let lastOpen = draft.range.end - step
    func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
    func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }
    // 上下两行：并排放两颗「日期 + 时刻」会比竖屏宽，把整张卡撑出屏幕。
    return VStack(alignment: .leading, spacing: ReviewSpace.xs) {
      DatePicker("起", selection: Binding(get: { date(draft.range.start) }, set: {
        guard let value = feature.draft else { return }
        feature.editRange(start: ms($0), end: value.range.end)
      }), in: ...date(lastOpen), displayedComponents: [.date, .hourAndMinute])
        .accessibilityIdentifier("review.capture.start")
      DatePicker("止", selection: Binding(get: { date(lastOpen) }, set: {
        guard let value = feature.draft else { return }
        feature.editRange(start: value.range.start, end: ms($0) + step)
      }), in: date(draft.range.start)...date(ReviewClock.now), displayedComponents: [.date, .hourAndMinute])
        .accessibilityIdentifier("review.capture.end")
    }
    .font(ReviewType.body).foregroundStyle(t.ink2)
    .datePickerStyle(.compact)
    .environment(\.timeZone, feature.tzOffset.timeZone)
  }
  /// 「更多 ⌄」：把握、来源、到期。收着的时候一行 44，展开后每样一行 44。
  @ViewBuilder private func more(_ draft: ReviewDraft) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button { withAnimation(.easeOut(duration: 0.2)) { moreOpen.toggle() } } label: {
        HStack(spacing: ReviewSpace.xs) {
          Text("更多").font(ReviewType.control)
          Image(systemName: "chevron.down").font(.system(size: ReviewControl.chevron, weight: .semibold))
            .rotationEffect(.degrees(moreOpen ? 180 : 0))
          Spacer()
        }
        .foregroundStyle(t.ink2)
        .frame(minHeight: ReviewControl.hit)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("review.capture.more")
      .accessibilityValue(moreOpen ? "已展开" : "已收起")
      if moreOpen {
        if draft.rule.direction != .observe {
          DatePicker("到期", selection: Binding(get: { Date(timeIntervalSince1970: Double(feature.draft?.rule.expires ?? ReviewClock.now) / 1000) }, set: {
            feature.draft?.rule.expires = Int64($0.timeIntervalSince1970 * 1000); feature.draft?.rule.expiryEdited = true; feature.saveDraft()
          }), in: Date()..., displayedComponents: [.date, .hourAndMinute])
            .font(ReviewType.body).foregroundStyle(t.ink2)
            .frame(minHeight: ReviewControl.hit)
            // 挑到期时刻用的时区 = 复盘本里写这个时刻用的时区（审查 B-08）。
            // 不灌的话这颗原生轮盘认设备时区：在「交易所」档上设 20:00，
            // 记录详情里会写成 12:00。
            .environment(\.timeZone, feature.tzOffset.timeZone)
        }
        menuRow("把握") {
          Picker("把握", selection: binding(\.confidence, fallback: nil)) {
            Text("未填写").tag(Int?.none)
            ForEach([50, 60, 70, 80, 90], id: \.self) { Text("\($0)%").tag(Optional($0)) }
          }
        }
        menuRow("来源") {
          Picker("来源", selection: binding(\.origin, fallback: .chartFirst)) {
            ForEach(ReviewOrigin.allCases, id: \.self) { Text($0.title).tag($0) }
          }
        }
      }
    }
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
