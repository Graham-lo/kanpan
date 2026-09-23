import KanpanChart
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

  var body: some View {
    NavigationStack {
      list
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSound) { AlertSoundPage(store: preferences) }
        .navigationDestination(isPresented: $showNew) {
          PriceAlertForm(initialSymbol: currentSymbol, resolve: quote, prepare: prepareQuote) { quote, target in
            let alert = store.addPrice(symbol: quote.symbol, target: target, current: quote.price,
                                       label: quote.label(target))
            guard alert != nil else { return }
            Task {
              await AlertNotifications.requestAuthorization()
              await MainActor.run { PushRegistration.startIfAuthorized() }
            }
          }
        }
    }
  }

  private var list: some View {
    PanelSheet(title: "提醒", subtitle: nil, asPage: false,
               action: PanelSheetAction(title: "新建", id: "alerts.new", run: { showNew = true })) {
      PanelRow(name: "提醒铃声", onTap: { showSound = true }) {
        HStack(spacing: 5) {
          Text(preferences.prefs.alertSound.title).font(PanelFont.seg)
          VectorIcon.chevronRight(11)
        }.foregroundStyle(t.amber)
      }
      .accessibilityIdentifier("alerts.sound.open")
      .accessibilityValue(preferences.prefs.alertSound.title)
      watchMoveRows
      if permission.needsSystemSettings { permissionRow }
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
    // `accessibilityIdentifier` 会把这个名字往下盖到每个子元素上，表头那颗「‹」的
    // `panel.done` 在无障碍树里就成了 `alerts.page`（和 `DisplaySettingsSection`
    // 那一排配色卡踩过的是同一个坑）。后果是这张表**关不掉**——UI 用例换皮肤那一步
    // 一直盖着同一张表截图，sage 与 terra 两张 PNG 逐字节相同。`.contain` 让它只当
    // 一个容器，子元素各留各的名字。`AlertPromptBar` 那一条也是这么写的。
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
        HStack(spacing: 4) {
          TextField("", text: $thresholdText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.body.monospacedDigit())
            .foregroundStyle(t.ink)
            .frame(width: 52)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(t.raised2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .focused($thresholdFocused)
            .onSubmit(commitThreshold)
            .accessibilityIdentifier("alerts.watchMove.threshold")
            .accessibilityLabel("五分钟涨跌超过")
          Text("%").font(.body).foregroundStyle(t.ink3)
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

  /// 通知被拒之后顶上那一行。**提示，不是拦路**：它不挡列表，下面该有几条还是几条。
  ///
  /// 三件事上和「要不要提醒」那条问句（`AlertPromptBar`）长一个样，不是巧合——
  /// 它俩是同一个功能的两句话，应该读成同一个东西：
  /// - 色走 `amberSoft` + `amberLine`，也就是**皮肤自己的强调色**兑得极淡的一层
  ///   （青苔是墨绿、陶土是赤陶）。**不用 `t.danger`**：那一支是给「删除 / 注销」
  ///   这种不可逆动作留的，这儿只是「有件事你可能不知道」，摆一条红的等于吓人；
  ///   也不能是系统那块黄警告条——那是外面贴上来的一块颜色，这张表要读成一整块材料。
  /// - 底是半透明的一层兑色，不是一块实底，身下那张 `raised` 照常透过去，不切硬边。
  /// - 行高 36、字 13，比一条提醒还轻一档——它不跟真正的内容抢眼睛。
  private var permissionRow: some View {
    Button(action: { permission.openSystemSettings() }) {
      HStack(spacing: 8) {
        Image(systemName: "bell.slash")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(t.amber)
        Text("通知关着，提醒到了不会响")
          .font(.scaled(13))
          .foregroundStyle(t.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Spacer(minLength: 6)
        HStack(spacing: 2) {
          Text("去打开").font(.scaled(13, .semibold))
          VectorIcon.chevronRight(11)
        }
        .foregroundStyle(t.amber)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity)
      .frame(height: 36)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(t.amberSoft)
          .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(t.amberLine, lineWidth: 0.5))
      )
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 10)
    .padding(.top, 4)
    .padding(.bottom, 6)
    .accessibilityIdentifier("alerts.permission")
  }

  private var empty: some View {
    VStack(spacing: 6) {
      Image(systemName: "bell").font(.system(size: 22, weight: .light)).foregroundStyle(t.ink3)
      Text("还没有提醒").font(PanelFont.name).foregroundStyle(t.ink3)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 48)
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

  var body: some View {
    SwipeToDelete(id: alert.id, open: $open, brick: .flush,
                  trailing: [.delete(t, run: onDelete)]) { swipe in
      row(swipe)
    }
  }

  private func row(_ swipe: SwipeDeleteProxy) -> some View {
    PanelRow(name: title, meta: meta, onTap: { swipe.isOpen ? swipe.close() : onOpen() }) {
      if alert.kind == .reviewDue {
        // 复盘到点没有「再次提醒」也没有条件可改：它跟着那条记录走。
        EmptyView()
      } else if alert.status == .fired {
        Button(action: { swipe.close(); onRearm() }) {
          Text("再次提醒")
            .font(PanelFont.seg)
            .foregroundStyle(t.badgeInk)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(t.amber))
        }
        .buttonStyle(.plain)
      } else {
        HStack(spacing: 10) {
          if alert.isActive { watchButton(swipe) }
          condition
        }
      }
    }
    .overlay(alignment: .leading) {
      CoinBadge(base: KanpanCore.Alert.base(of: alert.symbol), size: 24)
        .padding(.leading, PanelMetrics.hPad - 30)
        .allowsHitTesting(false)
    }
    .padding(.leading, 30)
  }

  /// 「盯一个」：把这条挂到锁屏 / 灵动岛上。盯着时实心，再点一次就不盯了。
  private func watchButton(_ swipe: SwipeDeleteProxy) -> some View {
    Button(action: { swipe.close(); onWatch() }) {
      Text(watched ? "盯着" : "盯一个")
        .font(PanelFont.seg)
        .foregroundStyle(watched ? t.badgeInk : t.amber)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(watched ? t.amber : Color.clear))
        .overlay(Capsule().stroke(t.amber, lineWidth: watched ? 0 : 1))
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
      HStack(spacing: 3) {
        Text(alert.condition.title).font(PanelFont.seg)
        VectorIcon.chevron(9, w: 1.7)
      }.foregroundStyle(t.amber)
    }
    .accessibilityIdentifier("alerts.condition")
  }

  private var title: String {
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
