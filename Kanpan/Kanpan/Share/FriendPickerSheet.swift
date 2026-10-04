import SwiftUI

struct FriendPickerSheet: View {
  var inbox: ShareInbox
  var onSend: (String) async throws -> Void
  @State private var username = ""
  @State private var adding = false
  @State private var sending = false
  @State private var error: String?
  @Environment(\.panelTheme) private var theme
  var body: some View {
    PanelSheet(title: "发给朋友", subtitle: nil) {
      if Self.showsList(adding: adding, typed: username, friends: inbox.friends.count) {
        ForEach(inbox.friends) { friend in
          PanelRow(name: friend.username, onTap: { send(friend.username) }) {
            Image(systemName: "paperplane.fill").font(TypeScale.bodyEmph).foregroundStyle(theme.amber)
          }.accessibilityIdentifier("share.friend.\(friend.username)")
        }
        PanelRow(name: "新朋友", divider: false, onTap: { adding = true })
          .accessibilityIdentifier("share.newFriend")
      } else {
        // 和朋友页的「加朋友」同一个输入框（`FriendNameField`），规则、置灰一个样。
        FriendNameField(text: $username, action: "发送", fieldID: "share.username",
                        buttonID: "share.send", ruleID: "share.username.rule") { send($0) }
      }
      if let error {
        Text(error).font(TypeScale.caption).foregroundStyle(theme.danger)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, PanelMetrics.hPad).padding(.vertical, Space.s)
          .accessibilityIdentifier("share.error")
      }
      if sending { ProgressView().tint(theme.amber).padding(Space.m) }
    }
    .disabled(sending)
    .accessibilityElement(children: .contain).accessibilityIdentifier("share.picker")
    .task { inbox.pull() }
    // 一开始打字就算「在填新朋友」：删光了重打，名单也不会趁那一下空着冒出来顶掉输入框。
    .onChange(of: username) { _, typed in if !typed.isEmpty { adding = true } }
  }
  /// 摆名单还是摆输入框。
  ///
  /// 名单是 `.task { inbox.pull() }` 拉回来的：第一次打开（本机还没缓存名单）时先摆输入框，
  /// 人已经开始打字了，名单这时才到——以前一到就把输入框换成名单，打了一半的名字没了（审查 D 线）。
  /// 所以输入框里有字就一直留着输入框；空着才在名单到了之后换成名单。
  static func showsList(adding: Bool, typed: String, friends: Int) -> Bool {
    !adding && typed.isEmpty && friends > 0
  }
  /// 名单里点的、输入框交来的都已经是服务端存的样子（`FriendNameField` 规整过）。
  private func send(_ name: String) {
    guard !sending, !name.isEmpty else { return }
    sending = true; error = nil
    Task {
      defer { sending = false }
      do { try await onSend(name) }
      catch is CancellationError {}
      catch { self.error = ShareClient.message(error) }
    }
  }
}
