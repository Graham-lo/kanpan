import KanpanCore
import SwiftUI
import WidgetKit

/// 刷新：15 分钟一次（系统可能更晚），app 在前台刷到行情时另外叫一次 `reloadAllTimelines`。
private let refreshEvery: TimeInterval = 15 * 60

struct FavoritesProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> QuoteEntry { QuoteEntry(date: Date(), snapshot: SnapshotStore.load()) }

  func snapshot(for configuration: FavoritesIntent, in context: Context) async -> QuoteEntry {
    QuoteEntry(date: Date(), snapshot: SnapshotStore.load(), group: configuration.group?.id)
  }

  func timeline(for configuration: FavoritesIntent, in context: Context) async -> Timeline<QuoteEntry> {
    let group = configuration.group?.id
    var snapshot = SnapshotStore.load()
    if let current = snapshot {
      snapshot = await LiveQuotes.refresh(current, symbols: current.rows(group: group).map(\.symbol))
    }
    let now = Date()
    let entry = QuoteEntry(date: now, snapshot: snapshot, group: group)
    // 价旧了按时变淡（`WidgetFreshness`）：在最早那只变旧的时刻再排一格同样的内容。
    let stale = WidgetFreshness.staleEntryDate(snapshot?.rows(group: group) ?? [], after: now)
      .map { QuoteEntry(date: $0, snapshot: snapshot, group: group) }
    return Timeline(entries: [entry] + (stale.map { [$0] } ?? []), policy: .after(now.addingTimeInterval(refreshEvery)))
  }
}

struct FavoritesWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "kanpan.favorites", intent: FavoritesIntent.self, provider: FavoritesProvider()) { entry in
      FavoritesWidgetView(entry: entry)
    }
    .configurationDisplayName("自选")
    .description("自选里的前四只")
    .supportedFamilies([.systemSmall])
  }
}

struct SymbolProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> QuoteEntry { QuoteEntry(date: Date(), snapshot: SnapshotStore.load()) }

  func snapshot(for configuration: SymbolIntent, in context: Context) async -> QuoteEntry {
    QuoteEntry(date: Date(), snapshot: SnapshotStore.load(), symbol: configuration.symbol?.id)
  }

  func timeline(for configuration: SymbolIntent, in context: Context) async -> Timeline<QuoteEntry> {
    let chosen = configuration.symbol?.id
    var snapshot = SnapshotStore.load()
    if let current = snapshot, let focus = current.focus(symbol: chosen) {
      snapshot = await LiveQuotes.refresh(current, symbols: [focus.symbol], sparkline: focus.symbol)
    }
    let now = Date()
    let entry = QuoteEntry(date: now, snapshot: snapshot, symbol: chosen)
    let focus = snapshot?.focus(symbol: chosen)
    // 告诉 app 这一格画的是谁：app 只给这几只取走势（`WidgetSparklineWants`）。
    if let focus, let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup) {
      WidgetSparklineWants.note(focus.symbol, in: container, now: now)
    }
    let stale = WidgetFreshness.staleEntryDate(focus.map { [$0] } ?? [], after: now)
      .map { QuoteEntry(date: $0, snapshot: snapshot, symbol: chosen) }
    return Timeline(entries: [entry] + (stale.map { [$0] } ?? []), policy: .after(now.addingTimeInterval(refreshEvery)))
  }
}

struct SymbolWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "kanpan.symbol", intent: SymbolIntent.self, provider: SymbolProvider()) { entry in
      SymbolWidgetView(entry: entry)
    }
    .configurationDisplayName("品种")
    .description("一只品种的价与走势")
    .supportedFamilies([.systemMedium])
  }
}
