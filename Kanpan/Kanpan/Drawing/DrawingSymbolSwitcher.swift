import KanpanCore
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

  /// 列表留多高：键盘起来时压到 92pt，没起来时 208pt。
  ///
  /// 横屏的键盘就是半块屏（iPhone 上约 209pt / 393pt）。208pt 的列表在键盘上来之后
  /// 有四分之三被盖住，用户看着一堆结果却只能点最上面一行。压到 92pt——正好是两行
  /// 加上下的留白——整块浮层就落在键盘上沿以内，前四个匹配结果始终露着，再多的照样滑。
  /// 而键盘没起来的时候（也就是一进来那会儿）列表是满的，「常看」十来个一眼看全。
  private var listHeight: Double { focused ? 92 : 208 }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(theme.ink3)
        TextField("搜索品种", text: $query)
          .font(.system(size: 13))
          // 品种代号全是 ASCII（BTCUSDT、TSLA、XAUUSD…）。不锁 `.asciiCapable` 的话，
          // 用户上次用的是中文输入法，这里就弹一副中文键盘出来——打 BTC 还得先切一次输入法。
          .keyboardType(.asciiCapable)
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
                Text(InstrumentID(symbol).display)
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
        .frame(maxHeight: listHeight)
        .animation(.easeOut(duration: 0.2), value: focused)
        .accessibilityIdentifier("draw.symbol.list")
      }
    }
    .frame(width: 236)
    .background(RoundedRectangle(cornerRadius: 12).fill(theme.raised2))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 0.5))
    .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
    .buttonStyle(.plain)
    // 进来**不**自动弹键盘。
    //
    // 原来一 `onAppear` 就 `focused = true`，理由是「点品种名就是为了打字」。可这块浮层
    // 的主体是底下那格「常看」——横屏里键盘一上来就盖掉小半块屏，用户要的那几个常看品种
    // 反而看不见了，还得先把键盘收了才能点。真要打字的人点一下搜索框就是了，那一下比
    // 每次都先关一次键盘便宜得多。
    // 这里**不**给整块浮层挂 `accessibilityIdentifier`：SwiftUI 会把容器上的这个标识
    // 盖到下面每个子元素头上，搜索框的 `draw.symbol.search` 会被一起改写成容器的名字，
    // 用例就再也点不到它了（实测过：树里那个 TextField 的 identifier 变成了容器的）。
    // 「这一层开着没有」用搜索框本身认——它只在这一层里有。
  }

  /// 点中就**立刻**收起——用户点名要的「直接收起搜索框」。换品种本身交给宿主：
  /// 画线是自动存的（`DrawingController.write()`），走之前不用问「要不要保存」。
  private func pick(_ symbol: String) {
    focused = false
    onPick(symbol)
    onClose()
  }
}
