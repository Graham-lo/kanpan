import KanpanCore
import SwiftUI

/// 提醒总表（「全部预警」）用到的宿主能力。总表有两处出现（深链 / 通知点开时是一张表，
/// 创建提醒页右上「全部预警」推进来是一层），两处接的是同一份，由宿主（`MainScreen`）拼好交过来。
struct AlertListContext {
  /// 点一行：去那条线上（复盘到点去那条记录）。宿主接成深链。
  var onOpen: (KanpanCore.Alert) -> Void = { _ in }
  /// 时间按用户在设置里选的那档时区写。
  var zone: TZOffset = .system
  /// 按用户打的代号查品种与现价（创建 / 编辑页要）。
  var quote: (String) -> PriceAlertQuote? = { _ in nil }
  /// 创建 / 编辑页定了品种之后叫一声，宿主去要一口价。
  var prepareQuote: (String) -> Void = { _ in }
  /// 创建 / 编辑页关了叫一声，宿主放掉 `prepareQuote` 点名要的那一只（图上那只照旧）。
  var releaseQuote: () -> Void = {}
}

/// 提醒总表：「全部预警」。
///
/// 2026-09-25 v3（用户：「再增加一个入口，能把所有预警都调出来，一类是自己创建的价格，
/// 一类是之前的画线预警」「行上只给一个删除 icon，别的操作都不要」）：
///
/// - **入口**：创建提醒页右上「全部预警」推进来（`presentedAsSheet == false`，系统返回）；
///   深链 `hkline://alerts` / 通知点开时仍是一张表（带左上关闭）。十字线动作栏不另加入口。
/// - **分组**：「价格提醒 N」「画线提醒 N」两张分组卡片，卡片里按品种分段（段头徽章 +
///   `BTC/USDT` + 场所小字）；有复盘待办到点时再单列一段「复盘到点 N」，没有就不出现。
///   分段是纯函数 `AlertRecordText.sections`。
/// - **只列还没触发的**：响过的提醒发完通知就删了（`AlertWatcher`），这里不会再有
///   「已触发」那一堆，也没有「再次提醒」。复盘到点的「已到点」照常列在它那一段。
/// - **行上只有一枚垃圾桶**：左划、「盯一个」（锁屏实时活动，`AlertActivityController`
///   代码留着、只是没入口了）、条件菜单都去掉了。点行去那条线上（`context.onOpen`）。
///
/// 图上那枚小铃铛只表示「这条线挂着提醒」，点它不弹任何菜单——同一个动作只留一个入口
/// （`kanpan-one-entry-per-action`）。建提醒也只有一个入口：图上十字线那颗「创建提醒」。
struct AlertListPage: View {
  @ObservedObject var store: AlertStore
  var context = AlertListContext()
  /// 自己是一张表（带 NavigationStack 与左上关闭），还是被推进来的一层（用外面的导航栈）。
  var presentedAsSheet = true

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

  /// 头部是系统导航栏（居中 17 标题），推进来的那一层用系统返回。
  private var content: some View {
    list
      .navigationTitle("全部预警")
      .navigationBarTitleDisplayMode(.inline)
  }

  private var list: some View {
    let sections = AlertRecordText.sections(store.all)
    return ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if sections.isEmpty {
          empty.transition(.opacity)
        } else {
          ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
            sectionView(section)
              .padding(.top, index == 0 ? 0 : Space.section)
              // 一段删空了整段（标题 + 卡片）淡出；最后一条删掉时空态淡入，不闪。
              .transition(.opacity)
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

  /// 一段：卡片外的分组标题 + 一张分组卡片。价格 / 画线两段卡片里按品种分，
  /// 复盘到点那段不分品种（标题里已经写着品种）。
  private func sectionView(_ section: AlertRecordText.Section) -> some View {
    VStack(alignment: .leading, spacing: Space.s) {
      AlertCardTitle(text: section.title)
        .contentTransition(.numericText())
      AlertGroupCard {
        ForEach(section.groups) { group in
          if section.kind != .reviewDue {
            AlertSymbolHeader(symbol: group.symbol, count: group.alerts.count)
              .transition(.opacity)
          }
          ForEach(Array(group.alerts.enumerated()), id: \.element.id) { index, alert in
            AlertRecordRow(
              alert: alert,
              title: AlertRecordText.title(alert, withSymbol: section.kind == .reviewDue),
              meta: AlertRecordText.meta(alert, zone: context.zone,
                                         decimals: context.quote(InstrumentID(alert.symbol).display)?.decimals,
                                         conditionInline: true),
              divider: index < group.alerts.count - 1 || group.id != section.groups.last?.id,
              onTap: { context.onOpen(alert) },
              onDelete: { withAnimation(.snappy) { store.remove(id: alert.id) } })
            .transition(AlertRecordRow.removal)
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.section.\(section.kind.rawValue)")
  }

  /// 空态：一枚实心图标 + 一句短字（UI 审查 2026-09-24：空态 = 36 图标 + 15 字，不写解释句）。
  private var empty: some View {
    VStack(spacing: Space.s) {
      Image(systemName: "bell.fill")
        .font(.system(size: ControlMetrics.emptyGlyph))
        .foregroundStyle(t.ink3)
        .accessibilityHidden(true)
      Text("暂无预警").font(TypeScale.body).foregroundStyle(t.ink3)
    }
    .frame(maxWidth: .infinity)
    // 整页居中：高度占满滚动容器，减掉外层上下内边距，免得空态一出现就能划动。
    .containerRelativeFrame(.vertical) { height, _ in max(0, height - Space.m - Space.section) }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("alerts.empty")
  }
}
