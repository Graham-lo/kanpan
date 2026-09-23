import SwiftUI

/// 「分享」点开后从面板底下升起的那块二选一：图片 / 画线。
///
/// 两块并排的大格，各写一句「对方收到的是什么」，不写「分享图片」「发给朋友」这种
/// 按实现起的名字——用户要选的是「发到微信」还是「让朋友在自己图上看见我的线」。
/// 画线那格发不了的时候（没登录、图上没线）照样摆着，只是变淡、底下那句换成原因：
/// 藏起来的话，用户不知道还有这条路。
///
/// 它盖在面板上而不是另起一张 sheet：竖屏面板本身就是 sheet，横屏是侧栏，
/// 两种外壳里「再弹一层」的行为不一样；画在面板自己身上，两边一个样子。
struct ShareChooser: View {
  var onImage: () -> Void
  var onLines: () -> Void
  /// 画线那格为什么发不了；nil 就是能发。
  var linesBlocked: String?
  var onCancel: () -> Void

  @Environment(\.panelTheme) private var t

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.black.opacity(0.28)
        .ignoresSafeArea()
        .onTapGesture(perform: onCancel)
        .accessibilityHidden(true)
        .transition(.opacity)

      VStack(spacing: 12) {
        HStack {
          Text("分享").font(PanelFont.title).foregroundStyle(t.ink)
          Spacer(minLength: 0)
          Button("取消", action: onCancel)
            .font(PanelFont.seg).foregroundStyle(t.ink2)
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 32)
            .accessibilityIdentifier("share.cancel")
        }
        HStack(spacing: 10) {
          tile("图片", "发到微信等任何地方", icon: "photo", id: "share.image", action: onImage)
          tile("画线", linesBlocked ?? "朋友在自己的图上看到你的线", icon: "scribble.variable",
               id: "share.lines", enabled: linesBlocked == nil, action: onLines)
        }
        // 两格按内容高、一样高；不然会被外层 ZStack 撑成整张面板那么高。
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, PanelMetrics.hPad)
      .padding(.top, 14)
      .padding(.bottom, 18)
      .background(t.raised, in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16,
                                                       style: .continuous))
      .overlay(alignment: .top) {
        UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
          .stroke(t.line, lineWidth: 0.5)
      }
      .transition(.move(edge: .bottom))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("share.chooser")
    }
  }

  private func tile(_ title: String, _ note: String, icon: String, id: String,
                    enabled: Bool = true, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(t.amber)
          .frame(height: 24)
        Text(title).font(PanelFont.cardName).foregroundStyle(t.ink)
        Text(note).font(PanelFont.meta).foregroundStyle(t.ink3)
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
      }
      .padding(12)
      .frame(maxWidth: .infinity, minHeight: 104, maxHeight: .infinity, alignment: .topLeading)
      .background(t.raised2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.45)
    .accessibilityLabel("\(title)，\(note)")
    .accessibilityIdentifier(id)
  }
}
