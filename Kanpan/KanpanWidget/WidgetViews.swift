import KanpanCore
import KanpanPresentation
import SwiftUI
import WidgetKit

extension Color {
  /// `#RRGGBB` / `#RRGGBBAA`。扩展进程没有 app 里那份 `Color(hex:)`，这儿照同一个口径写一份。
  init(widgetHex hex: String) {
    let c = Hex(hex).rgba
    self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
  }
}

/// 一次刷新拿到的东西。快照为空（app 还没开过、或者没有自选）也照样出一格。
struct QuoteEntry: TimelineEntry {
  var date: Date
  var snapshot: WidgetSnapshot?
  var group: String?
  var symbol: String?
}

struct WidgetPalette {
  var colors: WidgetSnapshot.Colors
  var ground: Color { Color(widgetHex: colors.ground) }
  var ink: Color { Color(widgetHex: colors.ink) }
  var ink3: Color { Color(widgetHex: colors.ink3) }
  var line: Color { Color(widgetHex: colors.line) }
  func tone(_ change: Double) -> Color {
    guard change.isFinite, change != 0 else { return Color(widgetHex: colors.ink3) }
    return Color(widgetHex: change > 0 ? colors.up : colors.down)
  }

  /// 快照还没有时的底色：青苔的浅 / 深两档，和 app 出厂皮肤一致。
  static func fallback(dark: Bool) -> WidgetSnapshot.Colors {
    WidgetSnapshot.Colors(seed: dark ? Palette.sageNightSeed : Palette.sageSeed, redUp: true)
  }

  init(snapshot: WidgetSnapshot?, dark: Bool) {
    colors = snapshot?.colors(systemDark: dark) ?? Self.fallback(dark: dark)
  }
}

/// 小组件的字号与间距（UI 整改 P3）。扩展进程看不到 app 的 `TypeScale` / `Space`，
/// 这儿只留小组件用得到的那几档，值与 app 那边同名令牌一致；全格最小 11（`caption2`）。
enum WidgetType {
  /// `TypeScale.controlOn`：品种名 13 semibold。
  static let name = Font.system(size: 13, weight: .semibold)
  /// 小号的价：13 medium 等宽数字。
  static let price = Font.system(size: 13, weight: .medium).monospacedDigit()
  /// `TypeScale.caption2Emph`：涨跌幅、时刻 11 medium（小组件里最小的字）。
  static let small = Font.system(size: 11, weight: .medium).monospacedDigit()
  /// `TypeScale.body` 加粗：中号的品种名 15 semibold。
  static let focusName = Font.system(size: 15, weight: .semibold)
  /// `TypeScale.price`：中号的价 22 semibold。
  static let focusPrice = Font.system(size: 22, weight: .semibold).monospacedDigit()
  /// `TypeScale.control`：中号的涨跌幅 13 medium。
  static let focusChange = Font.system(size: 13, weight: .medium).monospacedDigit()
  /// 缩字下限：13 × 0.85 ≈ 11，缩到头也不低于 11。
  static let minScale: CGFloat = 0.85
}

/// 价旧了要看得出来（UI 整改 P3）：小组件不在前台，系统说是 15 分钟刷一次，实际常常更晚，
/// 取不到新价时沿用快照（宁可旧、不画空）——于是一格价可能是几小时前的，看着却和新的一样。
/// 过了两个刷新周期（30 分钟）还没更新，那一格的价与涨跌就变淡；中号另在价下面写一行它是几点的价。
enum WidgetFreshness {
  static let staleAfter: TimeInterval = 30 * 60
  static let staleOpacity: Double = 0.45
  static func quoteDate(_ quote: WidgetSnapshot.Quote) -> Date {
    Date(timeIntervalSince1970: Double(quote.timeMs) / 1000)
  }
  /// 还没有价的那格（写「--」、`timeMs` 为 0）不算旧：那儿没东西可淡。
  static func isStale(_ quote: WidgetSnapshot.Quote, at now: Date) -> Bool {
    quote.timeMs > 0 && quote.price.isFinite && now.timeIntervalSince(quoteDate(quote)) > staleAfter
  }
  /// 时间线里再排一格：最早那只变旧的那一刻，好让它按时变淡，不必等下一次刷新。
  static func staleEntryDate(_ quotes: [WidgetSnapshot.Quote], after now: Date) -> Date? {
    let dates = quotes.map { quoteDate($0).addingTimeInterval(staleAfter) }.filter { $0 > now }
    return dates.min()
  }
}

private func symbolURL(_ symbol: String) -> URL { URL(string: "hkline://symbol/\(symbol)")! }

/// 小号：自选四行。整格点进去是自选页（小号系统只给一个点按区）。
struct FavoritesWidgetView: View {
  var entry: QuoteEntry
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let palette = WidgetPalette(snapshot: entry.snapshot, dark: scheme == .dark)
    let rows = entry.snapshot?.rows(group: entry.group) ?? []
    VStack(spacing: 0) {
      if rows.isEmpty {
        Spacer()
        Text("还没有自选").font(WidgetType.name).foregroundStyle(palette.ink3)
        Spacer()
      } else {
        ForEach(Array(rows.enumerated()), id: \.element.symbol) { index, quote in
          if index > 0 { Rectangle().fill(palette.line).frame(height: 0.5) }
          row(quote, palette: palette)
        }
        if rows.count < WidgetSnapshot.rowLimit { Spacer(minLength: 0) }
      }
    }
    .containerBackground(for: .widget) { palette.ground }
    .widgetURL(URL(string: "hkline://favorites"))
  }

  private func row(_ quote: WidgetSnapshot.Quote, palette: WidgetPalette) -> some View {
    // 三级：名 13 semibold / 价 13 medium 等宽 / 涨跌 11（原来 13 / 12 / 10，价和名差不出层级，
    // 涨跌 10 低于 HIG 下限）。
    HStack(spacing: 4) {
      Text(quote.base)
        .font(WidgetType.name)
        .foregroundStyle(palette.ink)
        .lineLimit(1).minimumScaleFactor(WidgetType.minScale)
      Spacer(minLength: 2)
      VStack(alignment: .trailing, spacing: 0) {
        Text(quote.priceLabel)
          .font(WidgetType.price)
          .foregroundStyle(palette.ink)
          .lineLimit(1).minimumScaleFactor(WidgetType.minScale)
        Text(quote.changeLabel)
          .font(WidgetType.small)
          .foregroundStyle(palette.tone(quote.change))
      }
      .opacity(WidgetFreshness.isStale(quote, at: entry.date) ? WidgetFreshness.staleOpacity : 1)
    }
    .frame(maxHeight: .infinity)
    .accessibilityElement(children: .combine)
  }
}

/// 中号：一只品种，左边价与涨跌幅，右边 24 小时收盘价折线。点进去是那只的图。
struct SymbolWidgetView: View {
  var entry: QuoteEntry
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let palette = WidgetPalette(snapshot: entry.snapshot, dark: scheme == .dark)
    let quote = entry.snapshot?.focus(symbol: entry.symbol)
    Group {
      if let quote {
        let stale = WidgetFreshness.isStale(quote, at: entry.date)
        HStack(alignment: .center, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text(quote.base).font(WidgetType.focusName).foregroundStyle(palette.ink)
            Spacer(minLength: 0)
            Group {
              Text(quote.priceLabel)
                .font(WidgetType.focusPrice)
                .lineLimit(1).minimumScaleFactor(0.5)
              Text(quote.changeLabel)
                .font(WidgetType.focusChange)
            }
            .foregroundStyle(palette.tone(quote.change))
            .opacity(stale ? WidgetFreshness.staleOpacity : 1)
            // 旧价写明是几点的（当天只写时刻，跨天带日期）。新价不写：满屏的时刻是噪音。
            if stale { staleTime(WidgetFreshness.quoteDate(quote), palette: palette) }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Sparkline(closes: quote.closes, color: palette.tone(quote.change))
            .opacity(stale ? WidgetFreshness.staleOpacity : 1)
            .frame(maxWidth: .infinity)
        }
        .widgetURL(symbolURL(quote.symbol))
      } else {
        Text("还没有自选").font(WidgetType.name).foregroundStyle(palette.ink3)
      }
    }
    .containerBackground(for: .widget) { palette.ground }
  }

  private func staleTime(_ date: Date, palette: WidgetPalette) -> some View {
    let sameDay = Calendar.current.isDate(date, inSameDayAs: entry.date)
    return Text(date, format: sameDay ? .dateTime.hour().minute() : .dateTime.month(.defaultDigits).day().hour().minute())
      .font(WidgetType.small)
      .foregroundStyle(palette.ink3)
  }
}

/// 收盘价折线，底下垫一层同色渐隐。
struct Sparkline: View {
  var closes: [Double]
  var color: Color

  var body: some View {
    GeometryReader { geo in
      let points = WidgetSnapshot.sparkline(closes).map { CGPoint(x: $0.x * geo.size.width, y: $0.y * geo.size.height) }
      if points.count >= 2 {
        let line = Path { p in p.addLines(points) }
        let area = Path { p in
          p.addLines(points)
          p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
          p.addLine(to: CGPoint(x: 0, y: geo.size.height))
          p.closeSubpath()
        }
        area.fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
        line.stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
      }
    }
    .padding(.vertical, 6)
  }
}
