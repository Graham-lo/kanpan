import SwiftUI
import KanpanCore
import ReviewUI

/// 「我的 › 交易所账户」：贴一把只读 Key，之后复盘本自己出交易复盘（自动复盘 3c）。
///
/// 没接：一行「币安 · 合约」、两个框（只读 API Key / Secret）、一颗「接入」。
/// 接入先过只读校验——Key 开着交易或提现权限就一行红字拒收，Keychain 一个字都不写。
/// 接着了：尾号四位、上次同步、回溯范围，「立即同步」与「移除」。
///
/// 不写教程、不写解释（`kanpan-ui-no-lecturing`）；Key 只在两个框里停留到按下「接入」，
/// 接上以后框清空，界面上只剩尾号。
struct ExchangeAccountPage: View {
  var bridge: ExchangeReviewBridge = .shared
  @Environment(\.panelTheme) private var t
  @State private var apiKey = ""
  @State private var secret = ""
  @State private var confirmRemove = false
  @FocusState private var focused: Field?
  private enum Field { case key, secret }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.l) {
        card
        if bridge.connected { connectedActions } else { connectForm }
      }
      .pageHorizontalInset()
      .padding(.vertical, Space.xl)
    }
    .scrollDismissesKeyboard(.interactively)
    .scrollBounceBehavior(.basedOnSize)
    .background(t.app.ignoresSafeArea())
    .navigationTitle("交易所账户")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("me.exchange.page")
    .confirmationDialog("移除这把 Key？", isPresented: $confirmRemove, titleVisibility: .visible) {
      Button("移除", role: .destructive) { Task { await bridge.disconnect() } }
        .accessibilityIdentifier("exchange.remove.confirm")
      Button("取消", role: .cancel) {}
    }
  }

  // MARK: - 卡片

  private var card: some View {
    VStack(spacing: 0) {
      HStack(spacing: Space.s) {
        Text(bridge.venue.rowTitle).font(TypeScale.heading).foregroundStyle(t.ink)
        Spacer(minLength: Space.s)
        Text(bridge.connected ? "已接入" : "未接入")
          .font(TypeScale.caption).foregroundStyle(bridge.connected ? t.amber : t.ink3)
          .accessibilityIdentifier("exchange.state")
      }
      .padding(.horizontal, Inset.card).padding(.vertical, Inset.rowV)
      .frame(minHeight: Inset.rowMin)
      if let status = bridge.status {
        divider
        info("Key", "••••" + status.keySuffix, id: "exchange.suffix")
        divider
        TimelineView(.periodic(from: .now, by: 30)) { context in
          info("上次同步", syncText(status, now: context.date), id: "exchange.lastSync")
        }
        divider
        info("回溯范围", Self.day(status.backfillFrom) + " 起", id: "exchange.backfill")
      }
    }
    .frame(maxWidth: .infinity)
    .background(t.raised2, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
  }

  private func syncText(_ status: ExchangeCredentialStore.Status, now: Date) -> String {
    if bridge.pulling { return "同步中" }
    guard let at = status.watermark else { return "还没同步" }
    return TradeLabels.ago(at, now: Int64(now.timeIntervalSince1970 * 1000))
  }

  private var divider: some View {
    Rectangle().fill(t.line).frame(height: 1 / 3).padding(.leading, Inset.card)
  }

  private func info(_ title: String, _ value: String, id: String) -> some View {
    HStack(spacing: Space.s) {
      Text(title).font(TypeScale.body).foregroundStyle(t.ink2)
      Spacer(minLength: Space.s)
      Text(value).font(TypeScale.body).foregroundStyle(t.ink).monospacedDigit()
        .accessibilityIdentifier(id)
    }
    .lineLimit(1)
    .padding(.horizontal, Inset.card).padding(.vertical, Inset.rowV)
    .frame(minHeight: Inset.rowMin)
  }

  // MARK: - 没接

  @ViewBuilder private var connectForm: some View {
    field {
      TextField("只读 API Key", text: $apiKey)
        .keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled()
        .focused($focused, equals: .key).submitLabel(.next).onSubmit { focused = .secret }
        .accessibilityIdentifier("exchange.key")
    }
    field {
      SecureField("Secret", text: $secret)
        .keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled()
        .focused($focused, equals: .secret).submitLabel(.go).onSubmit(submit)
        .accessibilityIdentifier("exchange.secret")
    }
    if let error = bridge.connectError {
      Text(error).font(TypeScale.footnote).foregroundStyle(t.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("exchange.error")
    }
    primary("接入", busy: bridge.connecting, enabled: ready, id: "exchange.connect", action: submit)
  }

  private var ready: Bool {
    !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func submit() {
    guard ready, !bridge.connecting else { return }
    focused = nil
    let key = apiKey, secret = self.secret
    Task {
      await bridge.connect(apiKey: key, secret: secret)
      if bridge.connected { apiKey = ""; self.secret = "" }
    }
  }

  private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content().font(TypeScale.body).padding(.horizontal, Space.m).frame(minHeight: Hit.min)
      .foregroundStyle(t.ink)
      .background(t.raised2, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
  }

  // MARK: - 接着

  @ViewBuilder private var connectedActions: some View {
    if let failure = bridge.lastFailure {
      Text(failure).font(TypeScale.footnote).foregroundStyle(t.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("exchange.error")
    }
    primary("立即同步", busy: bridge.pulling, enabled: true, id: "exchange.sync") {
      bridge.pull(force: true)
    }
    Button { confirmRemove = true } label: {
      Text("移除").font(TypeScale.bodyEmph).foregroundStyle(t.danger)
        .frame(maxWidth: .infinity, minHeight: Hit.min)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("exchange.remove")
  }

  /// 主按钮：和账号页同一套（琥珀胶囊 48 高；不可用时中性底 + `ink3` 字）。
  private func primary(_ title: String, busy: Bool, enabled: Bool, id: String,
                       action: @escaping () -> Void) -> some View {
    let live = busy || enabled
    return Button(action: action) {
      Group { if busy { ProgressView().tint(t.badgeInk) } else { Text(title) } }
        .font(TypeScale.title)
        .foregroundStyle(live ? t.badgeInk : PanelDisabled.ink(t))
        .frame(maxWidth: .infinity, minHeight: Hit.min + Space.xs)
        .background(Capsule().fill(live ? t.amber : PanelDisabled.fill(t)))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(busy || !enabled)
    .accessibilityIdentifier(id)
  }

  private static func day(_ ms: Int64) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
  }
}
