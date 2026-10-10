import KanpanCore
import SwiftUI

/// 一句拼好的事实 → 一行字：加粗段用 `strong` 的墨、semibold，其余继承外面的字号与墨色。
func highlightText(_ runs: [HighlightRun], strong: Color) -> Text {
  runs.reduce(Text(verbatim: "")) { acc, run in
    let piece = run.strong ? Text(verbatim: run.text).fontWeight(.semibold).foregroundStyle(strong) : Text(verbatim: run.text)
    return Text("\(acc)\(piece)")
  }
}

/// 报价下方、周期条上方的一行要点；没有内容时收起。
/// 点击打开盘口洞察。
struct HighlightsEntryStrip: View {
  let model: HighlightsModel
  /// 现价（每枚币）：价区包住它时那句写「现价内 a–b」，并优先取那条。
  var price: Double? = nil
  let open: () -> Void
  @Environment(\.panelTheme) private var t
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var sentence: [HighlightRun]? {
    guard let page = model.page, page.tracked else { return nil }
    // 没价位也没 1 时净主动、但有事件：写最近那一条事件。
    return HighlightsText.entrySentence(page, decimals: model.decimals, scale: model.scale, price: price)
      ?? page.events.first.map { HighlightsText.eventSentence($0, decimals: model.decimals, scale: model.scale, withPrice: false) }
  }

  var body: some View {
    let runs = sentence
    // 保留零高度宿主，没内容时外层 task 仍会启动轮询。
    VStack(spacing: 0) {
      if let runs {
        HStack(spacing: Space.s) {
          Text(HighlightTerm.entry.text).font(TypeScale.controlOn).foregroundStyle(t.amber)
          highlightText(runs, strong: t.ink)
            .font(TypeScale.footnote).foregroundStyle(t.ink2)
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
            .contentTransition(.numericText())
          Spacer(minLength: 0)
          Image(systemName: "chevron.right").font(TypeScale.caption2Emph).foregroundStyle(t.ink3)
        }
        .pageHorizontalInset()
        .frame(height: Hit.min)
      }
    }
    .frame(maxWidth: .infinity)
    .contentShape(Rectangle())
    .opacity(model.stale ? 0.6 : 1)
    .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.2), value: runs == nil)
    .onTapGesture { Haptics.press(); open() }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(HighlightTerm.title.text)
    .accessibilityValue(runs?.plain ?? "")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { open() }
    .accessibilityIdentifier("highlights.entry")
    .accessibilityHidden(runs == nil)
  }
}
