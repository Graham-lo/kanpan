import SwiftUI
import UIKit

/// 与提醒卡共用头部价格行；卡永不计时消失，划掉只记已读。
struct ShareCard: View {
  var item: ShareItem
  var inbox: ShareInbox
  var previewing = false
  var extra = 0
  var onOpen: () -> Void
  var onKeep: () -> Void
  var onExit: () -> Void
  var onReply: () -> Void = {}
  @Environment(\.panelTheme) private var theme
  var body: some View {
    // 2026-09-25 UI 整改 P2：字号吸到阶梯（名 12 / 副 11 / 按钮 13），内边距与圆角取 token。
    // 卡和提醒条落在头部同一个位置，高度同一个 36（`AlertPromptBar.height`）；
    // 里面每颗字按钮的点按区撑到 44×44，多出来的用负边距还给布局（`cardHit`）。
    HStack(spacing: Space.s) {
      // 缩略图上下各让 4，圆角与卡同心。
      ShareThumbnail(item: item, inbox: inbox, height: AlertPromptBar.height - 2 * Space.xs,
                     corner: Radius.concentric(outer: Radius.m, padding: Space.xs))
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(previewing ? "正在看 \(item.from) 的线" : item.replyTo != nil ? "\(item.from) 回了你" : item.from)
          .font(TypeScale.caption).foregroundStyle(theme.ink).lineLimit(1)
        if !previewing {
          Text("\(item.shortSymbol) · \(item.drawings.count) 条线" + (extra > 0 ? "  +\(extra)" : ""))
            .font(TypeScale.caption2).foregroundStyle(theme.ink3).lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      if previewing {
        let kept = inbox.items.first(where: { $0.id == item.id })?.keptAt != nil
        Button(kept ? "已保存" : "保存到图上", action: onKeep)
          .disabled(kept).foregroundStyle(kept ? PanelDisabled.ink(theme) : theme.amber)
          .cardHit()
          .accessibilityIdentifier("share.keep")
        Button("回给 \(item.from)", action: onReply).foregroundStyle(theme.amber).lineLimit(1)
          .cardHit()
          .accessibilityIdentifier("share.reply")
        Button("退出", action: onExit).foregroundStyle(theme.ink3)
          .cardHit()
          .accessibilityIdentifier("share.exit")
      } else {
        Button("查看", action: onOpen).foregroundStyle(theme.amber)
          .cardHit()
          .accessibilityIdentifier("share.open")
      }
    }
    .font(TypeScale.control).buttonStyle(.plain)
    .padding(.leading, Space.xs).padding(.trailing, Space.s)
    .frame(height: AlertPromptBar.height)
    .background(ShareCardSurface())
    .contentShape(Rectangle())
    .gesture(DragGesture(minimumDistance: 20).onEnded { value in
      if !previewing, abs(value.translation.width) > 44,
         abs(value.translation.width) > abs(value.translation.height) * 1.5 { inbox.opened(item) }
    })
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(previewing ? "share.preview" : "share.card")
    .accessibilityAction(named: "划掉") { if !previewing { inbox.opened(item) } }
  }
}
/// 「回给他」进行中：他的线已经留在我图上，我接着画，画好了点「发送」原路回过去。
/// 和收件卡同一个位置、同一副样子，不另起一层。
struct ShareReplyBar: View {
  var item: ShareItem
  var sending: Bool
  var onSend: () -> Void
  var onCancel: () -> Void
  @Environment(\.panelTheme) private var theme
  var body: some View {
    HStack(spacing: Space.s) {
      Image(systemName: "arrowshape.turn.up.left.fill").font(TypeScale.control).foregroundStyle(theme.amber)
      Text("回给 \(item.from)").font(TypeScale.caption).foregroundStyle(theme.ink).lineLimit(1)
      Spacer(minLength: 0)
      if sending {
        ProgressView().controlSize(.small).tint(theme.amber)
      } else {
        Button("发送", action: onSend).foregroundStyle(theme.amber)
          .cardHit()
          .accessibilityIdentifier("share.reply.send")
      }
      Button("取消", action: onCancel).foregroundStyle(theme.ink3)
        .cardHit()
        .accessibilityIdentifier("share.reply.cancel")
    }
    .font(TypeScale.control).buttonStyle(.plain).disabled(sending)
    .padding(.horizontal, Space.m).frame(height: AlertPromptBar.height)
    .background(ShareCardSurface())
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("share.replying")
  }
}
struct ShareThumbnail: View {
  var item: ShareItem
  var inbox: ShareInbox
  var height: CGFloat = AlertPromptBar.height
  var corner: CGFloat = Radius.xs
  /// 拿到的那张图和它属于哪封信。卡片换成下一封时旧图不能顶着新信的名字留在那儿。
  @State private var loaded: (id: String, image: UIImage)?
  @Environment(\.panelTheme) private var theme
  var body: some View {
    // 行滚出屏幕再滚回来（朋友页是懒加载的列表）状态就没了，先拿内存里现成的那张顶上，不闪占位图。
    let image = loaded?.id == item.id ? loaded?.image : inbox.cachedThumbnail(item.id)
    Group {
      if let image {
        Image(uiImage: image).resizable().scaledToFill()
      } else {
        Image(systemName: "chart.xyaxis.line").font(TypeScale.body).foregroundStyle(theme.ink3)
      }
    }
    .frame(width: Hit.min, height: height).clipped()
    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    // 已经有图的行只认信的 id；只有还没拿到图的（发的人截图还没传完、上一趟没拉下来）
    // 才跟着收件箱每拉一次重试一次。以前每拉一次，所有行的任务全部重跑（压测 H2）。
    .task(id: Self.loadKey(id: item.id, hasImage: image != nil, revision: inbox.revision)) {
      // 内存里现成的那张也记到自己身上，之后被淘汰出内存也不会退回占位图。
      if let image { if loaded?.id != item.id { loaded = (item.id, image) }; return }
      guard let fresh = await inbox.thumbnail(item.id) else { return }
      loaded = (item.id, fresh)
    }
    .accessibilityHidden(true)
  }
  /// 缩略图任务的身份。有图的行只认 id；`revision` 只在还没拿到图时才读（自动闭包），
  /// 有图的行连这个属性都不碰，收件箱每拉一次也不会让它们重画。
  static func loadKey(id: String, hasImage: Bool, revision: @autoclosure () -> Int) -> String {
    hasImage ? id : id + "#" + String(revision())
  }
}

/// 收件卡与「回给他」条共用的底：淡强调色、细描边，圆角取 `Radius.m`（连续曲率）。
private struct ShareCardSurface: View {
  @Environment(\.panelTheme) private var theme
  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
    shape.fill(theme.amberSoft).overlay(shape.strokeBorder(theme.amberLine, lineWidth: 0.5))
  }
}

private extension View {
  /// 卡里的字按钮：点击区 44×44，布局高度不超过卡高（和提醒条的 `promptHit` 同一个算法）。
  func cardHit() -> some View {
    hitTarget().padding(.vertical, -(Hit.min - AlertPromptBar.height) / 2)
  }
}
