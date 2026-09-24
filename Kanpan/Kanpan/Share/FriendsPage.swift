import SwiftUI
import KanpanAccount

struct FriendsPage: View {
  var inbox: ShareInbox
  /// 没登录时整页只摆一句话和一颗「登录」：朋友、收件箱都挂在账号上，空着的
  /// 「还没有朋友」「还没有收到画线」只会让人以为是真的没有（审查 U15）。
  var loggedIn: Bool
  var onLogin: () -> Void
  var onOpen: (ShareItem) -> Void
  @State private var adding = false
  @State private var name = ""
  @State private var saving = false
  @State private var error: String?
  @Environment(\.panelTheme) private var theme
  var body: some View {
    PanelSheet(title: "朋友", subtitle: nil) {
      if loggedIn { content } else { signedOut }
    }
    .accessibilityElement(children: .contain).accessibilityIdentifier("friends.page")
    .task { inbox.pull() }
  }
  private var signedOut: some View {
    VStack(spacing: 14) {
      Text("登录后可收发画线").font(.scaled(13)).foregroundStyle(theme.ink3)
        .accessibilityIdentifier("friends.signedOut")
      Button(action: onLogin) {
        Text("登录").font(.scaled(14, .semibold)).frame(minWidth: 120, minHeight: 44)
      }.buttonStyle(.borderedProminent).tint(theme.amber)
        .accessibilityIdentifier("friends.login")
    }.frame(maxWidth: .infinity).padding(.vertical, 28)
  }
  @ViewBuilder private var content: some View {
      ForEach(inbox.friends) { friend in
        FriendRow(friend: friend) { Haptics.warning(); Task { await inbox.removeFriend(friend.username) } }
      }
      if inbox.friends.isEmpty, !adding {
        Text("还没有朋友").font(.scaled(13)).foregroundStyle(theme.ink3).padding(22)
      }
      // 加朋友在这一页自己做，不必先画一条线去「发给朋友」才能结识（审查 U15）。
      // 输入框和「发给朋友」里填新朋友的是同一个（`FriendNameField`）。
      if adding {
        FriendNameField(text: $name, action: "加", fieldID: "friends.username",
                        buttonID: "friends.add.confirm", ruleID: "friends.username.rule") { add($0) }
          .disabled(saving)
        if let error {
          Text(error).font(.scaled(12)).foregroundStyle(theme.danger)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 8)
            .accessibilityIdentifier("friends.error")
        }
      } else {
        PanelRow(name: "加朋友", divider: false, onTap: { error = nil; adding = true }) {
          Image(systemName: "plus").foregroundStyle(theme.amber)
        }.accessibilityIdentifier("friends.add")
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
  private func add(_ username: String) {
    guard !saving else { return }
    saving = true; error = nil
    Task {
      defer { saving = false }
      do {
        try await inbox.addFriend(username)
        Haptics.success(); name = ""; adding = false
      } catch is CancellationError {
      } catch AccountError.http(400, "cannot_send_self") {
        error = "不能加自己"
      } catch {
        self.error = ShareClient.message(error)
      }
    }
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
