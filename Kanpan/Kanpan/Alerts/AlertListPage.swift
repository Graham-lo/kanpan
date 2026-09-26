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
  /// 总表行上那口价按几位小数写（按提醒存的规范键查目录）。**一口价都不读**：
  /// 总表只要小数位，原来借 `quote` 拿，而从创建页推进来的那张 `quote` 是带现价的——
  /// 读了图上那只的逐笔，整张总表就跟着每一笔成交重跑。
  var decimals: (String) -> Int? = { _ in nil }
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

  /// 2026-09-26 压测收尾第 5 项：原来是 `ScrollView { VStack }`，body 里现排
  /// `AlertRecordText.sections(store.all)`，两百条提醒一次全建出来；存档任何一次写
  /// （删一条、同步落一版、`notice`）都把整页连同每一行重跑一遍。现在：
  ///
  /// - 排好的那一列由 `AlertStore.listRows` 缓存，存档不变不再排；
  /// - `LazyVStack` 只建看得见的行；分组卡片摊成一片一片（`AlertCardSlice`，首片上圆角、
  ///   末片下圆角），样子和原来整张卡片一样；
  /// - 记录行是 `Equatable`（`AlertListRecord`），写一次只有输入真变了的那几行重画——
  ///   删一条：它自己、它那组的段头（数量）、段标题（数量）、以及接替它首尾位置的那一行。
  private var list: some View {
    let rows = store.listRows
    return ScrollView {
      Group {
        if rows.isEmpty {
          empty.transition(.opacity)
        } else {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { item in cell(item) }
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

  /// 一行：段标题（卡片外）、品种段头、记录。价格 / 画线两段卡片里按品种分，
  /// 复盘到点那段不分品种（标题里已经写着品种）。
  @ViewBuilder
  private func cell(_ item: AlertListItem) -> some View {
    switch item {
    case let .title(kind, text, first):
      AlertCardTitle(text: text)
        .contentTransition(.numericText())
        .padding(.top, first ? 0 : Space.section)
        .padding(.bottom, Space.s)
        // 一段删空了整段淡出；最后一条删掉时空态淡入，不闪。
        .transition(.opacity)
        .accessibilityIdentifier("alerts.section.\(kind.rawValue)")
    case let .header(_, symbol, count, top):
      AlertSymbolHeader(symbol: symbol, count: count)
        .modifier(AlertCardSlice(top: top, bottom: false))
        .transition(.opacity)
    case let .record(alert, withSymbol, divider, top, bottom):
      AlertListRecord(alert: alert, withSymbol: withSymbol, zone: context.zone,
                      decimals: context.decimals(alert.symbol),
                      divider: divider, top: top, bottom: bottom,
                      onTap: { [context] in context.onOpen(alert) },
                      onDelete: { [store] in withAnimation(.snappy) { store.remove(id: alert.id) } })
        .equatable()
        .transition(AlertRecordRow.removal)
    }
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

/// 总表摊平后的一行。纯值，`AlertStore.listRows` 缓存的就是它。
enum AlertListItem: Identifiable, Equatable {
  /// 卡片外的段标题（「价格提醒 3」）。`first`：第一段上面不留段距。
  case title(kind: KanpanCore.Alert.Kind, text: String, first: Bool)
  /// 卡片里一个品种的段头。`top`：卡片的第一片（上圆角）。
  case header(kind: KanpanCore.Alert.Kind, symbol: String, count: Int, top: Bool)
  /// 一条提醒。`withSymbol`：标题里带品种（复盘到点那段）；`bottom`：卡片的最后一片（下圆角）。
  case record(alert: KanpanCore.Alert, withSymbol: Bool, divider: Bool, top: Bool, bottom: Bool)

  var id: String {
    switch self {
    case let .title(kind, _, _): "title/" + kind.rawValue
    // 同一只品种可能同时在价格、画线两段里有段头。
    case let .header(kind, symbol, _, _): "head/" + kind.rawValue + "/" + symbol
    case let .record(alert, _, _, _, _): "alert/" + alert.id
    }
  }

  /// 分段摊成行。分隔线与首尾圆角的口径和原来整张卡片一致：组里最后一条、且是卡片里最后一组
  /// 的最后一条才不画线。
  static func rows(_ sections: [AlertRecordText.Section]) -> [AlertListItem] {
    var out: [AlertListItem] = []
    for (index, section) in sections.enumerated() {
      out.append(.title(kind: section.kind, text: section.title, first: index == 0))
      var top = true
      for (g, group) in section.groups.enumerated() {
        if section.kind != .reviewDue {
          out.append(.header(kind: section.kind, symbol: group.symbol, count: group.alerts.count, top: top))
          top = false
        }
        let lastGroup = g == section.groups.count - 1
        for (i, alert) in group.alerts.enumerated() {
          let lastInGroup = i == group.alerts.count - 1
          out.append(.record(alert: alert, withSymbol: section.kind == .reviewDue,
                             divider: !(lastInGroup && lastGroup), top: top, bottom: lastInGroup && lastGroup))
          top = false
        }
      }
    }
    return out
  }
}

/// 总表的一条记录：`AlertRecordRow` 套上卡片的那一片。按值比较（闭包不算——它们只认
/// 这一行自己的 id），SwiftUI 据此跳过没变的行。
struct AlertListRecord: View, Equatable {
  var alert: KanpanCore.Alert
  var withSymbol: Bool
  var zone: TZOffset
  var decimals: Int?
  var divider: Bool
  var top: Bool
  var bottom: Bool
  var onTap: () -> Void
  var onDelete: () -> Void

  nonisolated static func == (l: Self, r: Self) -> Bool {
    l.alert == r.alert && l.withSymbol == r.withSymbol && l.zone == r.zone && l.decimals == r.decimals
      && l.divider == r.divider && l.top == r.top && l.bottom == r.bottom
  }

  var body: some View {
    AlertRecordRow(
      alert: alert,
      title: AlertRecordText.title(alert, withSymbol: withSymbol),
      meta: AlertRecordText.meta(alert, zone: zone, decimals: decimals, conditionInline: true),
      divider: divider,
      onTap: onTap,
      onDelete: onDelete)
    .modifier(AlertCardSlice(top: top, bottom: bottom))
  }
}
