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
            Image(systemName: "paperplane").foregroundStyle(theme.amber)
          }.accessibilityIdentifier("share.friend.\(friend.username)")
        }
        PanelRow(name: "新朋友", divider: false, onTap: { adding = true })
          .accessibilityIdentifier("share.newFriend")
      } else {
        HStack(spacing: 10) {
          TextField("朋友的用户名", text: $username)
            .keyboardType(.asciiCapable).textInputAutocapitalization(.never)
            .autocorrectionDisabled().submitLabel(.send)
            .onSubmit { send(username) }
            .font(.system(size: 14)).foregroundStyle(theme.ink)
            .accessibilityIdentifier("share.username")
          Button("发送") { send(username) }
            .font(.system(size: 13)).foregroundStyle(theme.amber)
            .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("share.send")
        }.padding(.horizontal, 18).frame(minHeight: 54)
      }
      if let error {
        Text(error).font(.system(size: 12)).foregroundStyle(theme.danger)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 8)
          .accessibilityIdentifier("share.error")
      }
      if sending { ProgressView().tint(theme.amber).padding(12) }
    }
    .disabled(sending)
    .accessibilityElement(children: .contain).accessibilityIdentifier("share.picker")
    .task { inbox.pull() }
  }
  private func send(_ name: String) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
