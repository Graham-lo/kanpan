import KanpanCore
import SwiftUI

/// 提醒总表（方案 2.3 的「管理」）。
///
/// 全 app 管提醒只有这一处：改条件在这儿，删在这儿，重新上膛也在这儿。
/// 图上那枚小铃铛只表示「这条线挂着提醒」，点它不弹任何菜单——同一个动作
/// 只留一个入口（`kanpan-one-entry-per-action`）。
///
/// 跨品种的一张表，不按品种分段：用户来这儿是为了「我一共挂了几条、哪条响了」，
/// 按品种切成几堆反而要翻。
struct AlertListPage: View {
  @ObservedObject var store: AlertStore
  var preferences: PrefsStore
  @State private var showSound = false
  @State private var showNew = false
  /// 点一行：去那条线上（复盘到点去那条记录）。宿主接成深链。
  var onOpen: (KanpanCore.Alert) -> Void
  /// 时间按用户在设置里选的那档时区写。
  var zone: TZOffset = .system
  /// 「新建」那一页默认的品种（图上那只）。
  var currentSymbol: String = ""
  /// 按用户打的代号查品种与现价（宿主那边有目录、报价簿与图上那只的逐笔）。
  var quote: (String) -> PriceAlertQuote? = { _ in nil }
  /// 新建页定了品种之后叫一声，宿主去要一口价。
  var prepareQuote: (String) -> Void = { _ in }
  /// 新建页关了叫一声，宿主放掉 `prepareQuote` 点名要的那一只（图上那只照旧）。
  var releaseQuote: () -> Void = {}
  /// 锁屏上正盯着的那条提醒（一台设备只盯一条）。
  var watching: String? = nil
  /// 行上那颗「盯一个」：宿主去开 / 收锁屏实时活动。
  var onWatch: (KanpanCore.Alert) -> Void = { _ in }
  /// 自选波动的幅度，编辑时的那一格字。离开输入框才落盘（`kanpan-persist-on-gesture-end`）。
  @State private var thresholdText = ""
  @FocusState private var thresholdFocused: Bool

  @Environment(\.panelTheme) private var t
  /// 通知权限那一行的开关（见 `AlertPermission`）。总表自己养一个，别处不看它。
  @StateObject private var permission = AlertPermission()
  /// 「回前台再查一遍」那份登记。用户点了这一行就走了，回来时这张表还开着、
  /// `task` 不会再跑一次；而他很可能刚把开关拨上来，这一行就得自己消失。
  /// 走 `AppLifecycle` 是**规定**：全 app 只有那一处读前后台，谁要听就去报到，
  /// 不许自己挂 `UIApplication` 的通知（见 `AppLifecycle` 开头第 1 条）。
  @State private var lifecycle: AppLifecycle.ResourceToken?
  /// 当前左划开着的是哪一行。一张表同一时刻只许开一行（见 `SwipeToDelete`）。
  @State private var openSwipe: String?

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    // 2026-09-24 UI 整改 P1b：头部换成系统导航栏（居中 17 标题、左上关闭、右上「新建」，
    // 推进去的铃声页与新建页用系统返回）。原来自绘的「‹」钮 32×32 落在 x=9，比正文左缘还靠外，
    // 而且和设置 → 账号那套系统导航在同一条路径上来回切（视觉审查 2.9 #1、§3 #3）。
    NavigationStack {
      list
        .navigationTitle("提醒")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            // 标识符沿用 `panel.done`：UI 用例靠它收表。
            Button(role: .close) { dismiss() }
              .accessibilityIdentifier("panel.done")
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button("新建") { showNew = true }
              .accessibilityIdentifier("alerts.new")
          }
          // 数字键盘没有回车键，收不起来（视觉审查 2.9 #5）。
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完成") { thresholdFocused = false }
          }
        }
        .navigationDestination(isPresented: $showSound) { AlertSoundPage(store: preferences) }
        .navigationDestination(isPresented: $showNew) {
          PriceAlertForm(initialSymbol: currentSymbol, resolve: quote, prepare: prepareQuote,
                         release: releaseQuote) { quote, target in
            let alert = store.addPrice(symbol: quote.symbol, target: target, current: quote.price,
                                       label: quote.current(target))
            guard alert != nil else { return }
            Task {
              await AlertNotifications.requestAuthorization()
              await MainActor.run { PushRegistration.startIfAuthorized() }
            }
          }
        }
    }
    .tint(t.amber)
    .panelPageInset()
  }

  private var list: some View {
    ScrollView {
      VStack(spacing: 0) {
        PanelRow(name: "提醒铃声", onTap: { showSound = true }) {
          HStack(spacing: Space.xs) {
            Text(preferences.prefs.alertSound.title).font(PanelFont.name)
            VectorIcon.chevronRight(ControlMetrics.chevron)
          }.foregroundStyle(t.ink3)
        }
        .accessibilityIdentifier("alerts.sound.open")
        .accessibilityValue(preferences.prefs.alertSound.title)
        watchMoveRows
        if permission.needsSystemSettings { AlertPermissionRow { permission.openSystemSettings() } }
        if store.all.isEmpty {
          empty
        } else {
          ForEach(store.sorted) { alert in
            AlertRow(alert: alert,
                     open: $openSwipe,
                     onOpen: { onOpen(alert) },
                     onRearm: { store.rearm(id: alert.id) },
                     onCondition: { store.setCondition($0, id: alert.id) },
                     onDelete: { Haptics.warning(); store.remove(id: alert.id) },
                     watched: watching == alert.id,
                     onWatch: { onWatch(alert) },
                     zone: zone)
          }
        }
      }
      .padding(.top, Space.xs)
      .padding(.bottom, Space.l)
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    .background(t.raised.ignoresSafeArea())
    .task { await permission.refresh() }
    .onAppear {
      guard lifecycle == nil else { return }
      lifecycle = AppLifecycle.shared.registerResources(
        id: "alerts.permission",
        leave: {},
        enter: { Task { await permission.refresh() } })
    }
    .onDisappear {
      guard let token = lifecycle else { return }
      AppLifecycle.shared.unregisterResources(token: token)
      lifecycle = nil
    }
    // 「这张表在不在」的记号。**`children: .contain` 那一句不能省**：光写
    // `accessibilityIdentifier` 会把这个名字往下盖到每个子元素上（`DisplaySettingsSection`
    // 那一排配色卡踩过同一个坑），`.contain` 让它只当一个容器，子元素各留各的名字。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.page")
  }

  /// 自选波动提醒：一个开关，开着时下面一格幅度（手动输入，没有口径可选）。
  @ViewBuilder private var watchMoveRows: some View {
    let on = preferences.prefs.watchMoveAlert
    PanelRow(name: "自选波动提醒") {
      PanelSwitch(isOn: on) {
        commitThreshold()
        preferences.update { $0.watchMoveAlert.toggle() }
      }
      .accessibilityIdentifier("alerts.watchMove")
    }
    if on {
      PanelRow(name: "五分钟涨跌超过") {
        HStack(spacing: Space.xs) {
          TextField("", text: $thresholdText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(TypeScale.body).monospacedDigit()
            .foregroundStyle(t.ink)
            .frame(width: Hit.min)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.s)
            .background(t.raised2, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .focused($thresholdFocused)
            .onSubmit(commitThreshold)
            .accessibilityIdentifier("alerts.watchMove.threshold")
            .accessibilityLabel("五分钟涨跌超过")
          Text("%").font(TypeScale.body).foregroundStyle(t.ink3)
        }
      }
      .onAppear { thresholdText = Self.format(preferences.prefs.watchMoveThreshold) }
      .onChange(of: thresholdFocused) { _, focused in if !focused { commitThreshold() } }
      .onDisappear(perform: commitThreshold)
    }
  }

  private func commitThreshold() {
    let text = thresholdText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return }
    let value = Double(text).map(WatchMove.clampThreshold) ?? preferences.prefs.watchMoveThreshold
    thresholdText = Self.format(value)
    guard value != preferences.prefs.watchMoveThreshold else { return }
    preferences.update { $0.watchMoveThreshold = value }
  }

  private static func format(_ value: Double) -> String {
    var text = String(format: "%.2f", value)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
  }

  private var empty: some View {
    VStack(spacing: Space.s) {
      // 实心款，不用线框（静态审查 3.9：图标不能是线框）；32 落在审查给的 32–44 里。
      Image(systemName: "bell.fill")
        .font(.system(size: ControlMetrics.iconDisc))
        .foregroundStyle(t.ink3)
        .accessibilityHidden(true)
      Text("还没有提醒").font(TypeScale.body).foregroundStyle(t.ink3)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Space.section * 2)
  }
}

/// 一行：徽章 + 品种 + 线种 + 状态。左划删除。
///
/// 左划那一套**不在这儿实现**：它是 `SwipeToDelete`，全 app 一份，画线管理
/// （`DrawingSheet`）用的是同一个零件。这一行原来自己 ZStack + DragGesture 画了
/// 一遍，画线管理那边又用系统的 `.swipeActions` 画了一遍——同一个动作两套实现，
/// 两块砖的字色还不一样（`kanpan-one-feature-one-module`）。
private struct AlertRow: View {
  var alert: KanpanCore.Alert
  @Binding var open: String?
  var onOpen: () -> Void
  var onRearm: () -> Void
  var onCondition: (KanpanCore.Alert.Condition) -> Void
  var onDelete: () -> Void
  var watched = false
  var onWatch: () -> Void = {}
  var zone: TZOffset

  @Environment(\.panelTheme) private var t
  @Environment(\.panelHPad) private var hPad

  var body: some View {
    SwipeToDelete(id: alert.id, open: $open, brick: .flush,
                  trailing: [.delete(t, run: onDelete)]) { swipe in
      row(swipe)
    }
  }

  /// 2026-09-24 UI 整改 P1b：不再往 `PanelRow` 上叠一层 overlay 把徽章硬塞进左留白
  /// （原来徽章 24、文字从 46 起，和上面两行对不齐）。徽章进正经的前导位（`listBadge` 32，
  /// 和板块、自选列表同一个尺寸），名 15、副 12，右边两颗胶囊视觉不变、点按区撑到 44。
  private func row(_ swipe: SwipeDeleteProxy) -> some View {
    Button(action: { swipe.isOpen ? swipe.close() : onOpen() }) {
      HStack(spacing: Space.m) {
        CoinBadge(base: KanpanCore.Alert.base(of: alert.symbol), size: ControlMetrics.listBadge)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Space.xxs) {
          Text(title)
            .font(TypeScale.body).monospacedDigit()
            .foregroundStyle(t.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
          Text(meta).font(TypeScale.caption).monospacedDigit().foregroundStyle(t.ink3)
        }
        Spacer(minLength: 0)
        // 胶囊的点按区撑到 44，但不把行撑高：往回收一个 `Space.s`，点按区落在行自己的上下留白里。
        trailing(swipe).padding(.vertical, -Space.s)
      }
      .padding(.horizontal, hPad)
      .padding(.vertical, Space.s)
      .frame(minHeight: Inset.rowMin)
      .contentShape(Rectangle())
      .overlay(alignment: .bottom) {
        // 分隔线从文字那一条起（iOS 带图标列表的惯例），徽章下面不划。
        Rectangle().fill(t.hair).frame(height: 1)
          .padding(.leading, hPad + ControlMetrics.listBadge + Space.m)
      }
    }
    .buttonStyle(.plain)
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
    // 「碰到 / 收盘穿过」这个选择**只住在这一行**。画完线那一下不问，
    // 图上也没有第二处能改（方案 2.3）。
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

  private var title: String {
    // 价格提醒的标题末尾那串价补上千分位（「BTC 跌到 12,345.00」）。老提醒存的是不带
    // 分隔的写法，这里在显示时补，`grouped` 对已经带分隔的串原样返回（视觉审查 2.9 #3）。
    if alert.kind == .price, let cut = alert.title.lastIndex(of: " ") {
      return String(alert.title[...cut]) + grouped(String(alert.title[alert.title.index(after: cut)...]))
    }
    if alert.kind != .drawing, !alert.title.isEmpty { return alert.title }
    // 别家带分隔的代号写 `BTC/USD`，币安照旧只写基础币（见 `Alert.name(of:)`）。
    let base = KanpanCore.Alert.name(of: alert.symbol)
    guard let name = alert.lineName else { return base }
    return base + " · " + name
  }

  private var meta: String {
    if alert.kind == .reviewDue {
      let at = alert.status == .fired ? alert.firedAt ?? alert.dueAt : alert.dueAt
      let time = at.map { ReviewLabels.dayTime(ms: Int64($0), offsetMinutes: zone) } ?? ""
      return alert.status == .fired ? "已到点 · " + time : "到期 " + time
    }
    switch alert.status {
    case .fired:
      guard let at = alert.firedAt else { return "已触发" }
      return "已触发 · " + ReviewLabels.dayTime(ms: Int64(at), offsetMinutes: zone)
    case .paused: return "已暂停"
    // 条件已经写在右边那颗胶囊上，这里不再复述一遍（2026-09-24 审查 6.4）。
    case .active: return "生效中"
    }
  }
}

/// 通知被拒之后顶上那一行。**提示，不是拦路**：它不挡列表，下面该有几条还是几条。
///
/// 色走 `amberSoft` + `amberLine`（皮肤自己的强调色兑得极淡的一层），和「要不要提醒」
/// 那条问句（`AlertPromptBar`）是同一个功能的两句话，读成同一个东西；不用 `t.danger`——
/// 那一支留给「删除 / 注销」这种不可逆动作。
///
/// 2026-09-24 UI 整改 P1b：高 36 → 44（整行就是按钮）、圆角取 `Radius.m`、左右跟正文同一条
/// 边（`hPad`，整页里随屏宽 16 / 20），去掉 SF 的铃铛线框，字 13 走 `TypeScale.footnote`。
private struct AlertPermissionRow: View {
  var open: () -> Void
  @Environment(\.panelTheme) private var t
  @Environment(\.panelHPad) private var hPad

  var body: some View {
    Button(action: open) {
      HStack(spacing: Space.s) {
        Text("通知关着，提醒到了不会响")
          .font(TypeScale.footnote)
          .foregroundStyle(t.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Spacer(minLength: Space.s)
        HStack(spacing: Space.xxs) {
          Text("去打开").font(TypeScale.footnoteEmph)
          VectorIcon.chevronRight(ControlMetrics.chevron)
        }
        .foregroundStyle(t.amber)
      }
      .padding(.horizontal, Space.m)
      .frame(maxWidth: .infinity)
      .frame(minHeight: Hit.min)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
          .fill(t.amberSoft)
          .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
            .strokeBorder(t.amberLine, lineWidth: 0.5))
      )
    }
    .buttonStyle(.plain)
    .padding(.horizontal, hPad)
    .padding(.vertical, Space.s)
    .accessibilityIdentifier("alerts.permission")
  }
}
