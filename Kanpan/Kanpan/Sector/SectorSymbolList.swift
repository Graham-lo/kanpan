import SwiftUI
import KanpanCore

/// 品种列表的排序。原型 `.lsort` 那两颗。
enum SectorSymbolSort: String, CaseIterable, Sendable {
  case change, volume

  var title: String {
    switch self {
    case .change: "涨跌幅"
    case .volume: "成交额"
    }
  }
}

/// 板块品种列表里的一行。
///
/// 纯值、好断言，写法照 `SymbolSections.swift`：视图只管摆，文案在这儿算完。
struct SectorSymbolRow: Sendable, Equatable, Identifiable {
  /// 大写代号，如 `BTC`。
  let base: String
  /// 完整合约代号，如 `BTCUSDT`。开行情页要的是它。
  let symbol: String
  let price: Double
  let pct: Double
  let quoteVolume: Double

  var id: String { symbol }

  /// 代号后面那截计价币。`BTCUSDT` → `USDT`。
  var quoteText: String {
    symbol.hasPrefix(base) ? String(symbol.dropFirst(base.count)) : ""
  }

  /// 价格小数位照原型 `fmtPx`：越小的币留越多位，不然一屏全是 0.00。
  var priceText: String {
    guard price.isFinite else { return "—" }
    let magnitude = abs(price)
    let decimals: Int = if magnitude >= 100 { 2 } else if magnitude >= 1 { 4 }
      else if magnitude >= 0.01 { 5 } else { 7 }
    return sectorGrouped(fmtNum(price, decimals))
  }

  var volumeText: String { quoteVolume.isFinite ? fmtVol(quoteVolume) : "—" }
  var isUp: Bool { pct >= 0 }
  /// 药丸里只写数，符号由前面那个小三角表达（和自选页一致）。
  var changeText: String { pct.isFinite ? toFixed(abs(pct), 2) + "%" : "—" }
  var signedText: String { sectorPctText(pct) }

  /// 把成员名单和行情拼成行。没有行情的成员直接不出现——聚合那边也没算它。
  static func build(members: [String], quotes: [String: SectorQuote],
                    symbolForBase: (String) -> String,
                    sort: SectorSymbolSort) -> [SectorSymbolRow] {
    let rows = members.compactMap { base -> SectorSymbolRow? in
      guard let quote = quotes[base] else { return nil }
      return SectorSymbolRow(base: base, symbol: symbolForBase(base), price: quote.price,
                             pct: quote.pct, quoteVolume: quote.quoteVolume)
    }
    switch sort {
    case .change: return rows.sorted { $0.pct > $1.pct }
    case .volume: return rows.sorted { $0.quoteVolume > $1.quoteVolume }
    }
  }
}

/// 第二层：某一个板块里的品种。
///
/// 视觉照抄自选页（`FavoritesView.row(_:first:)`）——同样的 66 高、同样的徽章、
/// 同样的两端渐隐发丝线、同样的价格与涨跌药丸。用户点过名：这儿要的是自选页那张
/// 列表，不是浮在球场上的胶囊卡片。
///
/// 底还是 `SectorBackdrop`，和球场同一块材料；不加玻璃纸（自选页 2026-09-17
/// 起已经改成「融合」）。
struct SectorSymbolList: View {
  var stat: SectorStat
  /// 板块成员（大写 base）。兜底桶也走这条路。
  var members: [String]
  var quotes: [String: SectorQuote]
  var basis: SectorBasis
  var symbolForBase: (String) -> String
  var onBack: () -> Void
  /// 点中一行：交出完整 symbol。
  var onPick: (String) -> Void

  @Environment(\.panelTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("sector.sort") private var sortID = SectorSymbolSort.change.rawValue

  private var skin: SectorSkin { SectorSkin(theme: theme) }
  private var sort: SectorSymbolSort { SectorSymbolSort(rawValue: sortID) ?? .change }

  var body: some View {
    let rows = SectorSymbolRow.build(members: members, quotes: quotes,
                                     symbolForBase: symbolForBase, sort: sort)
    return VStack(spacing: 0) {
      header
      sortBar(rows.count)
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
            row(item, first: index == 0)
          }
        }
        .padding(.top, 6).padding(.bottom, 8)
      }
      .scrollIndicators(.hidden)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    // 这一层底下还铺着球场。落在头部空处的点要在这儿吃掉，不然会穿下去点着一颗球。
    .contentShape(Rectangle())
    .onTapGesture { }
    .background { SectorBackdrop(skin: skin, reduceMotion: reduceMotion).ignoresSafeArea() }
    .accessibilityIdentifier("sector.list")
  }

  // MARK: - 头

  /// 原型 `enterList()`：返回、记号、板块名、「N 个品种 · 成交额 X」，右边是
  /// 聚合涨跌幅和它的口径名。
  private var header: some View {
    HStack(spacing: 6) {
      SectorBackButton(skin: skin, id: "sector.list.back", action: onBack)
      if let art = SectorIcons.art(stat.id) {
        SectorIconView(art: art, size: 38)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(stat.name).font(skin.serif(19)).tracking(0.76).foregroundStyle(theme.ink)
          .lineLimit(1).minimumScaleFactor(0.7)
        Text("\(stat.memberCount) 个品种 · 成交额 \(fmtVol(stat.quoteVolume))")
          .font(.system(size: 11)).monospacedDigit().tracking(0.33)
          .foregroundStyle(skin.ink4)
          .lineLimit(1).minimumScaleFactor(0.8)
      }
      .padding(.leading, 5)
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        Text(sectorPctText(stat.pct))
          .font(.system(size: 19, weight: .medium)).monospacedDigit()
          .foregroundStyle(stat.pct >= 0 ? theme.up : theme.down)
        Text(basis.title).font(.system(size: 10)).tracking(1)
          .foregroundStyle(skin.ink4)
      }
    }
    .padding(.leading, 15).padding(.trailing, 20).padding(.top, 6)
  }

  private func sortBar(_ count: Int) -> some View {
    HStack(spacing: 7) {
      ForEach(SectorSymbolSort.allCases, id: \.rawValue) { sortChip($0) }
      Spacer(minLength: 0)
      Text("\(count) 个")
        .font(.system(size: 10.5, design: .monospaced)).tracking(0.63)
        .foregroundStyle(skin.ink4)
    }
    .padding(.horizontal, 20).padding(.top, 10)
  }

  private func sortChip(_ value: SectorSymbolSort) -> some View {
    let on = sort == value
    return Button { sortID = value.rawValue } label: {
      Text(value.title).font(.system(size: 11.5)).tracking(0.23)
        .foregroundStyle(on ? theme.ink : theme.ink3)
        .padding(.horizontal, 10).frame(height: 25)
        .background {
          Capsule().fill(on ? skin.chipOn : Color.clear)
            .overlay(Capsule().strokeBorder(on ? skin.chipEdge : skin.rule, lineWidth: 0.5))
        }
        .contentShape(Capsule())
    }.buttonStyle(.plain)
      .accessibilityLabel(value.title)
      .accessibilityAddTraits(on ? .isSelected : [])
      .accessibilityIdentifier("sector.sort." + value.rawValue)
  }

  // MARK: - 行（照抄自选页）

  private func row(_ item: SectorSymbolRow, first: Bool) -> some View {
    HStack(spacing: 10) {
      badge(item.base)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(item.base).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(theme.ink)
          Text(item.quoteText).font(.system(size: 9, weight: .regular)).foregroundStyle(skin.ink4)
        }.lineLimit(1).minimumScaleFactor(0.75)
        // 自选页那行是「额 … · 幅 …」，振幅要 24h 高低价，全市场 ticker 的那一趟
        // 里没带回来，所以这儿只留成交额，排版和字号一模一样。
        Text("额 " + item.volumeText)
          .font(.system(size: 10)).monospacedDigit().foregroundStyle(theme.ink3)
          .lineLimit(1).minimumScaleFactor(0.8)
      }.frame(maxWidth: .infinity, alignment: .leading)
      quote(item)
    }
    .padding(.leading, 19).padding(.trailing, 20)
    .frame(height: 66)
    .contentShape(Rectangle())
    .onTapGesture { onPick(item.symbol) }
    .overlay(alignment: .top) {
      if !first { SectorHairline(skin: skin) }
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("sector.open." + item.symbol)
    .accessibilityAction { onPick(item.symbol) }
  }

  /// 徽章：品牌色晕 + `CoinBadge` + 一圈角向高光。和自选页同一支。
  private func badge(_ base: String) -> some View {
    let spec = CoinSpec.of(base)
    let brand = BadgeTint.gradient(from: spec.from, to: spec.to, seed: theme.seed).bottom
    return ZStack {
      RadialGradient(colors: [brand.opacity(skin.dark ? 0.34 : 0.2), brand.opacity(0)],
                     center: .center, startRadius: 2, endRadius: 24)
        .frame(width: 48, height: 48)
      CoinBadge(base: base, size: 33)
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
            .opacity(skin.dark ? 0.6 : 0.55)
            .padding(-3.5)
        }
    }.frame(width: 33, height: 33)
  }

  /// 右边一列：价 + 涨跌药丸。尺寸全部照自选页。
  private func quote(_ item: SectorSymbolRow) -> some View {
    let tint = item.pct.isFinite ? (item.isUp ? theme.up : theme.down) : skin.ink4
    return VStack(alignment: .trailing, spacing: 5) {
      Text(item.priceText)
        .font(.system(size: 15.5, weight: .medium)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(theme.ink)
        .accessibilityIdentifier("sector.price." + item.symbol)
      HStack(spacing: 4) {
        if item.pct.isFinite {
          SectorTriangle(up: item.isUp).fill(tint).frame(width: 6, height: 5)
            .accessibilityHidden(true)
        }
        Text(item.changeText)
          .font(.system(size: 11, weight: .semibold)).monospacedDigit()
          .foregroundStyle(tint)
          .accessibilityLabel(item.signedText)
          .accessibilityIdentifier("sector.change." + item.symbol)
      }
      .padding(.horizontal, 7).frame(height: 19).frame(minWidth: 54)
      .background {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(tint.opacity(0.14))
          .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
      }
    }.frame(minWidth: 86, alignment: .trailing)
  }
}

/// 价格千分位。`fmtNum` 只管小数位，逗号在这儿补。和自选页同一份实现。
func sectorGrouped(_ text: String) -> String {
  let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
  var head = String(parts[0])
  let negative = head.hasPrefix("-")
  if negative { head.removeFirst() }
  guard head.count > 3 else { return text }
  var out = ""
  for (index, character) in head.reversed().enumerated() {
    if index > 0, index % 3 == 0 { out.append(",") }
    out.append(character)
  }
  let body = (negative ? "-" : "") + String(out.reversed())
  return parts.count > 1 ? body + "." + parts[1] : body
}
