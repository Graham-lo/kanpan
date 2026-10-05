import KanpanCore
import SwiftUI

/// 顶栏那枚铃铛开的「提醒」表（2026-10-05，照 TradingView 手机版的 Alerts：列表 | 日志）。
///
/// - **列表**：就是提醒总表（`AlertListPage`），只是图上这只品种置顶成一组（组名是品种名，
///   下面分「价格」「画线」），其余品种照旧。底部一颗通栏「创建提醒」推进创建页——品种锁定为
///   图上这只、价格预填最新价。点一条价格 / 条件提醒推进它的编辑页（和创建提醒那张表同一套）。
/// - **日志**：响过的提醒（`AlertLogModel`，账在服务端），按天分组，一行是徽章 + 品种、
///   条件 · 触发价、时刻。进表就拉一趟，下拉再拉；右上「清空」要确认。没登录只有一句「登录后可查看」。
///
/// 十字线那颗「创建提醒」与「我的 › 全部预警」照旧，不受这张表影响。
struct AlertHubSheet: View {
  @ObservedObject var store: AlertStore
  var context: AlertListContext
  /// 图上那只（规范键或代号都行）。
  var symbol: String
  /// 开表那一刻的最新价，创建页预填用。nil = 创建页让人自己填。
  var price: Double?
  var log: AlertLogModel
  /// 当前账号。nil = 没登录。
  var owner: UUID?
  var fetch: AlertLogModel.Fetch?
  /// 建好了一条（表不收，新的那条出现在置顶那组里）。
  var onCreated: (KanpanCore.Alert) -> Void
  var onClearFailed: () -> Void = {}

  enum Tab: String, CaseIterable, Identifiable {
    case list = "列表"
    case log = "日志"
    var id: String { rawValue }
  }

  @State private var tab: Tab = .list
  @State private var composing = false
  @State private var editing: String?
  @State private var confirmClear = false
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  @Environment(\.panelHPad) private var hPad

  /// 底部「创建提醒」的高度，和创建页的主按钮一样。
  private static let buttonHeight = Inset.rowMin + Space.xs

  private var key: String { context.quote(symbol)?.symbol ?? InstrumentID.canonical(symbol) }

  var body: some View {
    NavigationStack {
      Group {
        switch tab {
        case .list: listPane
        case .log: logPane
        }
      }
      .safeAreaInset(edge: .top, spacing: 0) { tabs }
      .background(AlertPageStyle.background(t).ignoresSafeArea())
      .navigationTitle("提醒")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(role: .close) { dismiss() }
            .accessibilityIdentifier("panel.done")
        }
        if tab == .log, owner != nil, !log.records.isEmpty {
          ToolbarItem(placement: .topBarTrailing) {
            Button("清空") { confirmClear = true }
              .accessibilityIdentifier("alerts.log.clear")
          }
        }
      }
      .confirmationDialog("清空全部记录？", isPresented: $confirmClear, titleVisibility: .visible) {
        Button("清空", role: .destructive) {
          Task {
            if await log.clear(fetch: fetch) { Haptics.success() } else { onClearFailed() }
          }
        }
        Button("取消", role: .cancel) {}
      }
      .navigationDestination(isPresented: $composing) { compose }
      .navigationDestination(item: $editing) { id in edit(id) }
    }
    .tint(t.amber)
    .panelPageInset()
    .task { await log.refresh(owner: owner, fetch: fetch) }
  }

  // ---------------------------------------------------------------- 分段

  private var tabs: some View {
    Picker("提醒", selection: $tab) {
      ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .padding(.horizontal, hPad)
    .padding(.vertical, Space.s)
    .background(AlertPageStyle.background(t))
    .accessibilityIdentifier("alerts.hub.tab")
  }

  // ---------------------------------------------------------------- 列表

  private var listPane: some View {
    AlertListPage(store: store, context: context, presentedAsSheet: false, pinned: key, title: nil)
      .safeAreaInset(edge: .bottom, spacing: 0) { createButton }
  }

  private var createButton: some View {
    Button { composing = true } label: {
      Text("创建提醒")
        .font(TypeScale.title)
        .foregroundStyle(t.badgeInk)
        .frame(maxWidth: .infinity)
        .frame(height: Self.buttonHeight)
        .background(Capsule().fill(t.amber))
        .contentShape(Capsule())
    }
    .buttonStyle(AlertPressStyle())
    .padding(.horizontal, hPad)
    .padding(.top, Space.s)
    .padding(.bottom, Space.s)
    .background(AlertPageStyle.background(t).ignoresSafeArea())
    .accessibilityIdentifier("alerts.hub.create")
  }

  private var compose: some View {
    let key = key
    return AlertForm(initialSymbol: InstrumentID(key).display, initialPrice: price,
                     resolve: context.quote, prepare: context.prepareQuote, release: context.releaseQuote,
                     records: AlertRecordText.records(store.all, symbol: key), zone: context.zone,
                     onEditRecord: { editing = $0 }, onDeleteRecord: { store.remove(id: $0) },
                     conditions: context.conditions(key)) { draft in
      if let alert = store.commit(draft) { Haptics.success(); onCreated(alert) }
    }
  }

  @ViewBuilder private func edit(_ id: String) -> some View {
    if let alert = store.all.first(where: { $0.id == id }) {
      AlertForm(initialSymbol: InstrumentID(alert.symbol).display, existing: alert,
                resolve: context.quote, prepare: context.prepareQuote,
                release: context.releaseQuote, zone: context.zone,
                conditions: context.conditions(InstrumentID.canonical(alert.symbol))) { draft in
        if store.commit(draft, editing: id) != nil { Haptics.success() }
      }
    }
  }

  // ---------------------------------------------------------------- 日志

  private var logPane: some View {
    ScrollView {
      Group {
        if owner == nil {
          placeholder("登录后可查看", glyph: "person.crop.circle.fill", id: "alerts.log.signedOut")
        } else if log.records.isEmpty {
          if log.phase == .loading {
            ProgressView()
              .frame(maxWidth: .infinity)
              .containerRelativeFrame(.vertical) { height, _ in max(0, height - Space.m - Space.section) }
          } else {
            placeholder("暂无记录", glyph: "clock.fill", id: "alerts.log.empty")
          }
        } else {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(AlertLogText.days(log.records, zone: context.zone).enumerated()), id: \.element.id) {
              index, day in
              AlertCardTitle(text: day.title)
                .padding(.top, index == 0 ? 0 : Space.section)
                .padding(.bottom, Space.s)
                .accessibilityIdentifier("alerts.log.day")
              AlertGroupCard {
                ForEach(Array(day.records.enumerated()), id: \.element.id) { i, record in
                  AlertLogRow(record: record, zone: context.zone, decimals: context.decimals(record.symbol),
                              divider: i < day.records.count - 1)
                }
              }
            }
          }
        }
      }
      .padding(.horizontal, hPad)
      .padding(.top, Space.m)
      .padding(.bottom, Space.section)
    }
    .scrollBounceBehavior(.always)
    .refreshable { await log.refresh(owner: owner, fetch: fetch) }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.log")
  }

  /// 空态：一枚实心图标 + 一句短字，和总表的「暂无预警」同一套。
  private func placeholder(_ text: String, glyph: String, id: String) -> some View {
    VStack(spacing: Space.s) {
      Image(systemName: glyph)
        .font(.system(size: ControlMetrics.emptyGlyph))
        .foregroundStyle(t.ink3)
        .accessibilityHidden(true)
      Text(text).font(TypeScale.body).foregroundStyle(t.ink3)
    }
    .frame(maxWidth: .infinity)
    .containerRelativeFrame(.vertical) { height, _ in max(0, height - Space.m - Space.section) }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(id)
  }
}

/// 日志的一行：徽章 + 品种名、条件 · 触发价，行尾是响的时刻。只读，不可点。
struct AlertLogRow: View {
  var record: AlertLogRecord
  var zone: TZOffset
  var decimals: Int?
  var divider: Bool
  @Environment(\.panelTheme) private var t

  var body: some View {
    let detail = AlertLogText.detail(record, decimals: decimals)
    HStack(spacing: Space.m) {
      CoinBadge(base: SymbolInfo.placeholder(symbol: InstrumentID.canonical(record.symbol)).base,
                size: ControlMetrics.badge)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(AlertLogText.name(record))
          .font(TypeScale.bodyEmph)
          .foregroundStyle(t.ink)
        if !detail.isEmpty {
          Text(detail)
            .font(TypeScale.caption).monospacedDigit()
            .foregroundStyle(t.ink3)
        }
      }
      .lineLimit(1)
      Spacer(minLength: Space.s)
      Text(AlertLogText.clock(record.firedAt, zone: zone))
        .font(TypeScale.caption).monospacedDigit()
        .foregroundStyle(t.ink3)
    }
    .padding(.horizontal, Inset.card)
    .frame(minHeight: Inset.rowMin + Space.m)
    .overlay(alignment: .bottom) {
      if divider { AlertCardDivider(leading: ControlMetrics.badge + Space.m) }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("alerts.log.row")
  }
}
