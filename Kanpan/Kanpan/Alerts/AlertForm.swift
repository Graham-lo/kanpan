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
  /// 条件提醒（费率 / 持仓量 / 均线 / 大单墙）的条件；nil 是价格提醒（`target` + `condition`）。
  var rule: AlertRule? = nil
}

/// 条件提醒要的默认值，宿主按那只品种算（`MainScreen.alertConditions`）。
/// 整个是 nil = 这只 / 这时不给条件提醒：没登录（条件由服务端判，要账号），或者不是币安 U 本位。
struct ConditionAlertDefaults: Equatable {
  /// 均线的周期：图上当前那一档（1 年不在可选里，退到 1 日）。
  var interval: String
  /// 均线的 N：主图第一条 MA 的参数。
  var maLength: Int
  /// 大单墙的金额：这只品种 U 本位合约此刻生效的主力订单流门槛；还不知道就 nil。
  var wallThreshold: Double?
}

/// 创建页「条件」那一格能选的六样：前两样是价格提醒的两种判法，后四样是条件提醒。
enum AlertFormKind: String, Hashable, CaseIterable {
  case touch, close, funding, openInterest, ma, wall

  var title: String {
    switch self {
    case .touch: KanpanCore.Alert.Condition.touch.title
    case .close: KanpanCore.Alert.Condition.close.title
    case .funding: "资金费率"
    case .openInterest: "持仓量变化"
    case .ma: "均线"
    case .wall: "大单挂单墙"
    }
  }

  var isCondition: Bool { self != .touch && self != .close }

  static let priceKinds: [AlertFormKind] = [.touch, .close]
  static let conditionKinds: [AlertFormKind] = [.funding, .openInterest, .ma, .wall]

  init?(rule: AlertRule?) {
    switch rule {
    case .funding: self = .funding
    case .openInterestChange: self = .openInterest
    case .maCross: self = .ma
    case .orderflowWall: self = .wall
    default: return nil
    }
  }
}

extension AlertStore {
  /// 表单的「创建提醒 / 保存」落账。新建（图上十字线那颗「创建提醒」）与编辑（创建页底下
  /// 「当前提醒」那一行）共用这一处：建完顺手登记推送（有权限才登记）。
  /// 通知权限 2026-10-08 起不在这儿问了：改到创建页第一次露面时问（`AlertForm.askOnce`）——
  /// 点「创建提醒」那一下系统弹窗盖上来，人会以为提醒没建上。编辑（`editing` 给了 id）不碰推送。
  @discardableResult
  func commit(_ draft: AlertDraft, editing id: String? = nil) -> KanpanCore.Alert? {
    if let rule = draft.rule {
      if let id { return updateCondition(id: id, rule: rule, webhook: draft.webhook) }
      guard let alert = addCondition(symbol: draft.quote.symbol, rule: rule, webhook: draft.webhook) else { return nil }
      PushRegistration.startIfAuthorized()
      return alert
    }
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
    PushRegistration.startIfAuthorized()
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
///
/// 2026-09-27 条件提醒（`docs/条件提醒-协议-2026-09-27.md`）：登录了、又是币安 U 本位的品种，
/// 「条件」那一格从两段分段换成一个菜单，多出资金费率 / 持仓量变化 / 均线 / 大单挂单墙四样；
/// 换条件只换条件卡里上面那几行参数，别的不动。没登录或者别的市场，这一页和原来一模一样。
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
  /// 记录里的时间一律按上海 UTC+8 写（2026-09-28 起时区不再是设置项）。
  var zone: TZOffset = TZChoice.exchange.offsetMinutes
  /// 点一条价格提醒：推进它的编辑页。
  var onEditRecord: (String) -> Void = { _ in }
  /// 行尾垃圾桶删一条。
  var onDeleteRecord: (String) -> Void = { _ in }
  /// 条件提醒的默认值；nil = 这一页不给条件提醒（见 `ConditionAlertDefaults`）。
  var conditions: ConditionAlertDefaults? = nil
  var onSave: (AlertDraft) -> Void

  @State private var priceText = ""
  @State private var condition: KanpanCore.Alert.Condition = .touch
  @State private var kind: AlertFormKind = .touch
  @State private var fundingSide: AlertRule.Side = .above
  @State private var fundingText = "0.05"
  @State private var oiText = "3"
  @State private var maInterval = "1h"
  @State private var maLengthText = "20"
  @State private var maSide: AlertRule.Side = .above
  @State private var wallText = "1M"
  @State private var webhookURL = ""
  /// 这一页问过通知权限没有（`askOnce`）。
  @State private var askedPermission = false
  /// 内容与上下让位的高度：合起来就是这张表刚好装下整页要的高度（`alertFormFitHeight`）。
  @State private var contentHeight: CGFloat = 0
  @State private var chromeHeight: CGFloat = 0
  @Environment(\.alertFormFitHeight) private var fitHeight
  @State private var testing = false
  @State private var seeded = false
  @FocusState private var focus: Field?
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 页面左右边距（`panelPageInset` 按屏宽给 16 / 20，即 `Inset.page`）。
  @Environment(\.panelHPad) private var hPad

  private enum Field: Hashable { case price, url, param }

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
        if hasWebhook { webhookFootnote(quote) }
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
      .animation(.snappy, value: hasWebhook)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0; reportFit() }
    }
    // 量这一页上下被系统让掉的那两截（导航栏、底部安全区）。垫在键盘下面量：键盘起来时不算进去，
    // 不然一敲价格整张表就跟着键盘长高。
    .background {
      Color.clear
        .ignoresSafeArea(.keyboard)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } action: {
          chromeHeight = $0; reportFit()
        }
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    .background { AlertPageStyle.backdrop() }
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
      askOnce()
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

  /// 把「刚好装下这一页」的高度报给外面那张表（只有新建那张表接，`AlertComposeSheet`）。
  private func reportFit() {
    guard existing == nil, let fitHeight, contentHeight > 0 else { return }
    fitHeight(contentHeight + chromeHeight)
  }

  // ---------------------------------------------------------------- 通知权限

  /// 新建页第一次露面时问一次通知权限（2026-10-08）。没问过（`.notDetermined`）才会真弹，
  /// 问过的（允许或拒绝）`requestAuthorization` 直接回，所以整台机器上一辈子只弹一次；
  /// 编辑页不问。点「创建提醒」那一下不再问。
  private func askOnce() {
    guard existing == nil, !askedPermission else { return }
    askedPermission = true
    Task {
      await AlertNotifications.requestAuthorization()
      PushRegistration.startIfAuthorized()
    }
  }

  // ---------------------------------------------------------------- 预填

  private func seed(_ quote: PriceAlertQuote?) {
    guard !seeded else { return }
    seeded = true
    if let conditions {
      maInterval = conditions.interval
      maLengthText = String(conditions.maLength)
      // 回填用不舍位的写法：`units` 只留一位小数，不动直接保存会把门槛改小（深度审查 E-4）。
      if let wall = conditions.wallThreshold, wall >= 10_000 { wallText = AlertRule.editableAmount(wall) }
    }
    if let existing {
      if let target = existing.targetPrice {
        priceText = ReviewLabels.price(target, decimals: quote?.decimals)
      }
      condition = existing.condition
      kind = existing.condition == .close ? .close : .touch
      if existing.kind == .condition { seed(rule: existing.rule) }
      webhookURL = existing.webhook ?? ""
    } else if let initialPrice {
      priceText = quote?.label(initialPrice) ?? String(initialPrice)
    }
    // 没带价进来（预览、以后别的入口）直接对准价格框；图上带着价进来、或者编辑，先让人看全整页。
    if existing == nil, initialPrice == nil { focus = .price }
  }

  /// 编辑一条条件提醒：把它的条件摊回参数行。
  private func seed(rule: AlertRule?) {
    guard let picked = AlertFormKind(rule: rule) else { return }
    kind = picked
    switch rule {
    case let .funding(side, rate):
      fundingSide = side; fundingText = AlertRule.percent(rate, dp: 6)
    case let .openInterestChange(threshold):
      oiText = AlertRule.percent(threshold, dp: 4)
    case let .maCross(interval, length, side):
      maInterval = interval; maLengthText = String(length); maSide = side
    case let .orderflowWall(threshold):
      // 不舍位：编辑页不动门槛直接保存，存回去的仍是原数（深度审查 E-4）。
      wallText = AlertRule.decimal(threshold).map { AlertRule.editableAmount($0) } ?? ""
    default: break
    }
  }

  /// 「条件」那一格能选哪几样。编辑时只在同一类里换（价格提醒换不成条件提醒，反之亦然）。
  private var kinds: [AlertFormKind] {
    if let existing { return existing.kind == .condition ? AlertFormKind.conditionKinds : AlertFormKind.priceKinds }
    return conditions == nil ? AlertFormKind.priceKinds : AlertFormKind.priceKinds + AlertFormKind.conditionKinds
  }

  private func pick(_ next: AlertFormKind) {
    focus = nil
    withAnimation(.snappy) {
      kind = next
      if !next.isCondition { condition = next == .close ? .close : .touch }
    }
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
          // 和总表段头同一个写法：没有计价币的（美元指数）只写代号，不留一道斜杠。
          Text(AlertRecordText.pairName(key))
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
      // 换条件只换这几行参数；下面的「条件」那一格不动。
      switch kind {
      case .touch, .close: priceRows(quote)
      case .funding: fundingRows
      case .openInterest: openInterestRows
      case .ma: maRows
      case .wall: wallRows
      }
      AlertCardDivider()
      conditionRow
    }
  }

  @ViewBuilder private func priceRows(_ quote: PriceAlertQuote?) -> some View {
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
  }

  /// 「条件」：只有价格那两样时是原来的两段分段；有条件提醒时换成一个菜单（六样一段放不下）。
  private var conditionRow: some View {
    HStack(spacing: Space.m) {
      label("条件", term: .alertCondition)
      Spacer(minLength: Space.s)
      if kinds.count <= 2 {
        PanelSegment(options: kinds.map { ($0.title, $0) },
                     selection: kind, id: "alerts.new.condition",
                     track: AlertPageStyle.well(t)) { pick($0) }
      } else {
        Menu {
          ForEach(kinds, id: \.self) { item in
            Button { pick(item) } label: {
              if item == kind { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
            }
            .accessibilityIdentifier("alerts.new.kind." + item.rawValue)
          }
        } label: {
          menuLabel(kind.title)
        }
        .accessibilityIdentifier("alerts.new.condition")
      }
    }
    .padding(.horizontal, Inset.card)
    .padding(.vertical, PanelMetrics.vPad)
    .frame(minHeight: Inset.rowMin)
  }

  // ---------------------------------------------------------------- 条件提醒的参数行

  /// 资金费率：方向 + 费率（百分数，可以是负的，所以不用纯数字键盘）。
  @ViewBuilder private var fundingRows: some View {
    paramRow("方向") {
      Spacer(minLength: Space.s)
      PanelSegment(options: [("高于", AlertRule.Side.above), ("低于", AlertRule.Side.below)],
                   selection: fundingSide, id: "alerts.new.side",
                   track: AlertPageStyle.well(t)) { fundingSide = $0 }
    }
    AlertCardDivider()
    paramRow("费率") {
      inputWell(text: $fundingText, placeholder: "0.05", keyboard: .numbersAndPunctuation,
                id: "alerts.new.rate", title: "费率", suffix: "%")
    }
  }

  /// 1 小时持仓量变化超过 X%。
  private var openInterestRows: some View {
    paramRow("1 小时变化超过") {
      inputWell(text: $oiText, placeholder: "3", keyboard: .decimalPad,
                id: "alerts.new.oi", title: "变化超过", suffix: "%")
    }
  }

  /// 周期 + MA N + 站上 / 跌破。周期默认图上那一档，N 默认主图第一条 MA。
  @ViewBuilder private var maRows: some View {
    paramRow("周期") {
      Spacer(minLength: Space.s)
      Menu {
        ForEach(AlertRule.maIntervals, id: \.self) { raw in
          Button { maInterval = raw } label: {
            let text = Interval(rawValue: raw)?.display ?? raw
            if raw == maInterval { Label(text, systemImage: "checkmark") } else { Text(text) }
          }
        }
      } label: {
        menuLabel(Interval(rawValue: maInterval)?.display ?? maInterval)
      }
      .accessibilityIdentifier("alerts.new.interval")
    }
    AlertCardDivider()
    paramRow("均线") {
      inputWell(text: $maLengthText, placeholder: "20", keyboard: .numberPad,
                id: "alerts.new.length", title: "均线", prefix: "MA")
    }
    AlertCardDivider()
    paramRow("收盘") {
      Spacer(minLength: Space.s)
      PanelSegment(options: [("站上", AlertRule.Side.above), ("跌破", AlertRule.Side.below)],
                   selection: maSide, id: "alerts.new.side",
                   track: AlertPageStyle.well(t)) { maSide = $0 }
    }
  }

  /// 出现超过 X 的大单挂单墙。金额写 K / M / B，默认这只品种的主力订单流门槛。
  private var wallRows: some View {
    paramRow("金额超过") {
      inputWell(text: $wallText, placeholder: "1M", keyboard: .asciiCapable,
                id: "alerts.new.wall", title: "金额超过")
    }
  }

  private func paramRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(spacing: Space.m) {
      label(title)
      content()
    }
    .padding(.horizontal, Inset.card)
    .padding(.vertical, Space.xs)
    .frame(minHeight: Inset.rowMin)
  }

  private func menuLabel(_ text: String) -> some View {
    HStack(spacing: Space.xs) {
      Text(text)
        .font(TypeScale.body)
        .foregroundStyle(t.ink)
        .lineLimit(1)
      Image(systemName: "chevron.up.chevron.down")
        .font(TypeScale.caption)
        .foregroundStyle(t.ink3)
        .accessibilityHidden(true)
    }
    .frame(minHeight: Hit.min)
    .contentShape(Rectangle())
  }

  /// 参数的输入井：和价格井同一个画法（页面底色的井、小铅笔、聚焦描强调色）。
  private func inputWell(text: Binding<String>, placeholder: String, keyboard: UIKeyboardType,
                         id: String, title: String, prefix: String? = nil, suffix: String? = nil) -> some View {
    let focused = focus == .param
    return HStack(spacing: Space.s) {
      Image(systemName: "pencil")
        .font(TypeScale.caption)
        .foregroundStyle(focused ? t.amber : t.ink3)
        .accessibilityHidden(true)
      if let prefix {
        Spacer(minLength: 0)
        Text(prefix)
          .font(TypeScale.caption)
          .foregroundStyle(t.ink3)
      }
      TextField(placeholder, text: text)
        .keyboardType(keyboard)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .multilineTextAlignment(.trailing)
        .font(TypeScale.bodyEmph).monospacedDigit()
        .foregroundStyle(t.ink)
        .focused($focus, equals: .param)
        .fixedSize(horizontal: prefix != nil, vertical: false)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
      if let suffix {
        Text(suffix)
          .font(TypeScale.caption)
          .foregroundStyle(t.ink3)
      }
    }
    .padding(.horizontal, Space.m)
    .padding(.vertical, Space.s)
    .frame(maxWidth: .infinity)
    .background {
      let well = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
      well.fill(AlertPageStyle.well(t))
        .overlay { well.fill(focused ? t.amberSoft : .clear) }
        .overlay { well.strokeBorder(focused ? t.amberLine : .clear, lineWidth: 1) }
    }
    .animation(.easeOut(duration: Self.focusFade), value: focused)
    .contentShape(Rectangle())
    .onTapGesture { focus = .param }
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
      well.fill(AlertPageStyle.well(t))
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

  /// 填了地址就发、空着就不发——没有单独的开关（收设置项 E 组，2026-09-28）。
  private var notifyCard: some View {
    AlertGroupCard {
      HStack(spacing: Space.m) {
        label("网络回调", term: .webhook)
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
          .accessibilityLabel("网络回调地址")
      }
      .padding(.horizontal, Inset.card)
      .frame(minHeight: Inset.rowMin)
      .contentShape(Rectangle())
      .onTapGesture { focus = .url }
    }
  }

  private var trimmedWebhook: String { webhookURL.trimmingCharacters(in: .whitespacesAndNewlines) }
  /// 地址框里有字就算要发（写得不对主按钮灰着，不会悄悄当成不发）。
  private var hasWebhook: Bool { !trimmedWebhook.isEmpty }

  /// 卡片下面靠右一颗「发一条测试」。结果走全局提示条，不占页面。
  /// 「触发时向这个地址发一条 JSON」原来写在它左边，2026-09-28 挪进「Webhook」的问号卡。
  private func webhookFootnote(_ quote: PriceAlertQuote?) -> some View {
    let valid = KanpanCore.Alert.isValidWebhook(webhookURL)
    return HStack(spacing: Space.s) {
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
    let now = Date().timeIntervalSince1970 * 1000
    // 不带推送内容也不带备注：发的就是默认模板，和真触发时一模一样。
    let draft: KanpanCore.Alert
    if kind.isCondition {
      guard let rule else { return }
      draft = KanpanCore.Alert.condition(symbol: quote.symbol, rule: rule, now: now)
    } else {
      draft = KanpanCore.Alert.price(
        symbol: quote.symbol, target: target ?? price, current: quote.price,
        label: quote.current(target ?? price), now: now, condition: condition)
    }
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

  /// 能交了吗：品种认得、价是正数（条件提醒：参数在协议的范围里）、填了 Webhook 地址时地址合法。
  private func draft(_ quote: PriceAlertQuote?) -> AlertDraft? {
    guard let quote else { return nil }
    let url = trimmedWebhook
    if hasWebhook, !KanpanCore.Alert.isValidWebhook(url) { return nil }
    if kind.isCondition {
      guard let rule else { return nil }
      return AlertDraft(quote: quote, target: 0, condition: .touch, webhook: hasWebhook ? url : nil, rule: rule)
    }
    guard let target else { return nil }
    return AlertDraft(quote: quote, target: target, condition: condition,
                      webhook: hasWebhook ? url : nil)
  }

  /// 参数行拼出来的条件；写得不成数、超出协议范围都是 nil（主按钮灰着）。
  private var rule: AlertRule? {
    let built: AlertRule? = switch kind {
    case .touch, .close: nil
    case .funding: AlertRule.ratio(percent: fundingText).map { .funding(side: fundingSide, rate: $0) }
    case .openInterest: AlertRule.ratio(percent: oiText).map { .openInterestChange(threshold: $0) }
    case .ma: Int(maLengthText.trimmingCharacters(in: .whitespaces)).map { .maCross(interval: maInterval, length: $0, side: maSide) }
    case .wall: AlertRule.amount(wallText).map { .orderflowWall(threshold: $0) }
    }
    return built?.checked
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
            onTap: alert.kind == .price || (alert.kind == .condition && alert.rule?.isKnown == true)
              ? { onEditRecord(alert.id) } : nil,
            onDelete: { withAnimation(.snappy) { onDeleteRecord(alert.id) } })
          .transition(AlertRecordRow.removal)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.records")
  }

  // ---------------------------------------------------------------- 零件

  private func label(_ text: String, term: GlossaryTerm? = nil) -> some View {
    HStack(spacing: 0) {
      Text(text)
      if let term { TermMark(term, theme: t) }
    }
    .font(TypeScale.body).foregroundStyle(t.ink).lineLimit(1).fixedSize()
  }
}

extension EnvironmentValues {
  /// 新建提醒页把「刚好装下整页」的高度报给它所在的那张表（表的停靠高度跟内容走）。nil = 没人接。
  @Entry var alertFormFitHeight: ((CGFloat) -> Void)? = nil
}

/// 主按钮的按压反馈：按下缩一点、松手弹回。只动比例，不动颜色（禁用态由 `PanelDisabled` 管）。
struct AlertPressStyle: ButtonStyle {
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
  /// 新建页刚好装下的高度（量出来的，`AlertForm.reportFit`）。nil = 还没量到。
  @State private var fitted: CGFloat?
  @State private var detent: PresentationDetent = .large
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss

  /// 停靠高度（2026-10-08）：刚好装下新建页那一档 + 拉满。推进「全部预警」或编辑页时拉满，退回来再落回那一档。
  private var detents: Set<PresentationDetent> {
    var out: Set<PresentationDetent> = [.large]
    if let fitted { out.insert(.height(fitted)) }
    return out
  }

  private var pushed: Bool { showAll || editing != nil }

  /// 量到新的高度：原来就停在「刚好」那一档（或第一次量到）才跟着走；人已经拉满了就不往回收。
  private func fit(_ height: CGFloat) {
    let next = height.rounded(.up)
    guard abs(next - (fitted ?? 0)) >= 1 else { return }
    let following = fitted.map { detent == .height($0) } ?? true
    fitted = next
    if following, !pushed { detent = .height(next) }
  }

  var body: some View {
    let key = context.quote(symbol)?.symbol ?? InstrumentID.canonical(symbol)
    var inner = context
    // 总表空着时那颗「去创建」：退回这张创建页。
    inner.onCreate = { showAll = false }
    return NavigationStack {
      AlertForm(initialSymbol: symbol, initialPrice: price, resolve: context.quote,
                prepare: context.prepareQuote, release: context.releaseQuote,
                records: AlertRecordText.records(store.all, symbol: key),
                zone: context.zone,
                onEditRecord: { editing = $0 },
                onDeleteRecord: { store.remove(id: $0) },
                conditions: context.conditions(key)) { draft in
        if let alert = store.commit(draft) { Haptics.success(); onCreated(alert) }
      }
      .environment(\.alertFormFitHeight) { fit($0) }
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
        AlertListPage(store: store, context: inner, presentedAsSheet: false)
      }
      .navigationDestination(item: $editing) { id in
        if let alert = store.all.first(where: { $0.id == id }) {
          AlertForm(initialSymbol: InstrumentID(alert.symbol).display, existing: alert,
                    resolve: context.quote, prepare: context.prepareQuote,
                    release: context.releaseQuote, zone: context.zone,
                    conditions: context.conditions(InstrumentID.canonical(alert.symbol))) { draft in
            if store.commit(draft, editing: id) != nil { Haptics.success() }
          }
        }
      }
    }
    .tint(t.amber)
    .panelPageInset()
    .presentationDetents(detents, selection: $detent)
    .onChange(of: pushed) { _, now in
      withAnimation(.snappy) { detent = now ? .large : (fitted.map { .height($0) } ?? .large) }
    }
  }
}

/// 宿主那一张提醒表开的是哪一样。
enum AlertSheetRoute: Identifiable, Equatable {
  /// 提醒总表（`hkline://alerts`、通知点开）。
  case list
  /// 新建提醒（图上十字线那颗药丸），带着品种的代号与那一口价。
  case new(symbol: String, price: Double)
  /// 顶栏铃铛那张「提醒」表（列表 | 日志，2026-10-05）：图上那只与开表那一刻的最新价。
  case hub(symbol: String, price: Double?)

  var id: String {
    switch self {
    case .list: "list"
    case let .new(symbol, price): "new:\(symbol):\(price)"
    case let .hub(symbol, _): "hub:\(symbol)"
    }
  }

  /// 这张表里有没有要现价的页（新建 / 编辑）。只有总表的那张没有。
  var needsLiveQuote: Bool { self != .list }
}

/// 宿主 `sheet(item:)` 里那一层：按路由摆总表、新建页或「提醒」表。非泛型、一个类型，
/// 免得在 `MainScreen` 的修饰器链上再多挂一张表（文件头那条层数上限）。
struct AlertSheetView: View {
  var route: AlertSheetRoute
  @ObservedObject var store: AlertStore
  var context: AlertListContext
  /// 「提醒」表的日志（账号那份缓存 + 拉取）。
  var log: AlertLogModel
  var owner: UUID?
  var fetch: AlertLogModel.Fetch?
  var onCreated: (KanpanCore.Alert) -> Void
  var onClearFailed: () -> Void = {}

  var body: some View {
    switch route {
    case .list:
      AlertListPage(store: store, context: context, presentedAsSheet: true)
    case let .new(symbol, price):
      AlertComposeSheet(store: store, context: context, symbol: symbol, price: price,
                        onCreated: onCreated)
    case let .hub(symbol, price):
      AlertHubSheet(store: store, context: context, symbol: symbol, price: price, log: log,
                    owner: owner, fetch: fetch, onCreated: onCreated, onClearFailed: onClearFailed)
    }
  }
}
