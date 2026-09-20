import KanpanCore
import KanpanData
import SwiftUI

/// 顶栏：品种名 · 放大镜（§9.1）。
///
/// 品种名右边原来还有一颗连接状态圆点。用户的话是界面上不要出现「行情源 / 线路 /
/// 已同步」这类后台字段——连没连上、走的哪条线，是我们该自己搞定的事，
/// 摆出来只会让人盯着一颗点猜。断了就重连，重连不上会在拉不到历史时明说。
///
/// 右上角只剩一颗圆按钮：放大镜，进搜索页（`SymbolSearchView`）。品种名本身
/// **不再可点**——它以前开一个「最近看过的几个」的半屏弹层，搜索页做出来之后
/// 那一层就是重复入口了（用户 2026-09-18 定的）。左上角现在只负责回答
/// 「我正在看哪个」，换品种走放大镜，浏览走底栏的自选。
///
/// 自选星也在同一天撤了：加自选统一在搜索页和自选页的行上做（那儿一行一颗星，
/// 看着列表挑着加），顶栏这一颗既和它们重复，又贴着品种名最容易误触。
///
/// 2026-09-18 右上角多了一颗「复盘」。底栏那天换成了常驻标签栏（画线 · 图表 ·
/// 自选 · 设置），复盘按用户的话「放到图表里」——它是看着某张图时才想起来的事，
/// 所以落在行情页顶栏，挨着搜索。待办条数照旧画成一颗角标。
///
/// 字号、间距、图标都按原型 `style.css` 的 `.top` 那一段抄，别自己发挥——
/// 这一条和价格行是整个 app 里唯一常驻的文字，差一点点立刻显得不像同一个应用。
struct TopBar: View {
  @State private var iconTapCount = 0
  var theme: PanelTheme
  var symbol: String
  /// 复盘本里还欠着答案的条数。0 就不画角标。
  var reviewCount: Int = 0
  /// 有来路就有返回。非 nil 时最左边多一颗返回箭头，回到把人送进这张图的那一页
  /// （板块下钻、自选行）。从底栏直接点进来的「图表」没有来路，这颗就不画——
  /// 常驻标签栏那一格自己就是家，返回无处可去。
  var onBack: (() -> Void)?
  var onReview: (() -> Void)?
  var onSearch: () -> Void

  /// 「BTCUSDT」拆成「BTC」+「/USDT」：基础币用正文色、计价币降一级，
  /// 一眼扫过去认的是前半截。
  private var base: String {
    for quote in ["USDT", "USDC", "USD", "BUSD", "FDUSD"] where symbol.hasSuffix(quote) && symbol.count > quote.count {
      return String(symbol.dropLast(quote.count))
    }
    return symbol
  }
  private var quote: String { String(symbol.dropFirst(base.count)) }

  var body: some View {
    HStack(spacing: 9) {
      if let onBack {
        backButton(onBack)
      }
      HStack(spacing: 9) {
        CoinBadge(base: base, size: 29)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(base)
            .font(.system(size: 15.5, weight: .bold))
            .foregroundStyle(theme.ink)
          if !quote.isEmpty {
            Text("/" + quote)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(theme.ink3)
          }
          // 这儿原来还有一个 ▾。弹层没了，箭头就不能留——一个点不动的控件画着
          // 「点我展开」的记号，比没有记号更糟。
          Text("永续")
            // 10pt 是界面上文字的下限（9.5 那一档小到得凑近看）；纯符号不在此列。
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.ink3)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(theme.raised2, in: RoundedRectangle(cornerRadius: 4))
            .padding(.leading, 3)
        }
        .lineLimit(1)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("当前品种 \(symbol)")
      .accessibilityIdentifier("top.symbol")

      Spacer(minLength: 0)

      // 右上角这两颗单独成一组，间距 14 不是 9。
      //
      // 托底还是 30pt（用户定过的尺度，一点没动），命中区撑到 44×44（见 `iconButton`）。
      // 两颗之间的**步距**必须 ≥44 才不会让两块命中区叠在一起——叠上了就会出现
      // 「明明点的是搜索，开的是复盘」这种谁也说不清的一下。30 + 14 = 44，正好首尾相接：
      // 缝里没有点不着的死区，也没有归属不清的重叠带。多出来的 5pt 从 `Spacer` 里出，
      // 左边的品种名一个点都没挪。
      HStack(spacing: 14) {
        if let onReview {
          iconButton(VectorIcon.indicator, label: "复盘", action: onReview)
            .accessibilityIdentifier("top.review")
            .overlay(alignment: .topTrailing) {
              if reviewCount > 0 {
                Text("\(min(reviewCount, 99))")
                  // 角标里也是字，一样守 10pt 这个下限。
                  .font(.system(size: 10, weight: .semibold))
                  .foregroundStyle(theme.badgeInk)
                  .padding(.horizontal, 4).padding(.vertical, 1.5)
                  .background(theme.amber, in: Capsule())
                  .offset(x: 5, y: -3)
                  .allowsHitTesting(false)
              }
            }
        }

        iconButton(VectorIcon.search(15), label: "搜索品种", action: onSearch)
          .accessibilityIdentifier("top.search")
      }
    }
  }

  /// 最左边那颗返回。和右上角两颗圆按钮同一副托底（30pt `raised` 圆 + 二级墨色），
  /// 箭头照板块页 `SectorBackButton` 的 15pt semibold —— 整个 app 的返回只有一种长相。
  private func backButton(_ action: @escaping () -> Void) -> some View {
    Button {
      iconTapCount += 1
      action()
    } label: {
      Image(systemName: "chevron.left")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(theme.ink2)
        .frame(width: 30, height: 30)
        .background(theme.raised, in: Circle())
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(-7)
    .accessibilityLabel("返回")
    .accessibilityIdentifier("top.back")
  }

  /// 右上角的圆按钮：30pt 的托底 + 15pt 的线性图标（用户定过的尺度）。
  /// 图标用二级墨色配一层中性托底，不要用强调色填满——它旁边就是价格，
  /// 填满会把视线从价格上抢走。
  private func iconButton(
    _ icon: VectorIcon, label: String, action: @escaping () -> Void
  ) -> some View {
    Button {
      iconTapCount += 1
      action()
    } label: {
      icon
        .foregroundStyle(theme.ink2)
        .frame(width: 30, height: 30)
        .background(theme.raised, in: Circle())
        // 画出来的还是 30pt，手指够得着的是 44×44。
        //
        // 放大只能写在 `label` 里面：`Button` 认的是标签自己的 `contentShape`，
        // 套在按钮外面的 `frame` 它一点都不认。外面那句 `-7` 再把**版面**收回 30×30，
        // 顶栏一个点都没变高——多出来的那一圈竖着落在顶栏与价格行之间那 9pt 的空隙里，
        // 够不到价格行上那个横滑换品种的手势（`MainScreen.header`）。
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(-7)
    .accessibilityLabel(label)
    // 点击计数只给 UI 用例读，**只在 DEBUG 构建里挂上去**（审查 C-02）：
    // 正式包的读屏不该因为一个环境变量多念一串数字。
    .accessibilityValue(diagnosticsValue)
  }

  private var diagnosticsValue: String {
    #if DEBUG
    return ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1" ? String(iconTapCount) : ""
    #else
    return ""
    #endif
  }
}


/// 价格块：左边一列「大价 + 涨跌幅药丸」，右边两列三行六格（§9.1，2026-09-20 改版）。
///
/// 涨跌幅用币安 `ticker24h` 的 `P` 字段，不自己算（§4.4）；最新价的颜色跟着它走，
/// 和原型 `renderTop()` 一致——不是跟着「这一根的涨跌」走。
///
/// 价和涨跌幅永远是头部的主角：一屏看下来先看到的就该是「现在多少钱、今天涨没涨」。
/// 主角地位靠对比建立而不是靠字号——价停在 22pt 的等宽数字（跳数时行宽不动），
/// 涨跌幅做成填色药丸带方向箭头，这两样一起就够抢眼了，别再往大里加。
///
/// 右边六格是 AICoin 头部块（`ui_ticker_include_detail_price_block.xml`）的标签习惯：
/// **仓 / 额 · 市值 / 费率 · 结算 / 振幅**，标签在左、数值在右，两列各自对齐。
/// AICoin 自己那格写的是单字 `FR`，这儿按用户 2026-09-18 的定稿写「费率」。AICoin 实测是
/// 数值 13sp、标签 11sp，落到这儿降到 11.5 / 10——它那块整体比我们大一档（主价 26sp），
/// 照搬会把配角做得和主价一样响。持仓那一格按 AICoin 的样子重一档字重。
///
/// 2026-09-20 从四格变六格：结算倒计时从费率格里搬出来单独成格（挤在一起时
/// 两串数糊成一团），振幅补回右下角（口径见 `HeaderStats.amplitudeText`）。
/// 头部为此高一行统计，图表让出这几十 pt——用户的原则是「上部不够可以压缩图表，
/// 但头部的字不许靠缩、截、挤来凑」。
/// 拿不到的格子一律 `--`（只有「结算」是留空），不解释、不弹提示。
struct PriceRow: View {
  var theme: PanelTheme
  var ticker: Ticker?
  var lastPrice: Double?
  var decimals: Int
  /// 成交额的单位由外面按品种钉住（见 `MarketModel.volumeUnit`），这儿不自己挑。
  var volumeUnit: VolUnit?
  /// 持仓量（**只认美元名义**，见 `HeaderStats.openInterestText`）和它钉住的单位。
  var openInterest: Double?
  var openInterestUnit: VolUnit?
  /// 总供应量（后端给）。市值在这儿乘出来，乘的就是上面那口正在显示的价，
  /// 不会出现「价已经跳了、市值还是上一口算的」。
  var totalSupply: Double?
  /// 资金费率，已经是小数（`0.0001` = 0.01%）。超过展示寿命的帧由外面先判成 `nil`
  /// （`MarketModel.displayedFundingRate`），这儿看到的就是「现在还算数」的值。
  var fundingRate: Double?
  /// 下一次资金费率结算的时刻（`MarkPriceTick.nextFundingTime`）。「结算」那一格
  /// 读它；没有就留空（见 `HeaderStats.fundingCountdownText`）。
  var nextFundingTimeMs: Int64?
  /// 这口价不能当「现在的价」看：上一条线路留下的，或者这个品种已经不在交易了。
  /// 灰显，不改字号也不加任何说明文字——「为什么是灰的」不需要解释，新数据到了
  /// 它自己就亮回来（§2B #54）。
  ///
  /// 除了灰显，它还会把「额 / 市值 / 费率 / 振幅」几格压成 `--`（审查 B.8）：那几个数
  /// 和价来自同一帧，价已经判定为旧的，它们摆在那儿只会让人当成现在的数。
  var stale = false

  private var pct: Double? {
    guard let value = ticker?.changePercent, value.isFinite else { return nil }
    return value
  }
  private var tint: Color {
    guard let pct else { return theme.ink }
    return pct >= 0 ? theme.up : theme.down
  }

  /// 头部：左边价 + 涨跌药丸，右边两列三行六格（仓/额 · 市值/费率 · 结算/振幅）。
  ///
  /// **一套版面走到底**：宽屏和 iPhone SE 是同一组格子、同一档字号，没有一个写死的
  /// 宽度。六格里没有一个字会被缩（`minimumScaleFactor` 全撤了）或被截：每一列自己是
  /// 一张两列 `Grid`，列宽按这一列里最宽的那一格算，数变长格子就变宽。
  /// 屏宽不够时变的只有空当和摆法（见下面那三档候选），字一个点都不动。
  ///
  /// 比上一版高一行：倒计时从费率格里搬出来单独成格（用户看到那两串数挤在一起），
  /// 顺手把 24h 振幅补回右下角。图表纵向余量足，让出这几十 pt 是用户 2026-09-20
  /// 定的取舍——「上部空间不够时可以压缩图表区域，但头部的字不许靠缩、截、挤来凑」。
  ///
  /// 价与药丸那一块在这三行的高度里**垂直居中**（`alignment: .center`），
  /// 不再顶着第一行的基线跑。
  ///
  /// 三档候选，`ViewThatFits` 从上往下挑第一个**整个装得下**的——挑的是间距和
  /// 摆法，不是字号：
  /// 1. 并排，间距照常（iPhone 16 Pro 这种宽屏）；
  /// 2. 并排，格与格之间紧一点（iPhone SE 375pt：宽屏那一档差几个 pt，
  ///    紧一点就整整齐齐，价还是 22pt 一个字不缩）；
  /// 3. 上下两块：价与药丸一行，六格整块挪到它下面。价特别长的品种走这一档，
  ///    头部再长高一截——长高好过把「80,848.00」截成「80,848....」。
  var body: some View {
    ViewThatFits(in: .horizontal) {
      sideBySide(gap: 12, columnSpacing: 14)
      sideBySide(gap: 8, columnSpacing: 10)
      stacked
    }
  }

  private func sideBySide(gap: CGFloat, columnSpacing: CGFloat) -> some View {
    HStack(alignment: .center, spacing: 0) {
      priceBlock
      Spacer(minLength: gap)
      stats(columnSpacing: columnSpacing)
    }
  }

  private var stacked: some View {
    VStack(alignment: .leading, spacing: 7) {
      priceBlock
      stats(columnSpacing: 14)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var priceBlock: some View {
    HStack(alignment: .firstTextBaseline, spacing: 9) {
      Text(lastText)
        .font(.system(size: 22, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(lastPrice == nil ? theme.ink : (stale ? theme.ink3 : tint))
        .lineLimit(1)
        .accessibilityIdentifier("top.lastPrice")
      pill
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  /// 涨跌幅药丸：填色 + 白字 + 方向箭头。填的色和自选表里那一列是同一支
  /// （`badgeFill`），两处对不上会让人以为是两个口径。
  private var pill: some View {
    HStack(spacing: 3) {
      if let pct {
        Image(systemName: pct >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
          .font(.system(size: 7.5))
      }
      Text(pct.map { ($0 >= 0 ? "+" : "") + toFixed($0, 2) + "%" } ?? "—")
        .font(.system(size: 11.5, weight: .semibold))
        .monospacedDigit()
    }
    // 窄屏（iPhone SE 这一档）上右边六格把这一行挤紧时，药丸里的「-1.09%」会被折成
    // 两行、头部当场再长高一截。它是一枚记号，不是一段话：钉死一行、按自己的字长占位。
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .foregroundStyle(pct == nil || stale ? theme.ink3 : theme.badgeInk)
    .padding(.horizontal, 7)
    .padding(.vertical, 3.5)
    .background(pct == nil || stale ? theme.raised2 : theme.badgeFill(up: pct! >= 0),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    .accessibilityIdentifier("top.changePercent")
  }

  /// 价格的小数位由品种自己说（`pricePrecision`），极小的正价会自动多给几位，
  /// 绝不四舍五入成 `0.00`（审查 B-07，规则在 `fmtPrice`）。
  private var lastText: String {
    guard let p = lastPrice else { return "—" }
    return grouped(fmtPrice(p, decimals: decimals))
  }

  // ---------------------------------------------------------------- 右侧六格
  // 六格取什么值全在 `HeaderStats` 里（纯函数，用例守着）；这儿只管画。
  // 单位由外面按品种钉住（§2B #53），`HeaderStats` 只在还没钉上时按眼前这个数认一次。

  private var turnoverText: String? {
    HeaderStats.turnoverText(quoteVolume: ticker?.quoteVolume, unit: volumeUnit, fresh: !stale)
  }

  private var openInterestText: String? {
    HeaderStats.openInterestText(value: openInterest, unit: openInterestUnit)
  }

  private var marketCapText: String? {
    HeaderStats.marketCapText(totalSupply: totalSupply, price: lastPrice, fresh: !stale)
  }

  private var fundingText: String? {
    HeaderStats.fundingText(rate: fundingRate, fresh: !stale)
  }

  /// 「振幅」= 24h (高 − 低) / 低。高低价和价来自同一帧，价旧了它一起 `--`。
  private var amplitudeText: String? {
    HeaderStats.amplitudeText(high: ticker?.high, low: ticker?.low, fresh: !stale)
  }

  /// 六格，两列三行：左列 仓 / 市值 / 结算，右列 额 / 费率 / 振幅。
  ///
  /// 上一版是 2×2，倒计时挤在费率值后面同一格里——用户看到的就是两串数糊成一团。
  /// 现在倒计时自己占「结算」那一格，右下角补上振幅，头部因此高一行统计。
  ///
  /// 宽度不再写死、也不再按屏宽分档：每一列自己是一张两列的 `Grid`（标签靠左、
  /// 值靠右），列宽按这一列里最宽的那一格算，数变长格子跟着变宽。
  /// `minimumScaleFactor` 全撤了——这六格的字一个都不缩、不截，装不下宁可
  /// 让头部再长高一点，图表让出那几十 pt（用户 2026-09-20 定的取舍）。
  ///
  /// `fixedSize` 是这条规矩的保险：谁也别想把这六格挤窄。两列之间默认 14pt，
  /// 一眼看出是两列而不是六个并排的词；窄屏上 `body` 会挑那档紧一点的（10pt），
  /// 紧的是空当，字一个都没动。
  private func stats(columnSpacing: CGFloat) -> some View {
    HStack(alignment: .top, spacing: columnSpacing) {
      statColumn {
        statRow("仓", openInterestText, id: "top.openInterest", heavy: true)
        statRow("市值", marketCapText, id: "top.marketCap")
        settlementRow
      }
      statColumn {
        statRow("额", turnoverText, id: "top.turnover")
        statRow("费率", fundingText, id: "top.funding", tint: frTint)
        statRow("振幅", amplitudeText, id: "top.amplitude")
      }
    }
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("top.stats")
  }

  private func statColumn<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
    Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 3) { rows() }
  }

  private func statRow(_ label: String, _ value: String?, id: String,
                       heavy: Bool = false, tint: Color? = nil) -> some View {
    GridRow {
      statLabel(label)
      statValue(value ?? "--", missing: value == nil, id: id, heavy: heavy, tint: tint)
    }
  }

  /// 「结算」：离下一次资金费率结算还有多久（`HeaderStats.fundingCountdownText`）。
  /// 时间自己会走，所以这一格带一根 30 秒的节拍（`TimelineView`）——只有它重画，
  /// 价格和药丸不受影响。拿不到结算时刻就**留空**：不写「--」，也不解释
  /// （留的是一个空格，为的是这一行的高度和另外两行一样）。
  private var settlementRow: some View {
    GridRow {
      statLabel("结算")
      TimelineView(.periodic(from: .now, by: 30)) { context in
        statValue(countdownText(now: context.date) ?? " ", missing: false, id: "top.settlement")
      }
      .gridColumnAlignment(.trailing)
    }
  }

  private func countdownText(now: Date) -> String? {
    guard !stale, fundingRate != nil else { return nil }
    return HeaderStats.fundingCountdownText(nextFundingTimeMs: nextFundingTimeMs, now: now)
  }

  /// 费率的正负是它唯一要读的信息，按涨跌色给——和药丸、自选表用的是同两支色。
  private var frTint: Color? {
    guard !stale, let r = fundingRate, r.isFinite, r != 0 else { return nil }
    return r > 0 ? theme.up : theme.down
  }

  private func statLabel(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 10))
      .foregroundStyle(theme.ink3)
      .gridColumnAlignment(.leading)
  }

  private func statValue(_ text: String, missing: Bool, id: String,
                         heavy: Bool = false, tint: Color? = nil) -> some View {
    Text(text)
      .font(.system(size: 11.5, weight: heavy ? .semibold : .medium))
      .monospacedDigit()
      .foregroundStyle(missing || stale ? theme.ink3 : (tint ?? theme.ink2))
      .gridColumnAlignment(.trailing)
      .accessibilityIdentifier(id)
  }
}

/// 给整数部分插千分位。只给头部这一个「大字价格」用：
/// 价格轴、十字线读数那些是密排的数据，加了分隔反而更挤。
func grouped(_ text: String) -> String {
  let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
  guard let head = parts.first else { return text }
  let neg = head.hasPrefix("-")
  let digits = Array(neg ? head.dropFirst() : head)
  guard digits.count > 4, digits.allSatisfy(\.isNumber) else { return text }
  var out: [Character] = []
  for (i, d) in digits.enumerated() {
    if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
    out.append(d)
  }
  let intPart = (neg ? "-" : "") + String(out)
  return parts.count > 1 ? intPart + "." + parts[1] : intPart
}



