import SwiftUI
import KanpanCore

/// 换品种的**唯一**入口：顶栏品种名点开的半屏弹层。
///
/// 三个入口收敛成一个之后，原来那两个去处都进了这儿的第一屏：第一行「搜索品种」
/// 开全屏搜索，第二行「全部自选与分组」开完整自选页。它们做成整行而不是角上的
/// 小图标——弹层一拉起来手指就在下半屏，够得着的是行，不是标题栏。
struct FavoritesQuickPicker: View {
  @Bindable var model: SymbolPickerModel
  var current: String
  var onClose: () -> Void
  var onSearch: () -> Void
  /// 打开完整自选页（分组、排序、历史）。
  var onAll: () -> Void
  @Environment(\.panelTheme) private var theme

  var body: some View {
    VStack(spacing: 0) {
      // 出口在左上角的「‹」，和面板、自选页、品种页同一个位置（2026-09-15）。
      HStack(spacing: 6) {
        Button(action: onClose) {
          Image(systemName: "chevron.left")
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .foregroundStyle(theme.amber)
        .accessibilityLabel("返回").accessibilityIdentifier("quickFavorites.close")
        Text("自选").font(.system(size: 17, weight: .semibold))
        Text("\(model.prefs.favorites.count)").font(.system(size: 12)).foregroundStyle(theme.ink3)
        Spacer()
      }.padding(.leading, 18 - 7).padding(.trailing, 6).padding(.top, 8)
      entry("magnifyingglass", "搜索品种", "quickFavorites.search", action: onSearch)
      entry("star", "全部自选与分组", "quickFavorites.all", action: onAll)
      theme.line.frame(height: 0.5)
      if model.prefs.favorites.isEmpty {
        Button("添加品种", action: onSearch).foregroundStyle(theme.amber).padding(30)
        Spacer()
      } else {
        List(model.prefs.favorites, id: \.self) { symbol in
          let info = model.info(for: symbol) ?? SymbolInfo(symbol: symbol,
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
    }
    .background(theme.app).foregroundStyle(theme.ink)
    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    .task { await model.appear() }
  }

  private func entry(
    _ icon: String, _ title: String, _ id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon).font(.system(size: 14)).frame(width: 20)
        Text(title).font(.system(size: 15))
        Spacer()
        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(theme.ink3)
      }
      .foregroundStyle(theme.ink)
      .padding(.horizontal, 18).frame(height: 46).contentShape(Rectangle())
    }
    .buttonStyle(.plain).accessibilityIdentifier(id)
  }
}
