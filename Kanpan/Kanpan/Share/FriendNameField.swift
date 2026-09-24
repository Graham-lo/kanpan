import SwiftUI
import KanpanAccount

/// 填朋友用户名的那一行：「发给朋友」里的新朋友、朋友页上的「加朋友」共用这一个。
///
/// 规则和注册用户名同一条（`AccountCredentialRules`，服务端 `share.rs` 的 `username`
/// 对同一份夹具）：不合规则时右边的按钮置灰，框下只在填了、而且不合格时摆一行规则字；
/// 交出去的是服务端会存的样子（去首尾空白、小写）。
struct FriendNameField: View {
  @Binding var text: String
  /// 按钮上的字：「发送」「加」。
  var action: String
  /// 输入框、按钮、规则字三处的无障碍 id 前缀，如 `share` → `share.username` / `share.send`。
  var fieldID: String
  var buttonID: String
  var ruleID: String
  var onCommit: (String) -> Void
  @FocusState private var focused: Bool
  @Environment(\.panelTheme) private var theme

  private var name: String? { AccountCredentialRules.username(text) }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 10) {
        TextField("朋友的用户名", text: $text)
          .keyboardType(.asciiCapable).textInputAutocapitalization(.never)
          .autocorrectionDisabled().submitLabel(.done)
          .focused($focused)
          .onSubmit { commit() }
          .font(.scaled(14)).foregroundStyle(theme.ink)
          .accessibilityIdentifier(fieldID)
        Button(action) { commit() }
          .font(.scaled(13)).foregroundStyle(name == nil ? theme.ink3 : theme.amber)
          .disabled(name == nil)
          .accessibilityIdentifier(buttonID)
      }.frame(minHeight: 54)
      if !text.isEmpty, name == nil {
        Text(AccountCredentialRules.usernameRule).font(.scaled(11)).foregroundStyle(theme.ink3)
          .padding(.bottom, 8).accessibilityIdentifier(ruleID)
      }
    }.padding(.horizontal, 18)
  }

  private func commit() {
    guard let name else { return }
    onCommit(name)
  }
}
