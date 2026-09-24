import SwiftUI

/// 「分享」点开后推进去的那一层二选一：图片 / 画线。
///
/// 两块并排的大格，各写一句「对方收到的是什么」，不写「分享图片」「发给朋友」这种
/// 按实现起的名字——用户要选的是「发到微信」还是「让朋友在自己图上看见我的线」。
/// 画线那格发不了的时候（没登录、图上没线）照样摆着，只是变淡、底下那句换成原因：
/// 藏起来的话，用户不知道还有这条路。
///
/// 2026-09-24（HIG 整改 P0b）：它原来是盖在面板上、自带一层黑色遮罩升起来的一块，
/// 面板本身是 sheet，背后已经有系统那一层遮罩，叠起来就是两层变暗。现在和「指标」
/// 「更多设置」同一种推法：面板里推进去一层，「‹」回到图表设置，不关面板，只有一层遮罩。
/// 竖屏 sheet 和横屏侧栏里都是同一个样子。
struct ShareChooser: View {
  var onImage: () -> Void
  var onLines: () -> Void
  /// 画线那格为什么发不了；nil 就是能发。
  var linesBlocked: String?
  var onBack: () -> Void

  @Environment(\.panelTheme) private var t

  var body: some View {
    PanelSheet(title: "分享", subtitle: nil, onBack: onBack) {
      HStack(spacing: Space.m) {
        tile("图片", "发到微信等任何地方", icon: "photo", id: "share.image", action: onImage)
        tile("画线", linesBlocked ?? "朋友在自己的图上看到你的线", icon: "scribble.variable",
             id: "share.lines", enabled: linesBlocked == nil, action: onLines)
      }
      // 两格按内容高、一样高。
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, PanelMetrics.hPad)
      .padding(.top, Space.m)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("share.chooser")
    }
  }

  private func tile(_ title: String, _ note: String, icon: String, id: String,
                    enabled: Bool = true, action: @escaping () -> Void) -> some View {
    let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
    return Button(action: action) {
      VStack(alignment: .leading, spacing: Space.s) {
        // 禁用时只有图标（纯装饰）乘禁用透明度；字不靠透明度淡化，换成对比仍 ≥3:1 的色阶。
        Image(systemName: icon)
          .font(TypeScale.price)
          .foregroundStyle(enabled ? t.amber : t.ink3)
          .opacity(enabled ? 1 : ControlMetrics.disabledOpacity)
          .frame(height: Space.xxl)
        Text(title).font(PanelFont.cardName).foregroundStyle(enabled ? t.ink : PanelDisabled.ink(t))
        Text(note).font(PanelFont.meta).foregroundStyle(t.ink3)
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
      }
      .padding(Inset.card)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(t.raised2, in: shape)
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityLabel("\(title)，\(note)")
    .accessibilityIdentifier(id)
  }
}
