import SwiftUI

// ============================================================ 画线工作台里换品种
//
// 竖屏行情页左上角的品种名一律**不是**按钮（2026-09-18 用户定的口径，
// `FavoritesQuickPicker` 就是那时删掉的）。横屏画线是唯一的例外：
//
//   「进入画线里面如果我想继续画别的品种就必须退出然后重新从别的入口进入，
//     中间不是展示了该画线的品种吗，点击该品种……出现一个上面是一个搜索框，
//     当没输入时，下面是经常看的一些品种，输入时就展示匹配的品种……
//     列表只展示品种，不显示其它信息，选择品种或者搜到品种点击后直接收起搜索框，
//     然后画线的品种变成该点击品种」
//
// 理由跟竖屏那条口径并不冲突：画线是连续作业，退出横屏再从搜索/自选进来会把
// 整条工作流打断。所以这一层只在画线工作台里存在，别据此把竖屏的品种名改回按钮。
//
// 形态抄的是 AICoin 手机端横屏画线那套：不铺满整屏，只在品种名底下落一小块浮层，
// K 线始终露着——用户挑品种时还在看图。
//
// **只有代号**，没有价格、涨跌、徽章。用户点名要的：这一层是「换目标」，不是「选股」；
// 带上行情就又变成一张小号品种页，还得等报价到齐才排得出来。
//
// 「经常看」不是「最近」：`recents` 是时间倒序、只有 10 格，搜索里滑过一下、点错一次
// 都会把天天盯的那几个顶出去。这里问的是**次数**，见 `SymbolPrefs.noteDwell(_:)`。

struct DrawingSymbolSwitcher: View {
  var theme: PanelTheme
  /// 没输入时列的那一列（常看）。
  var frequent: [String]
  /// 输入时列的那一列（匹配结果）。
  var matches: (String) -> [String]
  var current: String
  var onPick: (String) -> Void
  var onClose: () -> Void

  @State private var query = ""
  @FocusState private var focused: Bool

  private var rows: [String] {
    let q = query.trimmingCharacters(in: .whitespaces)
    return q.isEmpty ? frequent : matches(q)
  }

  private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(theme.ink3)
        TextField("搜索品种", text: $query)
          .font(.system(size: 13))
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .submitLabel(.go)
          .focused($focused)
          .onSubmit { if let first = rows.first { pick(first) } }
          .accessibilityIdentifier("draw.symbol.search")
        if !query.isEmpty {
          Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 13)) }
            .foregroundStyle(theme.ink3).accessibilityLabel("清空")
        }
      }
      .padding(.horizontal, 10).frame(height: 36)
      theme.line.frame(height: 0.5)

      if query.trimmingCharacters(in: .whitespaces).isEmpty {
        Text("常看").font(.system(size: 10)).foregroundStyle(theme.ink3)
          .padding(.horizontal, 10).padding(.top, 7).padding(.bottom, 1)
      }

      if rows.isEmpty {
        Text("没有这个品种").font(.system(size: 12)).foregroundStyle(theme.ink3)
          .padding(.horizontal, 10).padding(.vertical, 14)
      } else {
        ScrollView(.vertical, showsIndicators: false) {
          LazyVGrid(columns: columns, spacing: 4) {
            ForEach(rows, id: \.self) { symbol in
              Button { pick(symbol) } label: {
                Text(symbol)
                  .font(.system(size: 12, weight: symbol == current ? .semibold : .regular))
                  .lineLimit(1).minimumScaleFactor(0.8)
                  .frame(maxWidth: .infinity, minHeight: 32)
                  .background(symbol == current ? theme.amberSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
                  .foregroundStyle(symbol == current ? theme.amber : theme.ink)
                  .contentShape(Rectangle())
              }
              .accessibilityIdentifier("draw.symbol.\(symbol)")
            }
          }
          .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .frame(maxHeight: 208)
      }
    }
    .frame(width: 236)
    .background(RoundedRectangle(cornerRadius: 12).fill(theme.raised2))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 0.5))
    .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
    .buttonStyle(.plain)
    // 键盘一进来就在：用户点品种名就是为了打字，多按一下输入框是白让他按的。
    .onAppear { focused = true }
    .accessibilityIdentifier("draw.symbol.switcher")
  }

  /// 点中就**立刻**收起——用户点名要的「直接收起搜索框」。换品种本身交给宿主：
  /// 画线是自动存的（`DrawingController.persist`），走之前不用问「要不要保存」。
  private func pick(_ symbol: String) {
    focused = false
    onPick(symbol)
    onClose()
  }
}
