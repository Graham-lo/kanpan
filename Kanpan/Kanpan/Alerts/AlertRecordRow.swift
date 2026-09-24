import KanpanCore
import SwiftUI

// ============================================================ 提醒页的分组卡片与记录行
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
/// 划出删除的砖块画在行底下，卡片的圆角把它一起裁掉。
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

/// 卡片外、卡片上方的分组标题（「提醒记录」「生效中」）：`PanelGroupTitle` 同一支笔，
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

/// 一条提醒记录：状态圆点 + 标题 + 一行灰字，右边随调用方放东西（箭头、再次提醒、条件…）。
///
/// 创建页底下的「提醒记录」与提醒总表是同一份零件，只是标题与灰字按场合取
/// （`AlertRecordText`）：创建页只列这一只品种，标题里不再写品种名；总表跨品种，要写。
struct AlertRecordRow<Trailing: View>: View {
  var alert: KanpanCore.Alert
  var title: String
  var meta: String
  var divider: Bool = true
  /// 点一行。nil 就不可点（已触发的记录）。
  var onTap: (() -> Void)? = nil
  @ViewBuilder var trailing: () -> Trailing

  @Environment(\.panelTheme) private var t

  /// 状态圆点的直径。
  static var dot: CGFloat { Space.xs + Space.xxs }

  var body: some View {
    if let onTap {
      Button(action: onTap) { row }
        .buttonStyle(.plain)
        .accessibilityIdentifier("alerts.record")
    } else {
      row
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.record")
    }
  }

  private var row: some View {
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
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(t.ink3)
              .accessibilityLabel("Webhook")
              .accessibilityIdentifier("alerts.row.webhook")
          }
        }
      }
      Spacer(minLength: Space.s)
      trailing()
    }
    .padding(.horizontal, Inset.card)
    .padding(.vertical, Space.s)
    .frame(minHeight: Inset.rowMin)
    .contentShape(Rectangle())
    .overlay(alignment: .bottom) {
      if divider { AlertCardDivider(leading: Self.dot + Space.m) }
    }
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
  /// - 生效中：创建页写条件（「碰到」「收盘穿过」）；总表写「生效中」——条件在它右边那颗
  ///   可改的胶囊上，不复述一遍（2026-09-24 审查 6.4）。
  /// - 已触发：「已触发 · 9/24 16:44 · 现价 84,670.5」。
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
      return conditionInline ? "已暂停 · " + alert.condition.title : "已暂停"
    case .active:
      return conditionInline ? alert.condition.title : "生效中"
    }
  }

  /// 创建页记录的顺序：生效中的在前、已触发的在后，各按创建时间倒序。复盘到点不列。
  static func records(_ alerts: [KanpanCore.Alert], symbol: String) -> [KanpanCore.Alert] {
    let key = InstrumentID.canonical(symbol)
    let mine = alerts.filter { $0.kind != .reviewDue && InstrumentID.canonical($0.symbol) == key }
    return mine.sorted {
      let a = $0.status == .fired ? 1 : 0, b = $1.status == .fired ? 1 : 0
      return a != b ? a < b : $0.created > $1.created
    }
  }

  /// 品种卡第二行：「币安 · USDT 永续」「Coinbase · 现货」。按规范键里的交易所与市场拼。
  static func venueLine(_ symbol: String) -> String {
    let id = InstrumentID(symbol)
    let venue = ["binance": "币安", "coinbase": "Coinbase", "okx": "OKX"][id.venue] ?? id.venue.capitalized
    let product: String = switch id.market {
    case "usd_m": "USDT 永续"
    case "coin_m": "币本位永续"
    case "spot": "现货"
    default: id.productLabel
    }
    return venue + " · " + product
  }
}
