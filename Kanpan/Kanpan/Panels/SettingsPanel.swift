import SwiftUI
import KanpanCore
import KanpanData
import KanpanNetwork

/// 设置面板（A6.3 / A6.7 / A6.8 / A6.9 / A6.10 / A6.11）。
///
/// 条目顺序：先照原型（外观 · 涨跌配色 · 时区 · 十字线吸附），再按任务书 §10.6 追加
/// 原型里没有的那几项（盯盘时不锁屏 · 行情线路 · 清理存储空间）。原型里的
/// 「演示实时跳动」是原型自己的假数据开关，不进 app。
///
/// 和「图表」的分界：**画在图上的东西归图表面板**。原型那份「价格轴」和「本根倒计时」
/// 在两边各有一份，改的却是同一个字段，现在只留图表那边（见 `ChartPanel`）。
///
/// 「高级与诊断」（API 域名、推送域名、缓存占用）整段撤出界面了。
/// 用户的话是界面上不要出现行情源 / 线路这类后台字段——那几行是工程排查用的，
/// 摆在设置里只会让人以为「是不是我哪儿设错了」。`apiHost` / `streamHost` 两个字段、
/// 「智能行情线路」开关 2026-09-24 都整条删了：主机一律由 `RouteResolver` 按线路给。
/// 唯一留下的是清缓存（界面上写「清理存储空间」）：那是用户真会想干的一件事。
///
/// 没有「确定」也没有「取消」：改一下立刻生效、立刻落盘，并给一次 selection 触觉。
///
/// 2026-09-18 起它是标签栏最右边那一整页，不再是半屏（`asPage`）。用户定的是
/// 「这四个底部栏都单独是一个页面」——设置里要翻的东西不少，半屏拉上拉下本来就别扭。
struct SettingsPanel: View {
  var store: PrefsStore
  /// 当作标签栏上的整页画：不要左上角的「‹」，底色用页面底色。
  var asPage = false
  var onFriends: (() -> Void)?

  @Environment(\.panelTheme) private var t
  @Environment(\.accountFeature) private var account

  private var prefs: Prefs { store.prefs }

  /// 整页时推进设置自己这个导航栈的那几层（账号、朋友）。路径住在宿主（`MainScreen`）：
  /// 登录成功要退回、点开一条收到的线要清空，都得宿主能动它。nil = 不推，走宿主的表。
  var path: Binding<[SettingsRoute]>? = nil
  /// 每一层画什么由宿主给——朋友页要的收件箱、打开收到的线，都在宿主那儿。
  var destination: ((SettingsRoute) -> AnyView)? = nil
  /// 账号那一行。整页时推一层账号页（系统返回，底栏常驻）；nil 走 `account.open()` 那张表。
  var onAccount: (() -> Void)? = nil
  /// 整页时身下那条标签栏的高度。宿主的 `safeAreaInset` 进不了 `NavigationStack`，
  /// 这一页和推进来的每一层都自己让出这一截，滚到底最后一行才在标签栏上沿以内。
  var bottomInset: CGFloat = 0

  var body: some View {
    page
      // 账号页由**一个** presenter 持有（审查 C-06）。
      //
      // 这一页当标签栏整页画的时候，它是长在根视图树里的一节，而根那一层
      // （`MainScreen`）已经拿同一个 `account.presented` 挂了一张 `.sheet`。
      // 两个 presenter 抢同一个布尔：SwiftUI 只认一个，另一个的呈现状态没人收，
      // 「关掉之后要点两下才再开」这类症状就是从那儿来的。所以整页时这儿不挂，
      // 点账号入口只是把布尔置位，开页的事交给根。
      //
      // `asPage == false` 的那条路留着：那时这一页自己是一张 sheet，账号页得叠在
      // 它上面，根的 sheet 够不着——那才是「真正作为上层 sheet 的设置上下文」。
      .modifier(AccountPresenter(account: asPage ? nil : account))
      .sensoryFeedback(.selection, trigger: prefs)
  }

  /// 整页走系统 `NavigationStack`：行内标题 17 semibold、滚动时系统自己的边缘效果
  /// （UI 审查 2026-09-24 定的导航写法：标签页整页与它钻进去的子页一律系统导航栏，
  /// 面板 / 半屏里的子页才用 `PanelSheet` 的「‹」）。半屏那条路（`asPage == false`，
  /// 预览与旧入口）仍是 `PanelSheet`，两条路各走各的，同一条路径上不中途换写法。
  @ViewBuilder private var page: some View {
    if asPage {
      // 设置 → 账号 / 朋友推在这个栈里（UI 整改 P2，2026-09-25）：底栏常驻、系统返回，
      // 回来时滚动位置还在。别的入口（图表面板、分享、深链）进来的仍是表。
      NavigationStack(path: path ?? .constant([])) {
        ScrollView {
          VStack(spacing: 0) { rows }
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("panel.content")
        .safeAreaPadding(.bottom, bottomInset)
        .background(t.app.ignoresSafeArea())
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SettingsRoute.self) { route in
          destination?(route).safeAreaPadding(.bottom, bottomInset)
        }
      }
      // 行文、分组标题、皮肤卡左右跟页面外边距走：16 Pro 上 16，17 Pro Max 上 20。
      .panelPageInset()
    } else {
      PanelSheet(title: "设置", subtitle: nil) { rows }
    }
  }

  /// 分组照 UI 审查 §4.4：配色 / 深浅（`DisplaySettingsSection`）之后是「行情」「通知」
  /// 「通用」三组，只有组名、没有说明文字。账号那一行照系统设置的习惯排在最上面，自己不成组。
  /// 进下一页的行尾一律是箭头；就地动作（恢复、清除）是强调色的字，整行都能点。
  @ViewBuilder private var rows: some View {
    if let account {
      // 登录后这一行报的是「上次同步多久以前」，不是「成功」——「成功」说的是
      // 上一次请求的结果，用户想知道的是「我这台机器上的东西新不新」。
      PanelRow(name: account.user?.email ?? "登录",
               meta: account.user == nil ? nil : syncMeta(account),
               onTap: { if let onAccount { onAccount() } else { account.open() } }) {
        nextPageMark
      }.accessibilityIdentifier("settings.account")
    }
    DisplaySettingsSection(store: store)

    PanelGroupTitle(text: "行情")
    PanelRow(name: "涨跌配色") {
      PanelSegment(options: [("绿涨红跌", false), ("红涨绿跌", true)], selection: prefs.redUp) { v in
        store.update { $0.redUp = v }
      }
    }
    PanelRow(name: "涨跌幅起点") {
      // 自带标签的 `Menu(_:)` 会用系统强调色（蓝），整页就这一处跳出配色之外。
      // 自己搭标签，颜色从 `PanelTheme` 取。
      Menu {
        ForEach(ChangeBasis.allCases, id: \.self) { basis in
          Button(basis.title) { store.update { $0.changeBasis = basis } }
        }
      } label: {
        HStack(spacing: Space.xs) {
          Text(prefs.changeBasis.title).font(PanelFont.seg)
          VectorIcon.chevron(ControlMetrics.chevron, w: 1.7)
        }
        .foregroundStyle(t.amber)
        .rowHitTarget()
      }.accessibilityIdentifier("settings.changeBasis")
    }
    PanelRow(name: "时区") {
      PanelSegment(options: SettingsPanel.zones, selection: prefs.timeZone) { v in
        store.update { $0.timeZone = v }
      }
    }
    // 画线「更多」里还有一颗「吸附到 K 线」：那颗管画线端点，这颗管长按出来的十字线，
    // 两件事、两个出厂档位（`Prefs.magnet` 的注释）。同一个动词、各自写明主语，
    // 不再一个叫「磁吸」一个叫「吸附」（审查 U13）。
    switchRow("十字线吸附到 K 线", nil, prefs.magnet) { $0.magnet = $1 }
      .accessibilityIdentifier("settings.magnet")
    switchRow("盯盘时不锁屏", nil, prefs.keepAwake) { $0.keepAwake = $1 }
      .accessibilityIdentifier("settings.keepAwake")
    // 「启动快照」不再摆出来（2026-09-24 审查 U13）：它是工程开关，用户没有理由关它。
    // 字段也一起删了，启动快照一律开着（`MainScreen.boot`）。

    // 线路是用户定的，选了哪条就走哪条，没有「自动」：原来那套对冲 + 自动切源
    // 偶尔会把一次探测失败当成「这台机器上不去币安」，整套换到 OKX 还要等好几
    // 分钟才肯回头。选择只记在本机这台设备上（审查 B7）。
    PanelRow(name: "行情线路", divider: false) {
      PanelSegment(options: SettingsPanel.routes, selection: prefs.routePolicy,
                   id: "settings.routePolicy") { v in
        store.update { $0.routePolicy = v }
      }
    }

    // 通知：铃声、自选波动、通知权限（2026-09-25 从提醒总表搬过来）。「提醒」那一行删了：
    // 建提醒在图上十字线那颗药丸，管提醒在新建页右上「全部预警」（用户：「入口改到了外面了就不需要了」）。
    AlertSettingsSection(preferences: store)

    PanelGroupTitle(text: "通用")
    // 「朋友」原来和「提醒」同一组；提醒那一行走了，它不单独顶一个同名分组标题（审查 U13），
    // 排在通用组最上面。
    if let onFriends {
      PanelRow(name: "朋友", onTap: onFriends) {
        nextPageMark
      }.accessibilityIdentifier("settings.friends")
    }
    aboutRow
    // 不弹确认框：确认框把「点错了」的代价前置给每一次点击，而这件事本来就
    // 撤得回来。直接恢复，右边留一颗「撤销」五秒。
    PanelRow(name: "恢复默认", onTap: { resetAll() }) {
      Text("恢复").font(PanelFont.seg).foregroundStyle(t.amber)
    }
    .accessibilityIdentifier("settings.reset")
    // 清缓存是排查用的，平时用不着，放在最底（2026-09-24 审查 U13）。
    cacheRow
  }

  /// 进下一页的行尾箭头。全 app 列表箭头一个尺寸（`ControlMetrics.chevron`），灰色——
  /// 强调色留给就地动作（「恢复」「清除」「隐私政策」）。
  private var nextPageMark: some View {
    VectorIcon.chevronRight(ControlMetrics.chevron).foregroundStyle(t.ink3)
  }

  // MARK: - 行

  private func switchRow(_ name: String, _ meta: String?, _ on: Bool,
                         _ set: @escaping (inout Prefs, Bool) -> Void) -> some View {
    PanelRow(name: name, meta: meta) {
      PanelSwitch(isOn: on) { store.update { set(&$0, !on) } }
    }
  }

  /// A6.11：清的是 `KanpanData.Paths` 指的那几处，不是另拼一套目录。
  ///
  /// 右边不再报「占了多少 MB」：那个数字是给我们排查用的，用户看到它只会开始
  /// 琢磨「多少算多」。「已清理存储空间」那一句带着「撤销」才说（P2.7）——它不是报喜，
  /// 是这一下还能反悔；只报成功、没有下一步可做的提示仍然不说（2026-09-21）。
  private var cacheRow: some View {
    // 行名写用户得到什么（空间），不写我们清的是什么（缓存）（审查 U13）。清的都是
    // 没了还能原样取回的行情数据，偏好、画线、自选一样不碰（`MarketCacheTests`）。
    // 点下去先给五秒反悔，过了才真清（P2.7），所以这里不再转圈。整行都能点，
    // 和「恢复默认」同一种写法（UI 审查：「清除」原来只有 26×14 的字能点）。
    PanelRow(name: "清理存储空间", divider: false,
             onTap: { Haptics.warning(); store.clearCacheLater() }) {
      Text("清除").font(PanelFont.seg).foregroundStyle(t.amber)
    }
    .accessibilityIdentifier("settings.clearCache")
  }

  /// 「关于」（P3.6）：版本号、构建号，和托管在账号服务上的两张静态页。
  /// 正文由 `kanpan-api` 的 `/privacy`、`/terms` 发（`legal.rs`），这里只放链接，
  /// 用系统浏览器打开；账号服务地址没配（开发包）就不摆链接。
  private var aboutRow: some View {
    PanelRow(name: "关于", meta: SettingsPanel.version) {
      if let base = SettingsPanel.legalBase {
        HStack(spacing: Space.xs) {
          Link(destination: base.appending(path: "privacy")) { Text("隐私政策").rowHitTarget() }
            .accessibilityIdentifier("settings.privacy")
          Link(destination: base.appending(path: "terms")) { Text("服务条款").rowHitTarget() }
            .accessibilityIdentifier("settings.terms")
        }
        .font(PanelFont.seg).foregroundStyle(t.amber)
      }
    }
    // 不 contain 的话外层这个 id 会盖到两条链接上，`settings.privacy` / `settings.terms` 就找不到了。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("settings.about")
  }

  static var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let short = info["CFBundleShortVersionString"] as? String ?? "—"
    let build = info["CFBundleVersion"] as? String ?? "—"
    return "Hkline \(short)（\(build)）"
  }

  static var legalBase: URL? { ServerHosts.accountAPI }

  private func resetAll() {
    let before = store.prefs
    store.resetToDefaults()
    Haptics.warning()
    store.note("已恢复默认", undo: { store.restore(before) })
  }

  /// 账号行右边那句。同步真出错时它换成那句错误——按 §2G 的规矩，
  /// 同步失败只在这一处说一次，复盘本里不再重复。
  private func syncMeta(_ account: AccountFeature) -> String {
    let canned: Set<String> = ["", "已暂停", "待同步", "尚未同步", "已同步", "同步中"]
    if !canned.contains(account.syncStatus) { return account.syncStatus }
    guard let at = account.lastSync else { return "尚未同步" }
    let age = Int(Date().timeIntervalSince(at))
    if age < 60 { return "刚刚同步" }
    if age < 3600 { return "上次同步 \(age / 60) 分钟前" }
    if age < 86_400 { return "上次同步 \(age / 3600) 小时前" }
    return "上次同步 \(age / 86_400) 天前"
  }

  // MARK: - 分段选项

  /// A6.9。三档照原型：本地 / UTC / 交易所，第三档字面写「UTC+8」（审查 U13：「UTC」「交易所」
  /// 并排像同一件事）。文字取 `TZChoice.display`，不在这儿另写一份。
  static let zones: [(String, TZChoice)] = TZChoice.allCases.map { ($0.display, $0) }

  /// 行情线路两档。顺序照 `MarketRoutePolicy.allCases`：直连 / 网关。
  static let routes: [(String, MarketRoutePolicy)] =
    MarketRoutePolicy.allCases.map { ($0.title, $0) }
}

#if DEBUG
#Preview("设置") {
  PanelPreviewHost { store in SettingsPanel(store: store) }
}
#endif

/// 把账号页挂在调用方自己这一层。`account` 为 nil 时整段不挂——
/// 那说明账号呈现权在别人手里（见 `SettingsPanel` 里那段说明）。
private struct AccountPresenter: ViewModifier {
  var account: AccountFeature?
  func body(content: Content) -> some View {
    if let account {
      content.sheet(isPresented: Binding(get: { account.presented },
                                         set: { account.presented = $0 })) {
        AccountView(feature: account)
      }
    } else {
      content
    }
  }
}

/// 设置整页推进去的那几层。
enum SettingsRoute: Hashable {
  case account
  case friends
}
