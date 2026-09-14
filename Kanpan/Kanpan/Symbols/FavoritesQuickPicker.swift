import SwiftUI
import KanpanCore

/// Flat quick switcher: includes every saved favorite, independent of its folder.
struct FavoritesQuickPicker: View {
  @Bindable var model: SymbolPickerModel
  var current: String
  var onClose: () -> Void
  var onSearch: () -> Void
  @Environment(\.panelTheme) private var theme

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("自选").font(.system(size: 17, weight: .semibold))
        Text("\(model.prefs.favorites.count)").font(.system(size: 12)).foregroundStyle(theme.ink3)
        Spacer()
        Button(action: onSearch) { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
          .accessibilityLabel("搜索品种").accessibilityIdentifier("quickFavorites.search")
        Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
          .accessibilityLabel("关闭").accessibilityIdentifier("quickFavorites.close")
      }.padding(.leading, 18).padding(.trailing, 6).padding(.top, 8)
      if model.prefs.favorites.isEmpty {
        Button("添加品种", action: onSearch).foregroundStyle(theme.amber).padding(30)
        Spacer()
      } else {
        List(model.prefs.favorites, id: \.self) { symbol in
          let info = model.catalog.first { $0.symbol == symbol } ?? SymbolInfo(symbol: symbol,
            base: symbol.hasSuffix("USDT") ? String(symbol.dropLast(4)) : symbol, pricePrecision: 2, tickSize: 0.01)
          let row = SymbolRow(match: SymbolMatch(info: info), ticker: model.ticker(for: symbol))
          Button { model.pick(info) } label: {
            HStack(spacing: 10) {
              VStack(alignment: .leading, spacing: 3) {
                Text(info.base).font(.system(size: 15, weight: .semibold))
                Text(info.quote + " 永续").font(.system(size: 10)).foregroundStyle(theme.ink3)
              }
              if symbol == current { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(theme.amber) }
              Spacer(minLength: 12)
              VStack(alignment: .trailing, spacing: 3) {
                Text(row.priceText).font(.system(size: 15, weight: .medium, design: .monospaced))
                Text(row.changeText).font(.system(size: 11, design: .monospaced)).foregroundStyle(row.isUp ? theme.up : theme.down)
              }
            }.foregroundStyle(theme.ink).padding(.vertical, 5).contentShape(Rectangle())
          }.buttonStyle(.plain).listRowBackground(theme.app).listRowSeparatorTint(theme.line)
            .accessibilityIdentifier("quickFavorites.open." + symbol)
        }.listStyle(.plain).scrollContentBackground(.hidden)
      }
    }.background(theme.app).foregroundStyle(theme.ink)
      .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
      .task { await model.appear() }
  }
}
