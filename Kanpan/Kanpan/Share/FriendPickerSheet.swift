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
      if !adding, !inbox.friends.isEmpty {
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
