import KanpanCore
import SwiftUI

/// 提醒总表（方案 2.3 的「管理」）用到的宿主能力。总表有两处出现（深链 / 通知点开时是一张
/// 表，新建提醒页右上「全部」推进来是一层），两处接的是同一份，由宿主（`MainScreen`）拼好交过来。
struct AlertListContext {
  /// 点一行：去那条线上（复盘到点去那条记录）。宿主接成深链。
  var onOpen: (KanpanCore.Alert) -> Void = { _ in }
  /// 时间按用户在设置里选的那档时区写。
  var zone: TZOffset = .system
  /// 按用户打的代号查品种与现价（编辑页要）。
  var quote: (String) -> PriceAlertQuote? = { _ in nil }
  /// 编辑页定了品种之后叫一声，宿主去要一口价。
  var prepareQuote: (String) -> Void = { _ in }
  /// 编辑页关了叫一声，宿主放掉 `prepareQuote` 点名要的那一只（图上那只照旧）。
  var releaseQuote: () -> Void = {}
  /// 锁屏上正盯着的那条提醒（一台设备只盯一条）。
  var watching: String? = nil
  /// 行上那颗「盯一个」：宿主去开 / 收锁屏实时活动。
  var onWatch: (KanpanCore.Alert) -> Void = { _ in }
}

/// 提醒总表（方案 2.3 的「管理」）。
///
/// 全 app 管提醒只有这一处：改条件、编辑、删除、重新上膛都在这儿。
/// 图上那枚小铃铛只表示「这条线挂着提醒」，点它不弹任何菜单——同一个动作
/// 只留一个入口（`kanpan-one-entry-per-action`）。建提醒也只有一个入口：图上十字线那颗
/// 「创建提醒」，所以这张表右上不再有「新建」。
///
/// 2026-09-25 起它不再挂在设置里（入口搬到了图上）：从新建提醒页右上「全部」推进来
/// （`presentedAsSheet == false`，系统返回），深链 `hkline://alerts` / 通知点开时仍是一张表
/// （带左上关闭）。铃声、自选波动、通知权限这三样设置项搬去了设置整页的「通知」组
/// （`AlertSettingsSection`）。
///
/// 跨品种的一张表，不按品种分段：用户来这儿是为了「我一共挂了几条、哪条响了」，
/// 按品种切成几堆反而要翻。
struct AlertListPage: View {
  @ObservedObject var store: AlertStore
  var context = AlertListContext()
  /// 自己是一张表（带 NavigationStack 与左上关闭），还是被推进来的一层（用外面的导航栈）。
  var presentedAsSheet = true

  /// 当前左划开着的是哪一行。一张表同一时刻只许开一行（见 `SwipeToDelete`）。
  @State private var openSwipe: String?
  /// 左划「编辑」点的是哪一条（推进编辑页）。
  @State private var editing: String?

  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  @Environment(\.panelHPad) private var hPad

  var body: some View {
    if presentedAsSheet {
      NavigationStack {
        content
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              // 标识符沿用 `panel.done`：UI 用例靠它收表。
              Button(role: .close) { dismiss() }
                .accessibilityIdentifier("panel.done")
            }
          }
      }
      .tint(t.amber)
      .panelPageInset()
    } else {
      content
    }
  }

  /// 2026-09-24 UI 整改 P1b：头部是系统导航栏（居中 17 标题）；推进去的编辑页用系统返回。
  private var content: some View {
    list
      .navigationTitle("提醒")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(item: $editing) { id in
        if let alert = store.all.first(where: { $0.id == id }) {
          AlertForm(initialSymbol: InstrumentID(alert.symbol).display, existing: alert,
                    resolve: context.quote, prepare: context.prepareQuote,
                    release: context.releaseQuote, zone: context.zone) { draft in
            store.commit(draft, editing: id)
          }
        }
      }
  }

  private var list: some View {
    ScrollView {
      VStack(spacing: 0) {
        if store.all.isEmpty {
          empty
        } else {
          // 2026-09-25 v2：和创建提醒页底下的「提醒记录」同一种写法——一张分组卡片、同一个
          // `AlertRecordRow`，只是这里跨品种，标题带品种名，右边多出再次提醒 / 盯一个 / 条件。
          let rows = store.sorted
          AlertGroupCard {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, alert in
              AlertRow(alert: alert,
                       open: $openSwipe,
                       divider: index < rows.count - 1,
                       onOpen: { context.onOpen(alert) },
                       onRearm: { store.rearm(id: alert.id) },
                       onCondition: { store.setCondition($0, id: alert.id) },
                       onEdit: alert.kind == .price ? { editing = alert.id } : nil,
                       onDelete: { Haptics.warning(); store.remove(id: alert.id) },
                       watched: context.watching == alert.id,
                       onWatch: { context.onWatch(alert) },
                       zone: context.zone,
                       decimals: context.quote(InstrumentID(alert.symbol).display)?.decimals)
            }
          }
        }
      }
      .padding(.horizontal, hPad)
      .padding(.top, Space.m)
      .padding(.bottom, Space.section)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(AlertPageStyle.background(t).ignoresSafeArea())
    // 「这张表在不在」的记号。**`children: .contain` 那一句不能省**：光写
    // `accessibilityIdentifier` 会把这个名字往下盖到每个子元素上（`DisplaySettingsSection`
    // 那一排配色卡踩过同一个坑），`.contain` 让它只当一个容器，子元素各留各的名字。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.page")
  }

  private var empty: some View {
    VStack(spacing: Space.s) {
      // 实心款，不用线框（静态审查 3.9：图标不能是线框）；32 落在审查给的 32–44 里。
      Image(systemName: "bell.fill")
        .font(.system(size: ControlMetrics.iconDisc))
        .foregroundStyle(t.ink3)
        .accessibilityHidden(true)
      Text("在图上点一下，就能按那口价加提醒").font(TypeScale.body).foregroundStyle(t.ink3)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Space.xl)
    .padding(.vertical, Space.section * 2)
  }
}

/// 总表的一行：`AlertRecordRow`（圆点 + 标题 + 灰字）+ 右边的动作。左划删除 / 编辑。
///
/// 左划那一套**不在这儿实现**：它是 `SwipeToDelete`，全 app 一份，画线管理
/// （`DrawingSheet`）和创建提醒页的「提醒记录」用的是同一个零件（`kanpan-one-feature-one-module`）。
private struct AlertRow: View {
  var alert: KanpanCore.Alert
  @Binding var open: String?
  var divider: Bool
  var onOpen: () -> Void
  var onRearm: () -> Void
  var onCondition: (KanpanCore.Alert.Condition) -> Void
  /// 左划「编辑」（只有价格提醒有：画线提醒的价在线上，复盘到点跟着记录走）。
  var onEdit: (() -> Void)?
  var onDelete: () -> Void
  var watched = false
  var onWatch: () -> Void = {}
  var zone: TZOffset
  var decimals: Int?

  @Environment(\.panelTheme) private var t

  var body: some View {
    SwipeToDelete(id: alert.id, open: $open, brick: .flush, trailing: actions) { swipe in
      AlertRecordRow(alert: alert,
                     title: AlertRecordText.title(alert, withSymbol: true),
                     meta: AlertRecordText.meta(alert, zone: zone, decimals: decimals,
                                                conditionInline: false),
                     divider: divider,
                     onTap: { swipe.isOpen ? swipe.close() : onOpen() }) {
        // 胶囊的点按区撑到 44，但不把行撑高：往回收一个 `Space.s`，点按区落在行自己的上下留白里。
        trailing(swipe).padding(.vertical, -Space.s)
      }
    }
  }

  /// 删除贴屏幕边（第一颗），编辑在它里面一格。
  private var actions: [SwipeAction] {
    var list: [SwipeAction] = [.delete(t, run: onDelete)]
    if let onEdit { list.append(SwipeAction(id: "edit", title: "编辑", fill: t.amber, run: onEdit)) }
    return list
  }

  @ViewBuilder private func trailing(_ swipe: SwipeDeleteProxy) -> some View {
    if alert.kind == .reviewDue {
      // 复盘到点没有「再次提醒」也没有条件可改：它跟着那条记录走。
      EmptyView()
    } else if alert.status == .fired {
      Button(action: { swipe.close(); onRearm() }) {
        Text("再次提醒")
          .font(PanelFont.seg)
          .foregroundStyle(t.badgeInk)
          .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
          .background(Capsule().fill(t.amber))
          .hitTarget()
      }
      .buttonStyle(.plain)
    } else {
      HStack(spacing: Space.s) {
        if alert.isActive { watchButton(swipe) }
        condition
      }
    }
  }

  /// 「盯一个」：把这条挂到锁屏 / 灵动岛上。盯着时实心，再点一次就不盯了。
  private func watchButton(_ swipe: SwipeDeleteProxy) -> some View {
    Button(action: { swipe.close(); onWatch() }) {
      Text(watched ? "盯着" : "盯一个")
        .font(PanelFont.seg)
        .foregroundStyle(watched ? t.badgeInk : t.amber)
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .background(Capsule().fill(watched ? t.amber : Color.clear))
        .overlay(Capsule().stroke(t.amber, lineWidth: watched ? 0 : 1))
        .hitTarget()
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("alerts.watch")
    .accessibilityValue(watched ? "on" : "off")
  }

  @ViewBuilder private var condition: some View {
    // 「碰到 / 收盘穿过」在总表里住在这一行右边（创建页里在「条件」那一格）。
    Menu {
      ForEach([KanpanCore.Alert.Condition.touch, .close], id: \.self) { c in
        Button(c.title) { onCondition(c) }
      }
    } label: {
      HStack(spacing: Space.xxs) {
        Text(alert.condition.title).font(PanelFont.seg)
        VectorIcon.chevron(ControlMetrics.chevron, w: 1.7)
      }
      .foregroundStyle(t.amber)
      .hitTarget()
    }
    .accessibilityIdentifier("alerts.condition")
  }
}
