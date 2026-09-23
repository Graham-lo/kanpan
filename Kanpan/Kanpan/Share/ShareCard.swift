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
    HStack(spacing: 7) {
      ShareThumbnail(item: item, inbox: inbox)
      VStack(alignment: .leading, spacing: 1) {
        Text(previewing ? "正在看 \(item.from) 的线" : item.replyTo != nil ? "\(item.from) 回了你" : item.from)
          .font(.system(size: 12)).foregroundStyle(theme.ink).lineLimit(1)
        if !previewing {
          Text("\(item.shortSymbol) · \(item.drawings.count) 条线" + (extra > 0 ? "  +\(extra)" : ""))
            .font(.system(size: 11)).foregroundStyle(theme.ink3).lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      if previewing {
        let kept = inbox.items.first(where: { $0.id == item.id })?.keptAt != nil
        Button(kept ? "已留下" : "留下", action: onKeep)
          .disabled(kept).foregroundStyle(kept ? theme.ink3 : theme.amber)
          .accessibilityIdentifier("share.keep")
        Button("回给 \(item.from)", action: onReply).foregroundStyle(theme.amber).lineLimit(1)
          .accessibilityIdentifier("share.reply")
        Button("退出", action: onExit).foregroundStyle(theme.ink3)
          .accessibilityIdentifier("share.exit")
      } else {
        Button("看看", action: onOpen).foregroundStyle(theme.amber)
          .accessibilityIdentifier("share.open")
      }
    }
    .font(.system(size: 13)).buttonStyle(.plain)
    .padding(.horizontal, 9).frame(height: 36)
    .background(RoundedRectangle(cornerRadius: 10).fill(theme.amberSoft)
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.amberLine, lineWidth: 0.5)))
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
    HStack(spacing: 10) {
      Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 13)).foregroundStyle(theme.amber)
      Text("回给 \(item.from)").font(.system(size: 12)).foregroundStyle(theme.ink).lineLimit(1)
      Spacer(minLength: 0)
      if sending {
        ProgressView().controlSize(.small).tint(theme.amber)
      } else {
        Button("发送", action: onSend).foregroundStyle(theme.amber)
          .accessibilityIdentifier("share.reply.send")
      }
      Button("取消", action: onCancel).foregroundStyle(theme.ink3)
        .accessibilityIdentifier("share.reply.cancel")
    }
    .font(.system(size: 13)).buttonStyle(.plain).disabled(sending)
    .padding(.horizontal, 9).frame(height: 36)
    .background(RoundedRectangle(cornerRadius: 10).fill(theme.amberSoft)
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.amberLine, lineWidth: 0.5)))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("share.replying")
  }
}
struct ShareThumbnail: View {
  var item: ShareItem
  var inbox: ShareInbox
  @State private var bytes: Data?
  @Environment(\.panelTheme) private var theme
  var body: some View {
    Group {
      if let bytes, let image = UIImage(data: bytes) {
        Image(uiImage: image).resizable().scaledToFill()
      } else {
        Image(systemName: "chart.xyaxis.line").font(.system(size: 15)).foregroundStyle(theme.ink3)
      }
    }
    .frame(width: 44, height: 36).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
    .task(id: item.id + "-" + String(inbox.revision)) { bytes = await inbox.shot(item.id) }
    .accessibilityHidden(true)
  }
}
