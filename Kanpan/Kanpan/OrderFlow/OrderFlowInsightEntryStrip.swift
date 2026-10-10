import KanpanCore
import SwiftUI

/// 行情画布外的上滑入口条（点按，或上滑 48pt 且纵向超过横向 1.8 倍才开）。
/// 2026-10-10 气泡页回退到 10-08 定版后，入口暂时打开「大单与爆仓」页，文案随之用 `BigTradeTerm.title`；
/// 新的「盘口要点」半页另行设计后再换回。
struct OrderFlowInsightEntryStrip: View {
  let open: () -> Void
  @Environment(\.panelTheme) private var t
  var body: some View {
    HStack(spacing: Space.s) {
      Image(systemName: "chevron.up").font(TypeScale.captionEmph)
      Text(BigTradeTerm.title.text).font(TypeScale.controlOn)
      Spacer(minLength: Space.s)
    }
    .foregroundStyle(t.ink2).padding(.horizontal, Space.l)
    .frame(minHeight: Hit.min).contentShape(Rectangle())
    .gesture(TapGesture().exclusively(before: DragGesture(minimumDistance: 20)).onEnded { value in
      switch value {
      case .first: open()
      case .second(let drag):
        if drag.translation.height < -48, abs(drag.translation.height) > abs(drag.translation.width) * 1.8 { open() }
      }
    })
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { open() }
    .accessibilityIdentifier("insights.entry")
  }
}
