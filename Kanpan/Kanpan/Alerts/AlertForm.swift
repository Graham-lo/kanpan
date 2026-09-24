import KanpanCore
import SwiftUI

/// 某只品种此刻的价，新建价格提醒时用。宿主按用户打的代号查出来（`MainScreen.alertQuote`）。
struct PriceAlertQuote: Equatable {
  /// 规范键（`binance/usd_m/ETHUSDT`；「ETH」会被认成这一只）。框里给人看的是代号，
  /// 提交时交出去的是它。
  var symbol: String
  var price: Double?
  var decimals: Int?

  func label(_ value: Double) -> String { ReviewLabels.price(value, decimals: decimals) }
  /// 页上「当前 xxx」那口现价：和行情页头部那口价同一个写法——小数位由品种说
  /// （`decimals`），整数部分插千分位（`grouped`，头部 `TopBar.lastText` 用的就是它）。
  /// 同一只 BTC，头部写 86,781.5、这里写 86781.50 就对不上眼（审查 D3）。
  /// 2026-09-24 UI 整改 P1b：提醒标题也用这个写法（「BTC 跌到 12,345.00」），通知、锁屏、
  /// 总表三处的数一个样（视觉审查 2.9 #3 / §3 #7 数字写法统一）。
  func current(_ value: Double) -> String { grouped(label(value)) }
  /// 计价币（`USDT`、`USD`），价格框右边那一小格。
  var quoteAsset: String { SymbolInfo.placeholder(symbol: symbol).quote }
}

/// 表单填完交出去的那一份。落账在 `AlertStore.commit`。
struct AlertDraft {
  var quote: PriceAlertQuote
  var target: Double
  var condition: KanpanCore.Alert.Condition
  var webhook: String?
  var webhookText: String?
  var note: String?
}

extension AlertStore {
  /// 表单的「创建提醒 / 保存」落账。新建（图上十字线那颗「涨到 X 提醒我」）与编辑（总表左划
  /// 「编辑」）共用这一处：建完顺手要通知权限、登记推送——按方案，第一次建提醒
  /// 才问权限。编辑（`editing` 给了 id）不再问。
  @discardableResult
  func commit(_ draft: AlertDraft, editing id: String? = nil) -> KanpanCore.Alert? {
    let label = draft.quote.current(draft.target)
    if let id {
      return update(id: id, target: draft.target, current: draft.quote.price, label: label,
                    condition: draft.condition, webhook: draft.webhook,
                    webhookText: draft.webhookText, note: draft.note)
    }
    let alert = addPrice(symbol: draft.quote.symbol, target: draft.target, current: draft.quote.price,
                         label: label, condition: draft.condition, webhook: draft.webhook,
                         webhookText: draft.webhookText, note: draft.note)
    guard alert != nil else { return nil }
    Task {
      await AlertNotifications.requestAuthorization()
      await MainActor.run { PushRegistration.startIfAuthorized() }
    }
    return alert
  }

  /// 「最近用过」的 Webhook 地址：从已有提醒里去重，新建的在前，最多三个。
  var recentWebhooks: [String] {
    var seen: Set<String> = [], out: [String] = []
    for alert in archive.alerts.sorted(by: { $0.created > $1.created }) {
      guard let url = alert.webhook, !seen.contains(url) else { continue }
      seen.insert(url); out.append(url)
      if out.count == 3 { break }
    }
    return out
  }
}

/// 新建 / 编辑一条价格提醒的那一页。新建只有一个入口：图上十字线那颗「涨到 X 提醒我」
/// （`AlertComposeSheet`，价格与品种都已经填好，右上「全部」推进提醒总表）。编辑从总表那一行
/// 左划「编辑」进来，同一页，按钮换成「保存」。
///
/// - 品种默认就是图上那只，框里填的是给人看的代号（`BTCUSDT`、`BTC/USD`），不是内部的规范键
///   （`binance/usd_m/BTCUSDT`）；规范键只在宿主解析、提交时才出现。能改（打「ETH」就认成
///   `ETHUSDT`），点进框里整串全选，直接打就是覆盖；锁英文键盘（`kanpan-symbol-search-keyboard`）。
///   编辑时品种不能改（改了就是另一条提醒，删了重建）。
/// - 价格是手动输入框、等宽数字，不给加减步进器（`kanpan-no-steppers-use-text-fields`）；
///   下面一排 −2% −1% +1% +2% 按现价一点就填。
/// - **方向不让选**：比现价高就是「涨到」，低就是「跌到」，由 `Alert.price` 按建的那一刻的
///   现价定；价格下面一行小字「当前 xxx · 高 x%」让人知道自己在跟谁比。
/// - 只响一次（响过变「已触发」，总表里可以「再次提醒」）；没有「每次」这一档。
/// - 通知：Webhook 开关，开着时填地址、推送内容（带占位符），可以先发一条测试。
struct AlertForm: View {
  /// 图上那只给人看的代号（宿主交的是 `InstrumentID.display`）。
  var initialSymbol: String
  /// 预填的价（图上十字线那一口）。nil 就空着、进来直接对准价格框。
  var initialPrice: Double? = nil
  /// 编辑哪一条。nil 是新建。
  var existing: KanpanCore.Alert? = nil
  /// 按用户打的字查品种与现价；查不到这只品种返回 nil。
  var resolve: (String) -> PriceAlertQuote?
  /// 品种定下来之后叫一声：宿主去要一口价（不在自选里的品种报价簿手上没有）。
  var prepare: (String) -> Void = { _ in }
  /// 页面关了叫一声，宿主把 `prepare` 点名要的那一只放掉。
  var release: () -> Void = {}
  /// 「最近用过」那几个 Webhook 地址（`AlertStore.recentWebhooks`）。
  var recentWebhooks: [String] = []
  var onSave: (AlertDraft) -> Void

  @State private var symbolText = ""
  @State private var symbolSelection: TextSelection?
  @State private var priceText = ""
  @State private var condition: KanpanCore.Alert.Condition = .touch
  @State private var webhookOn = false
  @State private var webhookURL = ""
  @State private var template = AlertMessage.defaultTemplate
  @State private var note = ""
  @State private var testing = false
  @State private var testResult: AlertWebhook.Outcome?
  @State private var seeded = false
  @FocusState private var focus: Field?
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  @Environment(\.panelHPad) private var hPad

  private enum Field: Hashable { case symbol, price, url, template, note }

  var body: some View {
    let quote = resolve(symbolText)
    // 2026-09-24 UI 整改 P1b：走系统导航栏（居中标题 + 系统返回 / 左上关闭），
    // 和铃声页、设置 → 账号同一套；不再自绘「‹」头。
    ScrollView {
      VStack(spacing: 0) {
        symbolRow
        priceRow(quote)
        currentLine(quote)
        nudges(quote)
        conditionRow
        notifySection(quote)
        noteRow
      }
      .padding(.top, Space.xs)
      .padding(.bottom, Space.l)
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    // 主按钮钉在底上：键盘起来时它跟着停在键盘上沿，不用先收键盘再去找。
    .safeAreaInset(edge: .bottom, spacing: 0) { saveButton(quote) }
    .background(t.raised.ignoresSafeArea())
    .navigationTitle(existing == nil ? "新建提醒" : "编辑提醒")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      // 价格是数字键盘，没有回车键收不起来（视觉审查 2.9 #5）。
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("完成") { focus = nil }
      }
    }
    .onAppear {
      seed()
      // 要价按宿主解析出来的规范键要；框里的代号（尤其 `BTC/USD`）直接交出去会被当成币安的裸代号。
      // 每次露面都要一次：推进「全部」再退回来时，上一次那一只已经在 `onDisappear` 里放掉了。
      prepare(resolve(symbolText)?.symbol ?? existing?.symbol ?? initialSymbol)
    }
    // 和 `prepare` 成对：推进下一层、退回总表、整张提醒表收起，都在这儿放掉点名的那一只。
    .onDisappear { release() }
    // 点进品种框就把整串选中：想换一只直接打，不用先删。等这一拍的光标落定再选，
    // 否则点按落下的插入点会把选区盖掉。
    .onChange(of: focus) { _, field in
      guard field == .symbol else { return }
      Task { @MainActor in
        symbolSelection = TextSelection(range: symbolText.startIndex..<symbolText.endIndex)
      }
    }
    .onChange(of: quote?.symbol) { _, symbol in if let symbol { prepare(symbol) } }
    .onChange(of: note) { _, text in
      let clipped = KanpanCore.Alert.clip(note: text)
      if clipped != text { note = clipped }
    }
    .onChange(of: webhookURL) { _, _ in testResult = nil }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.new.page")
  }

  // ---------------------------------------------------------------- 预填

  private func seed() {
    guard !seeded else { return }
    seeded = true
    if let existing {
      symbolText = InstrumentID(existing.symbol).display
      let decimals = resolve(symbolText)?.decimals
      if let target = existing.targetPrice { priceText = ReviewLabels.price(target, decimals: decimals) }
      condition = existing.condition
      webhookOn = existing.webhook != nil
      webhookURL = existing.webhook ?? ""
      template = existing.webhookText ?? AlertMessage.defaultTemplate
      note = existing.note ?? ""
    } else {
      symbolText = initialSymbol
      if let initialPrice { priceText = resolve(symbolText)?.label(initialPrice) ?? String(initialPrice) }
    }
    // 没带价进来（预览、以后别的入口）直接对准价格框；图上带着价进来、或者编辑，先让人看全整页。
    if existing == nil, initialPrice == nil { focus = .price }
  }

  // ---------------------------------------------------------------- 品种与价格

  private var symbolRow: some View {
    field("品种") {
      TextField("", text: $symbolText, selection: $symbolSelection)
        .keyboardType(.asciiCapable)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .focused($focus, equals: .symbol)
        .disabled(existing != nil)
        .accessibilityIdentifier("alerts.new.symbol")
        .accessibilityLabel("品种")
    }
  }

  private func priceRow(_ quote: PriceAlertQuote?) -> some View {
    field("价格", unit: quote?.quoteAsset) {
      TextField("", text: $priceText)
        .keyboardType(.decimalPad)
        .focused($focus, equals: .price)
        .accessibilityIdentifier("alerts.new.price")
        .accessibilityLabel("价格")
    }
  }

  /// 「当前 84,535.5」；填了价之后接上离现价多远（「· 高 0.15%」）。查不到品种用 `danger`。
  private func currentLine(_ quote: PriceAlertQuote?) -> some View {
    HStack {
      Text(currentText(quote))
        .font(TypeScale.caption).monospacedDigit()
        // 查不到品种是这一页唯一的错误态，用 `danger` 标出来，不和「当前 xxx」同一个灰。
        .foregroundStyle(quote == nil && !symbolText.isEmpty ? t.danger : t.ink3)
        .accessibilityIdentifier("alerts.new.current")
      Spacer(minLength: 0)
    }
    .padding(.horizontal, hPad)
    .padding(.top, Space.s)
  }

  private func currentText(_ quote: PriceAlertQuote?) -> String {
    guard let quote else { return symbolText.isEmpty ? " " : "没有这只品种" }
    guard let price = quote.price else { return "当前 —" }
    let head = "当前 " + quote.current(price)
    guard let target, price > 0 else { return head }
    let pct = (target - price) / price * 100
    guard abs(pct) >= 0.005 else { return head + " · 就是现价" }
    return head + " · " + (pct > 0 ? "高 " : "低 ") + String(format: "%.2f%%", abs(pct))
  }

  /// −2% −1% +1% +2%：按现价一点就填进价格框。没有现价就不摆。
  @ViewBuilder private func nudges(_ quote: PriceAlertQuote?) -> some View {
    if let quote, let price = quote.price {
      HStack(spacing: Space.s) {
        ForEach([-2, -1, 1, 2], id: \.self) { step in
          let text = (step < 0 ? "−" : "+") + "\(abs(step))%"
          Button {
            priceText = quote.label(price * (1 + Double(step) / 100))
          } label: {
            Text(text)
              .font(TypeScale.control).monospacedDigit()
              .foregroundStyle(t.ink2)
              .padding(.horizontal, Space.m)
              .frame(height: ControlMetrics.pillHeight)
              .background(Capsule().fill(t.raised2))
              .frame(minHeight: Hit.min)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("alerts.new.nudge.\(step)")
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, hPad)
    }
  }

  private var conditionRow: some View {
    PanelRow(name: "条件") {
      PanelSegment(options: KanpanCore.Alert.Condition.allCases.map { ($0.title, $0) },
                   selection: condition, id: "alerts.new.condition") { condition = $0 }
    }
  }

  // ---------------------------------------------------------------- 通知

  @ViewBuilder private func notifySection(_ quote: PriceAlertQuote?) -> some View {
    PanelGroupTitle(text: "通知")
    PanelRow(name: "Webhook") {
      PanelSwitch(isOn: webhookOn) {
        webhookOn.toggle()
        if webhookOn, webhookURL.isEmpty { focus = .url }
      }
      .accessibilityIdentifier("alerts.new.webhook")
    }
    if webhookOn {
      field("地址") {
        TextField("https://", text: $webhookURL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($focus, equals: .url)
          .accessibilityIdentifier("alerts.new.webhook.url")
          .accessibilityLabel("地址")
      }
      recentRow
      templateBox
      tokenRow
      testRow(quote)
    }
  }

  @ViewBuilder private var recentRow: some View {
    let others = recentWebhooks.filter { $0 != webhookURL.trimmingCharacters(in: .whitespaces) }
    if !others.isEmpty {
      HStack(spacing: Space.s) {
        Text("最近用过").font(TypeScale.caption).foregroundStyle(t.ink3)
        ForEach(others, id: \.self) { url in
          chip(URL(string: url)?.host() ?? url) { webhookURL = url }
            .accessibilityIdentifier("alerts.new.webhook.recent")
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, hPad)
      .padding(.top, Space.xs)
    }
  }

  private var templateBox: some View {
    VStack(alignment: .leading, spacing: Space.s) {
      Text("推送内容").font(PanelFont.name).foregroundStyle(t.ink)
      TextField("", text: $template, axis: .vertical)
        .lineLimit(3...5)
        .font(TypeScale.body)
        .foregroundStyle(t.ink)
        .focused($focus, equals: .template)
        .padding(Space.s)
        .background(t.raised2, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .accessibilityIdentifier("alerts.new.webhook.text")
        .accessibilityLabel("推送内容")
    }
    .padding(.horizontal, hPad)
    .padding(.top, Space.m)
  }

  /// 占位符胶囊：点一下往推送内容末尾追加 `{名字}`。
  private var tokenRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Space.s) {
        ForEach(AlertMessage.placeholders, id: \.self) { name in
          chip(name) { template += "{\(name)}" }
            .accessibilityIdentifier("alerts.new.webhook.token.\(name)")
        }
      }
      .padding(.horizontal, hPad)
    }
    .scrollBounceBehavior(.basedOnSize)
  }

  private func testRow(_ quote: PriceAlertQuote?) -> some View {
    let valid = KanpanCore.Alert.isValidWebhook(webhookURL)
    return HStack(spacing: Space.s) {
      if let testResult {
        Text(testResult.toast)
          .font(TypeScale.caption)
          .foregroundStyle(testResult.ok ? t.ink3 : t.danger)
          .lineLimit(1)
          .accessibilityIdentifier("alerts.new.webhook.result")
      }
      Spacer(minLength: 0)
      Button { sendTest(quote) } label: {
        Text(testing ? "发送中…" : "发一条测试")
          .font(TypeScale.control)
          .foregroundStyle(valid && !testing ? t.amber : PanelDisabled.ink(t))
          .frame(minHeight: Hit.min)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!valid || testing)
      .accessibilityIdentifier("alerts.new.webhook.test")
    }
    .padding(.horizontal, hPad)
  }

  private func sendTest(_ quote: PriceAlertQuote?) {
    let quote = quote ?? PriceAlertQuote(symbol: existing?.symbol ?? symbolText, price: nil, decimals: nil)
    let price = quote.price ?? target ?? 0
    let draft = KanpanCore.Alert.price(
      symbol: quote.symbol, target: target ?? price, current: quote.price,
      label: quote.current(target ?? price), now: Date().timeIntervalSince1970 * 1000,
      condition: condition, webhookText: AlertStore.clean(template: template), note: note)
    let sent = existing.map { var a = draft; a.id = $0.id; return a } ?? draft
    testing = true
    testResult = nil
    Task { @MainActor in
      testResult = await AlertWebhook.test(sent, url: webhookURL, price: price, decimals: quote.decimals)
      testing = false
    }
  }

  // ---------------------------------------------------------------- 备注与主按钮

  private var noteRow: some View {
    field("备注") {
      TextField("选填，限 30 字", text: $note)
        .focused($focus, equals: .note)
        .accessibilityIdentifier("alerts.new.note")
        .accessibilityLabel("备注")
    }
    .padding(.top, Space.l)
  }

  private func saveButton(_ quote: PriceAlertQuote?) -> some View {
    let ready = draft(quote) != nil
    return Button {
      guard let draft = draft(quote) else { return }
      onSave(draft)
      dismiss()
    } label: {
      // 禁用时不再整块降到 0.4（琥珀底上的字只剩 1.05:1，看上去像没画出来）：
      // 底换成中性的 `raised2`、字换成 `ink3`，一眼看得出「还不能按」，字也读得清。
      Text(existing == nil ? "创建提醒" : "保存")
        .font(TypeScale.title)
        .foregroundStyle(ready ? t.badgeInk : PanelDisabled.ink(t))
        .frame(maxWidth: .infinity)
        .frame(minHeight: Hit.min)
        .background(Capsule().fill(ready ? t.amber : PanelDisabled.fill(t)))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(!ready)
    // 标识符挂在按钮本身：挂在下面那层铺到底的底色上，无障碍框会一路伸进键盘底下，
    // 点它的中心就点到了键盘（用例里「创建提醒」按了没反应就是这么来的）。
    .accessibilityIdentifier("alerts.new.create")
    .padding(.horizontal, hPad)
    .padding(.vertical, Space.s)
    .background(t.raised.ignoresSafeArea(edges: .bottom))
  }

  /// 能交了吗：品种认得、价是正数、开着 Webhook 时地址合法。
  private func draft(_ quote: PriceAlertQuote?) -> AlertDraft? {
    guard let quote, let target else { return nil }
    let url = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if webhookOn, !KanpanCore.Alert.isValidWebhook(url) { return nil }
    let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    return AlertDraft(quote: quote, target: target, condition: condition,
                      webhook: webhookOn ? url : nil,
                      webhookText: webhookOn ? AlertStore.clean(template: template) : nil,
                      note: trimmedNote.isEmpty ? nil : trimmedNote)
  }

  /// 用户打的价。逗号当千分位扔掉；非正数、读不出来的都不算。
  private var target: Double? {
    let text = priceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
    guard let value = Double(text), value.isFinite, value > 0 else { return nil }
    return value
  }

  // ---------------------------------------------------------------- 零件

  private func chip(_ text: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(text)
        .font(TypeScale.control)
        .foregroundStyle(t.ink2)
        .lineLimit(1)
        .padding(.horizontal, Space.m)
        .frame(height: ControlMetrics.pillHeight)
        .background(Capsule().fill(t.raised2))
        .frame(minHeight: Hit.min)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func field<Input: View>(_ label: String, unit: String? = nil,
                                  @ViewBuilder input: () -> Input) -> some View {
    // 和 `PanelRow` 同一套尺寸：行高 44、左右 `hPad`、底下一条 1pt 的 `hair`。
    // 输入框占满名字右边的剩余宽度，长代号（`BTC/USD`）和长价格都放得下。
    HStack(spacing: Space.m) {
      Text(label).font(PanelFont.name).foregroundStyle(t.ink)
      HStack(spacing: Space.xs) {
        input()
          .multilineTextAlignment(.trailing)
          .font(TypeScale.body)
          .monospacedDigit()
          .foregroundStyle(t.ink)
        if let unit {
          Text(unit).font(TypeScale.caption).foregroundStyle(t.ink3)
        }
      }
      .padding(.horizontal, Space.s)
      .padding(.vertical, Space.s)
      .frame(maxWidth: .infinity)
      .background(t.raised2, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
    }
    .padding(.horizontal, hPad)
    .padding(.vertical, Space.xs)
    .frame(minHeight: Inset.rowMin)
    .overlay(alignment: .bottom) { Rectangle().fill(t.hair).frame(height: 1) }
  }
}

/// 图上十字线那颗「涨到 X 提醒我」弹出来的那张表：新建提醒页 + 右上「全部」推进提醒总表。
///
/// 2026-09-25 起提醒总表的日常入口就是这颗「全部」（设置里那一行删了）；深链与通知点开时
/// 总表仍自己是一张表（`AlertListPage(presentedAsSheet: true)`）。两张表不会同时开：
/// 宿主用同一个 `sheet(item:)` 管它俩。
struct AlertComposeSheet: View {
  @ObservedObject var store: AlertStore
  var context: AlertListContext
  /// 图上那只给人看的代号。
  var symbol: String
  /// 十字线那一口价。
  var price: Double
  /// 建好了：宿主收表、说一句。
  var onCreated: (KanpanCore.Alert) -> Void

  @State private var showAll = false
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      AlertForm(initialSymbol: symbol, initialPrice: price, resolve: context.quote,
                prepare: context.prepareQuote, release: context.releaseQuote,
                recentWebhooks: store.recentWebhooks) { draft in
        if let alert = store.commit(draft) { onCreated(alert) }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(role: .close) { dismiss() }
            .accessibilityIdentifier("panel.done")
        }
        ToolbarItem(placement: .topBarTrailing) {
          let count = store.all.count
          Button(count > 0 ? "全部 \(count)" : "全部") { showAll = true }
            .monospacedDigit()
            .accessibilityIdentifier("alerts.all")
        }
      }
      .navigationDestination(isPresented: $showAll) {
        AlertListPage(store: store, context: context, presentedAsSheet: false)
      }
    }
    .tint(t.amber)
    .panelPageInset()
  }
}

/// 宿主那一张提醒表开的是哪一样。
enum AlertSheetRoute: Identifiable, Equatable {
  /// 提醒总表（`hkline://alerts`、通知点开）。
  case list
  /// 新建提醒（图上十字线那颗药丸），带着品种的代号与那一口价。
  case new(symbol: String, price: Double)

  var id: String {
    switch self {
    case .list: "list"
    case let .new(symbol, price): "new:\(symbol):\(price)"
    }
  }
}

/// 宿主 `sheet(item:)` 里那一层：按路由摆总表或新建页。非泛型、一个类型，
/// 免得在 `MainScreen` 的修饰器链上再多挂一张表（文件头那条层数上限）。
struct AlertSheetView: View {
  var route: AlertSheetRoute
  @ObservedObject var store: AlertStore
  var context: AlertListContext
  var onCreated: (KanpanCore.Alert) -> Void

  var body: some View {
    switch route {
    case .list:
      AlertListPage(store: store, context: context, presentedAsSheet: true)
    case let .new(symbol, price):
      AlertComposeSheet(store: store, context: context, symbol: symbol, price: price,
                        onCreated: onCreated)
    }
  }
}
