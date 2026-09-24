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
  @Environment(\.panelHPad) private var hPad

  private var name: String? { AccountCredentialRules.username(text) }

  var body: some View {
    // 左右边距和 `PanelRow` 同一个 `hPad`（原来 18，和上下几行的左缘差 2pt 对不齐）。
    VStack(alignment: .leading, spacing: Space.xs) {
      HStack(spacing: Space.m) {
        TextField("朋友的用户名", text: $text)
          .keyboardType(.asciiCapable).textInputAutocapitalization(.never)
          .autocorrectionDisabled().submitLabel(.done)
          .focused($focused)
          .onSubmit { commit() }
          .font(TypeScale.body).foregroundStyle(theme.ink)
          .accessibilityIdentifier(fieldID)
          // 输入框 44 高、圆角 8，和账号页的输入框同一种画法（UI 整改 P1b / P2）。
          .padding(.horizontal, Space.m)
          .frame(minHeight: Hit.min)
          .background(theme.raised2, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        Button { commit() } label: {
          Text(action).font(TypeScale.bodyEmph)
            .foregroundStyle(name == nil ? PanelDisabled.ink(theme) : theme.amber)
            .hitTarget()
        }
          .buttonStyle(.plain)
          .disabled(name == nil)
          .accessibilityIdentifier(buttonID)
      }.padding(.vertical, Space.xs)
      if !text.isEmpty, name == nil {
        Text(AccountCredentialRules.usernameRule).font(TypeScale.caption).foregroundStyle(theme.ink3)
          .padding(.bottom, Space.s).accessibilityIdentifier(ruleID)
      }
    }.padding(.horizontal, hPad)
  }

  private func commit() {
    guard let name else { return }
    onCommit(name)
  }
}
