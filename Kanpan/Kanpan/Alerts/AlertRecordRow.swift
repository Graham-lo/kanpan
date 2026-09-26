import KanpanCore
import KanpanNetwork
import SwiftUI

// ============================================================ 提醒页的分组卡片与记录行
//
// 2026-09-25 v3：行上只剩一枚垃圾桶（去掉左划、「盯一个」、条件菜单、「再次提醒」），
// 已触发的不再列（触发即删）；总表按「价格提醒 / 画线提醒」分两组、组里按品种分段。
//
// 2026-09-25 v2（用户看完第一版真机：「布局不太合理、做的有点粗糙」）：创建提醒页与提醒总表
// 整页只用一种语言——iOS 设置那种 inset grouped 的分组卡片。第一版一页里混着「左标签 +
// 右侧填色输入框」「小药丸」「大片空白」三种写法，这里把卡片、卡片里的行、行间发丝线、
// 记录行收成一份零件，创建页（`AlertForm`）和总表（`AlertListPage`）共用。
//
// 尺寸一律取 `DesignTokens`：卡片 `Radius.m`、行高 `Inset.rowMin`、行内左右 `Inset.card`。

/// 提醒这几页的页面底与卡片底。
///
/// 浅色：页面 `raised`、卡片 `raised2`（三套皮肤浅色下两者分得开）。
/// 深色：`raised` 和 `raised2` 只差一两个色阶（青苔深 `#131C18` / `#1A241F`），卡片几乎化进
/// 页面里；深色下页面退到更深的 `app`，卡片仍是 `raised2`——不新造颜色，只换页面那一层。
enum AlertPageStyle {
  static func background(_ t: PanelTheme) -> Color { t.dark ? t.app : t.raised }
  static func card(_ t: PanelTheme) -> Color { t.raised2 }
}

/// 一张分组卡片：`raised2` 底、`Radius.m` 圆角，里头的行首尾相接。
struct AlertGroupCard<Content: View>: View {
  @ViewBuilder var content: () -> Content
  @Environment(\.panelTheme) private var t

  var body: some View {
    VStack(spacing: 0) { content() }
      .frame(maxWidth: .infinity)
      .background(AlertPageStyle.card(t))
      .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
  }
}

/// 分组卡片摊开成一片一片（总表是 `LazyVStack`，整张卡片没法包住懒加载的行）：
/// 每片同一个 `raised2` 底，卡片第一片上圆角、最后一片下圆角，拼起来和 `AlertGroupCard` 一样。
struct AlertCardSlice: ViewModifier {
  var top: Bool
  var bottom: Bool
  @Environment(\.panelTheme) private var t

  func body(content: Content) -> some View {
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: top ? Radius.m : 0, bottomLeadingRadius: bottom ? Radius.m : 0,
      bottomTrailingRadius: bottom ? Radius.m : 0, topTrailingRadius: top ? Radius.m : 0,
      style: .continuous)
    content
      .frame(maxWidth: .infinity)
      .background(AlertPageStyle.card(t))
      .clipShape(shape)
  }
}

/// 卡片里行与行之间那条发丝线：从标签那一格起，不通到卡片左缘（iOS 分组表的惯例）。
struct AlertCardDivider: View {
  /// 左边再让出多少（记录行前面有一颗圆点，线从文字起）。
  var leading: CGFloat = 0
  @Environment(\.panelTheme) private var t

  var body: some View {
    Rectangle().fill(t.hair).frame(height: 1)
      .padding(.leading, Inset.card + leading)
  }
}

/// 卡片外、卡片上方的分组标题（「当前提醒 2」「价格提醒 3」）：`PanelGroupTitle` 同一支笔，
/// 左缘和卡片对齐。
struct AlertCardTitle: View {
  var text: String
  @Environment(\.panelTheme) private var t

  var body: some View {
    Text(text)
      .font(PanelFont.group)
      .tracking(1)
      .foregroundStyle(t.ink3)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// 一条提醒记录：状态圆点 + 标题 + 一行灰字，行尾只有一枚垃圾桶。
///
/// 2026-09-25 v3（用户：「行上只给一个删除 icon，别的操作都不要」）：左划删除、「盯一个」、
/// 条件菜单、「再次提醒」全部去掉——同一个动作只留一个入口，删除就是行尾那枚垃圾桶。
/// 创建页底下的「当前提醒」与提醒总表是同一份零件，只是标题与灰字按场合取
/// （`AlertRecordText`）：创建页只列这一只品种，标题里不再写品种名；总表跨品种，
/// 品种写在分组的段头上（`AlertSymbolHeader`），行里也不写。
///
/// 点行（有 `onTap` 时）和垃圾桶是两颗分开的按钮：整行作为一个容器，里头两个元素
/// 各自可点、各自可被辅助功能与 UI 测试找到。
struct AlertRecordRow: View {
  var alert: KanpanCore.Alert
  var title: String
  var meta: String
  var divider: Bool = true
  /// 点一行。nil 就不可点。
  var onTap: (() -> Void)? = nil
  var onDelete: () -> Void

  @Environment(\.panelTheme) private var t

  /// 状态圆点的直径。
  static var dot: CGFloat { Space.xs + Space.xxs }
  /// 删掉一行时的去向：往右（垃圾桶那一侧）滑走并淡出；配合 `withAnimation(.snappy)`，
  /// 下面的行顺势补上来。
  static var removal: AnyTransition { .opacity.combined(with: .move(edge: .trailing)) }

  var body: some View {
    HStack(spacing: 0) {
      if let onTap {
        Button(action: onTap) { content }
          .buttonStyle(.plain)
          .accessibilityIdentifier("alerts.record.open")
      } else {
        content
      }
      AlertDeleteButton(action: onDelete)
    }
    // 垃圾桶自带 44 的点击区，图形在点击区正中；右边只留 `Space.xs`，
    // 让图形的右缘大致落在 `Inset.card` 那条线上，和上面卡片里的行尾对齐。
    .padding(.leading, Inset.card)
    .padding(.trailing, Space.xs)
    .frame(minHeight: Inset.rowMin)
    .overlay(alignment: .bottom) {
      if divider { AlertCardDivider(leading: Self.dot + Space.m) }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.record")
  }

  private var content: some View {
    HStack(spacing: Space.m) {
      Circle()
        .fill(alert.isActive ? t.amber : t.ink3)
        .frame(width: Self.dot, height: Self.dot)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(title)
          .font(TypeScale.body).monospacedDigit()
          .foregroundStyle(t.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        HStack(spacing: Space.xs) {
          Text(meta)
            .font(TypeScale.caption).monospacedDigit()
            .foregroundStyle(t.ink3)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
          // 填了 Webhook 的在灰字末尾带一枚链接记号：读得出「这条响了还会往外发」。
          if alert.webhook != nil {
            Image(systemName: "link")
              .font(TypeScale.caption2Emph)
              .foregroundStyle(t.ink3)
              .accessibilityLabel("Webhook")
              .accessibilityIdentifier("alerts.row.webhook")
          }
        }
      }
      Spacer(minLength: Space.s)
    }
    .padding(.vertical, Space.s)
    .frame(minHeight: Inset.rowMin)
    .contentShape(Rectangle())
  }
}

/// 行尾那枚垃圾桶：平时 `ink3`，按下变强调色；字号和搜索页「清除历史」那枚同一档
/// （`TypeScale.footnote`），点击区 44。删除不再二次确认——一条提醒随手就能重建，
/// 确认框反倒是多一步；按下时给一记警示触感，读得出「删掉了」。
struct AlertDeleteButton: View {
  var action: () -> Void

  var body: some View {
    Button {
      Haptics.warning()
      action()
    } label: {
      Image(systemName: "trash")
        .font(TypeScale.footnote)
    }
    .buttonStyle(AlertDeleteStyle())
    .accessibilityLabel("删除")
    .accessibilityIdentifier("alerts.delete")
  }
}

private struct AlertDeleteStyle: ButtonStyle {
  @Environment(\.panelTheme) private var t

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(configuration.isPressed ? t.amber : t.ink3)
      .hitTarget()
  }
}

/// 总表里一个品种的段头：徽章 + 「BTC/USDT」+ 场所小字（「币安 · USDT 永续」），
/// 右边一枚灰色数量。和创建页顶上那张品种卡、自选列表的行是同一套字与节奏：
/// 名字 `TypeScale.bodyEmph`、小字 `TypeScale.caption`、行高 `Inset.rowMin`、左右 `Inset.card`。
struct AlertSymbolHeader: View {
  var symbol: String
  var count: Int
  @Environment(\.panelTheme) private var t

  var body: some View {
    HStack(spacing: Space.s) {
      CoinBadge(base: SymbolInfo.placeholder(symbol: symbol).base, size: ControlMetrics.badge)
        .accessibilityHidden(true)
      Text(AlertRecordText.pairName(symbol))
        .font(TypeScale.bodyEmph)
        .foregroundStyle(t.ink)
        .lineLimit(1)
        .layoutPriority(1)
      Text(AlertRecordText.venueLine(symbol))
        .font(TypeScale.caption)
        .foregroundStyle(t.ink3)
        .lineLimit(1)
      Spacer(minLength: Space.s)
      Text("\(count)")
        .font(TypeScale.caption).monospacedDigit()
        .foregroundStyle(t.ink3)
        .contentTransition(.numericText())
    }
    .padding(.horizontal, Inset.card)
    .frame(minHeight: Inset.rowMin)
    .overlay(alignment: .bottom) { AlertCardDivider() }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("alerts.symbol")
  }
}

/// 记录行的字。纯函数，单测直接调。
enum AlertRecordText {
  /// 标题。
  ///
  /// - `withSymbol == false`（创建页，只列这一只）：价格提醒「跌到 79,916.2」，
  ///   画线提醒「触到你画的水平线」——品种名已经写在头上那张品种卡里。
  /// - `withSymbol == true`（总表，跨品种）：「BTC 跌到 79,916.2」「BTC · 水平线」。
  static func title(_ alert: KanpanCore.Alert, withSymbol: Bool) -> String {
    switch alert.kind {
    case .price:
      // 标题末尾那串价补上千分位。老提醒存的是不带分隔的写法，这里在显示时补，
      // `grouped` 对已经带分隔的串原样返回（视觉审查 2.9 #3）。
      var parts = alert.title.split(separator: " ").map(String.init)
      if let last = parts.last { parts[parts.count - 1] = grouped(last) }
      if !withSymbol, parts.count > 1 { parts.removeFirst() }
      return parts.joined(separator: " ")
    case .drawing:
      let name = KanpanCore.Alert.name(of: alert.symbol)
      if withSymbol {
        guard let line = alert.lineName else { return name }
        return name + " · " + line
      }
      guard let line = alert.lineName else { return "画线提醒" }
      return "触到你画的" + line
    case .reviewDue:
      return alert.title.isEmpty ? KanpanCore.Alert.name(of: alert.symbol) : alert.title
    }
  }

  /// 标题下那行灰字。
  ///
  /// - 生效中：写条件（「价格达到」「收盘穿过」）。v3 起总表行上没有条件胶囊了，
  ///   两处都写条件（`conditionInline: true`）；`false` 只剩「生效中」这一种旧写法。
  /// - 已触发：「已触发 · 9/24 16:44 · 现价 84,670.5」。v3 触发即删，界面上基本见不到，
  ///   只在发出通知与删掉之间那一拍存在。
  /// - 复盘到点：「到期 9/24 16:44」/「已到点 · 9/24 16:44」。
  static func meta(_ alert: KanpanCore.Alert, zone: TZOffset, decimals: Int?,
                   conditionInline: Bool) -> String {
    if alert.kind == .reviewDue {
      let at = alert.status == .fired ? alert.firedAt ?? alert.dueAt : alert.dueAt
      let time = at.map { ReviewLabels.dayTime(ms: Int64($0), offsetMinutes: zone) } ?? ""
      return alert.status == .fired ? "已到点 · " + time : "到期 " + time
    }
    switch alert.status {
    case .fired:
      var parts = ["已触发"]
      if let at = alert.firedAt { parts.append(ReviewLabels.dayTime(ms: Int64(at), offsetMinutes: zone)) }
      if let price = alert.firedPrice {
        parts.append("现价 " + AlertMessage.groupedPrice(price, decimals: decimals))
      }
      return parts.joined(separator: " · ")
    case .paused:
      // 画线提醒只有「线找不到」这一种暂停（`AlertArchive.reconcile`）。
      let label = AlertArchive.isDrawingMissing(alert) ? AlertArchive.drawingMissingNote : "已暂停"
      return conditionInline ? label + " · " + alert.condition.title : label
    case .active:
      return conditionInline ? alert.condition.title : "生效中"
    }
  }

  /// 界面上看得见的：已触发的不列（v3 触发即删，删掉之前那一拍也不露脸）；
  /// 复盘到点例外——它的「已到点」本来就是给人看的，跟着复盘记录一天后清。
  static func isVisible(_ alert: KanpanCore.Alert) -> Bool {
    alert.kind == .reviewDue || alert.status != .fired
  }

  /// 创建页底下「当前提醒」：这一只品种还没触发的价格与画线提醒，按创建时间倒序。
  /// 复盘到点不列。
  static func records(_ alerts: [KanpanCore.Alert], symbol: String) -> [KanpanCore.Alert] {
    let key = InstrumentID.canonical(symbol)
    return alerts
      .filter { $0.kind != .reviewDue && $0.status != .fired && InstrumentID.canonical($0.symbol) == key }
      .sorted { $0.created > $1.created }
  }

  /// 总表的一段：一组提醒按品种分好（段里按创建时间倒序，段与段按各自最新那条倒序）。
  struct Section: Equatable, Identifiable {
    var kind: KanpanCore.Alert.Kind
    /// 按品种分的组。复盘到点那一段不分品种，只有一组、`symbol` 为空。
    var groups: [Group]
    var count: Int { groups.reduce(0) { $0 + $1.alerts.count } }
    var id: String { kind.rawValue }
    var title: String {
      switch kind {
      case .price: "价格提醒 \(count)"
      case .drawing: "画线提醒 \(count)"
      case .reviewDue: "复盘到点 \(count)"
      }
    }
  }

  struct Group: Equatable, Identifiable {
    var symbol: String
    var alerts: [KanpanCore.Alert]
    var id: String { symbol }
  }

  /// 「全部预警」的分段：价格提醒、画线提醒两组，有复盘到点再单列一段；空的段不出。
  static func sections(_ alerts: [KanpanCore.Alert]) -> [Section] {
    let visible = alerts.filter(isVisible)
    var out: [Section] = []
    for kind in [KanpanCore.Alert.Kind.price, .drawing] {
      let mine = visible.filter { $0.kind == kind }.sorted { $0.created > $1.created }
      guard !mine.isEmpty else { continue }
      var order: [String] = []
      var bySymbol: [String: [KanpanCore.Alert]] = [:]
      for alert in mine {
        let key = InstrumentID.canonical(alert.symbol)
        if bySymbol[key] == nil { order.append(key) }
        bySymbol[key, default: []].append(alert)
      }
      out.append(Section(kind: kind, groups: order.map { Group(symbol: $0, alerts: bySymbol[$0]!) }))
    }
    let due = visible.filter { $0.kind == .reviewDue }
      .sorted { ($0.dueAt ?? $0.created) > ($1.dueAt ?? $1.created) }
    if !due.isEmpty { out.append(Section(kind: .reviewDue, groups: [Group(symbol: "", alerts: due)])) }
    return out
  }

  /// 段头上的品种名：「BTC/USDT」「BTC/USD」，和创建页品种卡同一个写法。
  static func pairName(_ symbol: String) -> String {
    let info = SymbolInfo.placeholder(symbol: InstrumentID.canonical(symbol))
    return info.quote.isEmpty ? info.base : info.base + "/" + info.quote
  }

  /// 品种卡第二行：「币安 · USDT 永续」「<交易所> · 现货」。按规范键里的交易所与市场拼；
  /// 交易所的中文名只从 `VenueRegistry` 取（`Tools/check-venue-isolation.sh`：这一层不许点名）。
  static func venueLine(_ symbol: String) -> String {
    let id = InstrumentID(symbol)
    let venue = VenueRegistry.descriptor(id.venue)?.displayName ?? id.venue.uppercased()
    let product: String = switch id.market {
    case "usd_m": "USDT 永续"
    case "coin_m": "币本位永续"
    case "spot": "现货"
    default: id.productLabel
    }
    return venue + " · " + product
  }
}
