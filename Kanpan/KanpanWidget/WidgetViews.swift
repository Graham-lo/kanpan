import KanpanCore
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
        Text("还没有自选").font(.system(size: 13, weight: .medium)).foregroundStyle(palette.ink3)
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
    HStack(spacing: 4) {
      Text(quote.base)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(palette.ink)
        .lineLimit(1).minimumScaleFactor(0.7)
      Spacer(minLength: 2)
      VStack(alignment: .trailing, spacing: 0) {
        Text(quote.priceLabel)
          .font(.system(size: 12, weight: .medium).monospacedDigit())
          .foregroundStyle(palette.ink)
          .lineLimit(1).minimumScaleFactor(0.6)
        Text(quote.changeLabel)
          .font(.system(size: 10, weight: .medium).monospacedDigit())
          .foregroundStyle(palette.tone(quote.change))
      }
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
        HStack(alignment: .center, spacing: 14) {
          VStack(alignment: .leading, spacing: 4) {
            Text(quote.base).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.ink)
            Spacer(minLength: 0)
            Text(quote.priceLabel)
              .font(.system(size: 22, weight: .semibold).monospacedDigit())
              .foregroundStyle(palette.tone(quote.change))
              .lineLimit(1).minimumScaleFactor(0.5)
            Text(quote.changeLabel)
              .font(.system(size: 13, weight: .medium).monospacedDigit())
              .foregroundStyle(palette.tone(quote.change))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Sparkline(closes: quote.closes, color: palette.tone(quote.change))
            .frame(maxWidth: .infinity)
        }
        .widgetURL(symbolURL(quote.symbol))
      } else {
        Text("还没有自选").font(.system(size: 13, weight: .medium)).foregroundStyle(palette.ink3)
      }
    }
    .containerBackground(for: .widget) { palette.ground }
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
