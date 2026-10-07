import SwiftUI
import KanpanCore
import KanpanData
import KanpanNetwork

/// 设置面板（A6.3 / A6.7 / A6.8 / A6.9 / A6.10 / A6.11）。
///
/// 条目顺序：先照原型（外观 · 涨跌配色 · 十字线吸附），再按任务书 §10.6 追加
/// 原型里没有的「行情线路」。原型里的「演示实时跳动」是原型自己的假数据开关，不进 app。
///
/// 2026-09-28「收设置项」：只有必须由用户自己定的（配色、深浅、涨跌配色、线路）才留在这儿。
/// 「按屏幕亮度切换深浅」「涨跌幅起点」「时区」「盯盘时不锁屏」「清理存储空间」五行收掉——
/// 口径按品种类型自动定、时间一律上海 UTC+8、看图时自动常亮、缓存各自按上限自清。
/// 想恢复某一项看 tag `settings-before-trim-2026-09-28` 与 `.project-memory/PROJECT.md` 那一节。
///
/// 和「图表」的分界：**画在图上的东西归图表面板**。原型那份「价格轴」和「本根倒计时」
/// 在两边各有一份，改的却是同一个字段，现在只留图表那边（见 `ChartPanel`）。
///
/// 「高级与诊断」（API 域名、推送域名、缓存占用）整段撤出界面了。
/// 用户的话是界面上不要出现行情源 / 线路这类后台字段——那几行是工程排查用的，
/// 摆在设置里只会让人以为「是不是我哪儿设错了」。`apiHost` / `streamHost` 两个字段、
/// 「智能行情线路」开关 2026-09-24 都整条删了：主机一律由 `RouteResolver` 按线路给。
/// 清缓存那一行（「清理存储空间」）2026-09-28 也收了：各处缓存都有自己的上限、满了自己淘汰
/// （K 线 2000 条 / 512 MB、持仓量 20 MB LRU、快照 300 KB），而且都在 Caches/ 里，系统空间紧时会自己清。
///
/// 没有「确定」也没有「取消」：改一下立刻生效、立刻落盘，并给一次 selection 触觉
/// （只在手指拨到的那一下，`PrefsStore.updateByHand`）。
///
/// 2026-09-18 起它是标签栏最右边那一整页，不再是半屏（`asPage`）。用户定的是
/// 「这四个底部栏都单独是一个页面」——设置里要翻的东西不少，半屏拉上拉下本来就别扭。
///
/// 2026-09-27 起它不再占底栏一格：底栏收成四格，最右那格换成「我的」（`MePage`），
/// 设置从「我的」推进来一层（`MeRoute.settings`，系统返回、底栏常驻）。原来排在最上面的
/// 账号那一行、通用组里的「朋友」那一行随之删掉——两样都在「我的」里各占一块，
/// 同一个动作只留一个入口（`kanpan-one-entry-per-action`）。导航栈归「我的」，这一页不再自带。
struct SettingsPanel: View {
  var store: PrefsStore
  /// 当作推进来的整页画：系统导航栏、底色用页面底色。false 只剩预览在用（`PanelSheet` 那一版）。
  var asPage = false

  @Environment(\.panelTheme) private var t

  private var prefs: Prefs { store.prefs }

  // selection 触觉长在各个控件的动作上（`PrefsStore.updateByHand`），不挂在 `prefs` 上：
  // 挂在值上的话，这一页开着时云端落地、别处改设置也会震。
  var body: some View { page }

  /// 整页走系统导航栏：行内标题 17 semibold、滚动时系统自己的边缘效果
  /// （UI 审查 2026-09-24 定的导航写法：标签页整页与它钻进去的子页一律系统导航栏，
  /// 面板 / 半屏里的子页才用 `PanelSheet` 的「‹」）。栈是「我的」那一个（`MePage`），
  /// 标签栏让出的那一截由它给每一层补（`safeAreaPadding`），这儿不再管。
  @ViewBuilder private var page: some View {
    if asPage {
      ScrollView {
        VStack(spacing: 0) { rows }
          .padding(.top, Space.xs)
          .padding(.bottom, Space.l)
      }
      .scrollBounceBehavior(.basedOnSize)
      .accessibilityIdentifier("panel.content")
      // 琉璃底（带光斑），和「我的」同一块料（2026-10-08）。行仍是平铺的细线分隔：
      // 「通知」那一组（`AlertSettingsSection`）自带组名，这一页不另起玻璃卡，免得一半成卡一半不成。
      .background { LiuliBackdrop() }
      .navigationTitle("设置")
      .navigationBarTitleDisplayMode(.inline)
    } else {
      PanelSheet(title: "设置", subtitle: nil) { rows }
    }
  }

  /// 分组照 UI 审查 §4.4：配色 / 深浅（`DisplaySettingsSection`）之后是「行情」「通知」
  /// 「通用」三组，只有组名、没有说明文字。账号那一行 2026-09-27 搬去「我的」的账号卡。
  /// 进下一页的行尾一律是箭头；就地动作（恢复、清除）是强调色的字，整行都能点。
  @ViewBuilder private var rows: some View {
    DisplaySettingsSection(store: store)

    PanelGroupTitle(text: "行情")
    PanelRow(name: "涨跌色") {
      PanelSegment(options: [("绿涨红跌", false), ("红涨绿跌", true)], selection: prefs.redUp) { v in
        store.updateByHand { $0.redUp = v }
      }
    }
    // 「十字线吸附到 K 线」2026-09-28 收掉（收设置项 B 组）；2026-10-03 起十字线一律不吸附
    // 收盘价，横线跟着手指高度走（`kanpan-crosshair-follows-finger-no-magnet`）。
    // 「启动快照」不再摆出来（2026-09-24 审查 U13）：它是工程开关，用户没有理由关它。
    // 字段也一起删了，启动快照一律开着（`MainScreen.boot`）。

    // 线路是用户定的，选了哪条就走哪条，没有「自动」：原来那套对冲 + 自动切源
    // 偶尔会把一次探测失败当成「这台机器上不去币安」，整套换到 OKX 还要等好几
    // 分钟才肯回头。选择只记在本机这台设备上（审查 B7）。
    PanelRow(name: "线路", term: .route, divider: false) {
      PanelSegment(options: SettingsPanel.routes, selection: prefs.routePolicy,
                   id: "settings.routePolicy") { v in
        store.updateByHand { $0.routePolicy = v }
      }
    }

    // 通知：铃声、自选波动、通知权限（2026-09-25 从提醒总表搬过来）。「提醒」那一行删了：
    // 建提醒在图上十字线那颗药丸，管提醒在新建页右上「全部预警」（用户：「入口改到了外面了就不需要了」）。
    AlertSettingsSection(preferences: store)

    PanelGroupTitle(text: "通用")
    // 「自动适应」开关 + 「已学到的」（模块在 `Habits/`）。
    HabitSettingsRows(store: store)
    // 「朋友」原来排在这一组最上面，2026-09-27 搬去「我的 › 朋友与收件箱」。
    aboutRow
    // 不弹确认框：确认框把「点错了」的代价前置给每一次点击，而这件事本来就
    // 撤得回来。直接恢复，右边留一颗「撤销」五秒。
    PanelRow(name: "恢复默认", divider: false, onTap: { resetAll() }) {
      Text("恢复").font(PanelFont.seg).foregroundStyle(t.amber)
    }
    .accessibilityIdentifier("settings.reset")
  }

  // MARK: - 行

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

  /// 恢复默认。「撤销」只还原这一下改到的字段（`restore(_:from:)`）：撤销前那几秒里
  /// 云端落地的、别处改的，不跟着被抹回去。
  private func resetAll() {
    let before = store.prefs
    let changed = store.resetToDefaults()
    Haptics.warning()
    store.note("已恢复默认", undo: { store.restore(changed, from: before) })
  }

  // MARK: - 分段选项

  /// 行情线路两档。顺序照 `MarketRoutePolicy.allCases`：直连 / 网关。
  static let routes: [(String, MarketRoutePolicy)] =
    MarketRoutePolicy.allCases.map { ($0.title, $0) }
}

#if DEBUG
#Preview("设置") {
  PanelPreviewHost { store in SettingsPanel(store: store) }
}
#endif
