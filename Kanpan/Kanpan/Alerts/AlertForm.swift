import KanpanCore
import SwiftUI

/// 某只品种此刻的价，新建价格提醒时用。宿主按用户打的代号查出来（`MainScreen.alertQuote`）。
struct PriceAlertQuote: Equatable {
  /// 规范键（`binance/usd_m/ETHUSDT`；「ETH」会被认成这一只）。框里给人看的是代号，
  /// 提交时交出去的是它。
  var symbol: String
  var price: Double?
  var decimals: Int?
  /// 24h 涨跌幅（百分数，`1.2` = +1.2%）。创建页品种卡右下那一小行；取不到就空着。
  var changePercent: Double? = nil

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
///
/// 2026-09-25 v2：没有备注（用户「也不需要备注啊」）、没有推送内容模板（「webhook 不要给用户
/// 填写 json，只需要输入地址即可」）——Webhook 一律发默认模板，所以这两样不在草稿里；
/// 落账时对服务端契约照旧写 `note` / `webhookText` 两个键，值是 null。
struct AlertDraft {
  var quote: PriceAlertQuote
  var target: Double
  var condition: KanpanCore.Alert.Condition
  var webhook: String?
}

extension AlertStore {
  /// 表单的「创建提醒 / 保存」落账。新建（图上十字线那颗「创建提醒」）与编辑（创建页底下
  /// 「当前提醒」那一行）共用这一处：建完顺手要通知权限、登记推送——按方案，第一次建提醒
  /// 才问权限。编辑（`editing` 给了 id）不再问。
  @discardableResult
  func commit(_ draft: AlertDraft, editing id: String? = nil) -> KanpanCore.Alert? {
    let label = draft.quote.current(draft.target)
    if let id {
      return update(id: id, target: draft.target, current: draft.quote.price, label: label,
                    condition: draft.condition, webhook: draft.webhook,
                    webhookText: nil, note: nil)
    }
    let alert = addPrice(symbol: draft.quote.symbol, target: draft.target, current: draft.quote.price,
                         label: label, condition: draft.condition, webhook: draft.webhook,
                         webhookText: nil, note: nil)
    guard alert != nil else { return nil }
    Task {
      await AlertNotifications.requestAuthorization()
      await MainActor.run { PushRegistration.startIfAuthorized() }
    }
    return alert
  }
}

/// 创建 / 编辑一条价格提醒的那一页。
///
/// 新建只有一个入口：图上十字线那颗「创建提醒」（`AlertComposeSheet`，品种是图上那只，价格
/// 预填十字线那一口，右上「全部预警」推进提醒总表）。编辑从这一页底下「当前提醒」里点一条
/// 价格提醒进来，同一页，标题「编辑提醒」、按钮「保存」。
///
/// 2026-09-25 v2（用户：「布局不太合理、做的有点粗糙……品种不可编辑，也不需要 -2% 这种，
/// 通常用户就是设置某个具体值提醒」）整页重做成 iOS 设置那种分组卡片，一种语言到底：
///
/// 1. **品种卡**（只读）：徽章、`BTC/USDT`、「币安 · USDT 永续」，右边现价与涨跌幅实时跳。
///    品种不能改——提醒挂在哪只由入口决定，要给别的品种建提醒就去那只的图上点。
/// 2. **条件卡**：价格（手动输入、等宽数字，不给步进器也不给 ±% 快捷；v3 起放在一口输入井里，
///    一眼看得出能改）、价格下一行小字说离现价多远、「价格达到 | 收盘穿过」。
///    **方向不让选**：比现价高就是「涨到」，低就是「跌到」。
/// 3. **通知卡**：Webhook 开关，开着只填一个地址；推送内容由我们定（默认模板），卡片下面一行
///    脚注说清发的是什么，旁边「发一条测试」。
/// 4. 主按钮跟在卡片后面（不钉底）；再往下是这只品种的「当前提醒 N」（新建时才有）：
///    只列还没触发的价格与画线提醒（用户叫它「未生效预警」），每行右侧一枚垃圾桶，
///    价格提醒点行进编辑。
///
/// 只响一次，响完就删（`AlertWatcher`，2026-09-25 v3）；没有「每次」「再次提醒」。
struct AlertForm: View {
  /// 图上那只给人看的代号（宿主交的是 `InstrumentID.display`）。
  var initialSymbol: String
  /// 预填的价（图上十字线那一口）。nil 就空着、进来直接对准价格框。
  var initialPrice: Double? = nil
  /// 编辑哪一条。nil 是新建。
  var existing: KanpanCore.Alert? = nil
  /// 按代号查品种与现价；查不到这只品种返回 nil。
  var resolve: (String) -> PriceAlertQuote?
  /// 品种定下来之后叫一声：宿主去要一口价（不在自选里的品种报价簿手上没有）。
  var prepare: (String) -> Void = { _ in }
  /// 页面关了叫一声，宿主把 `prepare` 点名要的那一只放掉。
  var release: () -> Void = {}
  /// 这只品种还没触发的提醒（已排好序，见 `AlertRecordText.records`）。只有新建页摆。
  var records: [KanpanCore.Alert] = []
  /// 记录里的时间按设置里那档时区写。
  var zone: TZOffset = .system
  /// 点一条价格提醒：推进它的编辑页。
  var onEditRecord: (String) -> Void = { _ in }
  /// 行尾垃圾桶删一条。
  var onDeleteRecord: (String) -> Void = { _ in }
  var onSave: (AlertDraft) -> Void

  @State private var priceText = ""
  @State private var condition: KanpanCore.Alert.Condition = .touch
  @State private var webhookOn = false
  @State private var webhookURL = ""
  @State private var testing = false
  @State private var seeded = false
  @FocusState private var focus: Field?
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 页面左右边距（`panelPageInset` 按屏宽给 16 / 20，即 `Inset.page`）。
  @Environment(\.panelHPad) private var hPad

  private enum Field: Hashable { case price, url }

  /// 品种卡那一行的高度：徽章 28 + 两行字，比普通行（44）高一档。
  private static let symbolRowHeight = Inset.rowMin + Space.m
  /// 价格下面那行小字的高度（和价格同一张卡，中间不划线）。
  private static let hintHeight = Space.section
  /// 主按钮高度。
  private static let buttonHeight = Inset.rowMin + Space.xs
  /// 价格井聚焦 / 失焦的过渡时长。
  private static let focusFade: Double = 0.15

  private var symbolKey: String { existing?.symbol ?? initialSymbol }

  var body: some View {
    let quote = resolve(existing.map { InstrumentID($0.symbol).display } ?? initialSymbol)
    // 走系统导航栏（居中标题 + 系统返回 / 左上关闭），和铃声页、设置 → 账号同一套。
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        symbolCard(quote)
        conditionCard(quote)
          .padding(.top, Space.xl)
        notifyCard
          .padding(.top, Space.xl)
        if webhookOn { webhookFootnote(quote) }
        mainButton(quote)
          .padding(.top, Space.xl)
        if existing == nil, !records.isEmpty {
          // 最后一条删掉时整段（标题 + 卡片）一起淡出，不闪。
          recordsSection(quote)
            .padding(.top, Space.section)
            .transition(.opacity)
        }
      }
      .padding(.horizontal, hPad)
      .padding(.top, Space.m)
      .padding(.bottom, Space.section)
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    .background(AlertPageStyle.background(t).ignoresSafeArea())
    .navigationTitle(existing == nil ? "创建提醒" : "编辑提醒")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      // 价格是数字键盘，没有回车键收不起来（视觉审查 2.9 #5）。
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("完成") { focus = nil }
      }
    }
    .onAppear {
      seed(quote)
      // 要价按宿主解析出来的规范键要；代号（尤其 `BTC/USD`）直接交出去会被当成币安的裸代号。
      // 每次露面都要一次：推进「全部预警」或编辑页再退回来时，上一次那一只已经在 `onDisappear` 里放掉了。
      prepare(quote?.symbol ?? symbolKey)
    }
    // 和 `prepare` 成对：推进下一层、整张提醒表收起，都在这儿放掉点名的那一只。
    .onDisappear { release() }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.new.page")
  }

  // ---------------------------------------------------------------- 预填

  private func seed(_ quote: PriceAlertQuote?) {
    guard !seeded else { return }
    seeded = true
    if let existing {
      if let target = existing.targetPrice {
        priceText = ReviewLabels.price(target, decimals: quote?.decimals)
      }
      condition = existing.condition
      webhookOn = existing.webhook != nil
      webhookURL = existing.webhook ?? ""
    } else if let initialPrice {
      priceText = quote?.label(initialPrice) ?? String(initialPrice)
    }
    // 没带价进来（预览、以后别的入口）直接对准价格框；图上带着价进来、或者编辑，先让人看全整页。
    if existing == nil, initialPrice == nil { focus = .price }
  }

  // ---------------------------------------------------------------- 品种卡

  private func symbolCard(_ quote: PriceAlertQuote?) -> some View {
    let key = quote?.symbol ?? InstrumentID.canonical(symbolKey)
    let info = SymbolInfo.placeholder(symbol: key)
    let change = quote?.changePercent
    let tone = change.map { $0 < 0 ? t.down : ($0 > 0 ? t.up : t.ink) } ?? t.ink
    return AlertGroupCard {
      HStack(spacing: Space.m) {
        CoinBadge(base: info.base, size: ControlMetrics.badge)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Space.xxs) {
          Text(info.base + "/" + info.quote)
            .font(TypeScale.heading)
            .foregroundStyle(t.ink)
            .lineLimit(1)
            .accessibilityIdentifier("alerts.new.symbol")
          Text(AlertRecordText.venueLine(key))
            .font(TypeScale.caption)
            .foregroundStyle(t.ink3)
            .lineLimit(1)
        }
        Spacer(minLength: Space.s)
        VStack(alignment: .trailing, spacing: Space.xxs) {
          Text(quote?.price.map { quote!.current($0) } ?? "—")
            .font(TypeScale.bodyEmph).monospacedDigit()
            .foregroundStyle(tone)
            .contentTransition(.numericText())
            .accessibilityIdentifier("alerts.new.last")
          Text(changePercentText(change))
            .font(TypeScale.caption).monospacedDigit()
            .foregroundStyle(tone)
        }
        .lineLimit(1)
      }
      .padding(.horizontal, Inset.card)
      .frame(height: Self.symbolRowHeight)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.new.symbolCard")
  }

  // ---------------------------------------------------------------- 条件卡

  private func conditionCard(_ quote: PriceAlertQuote?) -> some View {
    AlertGroupCard {
      // 价格：一口输入井（v3，用户：「价格可以编辑吧」——原来一串裸数字看不出能改）。
      // 井底取页面底色（比卡片深一层，和条件分段的槽同一个底），`Radius.s` 圆角，
      // 前面一枚小铅笔；聚焦时描一圈强调色。整行点哪儿都进输入框（标签那一截也算）。
      HStack(spacing: Space.m) {
        label("价格")
        priceWell(quote)
      }
      .padding(.horizontal, Inset.card)
      .padding(.vertical, Space.xs)
      .frame(minHeight: Inset.rowMin)
      .contentShape(Rectangle())
      .onTapGesture { focus = .price }

      // 离现价多远：和价格同一格，中间不划线。
      Text(hintText(quote))
        .font(TypeScale.caption).monospacedDigit()
        .foregroundStyle(t.ink3)
        .lineLimit(1)
        // 跟着输入实时变：数字滚动换，不整句闪。
        .contentTransition(.numericText())
        .animation(.snappy, value: priceText)
        .frame(maxWidth: .infinity, minHeight: Self.hintHeight, alignment: .topLeading)
        .padding(.horizontal, Inset.card)
        .accessibilityIdentifier("alerts.new.current")
      AlertCardDivider()

      HStack(spacing: Space.m) {
        label("条件")
        Spacer(minLength: Space.s)
        PanelSegment(options: KanpanCore.Alert.Condition.allCases.map { ($0.title, $0) },
                     selection: condition, id: "alerts.new.condition",
                     track: AlertPageStyle.background(t)) { condition = $0 }
      }
      .padding(.horizontal, Inset.card)
      .padding(.vertical, PanelMetrics.vPad)
      .frame(minHeight: Inset.rowMin)
    }
  }

  private func priceWell(_ quote: PriceAlertQuote?) -> some View {
    let focused = focus == .price
    return HStack(spacing: Space.s) {
      Image(systemName: "pencil")
        .font(TypeScale.caption)
        .foregroundStyle(focused ? t.amber : t.ink3)
        .accessibilityHidden(true)
      TextField("0", text: $priceText)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .font(TypeScale.bodyEmph).monospacedDigit()
        .foregroundStyle(t.ink)
        .focused($focus, equals: .price)
        .accessibilityIdentifier("alerts.new.price")
        .accessibilityLabel("价格")
      Text(quote?.quoteAsset ?? SymbolInfo.placeholder(symbol: symbolKey).quote)
        .font(TypeScale.caption)
        .foregroundStyle(t.ink3)
    }
    .padding(.horizontal, Space.m)
    .padding(.vertical, Space.s)
    .frame(maxWidth: .infinity)
    .background {
      // 聚焦时井底微微提亮一层强调色的薄纱，描边换成强调色——一眼看得出「正在输这儿」。
      let well = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
      well.fill(AlertPageStyle.background(t))
        .overlay { well.fill(focused ? t.amberSoft : .clear) }
        .overlay { well.strokeBorder(focused ? t.amberLine : .clear, lineWidth: 1) }
    }
    .animation(.easeOut(duration: Self.focusFade), value: focused)
  }

  /// 「现价 83,964.6 · 低于现价 4.82%」。没填价 / 填的不是正数：「输入一个价格」。
  private func hintText(_ quote: PriceAlertQuote?) -> String {
    guard let target else { return "输入一个价格" }
    guard let quote, let price = quote.price, price > 0 else { return "现价 —" }
    let pct = (target - price) / price * 100
    guard abs(pct) >= 0.005 else { return "和现价相同" }
    return "现价 " + quote.current(price) + " · " + (pct > 0 ? "高于现价 " : "低于现价 ")
      + String(format: "%.2f%%", abs(pct))
  }

  // ---------------------------------------------------------------- 通知卡

  private var notifyCard: some View {
    AlertGroupCard {
      HStack(spacing: Space.m) {
        label("Webhook")
        Spacer(minLength: Space.s)
        Toggle("Webhook", isOn: Binding(get: { webhookOn }, set: { on in
          withAnimation(.snappy) { webhookOn = on }
          if on, webhookURL.isEmpty { focus = .url }
        }))
        .labelsHidden()
        .tint(t.amber)
        .accessibilityIdentifier("alerts.new.webhook")
      }
      .padding(.horizontal, Inset.card)
      .frame(minHeight: Inset.rowMin)

      if webhookOn {
        AlertCardDivider()
        HStack(spacing: Space.m) {
          label("地址")
          TextField("https://", text: $webhookURL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            // 地址键盘的回车键写「完成」，按下就收键盘，露出下面的主按钮。
            .submitLabel(.done)
            .onSubmit { focus = nil }
            .multilineTextAlignment(.trailing)
            .font(TypeScale.bodyEmph)
            .foregroundStyle(t.ink)
            .focused($focus, equals: .url)
            .accessibilityIdentifier("alerts.new.webhook.url")
            .accessibilityLabel("地址")
        }
        .padding(.horizontal, Inset.card)
        .frame(minHeight: Inset.rowMin)
        .contentShape(Rectangle())
        .onTapGesture { focus = .url }
      }
    }
  }

  /// 卡片下面一行脚注：发的是什么，旁边「发一条测试」。结果走全局提示条，不占页面。
  private func webhookFootnote(_ quote: PriceAlertQuote?) -> some View {
    let valid = KanpanCore.Alert.isValidWebhook(webhookURL)
    return HStack(spacing: Space.s) {
      Text("触发时向这个地址发一条 JSON")
        .font(TypeScale.caption)
        .foregroundStyle(t.ink3)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
      Spacer(minLength: Space.s)
      Button { sendTest(quote) } label: {
        Text(testing ? "发送中…" : "发一条测试")
          .font(TypeScale.caption)
          .foregroundStyle(valid && !testing ? t.amber : PanelDisabled.ink(t))
          .frame(minHeight: Hit.min)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!valid || testing)
      .accessibilityIdentifier("alerts.new.webhook.test")
    }
    // 点按区撑到 44，但脚注这一行看上去只有一行小字高：多出来的还给上下留白。
    .padding(.vertical, -(Hit.min - Self.hintHeight) / 2)
    .padding(.top, Space.s)
    .transition(.opacity)
  }

  private func sendTest(_ quote: PriceAlertQuote?) {
    let quote = quote ?? PriceAlertQuote(symbol: InstrumentID.canonical(symbolKey), price: nil, decimals: nil)
    let price = quote.price ?? target ?? 0
    // 不带推送内容也不带备注：发的就是默认模板，和真触发时一模一样。
    let draft = KanpanCore.Alert.price(
      symbol: quote.symbol, target: target ?? price, current: quote.price,
      label: quote.current(target ?? price), now: Date().timeIntervalSince1970 * 1000,
      condition: condition)
    let sent = existing.map { var a = draft; a.id = $0.id; return a } ?? draft
    let url = webhookURL
    testing = true
    Task { @MainActor in
      let outcome = await AlertWebhook.test(sent, url: url, price: price, decimals: quote.decimals)
      testing = false
      ToastCenter.shared.say(outcome.toast)
    }
  }

  // ---------------------------------------------------------------- 主按钮

  private func mainButton(_ quote: PriceAlertQuote?) -> some View {
    let ready = draft(quote) != nil
    return Button {
      guard let draft = draft(quote) else { return }
      focus = nil
      onSave(draft)
      dismiss()
    } label: {
      // 禁用时不整块降透明度（琥珀底上的字只剩 1.05:1，看上去像没画出来）：
      // 底换成中性的 `raised2`、字换成 `ink3`（`PanelDisabled`，对比度审查定的写法）。
      Text(existing == nil ? "创建提醒" : "保存")
        .font(TypeScale.title)
        .foregroundStyle(ready ? t.badgeInk : PanelDisabled.ink(t))
        .frame(maxWidth: .infinity)
        .frame(height: Self.buttonHeight)
        .background(Capsule().fill(ready ? t.amber : disabledFill))
        .contentShape(Capsule())
    }
    .buttonStyle(AlertPressStyle())
    .disabled(!ready)
    .animation(.snappy, value: ready)
    .accessibilityIdentifier("alerts.new.create")
  }

  /// 禁用的底：浅色下 `raised2` 就是卡片色，和卡片同一层；深色页面底换成了 `app`，
  /// 卡片色 `raised2` 在上面分得开，两种情况都用 `PanelDisabled`。
  private var disabledFill: Color { PanelDisabled.fill(t) }

  /// 能交了吗：品种认得、价是正数、开着 Webhook 时地址合法。
  private func draft(_ quote: PriceAlertQuote?) -> AlertDraft? {
    guard let quote, let target else { return nil }
    let url = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if webhookOn, !KanpanCore.Alert.isValidWebhook(url) { return nil }
    return AlertDraft(quote: quote, target: target, condition: condition,
                      webhook: webhookOn ? url : nil)
  }

  /// 用户打的价。逗号当千分位扔掉；非正数、读不出来的都不算。
  private var target: Double? {
    let text = priceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
    guard let value = Double(text), value.isFinite, value > 0 else { return nil }
    return value
  }

  // ---------------------------------------------------------------- 当前提醒

  /// 这只品种还没触发的提醒（用户叫它「未生效预警」）。行尾只有一枚垃圾桶；
  /// 价格提醒点行进编辑，画线提醒的价在线上，要改就去图上拖线，行本身不可点。
  private func recordsSection(_ quote: PriceAlertQuote?) -> some View {
    VStack(alignment: .leading, spacing: Space.s) {
      AlertCardTitle(text: "当前提醒 \(records.count)")
        .contentTransition(.numericText())
      AlertGroupCard {
        ForEach(Array(records.enumerated()), id: \.element.id) { index, alert in
          AlertRecordRow(
            alert: alert,
            title: AlertRecordText.title(alert, withSymbol: false),
            meta: AlertRecordText.meta(alert, zone: zone, decimals: quote?.decimals,
                                       conditionInline: true),
            divider: index < records.count - 1,
            onTap: alert.kind == .price ? { onEditRecord(alert.id) } : nil,
            onDelete: { withAnimation(.snappy) { onDeleteRecord(alert.id) } })
          .transition(AlertRecordRow.removal)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.records")
  }

  // ---------------------------------------------------------------- 零件

  private func label(_ text: String) -> some View {
    Text(text).font(TypeScale.body).foregroundStyle(t.ink).lineLimit(1).fixedSize()
  }
}

/// 主按钮的按压反馈：按下缩一点、松手弹回。只动比例，不动颜色（禁用态由 `PanelDisabled` 管）。
private struct AlertPressStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && enabled ? 0.98 : 1)
      .animation(.snappy(duration: 0.15), value: configuration.isPressed)
  }
}

/// 图上十字线那颗「创建提醒」弹出来的那张表：创建提醒页 + 右上「全部预警」推进提醒总表。
///
/// 2026-09-25 起提醒总表的日常入口就是这颗「全部预警」（设置里那一行删了；v3 起不带数量，
/// 十字线动作栏也不另加入口）；深链与通知点开时
/// 总表仍自己是一张表（`AlertListPage(presentedAsSheet: true)`）。两张表不会同时开：
/// 宿主用同一个 `sheet(item:)` 管它俩。页底「当前提醒」点一条推进它的编辑页，也在这一层的
/// 导航栈里（`AlertForm` 不能在自己身上挂一个推进自己的去处，那是个递归的类型）。
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
  @State private var editing: String?
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let key = context.quote(symbol)?.symbol ?? InstrumentID.canonical(symbol)
    NavigationStack {
      AlertForm(initialSymbol: symbol, initialPrice: price, resolve: context.quote,
                prepare: context.prepareQuote, release: context.releaseQuote,
                records: AlertRecordText.records(store.all, symbol: key),
                zone: context.zone,
                onEditRecord: { editing = $0 },
                onDeleteRecord: { store.remove(id: $0) }) { draft in
        if let alert = store.commit(draft) { Haptics.success(); onCreated(alert) }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(role: .close) { dismiss() }
            .accessibilityIdentifier("panel.done")
        }
        ToolbarItem(placement: .topBarTrailing) {
          // 导航栏按钮的字交给系统（和左上关闭同一套玻璃按钮），不另设字号。
          Button("全部预警") { showAll = true }
            .accessibilityIdentifier("alerts.all")
        }
      }
      .navigationDestination(isPresented: $showAll) {
        AlertListPage(store: store, context: context, presentedAsSheet: false)
      }
      .navigationDestination(item: $editing) { id in
        if let alert = store.all.first(where: { $0.id == id }) {
          AlertForm(initialSymbol: InstrumentID(alert.symbol).display, existing: alert,
                    resolve: context.quote, prepare: context.prepareQuote,
                    release: context.releaseQuote, zone: context.zone) { draft in
            if store.commit(draft, editing: id) != nil { Haptics.success() }
          }
        }
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
