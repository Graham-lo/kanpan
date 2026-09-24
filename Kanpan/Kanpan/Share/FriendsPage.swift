import SwiftUI
import KanpanAccount

/// 朋友页：朋友名单 + 「收到的线」（收件箱）。
///
/// 2026-09-25 UI 整改 P2：头部换成系统导航栏（居中 17 标题），写法照 P1b 的提醒总表。
/// 它出现在两处，同一个页面、两种宿主：
/// - 设置 → 朋友：推进设置自己那个 `NavigationStack` 的一层（`pushed == true`），
///   系统返回，底栏常驻；
/// - 分享、深链、通知点开：仍是一张表，自己带 `NavigationStack` 和左上关闭（`panel.done`）。
struct FriendsPage: View {
  var inbox: ShareInbox
  /// 没登录时整页只摆一句话和一颗「登录」：朋友、收件箱都挂在账号上，空着的
  /// 「还没有朋友」「还没有收到画线」只会让人以为是真的没有（审查 U15）。
  var loggedIn: Bool
  var onLogin: () -> Void
  var onOpen: (ShareItem) -> Void
  /// 推在设置的导航栈里（系统返回），而不是自己一张表。
  var pushed = false
  @State private var adding = false
  @State private var name = ""
  @State private var saving = false
  @State private var error: String?
  /// 当前左划开着的是哪位朋友。一张表同一时刻只许开一行（`SwipeToDelete`）。
  @State private var openSwipe: String?
  @Environment(\.panelTheme) private var theme
  /// 登录态以账号本身为准：推在设置里的这一页由导航栈的 destination 造出来，
  /// 宿主递进来的 `loggedIn` 是造的那一刻的快照，登完回来它不一定跟着变。
  @Environment(\.accountFeature) private var account
  @Environment(\.panelHPad) private var hPad
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    if pushed {
      page
    } else {
      NavigationStack {
        page.toolbar {
          ToolbarItem(placement: .topBarLeading) {
            // 标识符沿用 `panel.done`：和其他表同一个出口。
            Button(role: .close) { dismiss() }
              .accessibilityIdentifier("panel.done")
          }
        }
      }
      .tint(theme.amber)
      .panelPageInset()
    }
  }

  private var page: some View {
    // 外面这层 VStack 是「这一页在不在」的记号（`friends.page`，UI 用例按 otherElements 找）；
    // `children: .contain` 让它只当容器，里头的行各留各的名字。
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 0) {
          if signedIn { content } else { signedOut }
        }
        .padding(.top, Space.xs)
        .padding(.bottom, Space.l)
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.interactively)
    }
    .background((pushed ? theme.app : theme.raised).ignoresSafeArea())
    .navigationTitle("朋友")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("friends.page")
    .task { inbox.pull() }
  }

  private var signedIn: Bool { account.map { $0.user != nil } ?? loggedIn }

  private var signedOut: some View {
    VStack(spacing: Space.l) {
      emptyMark("person.2.fill", "登录后可收发画线", id: "friends.signedOut")
      // 主按钮 44 一档，和账号页那颗同一种画法：强调色胶囊、`badgeInk` 字。
      Button(action: onLogin) {
        Text("登录").font(TypeScale.bodyEmph).foregroundStyle(theme.badgeInk)
          .padding(.horizontal, Space.section)
          .frame(minHeight: Hit.min)
          .background(Capsule().fill(theme.amber))
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("friends.login")
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Space.section)
  }

  @ViewBuilder private var content: some View {
    ForEach(inbox.friends) { friend in
      SwipeToDelete(id: friend.username, open: $openSwipe,
                    trailing: [.delete(theme) { remove(friend) }]) { _ in
        PanelRow(name: friend.username)
      }
    }
    if inbox.friends.isEmpty, !adding {
      emptyMark("person.2.fill", "还没有朋友")
    }
    // 加朋友在这一页自己做，不必先画一条线去「发给朋友」才能结识（审查 U15）。
    // 输入框和「发给朋友」里填新朋友的是同一个（`FriendNameField`）。
    if adding {
      FriendNameField(text: $name, action: "加", fieldID: "friends.username",
                      buttonID: "friends.add.confirm", ruleID: "friends.username.rule") { add($0) }
        .disabled(saving)
      if let error {
        Text(error).font(TypeScale.caption).foregroundStyle(theme.danger)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, hPad).padding(.bottom, Space.s)
          .accessibilityIdentifier("friends.error")
      }
    } else {
      PanelRow(name: "加朋友", divider: false, onTap: { error = nil; adding = true }) {
        Image(systemName: "plus").font(TypeScale.bodyEmph).foregroundStyle(theme.amber)
      }.accessibilityIdentifier("friends.add")
    }
    PanelGroupTitle(text: "收到的线")
    ForEach(inbox.items) { item in
      Button { onOpen(item) } label: { inboxRow(item) }
        .buttonStyle(.plain).accessibilityIdentifier("share.item.\(item.id)")
    }
    if inbox.items.isEmpty {
      emptyMark("tray.fill", "还没有收到画线")
    }
    if let notice = inbox.notice {
      Button { inbox.pull() } label: {
        Text("\(notice) · 重试").font(TypeScale.caption).foregroundStyle(theme.ink3)
          .frame(maxWidth: .infinity, minHeight: Hit.min)
          .contentShape(Rectangle())
      }.buttonStyle(.plain)
    }
  }

  /// 收件箱一行：缩略图 + 「谁 · 哪只 · 几条线」（15）+ 时间 / 已保存（12，ink3）。
  private func inboxRow(_ item: ShareItem) -> some View {
    HStack(spacing: Space.m) {
      ShareThumbnail(item: item, inbox: inbox)
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text("\(item.from) · \(item.shortSymbol) · \(item.drawings.count) 条线")
          .font(PanelFont.name).foregroundStyle(theme.ink).lineLimit(1)
        HStack(spacing: Space.s) {
          if let date = item.createdDate { Text(date, format: .dateTime.month().day().hour().minute()) }
          if item.keptAt != nil { Text("已保存") }
        }.font(TypeScale.caption).foregroundStyle(theme.ink3)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, hPad)
    .padding(.vertical, Space.s)
    .frame(minHeight: Inset.rowMin)
    .contentShape(Rectangle())
  }

  /// 空态：36 的实心图标 + 15 的一句，不写解释句（UI 审查 2026-09-24）。
  private func emptyMark(_ icon: String, _ text: String, id: String? = nil) -> some View {
    VStack(spacing: Space.s) {
      Image(systemName: icon)
        .font(.system(size: ControlMetrics.emptyGlyph))
        .foregroundStyle(theme.ink3)
        .accessibilityHidden(true)
      Text(text).font(TypeScale.body).foregroundStyle(theme.ink3)
        .accessibilityIdentifier(id ?? "")
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Space.xl)
  }

  private func remove(_ friend: ShareFriend) {
    Haptics.warning()
    Task { await inbox.removeFriend(friend.username) }
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
