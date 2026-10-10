import KanpanCore
import SwiftUI

/// 一句拼好的事实 → 一行字：加粗段用 `strong` 的墨、semibold，其余继承外面的字号与墨色。
func highlightText(_ runs: [HighlightRun], strong: Color) -> Text {
  runs.reduce(Text(verbatim: "")) { acc, run in
    let piece = run.strong ? Text(verbatim: run.text).fontWeight(.semibold).foregroundStyle(strong) : Text(verbatim: run.text)
    return Text("\(acc)\(piece)")
  }
}

/// 行情画布下沿的「要点」入口条（原型 §7 / §8）：有价位或事件时 44 pt 一句话（离现价最近的价位，
/// 没价位写 1 时净主动）；什么都没有时缩成 16 pt 的抓手，高度还给图。点按或上滑 ≥ 48 pt
/// （纵向超过横向 1.8 倍）打开半页，横拖不算。
struct HighlightsEntryStrip: View {
  let model: HighlightsModel
  let open: () -> Void
  @Environment(\.panelTheme) private var t
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var sentence: [HighlightRun]? {
    guard let page = model.page, page.tracked else { return nil }
    // 没价位也没 1 时净主动、但有事件：写最近那一条事件。
    return HighlightsText.entrySentence(page, decimals: model.decimals, scale: model.scale)
      ?? page.events.first.map { HighlightsText.eventSentence($0, decimals: model.decimals, scale: model.scale, withPrice: false) }
  }

  var body: some View {
    let runs = sentence
    Group {
      if let runs {
        HStack(spacing: Space.s) {
          Image(systemName: "chevron.up").font(TypeScale.caption2Emph).foregroundStyle(t.amber)
          Text(HighlightTerm.entry.text).font(TypeScale.controlOn).foregroundStyle(t.amber)
          highlightText(runs, strong: t.ink)
            .font(TypeScale.footnote).foregroundStyle(t.ink2)
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
            .contentTransition(.numericText())
          Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.l)
        .frame(height: Hit.min)
      } else {
        Capsule().fill(t.ink3.opacity(0.45)).frame(width: 36, height: 4)
          .frame(maxWidth: .infinity).frame(height: 16)
      }
    }
    .contentShape(Rectangle())
    .opacity(model.stale ? 0.6 : 1)
    .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.2), value: runs == nil)
    .gesture(TapGesture().exclusively(before: DragGesture(minimumDistance: 12)).onEnded { value in
      switch value {
      case .first: Haptics.press(); open()
      case .second(let drag):
        if drag.translation.height < -48, abs(drag.translation.height) > abs(drag.translation.width) * 1.8 {
          Haptics.press(); open()
        }
      }
    })
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(HighlightTerm.title.text)
    .accessibilityValue(runs?.plain ?? "")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { open() }
    .accessibilityIdentifier("highlights.entry")
  }
}
