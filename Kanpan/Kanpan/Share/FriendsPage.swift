import KanpanChart
import SwiftUI

struct FriendsPage: View {
  var inbox: ShareInbox
  var onOpen: (ShareItem) -> Void
  @Environment(\.panelTheme) private var theme
  var body: some View {
    PanelSheet(title: "朋友", subtitle: nil) {
      ForEach(inbox.friends) { friend in
        FriendRow(friend: friend) { Haptics.warning(); Task { await inbox.removeFriend(friend.username) } }
      }
      if inbox.friends.isEmpty {
        Text("还没有朋友").font(.scaled(13)).foregroundStyle(theme.ink3).padding(22)
      }
      PanelGroupTitle(text: "收到的线")
      ForEach(inbox.items) { item in
        Button { onOpen(item) } label: {
          HStack(spacing: 10) {
            ShareThumbnail(item: item, inbox: inbox)
            VStack(alignment: .leading, spacing: 4) {
              Text("\(item.from) · \(item.shortSymbol) · \(item.drawings.count) 条线")
                .font(.scaled(13)).foregroundStyle(theme.ink).lineLimit(1)
              HStack(spacing: 6) {
                if let date = item.createdDate { Text(date, format: .dateTime.month().day().hour().minute()) }
                if item.keptAt != nil { Text("已保存") }
              }.font(.scaled(11)).foregroundStyle(theme.ink3)
            }
            Spacer(minLength: 0)
          }.padding(.horizontal, 18).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("share.item.\(item.id)")
      }
      if inbox.items.isEmpty {
        Text("还没有收到画线").font(.scaled(13)).foregroundStyle(theme.ink3).padding(22)
      }
      if let notice = inbox.notice {
        Button("\(notice) · 重试") { inbox.pull() }
          .font(.scaled(12)).foregroundStyle(theme.ink3).padding(16)
      }
    }
    .accessibilityElement(children: .contain).accessibilityIdentifier("friends.page")
    .task { inbox.pull() }
  }
}
private struct FriendRow: View {
  var friend: ShareFriend
  var onDelete: () -> Void
  @State private var revealed = false
  @Environment(\.panelTheme) private var theme
  var body: some View {
    ZStack(alignment: .trailing) {
      Button("删除") { onDelete() }.font(.scaled(13)).foregroundStyle(theme.danger)
        .frame(width: 64, height: 48).opacity(revealed ? 1 : 0)
        .accessibilityIdentifier("friends.delete.\(friend.username)")
      Text(friend.username).font(.scaled(14)).foregroundStyle(theme.ink)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 18).background(theme.raised).offset(x: revealed ? -64 : 0)
        .gesture(DragGesture(minimumDistance: 18).onEnded { value in
          guard abs(value.translation.width) > abs(value.translation.height) else { return }
          withAnimation(.easeOut(duration: 0.18)) { revealed = value.translation.width < -25 }
        })
        .accessibilityAction(named: "删除朋友", onDelete)
    }.clipped()
  }
}
