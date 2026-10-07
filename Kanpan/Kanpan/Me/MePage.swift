import SwiftUI
import KanpanCore
import ReviewUI

/// 底栏第四格「我的」：个人的东西都从这一页进（2026-09-27 用户定的，方案
/// `docs/方案-我的-自动复盘-周期分组指标-2026-09-27.md` §1.3，原话「我的确实是对的」）。
///
/// 原来这些散在四处：复盘本挂在顶栏一颗按钮上（带角标）、全部预警只能从创建提醒页右上
/// 推进去、朋友和登录是设置里的两行、设置自己占着底栏最右那一格。现在底栏收成四格，
/// 这一页把它们收拢成六块：账号卡、复盘本、全部预警、朋友与收件箱、交易所、设置。
///
/// 规矩（`kanpan-ui-follows-hig-type-and-spacing-scales`、`kanpan-ui-no-lecturing`、
/// `kanpan-no-engineering-status-fields`）：
/// - 每块只有一行标题（16）+ 一行状态（12），不写解释（设置那块照方案 §2 没有状态行）；
/// - 外边距跟页面走（`Inset.page`：16 Pro 16 / 17 Pro Max 20），卡片内 16，卡片之间 16，
///   标题与状态之间 2；
/// - 整页铺琉璃底（`LiuliBackdrop`，2026-10-08 起），卡片是同一份琉璃材质的玻璃卡
///   （`liuliCard`），分隔线是材质里那根 1/3pt 细线，不另起颜色；
/// - 状态里的数全是现成缓存：复盘 `ReviewFeature.pendingCount` / `tally`（记录一变才重数）、
///   提醒 `AlertStore.liveCount`（存档一变才重数）、收件箱 `ShareInbox.unseen`（本来就是缓存）、
///   账号 `AccountFeature` 的同步字段——这一页重画不扫整张表。
///
/// 下一层都推在这一页自己的 `NavigationStack` 里（系统返回、底栏常驻），路径住在宿主
/// （`MainScreen.mePath`）：登录成功退回、点开一条收到的线、换号，都要宿主能动它。
/// 复盘本例外：它本来就是一整屏的 `fullScreenCover`（`ReviewBook`），从这儿点照旧开那一屏。
struct MePage: View {
  var store: PrefsStore
  var review: ReviewFeature
  @ObservedObject var alerts: AlertStore
  var inbox: ShareInbox
  @Binding var path: [MeRoute]
  /// 每一层画什么由宿主给——朋友页要的收件箱、提醒总表要的行情能力，都在宿主那儿。
  var destination: (MeRoute) -> AnyView
  var onReviewBook: () -> Void
  /// 账号卡：推一层账号页（同时 `account.open()`，登成功由宿主退回）。
  var onAccount: () -> Void
  /// 身下那条标签栏的高度。宿主的 `safeAreaInset` 进不了 `NavigationStack`，
  /// 这一页和推进来的每一层都自己让出这一截。
  var bottomInset: CGFloat = 0
  /// 交易所只读账户（自动复盘 3c）：交易所那一行、复盘本的交易那半句都从它来。
  var exchange: ExchangeReviewBridge = .shared

  @Environment(\.panelTheme) private var t
  @Environment(\.accountFeature) private var account

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        VStack(spacing: Space.l) {
          card { accountRow }
          card {
            row("复盘本", reviewStatus, tradeStatus, id: "me.review", action: onReviewBook)
            divider
            row("全部预警", alertStatus, id: "me.alerts") { path.append(.alerts) }
          }
          card {
            row("朋友与收件箱", friendsStatus, id: "me.friends") { path.append(.friends) }
            divider
            row("交易所", exchangeStatus, id: "me.exchange") { path.append(.exchange) }
          }
          card {
            row("设置", nil, id: "me.settings") { path.append(.settings) }
          }
        }
        .padding(.top, Space.xs)
        .padding(.bottom, Space.l)
        .pageHorizontalInset()
      }
      .scrollBounceBehavior(.basedOnSize)
      .safeAreaPadding(.bottom, bottomInset)
      .background { LiuliBackdrop() }
      .scrollContentBackground(.hidden)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("me.page")
      .navigationTitle("我的")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: MeRoute.self) { route in
        destination(route).safeAreaPadding(.bottom, bottomInset)
      }
    }
    .tint(t.amber)
    // 推进来的设置页、提醒总表、朋友页用的是面板零件，左右跟页面外边距走。
    .panelPageInset()
  }

  // MARK: - 六块

  /// 账号卡：没登录是「账号 / 登录 / 注册」；登录了是用户名 + 同步状态，行尾一颗「立即同步」
  /// （方案 §2 那一行，原来藏在账号页里一个 `Section` 里）。
  @ViewBuilder private var accountRow: some View {
    if let account {
      if account.user == nil {
        // 没登录：一句「未登录」+ 一颗「登录 / 注册」，整行仍可点（同一个 `me.account`）。
        HStack(spacing: Space.s) {
          row("账号", "未登录", id: "me.account", chevron: false, action: onAccount)
          LiuliPill("登录 / 注册", fill: false, action: onAccount)
            .padding(.trailing, Inset.card)
            .accessibilityIdentifier("me.account.login")
        }
      } else {
        HStack(spacing: 0) {
          row(account.user?.email ?? "", Self.syncMeta(account), id: "me.account",
              chevron: false, action: onAccount)
          Button { account.onSynchronize?() } label: {
            Text("立即同步").font(PanelFont.seg).foregroundStyle(t.amber)
              .padding(.horizontal, Inset.card)
              .frame(minHeight: Inset.rowMin)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("me.account.sync")
        }
      }
    }
  }

  /// 复盘本第一行：「观点 N 条 · 待判定 N」（方案 §2）。待判定和底栏角标同一个数，0 就不写。
  private var reviewStatus: String {
    let base = "观点 \(review.tally.live) 条"
    return review.pendingCount > 0 ? base + " · 待判定 \(review.pendingCount)" : base
  }

  /// 复盘本第二行（交易那半句）：「交易 上周 N 笔 · 净盈亏 ±X · 胜率 Y%」；
  /// 没接交易所、本机也没有回合就是「接入交易所后自动生成」。上周那一张和复盘本里的周报同一个口径。
  private var tradeStatus: String {
    guard exchange.connected || !review.trades.items.isEmpty else { return "接入交易所后自动生成" }
    let s = review.trades.weekly(now: Int64(Date().timeIntervalSince1970 * 1000), calendar: review.calendar).summary
    guard s.count > 0 else { return "交易 上周 0 笔" }
    return "交易 上周 \(s.count) 笔 · 净盈亏 \(TradeLabels.money(s.netPnl)) · 胜率 \(TradeLabels.percent(s.winRate))"
  }

  /// 交易所：「未接入」或「币安合约 · 上次同步 x 分钟前」。
  private var exchangeStatus: String {
    guard let status = exchange.status else { return "未接入" }
    let name = exchange.venue.displayName
    if exchange.pulling { return name + " · 同步中" }
    guard let at = status.watermark else { return name + " · 还没同步" }
    let ago = TradeLabels.ago(at, now: Int64(Date().timeIntervalSince1970 * 1000))
    return name + (ago == "刚刚" ? " · 刚同步" : " · 上次同步 " + ago)
  }

  /// 全部预警：还在等的价格 / 画线提醒几条（复盘到点不算，它在复盘本里说）。
  private var alertStatus: String { "生效中 \(alerts.liveCount)" }

  /// 朋友与收件箱：没看过的线几封；没登录就说没登录（朋友和收件箱都挂在账号上）。
  private var friendsStatus: String {
    guard account?.user != nil else { return "未登录" }
    return "未读 \(inbox.unseen.count)"
  }

  /// 账号卡的状态行（原来是设置里账号那一行的右半边，2026-09-27 随账号行搬过来）。
  /// 报的是「新不新」，不是「成功」——「成功」说的是上一次请求的结果，用户想知道的是
  /// 「我这台机器上的东西新不新」：有没推上去的就报几项，推完了报多久以前。
  /// 同步真出错时换成那句错误：按 §2G 的规矩同步失败只在这一处说一次，复盘本里不再重复。
  static func syncMeta(_ account: AccountFeature, now: Date = Date()) -> String {
    let canned: Set<String> = ["", "待同步", "尚未同步", "已同步", "同步中"]
    if !canned.contains(account.syncStatus) { return account.syncStatus }
    if account.pending > 0 { return "待同步 \(account.pending) 项" }
    guard let at = account.lastSync else { return "尚未同步" }
    let age = Int(now.timeIntervalSince(at))
    if age < 60 { return "已同步" }
    if age < 3600 { return "上次 \(age / 60) 分钟前" }
    if age < 86_400 { return "上次 \(age / 3600) 小时前" }
    return "上次 \(age / 86_400) 天前"
  }

  // MARK: - 零件

  private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(spacing: 0) { content() }
      .frame(maxWidth: .infinity)
      .liuliCard(radius: Radius.m)
  }

  private var divider: some View {
    Rectangle().fill(LiuliMaterial(t).rule).frame(height: LiuliMaterial.hairline).padding(.leading, Inset.card)
  }

  /// 一块：标题一行、状态一行（复盘本多一行交易那半句），行尾一枚灰箭头。整行都能点，最矮 44。
  private func row(_ title: String, _ status: String?, _ second: String? = nil, id: String, chevron: Bool = true,
                   action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: Space.s) {
        VStack(alignment: .leading, spacing: Space.xxs) {
          Text(title).font(TypeScale.heading).foregroundStyle(t.ink)
          if let status {
            Text(status).font(TypeScale.caption).foregroundStyle(t.ink3).monospacedDigit()
          }
          if let second {
            Text(second).font(TypeScale.caption).foregroundStyle(t.ink3).monospacedDigit()
          }
        }
        .lineLimit(1)
        Spacer(minLength: Space.s)
        if chevron { VectorIcon.chevronRight(ControlMetrics.chevron).foregroundStyle(t.ink3) }
      }
      .padding(.horizontal, Inset.card)
      .padding(.vertical, Inset.rowV)
      .frame(minHeight: Inset.rowMin)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(id)
    .accessibilityAddTraits(.isButton)
  }
}

/// 「我的」推进去的那几层。
enum MeRoute: Hashable {
  case account
  case friends
  case alerts
  case exchange
  case settings
}
