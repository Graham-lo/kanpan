import SwiftUI
import KanpanCore
import KanpanNetwork

// ============================================================ 品种行（全 app 共用）
//
// UI 审查 2026-09-24（汇总 §1 第 8 条、静态审查 §2.6 / §3.3–3.5）查出来品种行有两种长相、
// 四份手抄：自选页和板块内品种表各抄一份「琉璃行」，搜索页和品种整页共用一份「整页行」；
// 抄着抄着漂开了——搜索与整页的价格没有千分位、板块那份写「额」而自选写「成交额」、
// 板块没有「新」、缺值药丸两种画法、跌幅有的写「▼」有的写「−」。
//
// 现在全收到这一个文件里：
//
// - 数字写法一处（`SymbolRowText`）：价格千分位 + 品种自己的小数位，涨跌一律带「+ / −」
//   （U+2212），不再用小三角说方向。数字一律 SF Pro 等宽数字，不用 SF Mono。
// - 涨跌药丸一种（`ChangePill`）：列表、板块、长按预览卡同一颗。颜色取 `PanelTheme.up / down`。
// - 行两种排法，零件同一套：
//   - `LiuliSymbolRow`：自选分类页与板块内品种表（用户定稿的「琉璃」版，66 高、徽章 33 带光晕、
//     价格比名字大一档）。
//   - `SymbolRowView`：搜索页与品种整页（行尾一颗星，名字带搜索命中高亮，徽章 `ControlMetrics.listBadge`）。
// - 左右边距跟页面走（`.pageHorizontalInset()`：16 Pro 16、Pro Max 20），行高不低于 44。

// MARK: - 数字写法

enum SymbolRowText {
  /// 缺值一律写这个（静态审查 §2.6「缺值符号」：列表「—」、预览卡「--」两种 → 一种）。
  static let missing = "—"
  /// 副文案里两段之间的分隔（自选页定下的写法，板块那份「 · 」跟着改）。
  static let separator = "  ·  "

  /// 价格：品种自己的小数位（没有就按大小退回共用那把梯子）+ 千分位。
  static func price(_ price: Double, decimals: Int?) -> String {
    guard price.isFinite else { return missing }
    return grouped(fmtPrice(price, decimals: decimals ?? priceDecimalsFallback(price)))
  }

  /// 涨跌额：带「+ / −」、千分位。四舍五入后是零的写「+0.00」，不写「−0.00」。
  static func signedAmount(_ amount: Double, decimals: Int) -> String {
    guard amount.isFinite else { return missing }
    let magnitude = grouped(toFixed(abs(amount), decimals))
    let zero = !magnitude.contains { $0 != "0" && $0 != "." && $0 != "," }
    return (amount < 0 && !zero ? "\u{2212}" : "+") + magnitude
  }
}

// MARK: - 涨跌药丸

/// 一颗涨跌药丸：实心涨跌色底、反白的数，等宽一列。
///
/// 自选页、板块内品种表、长按预览卡三处同一颗（静态审查 §3.4「预览卡涨跌药丸」）。
/// 2026-09-25 用户拿富途式的自选表当参照，把琉璃行右边改成「价格在前、涨跌幅在后」横排：
/// 药丸从淡底描边改成实心块，宽度固定，一列药丸的左右缘在同一条线上，扫一眼就是一列涨跌。
/// 方向只靠「+ / −」和颜色说，不再在前面挂小三角（视觉审查 §3 第 4 条：同一个数三种写法）。
/// 字用 `theme.badgeInk`（浅色白、深色近黑），和分类条选中格压在强调色上的字一个口径。
struct ChangePill: View {
  /// 只拿来判「有没有」与「涨还是跌」。
  let value: Double
  /// 已经写好的带符号文字（`changePercentText` 或 `SymbolRowText.signedAmount`）。
  let text: String
  /// 还在路上：药丸只剩一块底，不写字（写「—」会被读成「没有涨跌幅」）。
  /// 为 `false` 时缺值写「—」（已下架、停牌这种确实没有的）。
  var pending = false
  var id: String? = nil

  @Environment(\.panelTheme) private var theme
  /// 固定宽：`−12.34%` 这种最长的也放得下；字号放大时跟着长。
  @ScaledMetric(relativeTo: .footnote) private var width: CGFloat = 72
  @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = ControlMetrics.pillHeight

  var body: some View {
    let finite = value.isFinite
    // 方向按写出来的那个数判，不按原始值：−0.004% 写出来是「+0.00%」，底色也得跟着算涨，
    // 否则一颗绿底上写着「+」（红涨绿跌时）会被读成「涨」和「跌」各说各的。
    let up = !(text.hasPrefix("\u{2212}") || text.hasPrefix("-"))
    let tint = finite ? (up ? theme.up : theme.down) : SymbolRowInk.rule(theme)
    Text(finite ? text : SymbolRowText.missing)
      .font(TypeScale.controlOn).monospacedDigit()
      .lineLimit(1).minimumScaleFactor(0.8)
      .foregroundStyle(finite ? theme.badgeInk : (pending ? .clear : SymbolRowInk.faint(theme)))
      .padding(.horizontal, Space.xs)
      .frame(width: width, height: height)
      .background(tint, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
      .accessibilityIdentifier(id ?? "")
  }
}

// MARK: - 字与墨

/// 品种行上的字。字号全在阶梯上（UI 审查 2026-09-24：13.5 → 13、15.5 → 15、9 / 10 → 11）。
enum SymbolRowFont {
  /// 琉璃行的品种名：13 semibold（原 13.5，只吸附到阶梯，比例不变）。
  static let liuliName = ScaledFont(TypeScale.footnote.size, .semibold, relativeTo: .footnote)
  /// 琉璃行的价格：15 medium（原 15.5）。
  static let liuliPrice = TypeScale.bodyEmph
  /// 计价币、副文案：11（下限；原 9 / 10）。
  static let small = TypeScale.caption2
}

/// 琉璃两页（自选、板块）共用的两支弱墨，公式和它们各自的 skin 一字不差。
enum SymbolRowInk {
  /// 比 ink3 再弱一档：计价币、缺值。
  static func faint(_ theme: PanelTheme) -> Color { Color(hex: theme.seed.ink3).opacity(0.7) }
  /// 发丝线、缺值药丸的底。
  static func rule(_ theme: PanelTheme) -> Color {
    Color(hex: theme.seed.ink).opacity(theme.dark ? 0.11 : 0.09)
  }
}

// MARK: - 琉璃行的徽章

/// 品牌色晕 + `CoinBadge` + 一圈角向高光。琉璃行专用，33（任务单：琉璃行保留 33）。
struct LiuliBadge: View {
  let base: String
  var asset: SymbolClassification.Asset? = nil

  @Environment(\.panelTheme) private var theme

  static let size: CGFloat = 33

  var body: some View {
    let spec = CoinSpec.of(base, asset: asset)
    let brand = BadgeTint.gradient(from: spec.from, to: spec.to, seed: theme.seed).bottom
    ZStack {
      RadialGradient(colors: [brand.opacity(theme.dark ? 0.34 : 0.2), brand.opacity(0)],
                     center: .center, startRadius: 2, endRadius: 24)
        .frame(width: 48, height: 48)
      CoinBadge(base: base, asset: asset, size: Self.size)
        .overlay {
          RoundedRectangle(cornerRadius: 13.7, style: .continuous)
            .strokeBorder(AngularGradient(
              gradient: Gradient(stops: [
                .init(color: brand, location: 0),
                .init(color: brand.opacity(0.2), location: 0.3),
                .init(color: brand, location: 0.55),
                .init(color: brand.opacity(0.15), location: 0.83),
                .init(color: brand, location: 1)]),
              center: .center, angle: .degrees(210)), lineWidth: 1)
            .opacity(theme.dark ? 0.6 : 0.55)
            .padding(-3.5)
        }
    }.frame(width: Self.size, height: Self.size)
  }
}

// MARK: - 琉璃行

/// 自选分类页与板块内品种表共用的那一行（用户定稿的「琉璃」版）。
///
/// 左：徽章、名字 + 计价币 +「新」、一行副文案（调用方给）；右：可选的附件（自选页的迷你走势）、
/// 价格、涨跌药丸。整行一块点击区；行与行之间一根两端渐隐的发丝线，和内容同一条左右竖线。
struct LiuliSymbolRow<Detail: View, Accessory: View>: View {
  let symbol: String
  let base: String
  let quote: String
  var asset: SymbolClassification.Asset?
  var isNew: Bool
  var first: Bool
  let priceText: String
  /// 价格的墨色。`nil` 用正文墨。
  var priceInk: Color?
  /// 价格还在路上：摆一块骨架，不写字。
  var priceSkeleton: Bool
  let priceID: String
  let change: Double
  let changeText: String
  var changePending: Bool
  let changeID: String
  let openID: String
  let onOpen: () -> Void
  let detail: Detail
  let accessory: Accessory

  @Environment(\.panelTheme) private var theme

  /// 行高：66（琉璃版定稿值，不在这次整改范围内；字号放大时跟着长，不截）。
  static var height: CGFloat { 66 }

  init(symbol: String, base: String, quote: String,
       asset: SymbolClassification.Asset? = nil, isNew: Bool = false, first: Bool,
       priceText: String, priceInk: Color? = nil, priceSkeleton: Bool = false, priceID: String,
       change: Double, changeText: String, changePending: Bool = false, changeID: String,
       openID: String, onOpen: @escaping () -> Void,
       @ViewBuilder detail: () -> Detail,
       @ViewBuilder accessory: () -> Accessory) {
    self.symbol = symbol
    self.base = base
    self.quote = quote
    self.asset = asset
    self.isNew = isNew
    self.first = first
    self.priceText = priceText
    self.priceInk = priceInk
    self.priceSkeleton = priceSkeleton
    self.priceID = priceID
    self.change = change
    self.changeText = changeText
    self.changePending = changePending
    self.changeID = changeID
    self.openID = openID
    self.onOpen = onOpen
    self.detail = detail()
    self.accessory = accessory()
  }

  var body: some View {
    HStack(spacing: Space.m) {
      LiuliBadge(base: base, asset: asset)
      VStack(alignment: .leading, spacing: Space.xs) {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
          Text(base).font(SymbolRowFont.liuliName).foregroundStyle(theme.ink)
          Text(quote).font(SymbolRowFont.small).foregroundStyle(SymbolRowInk.faint(theme))
          if isNew {
            NewListingMark(symbol: symbol, accent: theme.amber)
          }
        }.lineLimit(1)
        detail
          .font(SymbolRowFont.small).monospacedDigit()
          .lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
      accessory
      quoteColumn
    }
    .pageHorizontalInset()
    .frame(minHeight: Self.height)
    .contentShape(Rectangle())
    .onTapGesture(perform: onOpen)
    .overlay(alignment: .top) {
      if !first {
        LinearGradient(colors: [.clear, SymbolRowInk.rule(theme), SymbolRowInk.rule(theme), .clear],
                       startPoint: .leading, endPoint: .trailing)
          .frame(height: 0.5)
          .pageHorizontalInset()
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier(openID)
    .accessibilityAction(.default, onOpen)
  }

  /// 右边：价格在前、涨跌药丸在后，横排（2026-09-25 照用户给的富途式自选表改）。
  /// 价格靠右贴着药丸，药丸定宽，于是两列各自成一条竖线。
  private var quoteColumn: some View {
    HStack(spacing: Space.m) {
      Text(priceText)
        .font(SymbolRowFont.liuliPrice).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(priceSkeleton ? .clear : (priceInk ?? theme.ink))
        .overlay(alignment: .trailing) {
          if priceSkeleton {
            RoundedRectangle(cornerRadius: Radius.xs).fill(SymbolRowInk.rule(theme))
              .frame(width: 70, height: 13)
              .accessibilityHidden(true)
          }
        }
        .accessibilityIdentifier(priceID)
      ChangePill(value: change, text: changeText, pending: changePending, id: changeID)
    }
  }
}

// MARK: - 整页行（搜索页、品种整页）

/// 搜索页与品种整页的一行：徽章、名字（命中片段高亮）、一行小字，右边价格与涨跌，行尾一颗星。
///
/// 字号按审查定案：名 15、计价币与小字 12、价格 15 等宽数字、涨跌 13
/// （原来名 14 / 价 13.5 SF Mono / 涨跌 11，名字和价格的大小关系和自选页是反的）。
/// 左右边距跟页面，竖向 12（`Inset.rowV`），行高不低于 44；星的点击区 44。
struct SymbolRowView: View {
  let row: SymbolRow
  let isFavorite: Bool
  /// 涨跌配色。按它和皮肤现造一份 `PanelTheme` 取 `up / down`，与宿主给的 `redUp` 一致。
  let theme: PanelTheme
  let onStar: () -> Void
  let onPick: () -> Void

  // 名字是逐段拼的 `Text`（命中片段换色），只能吃 `Font`，吃不了 `ScaledFont`，
  // 所以字号在这儿按同一条曲线量一份。
  @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = TypeScale.body.size
  @ScaledMetric(relativeTo: .caption) private var quoteSize: CGFloat = TypeScale.caption.size

  /// 星本身画多大。点击区另算（`Hit.min`）。
  static let starSize: CGFloat = 15
  /// 分隔线从哪儿起：徽章右边、文字起点（页边距另加）。
  nonisolated static let textLead: CGFloat = ControlMetrics.listBadge + Space.m

  // 行和星都**不是 `Button`**，是两块 `contentShape` 加 `onTapGesture`，
  // 无障碍身份靠 `.isButton` 补回去（自选分类页那一行就是这么写的）。
  //
  // 这不是风格问题：`.buttonStyle(.plain)` 的 `Button` 在 `List` 的行里
  // 认的是「按下—抬手」，横着拖过去一百二十点它照样当成点了一下，而且它把
  // 这一趟触摸整个占住，外层 `SwipeToDelete` 那道 `simultaneousGesture`
  // 一次 `onChanged` 都收不到。2026-09-22 在 iPhone 15 上六次起手全灭。
  // `TapGesture` 则在手指挪过点击容差时自己作废，横拖就干净地落给左划。
  var body: some View {
    HStack(spacing: 0) {
      HStack(spacing: Space.m) {
        // 事实分类直接从 `row.info` 算，比让徽章自己去猜准。
        CoinBadge(base: row.info.base, asset: SymbolClassifier.classify(row.info).asset,
                  size: ControlMetrics.listBadge)
        VStack(alignment: .leading, spacing: Space.xxs) {
          HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            name
            if NewListingMark.shows(row.info) {
              NewListingMark(symbol: row.id, accent: theme.amber)
            }
            // 别家交易所的品种在名字右边标一个灰色小字（默认那一家不标）——
            // 两家所都有 BTC，搜出来并排时靠它分。
            if let tag = VenueRegistry.descriptor(forSymbol: row.id).searchTag {
              Text(tag)
                .font(TypeScale.caption)
                .foregroundStyle(theme.ink3)
                .accessibilityIdentifier("symbols.venue.\(row.id)")
            }
          }.lineLimit(1)
          Text(row.meta)
            .font(TypeScale.caption)
            .foregroundStyle(theme.ink3)
            .lineLimit(1)
        }
        Spacer(minLength: Space.s)
        VStack(alignment: .trailing, spacing: Space.xxs) {
          Text(row.priceText)
            .font(TypeScale.bodyEmph).monospacedDigit()
            .foregroundStyle(theme.ink)
          Text(row.changeText)
            .font(TypeScale.footnoteEmph).monospacedDigit()
            .foregroundStyle(row.ticker?.changePercent.isFinite == true
                             ? (row.isUp ? theme.up : theme.down) : theme.ink3)
        }.lineLimit(1)
      }
      .padding(.vertical, Inset.rowV)
      .contentShape(Rectangle())
      .onTapGesture(perform: onPick)
      .accessibilityElement(children: .contain)
      .accessibilityAddTraits(.isButton)
      .accessibilityIdentifier("symbols.row.\(row.id)")
      .accessibilityAction(.default, onPick)
      StarShape()
        .fill(isFavorite ? theme.amber : .clear)
        .overlay(StarShape().stroke(isFavorite ? theme.amber : theme.ink3,
                                    style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)))
        .frame(width: Self.starSize, height: Self.starSize)
        // 星画得小是视觉上的克制，点击区撑到 44；多出来的半截伸进右边距里，
        // 星本身仍然贴着页面右边那条竖线。
        .frame(width: Hit.min, height: Hit.min)
        .contentShape(Rectangle())
        .padding(.trailing, -(Hit.min - Self.starSize) / 2)
        .animation(.easeOut(duration: 0.2), value: isFavorite)
        .onTapGesture(perform: onStar)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isFavorite ? "取消自选" : "加入自选")
        .accessibilityIdentifier("symbols.star.\(row.id)")
        .accessibilityAction(.default, onStar)
    }
    .frame(minHeight: Inset.rowMin)
    .pageHorizontalInset()
  }

  /// `BTC` + 灰的 ` / USDT`；搜索命中的片段用强调色标出来（§10.5 匹配片段高亮）。
  private var name: Text {
    let base = row.info.base
    let quote = row.info.quote
    // `Text + Text` iOS 26 起废弃了，改用 `Text` 插值拼，逐段的字体/颜色照样保留。
    var out = Text("")
    for seg in SymbolQuery.split(base, highlight: row.match.highlight, offset: 0) {
      let piece = Text(seg.text)
        .font(.system(size: nameSize, weight: .medium))
        .foregroundStyle(seg.hit ? theme.amber : theme.ink)
      out = Text("\(out)\(piece)")
    }
    let slash = Text(" / ").font(.system(size: quoteSize)).foregroundStyle(theme.ink3)
    out = Text("\(out)\(slash)")
    for seg in SymbolQuery.split(quote, highlight: row.match.highlight, offset: base.count) {
      let piece = Text(seg.text)
        .font(.system(size: quoteSize))
        .foregroundStyle(seg.hit ? theme.amber : theme.ink3)
      out = Text("\(out)\(piece)")
    }
    return out
  }
}

/// 搜索页那一列行之间的分隔：左从文字起点、右到页边，和品种整页的系统分隔线同一个位置。
struct SymbolRowDivider: View {
  @Environment(\.panelTheme) private var theme

  var body: some View {
    theme.hair.frame(height: 0.5)
      .padding(.leading, SymbolRowView.textLead)
      .pageHorizontalInset()
      .accessibilityHidden(true)
  }
}

// MARK: - 搜索框

/// 搜索页与品种整页共用的那一个输入框（静态审查 §3.4：全 app 原有三种搜索框）。
///
/// 44 高胶囊，放大镜 16、字 15，和自选页入口那条假框同一个样子。
/// 品种代号全是 ASCII，锁住英文键盘、不自动纠错、自动大写。
/// 聚焦与否由页面自己决定（搜索页进来就聚焦，品种整页不抢，见各自的 `.task`）。
struct SymbolSearchField: View {
  @Binding var text: String
  var focused: FocusState<Bool>.Binding
  let id: String
  var onSubmit: () -> Void = {}
  /// 给了才在有字时露出框内的「×」。
  var clearID: String? = nil
  var onClear: (() -> Void)? = nil

  @Environment(\.panelTheme) private var theme

  static let height: CGFloat = Hit.min
  static let iconSize: CGFloat = 16
  static let hPad: CGFloat = Space.l

  var body: some View {
    let on = focused.wrappedValue
    HStack(spacing: Space.s) {
      VectorIcon.search(Self.iconSize).foregroundStyle(theme.ink3)
      TextField("", text: $text, prompt: Text("搜 BTC、ETH、SOL…").foregroundStyle(theme.ink3))
        .font(TypeScale.body)
        .foregroundStyle(theme.ink)
        .keyboardType(.asciiCapable)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .focused(focused)
        .onSubmit(onSubmit)
        .accessibilityIdentifier(id)
      if let onClear, !text.isEmpty {
        Button(action: onClear) {
          Image(systemName: "xmark.circle.fill")
            .font(TypeScale.body)
            .foregroundStyle(theme.ink3)
            .frame(width: Hit.min, height: Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 点击区 44，多出来的那截伸到框的右内边距里，× 本身离框右沿和放大镜离左沿一样远。
        .padding(.trailing, -(Hit.min - Self.iconSize) / 2)
        .accessibilityLabel("清空搜索框")
        .accessibilityIdentifier(clearID ?? "")
      }
    }
    .padding(.horizontal, Self.hPad)
    .frame(height: Self.height)
    .background(Capsule().fill(theme.raised2))
    .overlay(Capsule().strokeBorder(on ? theme.amberLine : theme.line, lineWidth: on ? 2 : 1))
  }
}

// MARK: - 小块

/// 全 app 一种「小块」：搜索历史词、品种整页的市场 / 板块筛选、板块内品种表的排序。
///
/// 原来四套（胶囊 40 / 胶囊 25 / 圆角 8 方块 30 / 只有文字），现在照面板分段那一格（P0b）：
/// 胶囊，看得见的 28（`ControlMetrics.pillHeight`），字 13，点击区撑到 44。
/// 没选中是一层淡淡的井，选中抬成白 / 亮一档并描边——在纯底色和琉璃背景上都读得出来。
struct SymbolChip: View {
  let title: String
  var selected = false
  /// 点开是一张菜单的（筛选）在字右边挂一个 ▾。
  var menu = false
  let action: () -> Void

  @Environment(\.panelTheme) private var theme
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    Button(action: action) {
      HStack(spacing: Space.xs) {
        Text(title).font(selected ? TypeScale.controlOn : TypeScale.control)
          .lineLimit(1)
        if menu {
          Image(systemName: "chevron.down")
            .font(.scaled(TypeScale.caption2.size, .semibold, relativeTo: .caption2))
            .accessibilityHidden(true)
        }
      }
      .foregroundStyle(selected ? theme.ink : theme.ink2)
      .padding(.horizontal, Space.m)
      .frame(height: ControlMetrics.pillHeight)
      .background {
        Capsule()
          .fill(selected ? Self.onFill(theme) : Self.well(theme))
          .overlay(Capsule().strokeBorder(selected ? Self.onEdge(theme) : .clear, lineWidth: 0.5))
      }
      .opacity(enabled ? 1 : ControlMetrics.disabledOpacity)
      .frame(minHeight: Hit.min)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  static func well(_ theme: PanelTheme) -> Color {
    Color(hex: theme.seed.ink).opacity(theme.dark ? 0.07 : 0.06)
  }
  static func onFill(_ theme: PanelTheme) -> Color {
    Color(hex: theme.dark ? theme.seed.ink : theme.seed.raised).opacity(theme.dark ? 0.12 : 0.85)
  }
  static func onEdge(_ theme: PanelTheme) -> Color {
    Color(hex: theme.dark ? theme.seed.ink : theme.seed.line).opacity(theme.dark ? 0.2 : 1)
  }
}
