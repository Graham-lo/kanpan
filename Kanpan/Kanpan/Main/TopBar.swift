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
    SymbolInfo.placeholder(symbol: symbol).base
  }
  private var quote: String { SymbolInfo.placeholder(symbol: symbol).quote }

  var body: some View {
    HStack(spacing: 9) {
      if let onBack {
        backButton(onBack)
      }
      HStack(spacing: 9) {
        CoinBadge(base: base, size: 29)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(base)
            .font(.scaled(15.5, .bold))
            .foregroundStyle(theme.ink)
          if !quote.isEmpty {
            Text("/" + quote)
              .font(.scaled(12, .medium))
              .foregroundStyle(theme.ink3)
          }
          // 这儿原来还有一个 ▾。弹层没了，箭头就不能留——一个点不动的控件画着
          // 「点我展开」的记号，比没有记号更糟。
          Text(InstrumentID(symbol).productLabel)
            // 10pt 是界面上文字的下限（9.5 那一档小到得凑近看）；纯符号不在此列。
            .font(.scaled(10, .medium))
            .foregroundStyle(theme.ink3)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(theme.raised2, in: RoundedRectangle(cornerRadius: 4))
            .padding(.leading, 3)
        }
        .lineLimit(1)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("当前品种 \(InstrumentID(symbol).display)")
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
                  .font(.scaled(10, .semibold))
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


/// 行情页价格行：左侧价格与涨跌小字，右侧两列三行数据。
/// 六格始终在价格右侧；字号跟随系统，但密集数据行有独立封顶。
struct PriceRow: View {
  @ScaledMetric(relativeTo: .body) private var priceSize: CGFloat = 22
  @ScaledMetric(relativeTo: .body) private var changeSize: CGFloat = 13
  @ScaledMetric(relativeTo: .body) private var labelSize: CGFloat = 12
  @ScaledMetric(relativeTo: .body) private var valueSize: CGFloat = 13
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var theme: PanelTheme
  /// 这口价属于哪只：完整品种键（`venue/market/symbol`，即 `MarketModel.symbol`）。
  /// 价格的逐位滚动只在同一个键下做，换了键就直接换字（见 `body`）。
  var instrument: String
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
  /// 读它；没有就显示破折号（见 `HeaderStats.fundingCountdownText`）。
  var nextFundingTimeMs: Int64?
  /// 这口价不能当「现在的价」看：上一条线路留下的，或者这个品种已经不在交易了。
  /// 灰显，不改字号也不加任何说明文字——「为什么是灰的」不需要解释，新数据到了
  /// 它自己就亮回来（§2B #54）。
  ///
  /// 除了灰显，它还会把「额 / 市值 / 费率 / 振幅」几格压成 `—`（审查 B.8）：那几个数
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

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      VStack(alignment: .leading, spacing: 3) {
        Text(lastText)
          .font(.system(size: priceSize, weight: .medium))
          .monospacedDigit()
          .foregroundStyle(lastPrice == nil || stale ? theme.ink3 : tint)
          // 跳价时逐位滚过去（P2.8），只动变了的那几位；「减少动效」下直接换字。
          .contentTransition(reduceMotion ? .identity : .numericText(value: lastPrice ?? 0))
          .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: lastText)
          // 逐位滚动只在**同一只**里做。换品种（横滑扫图、搜索、自选 / 板块点进）时
          // 视图身份跟着完整品种键换掉：新的那只的价直接落（有种子就是种子，没有就是「—」），
          // 不从上一只的数滚过来——否则标题已经是 ETH，底下还闪过一串 BTC 量级的数。
          .id(instrument)
          .transition(.identity)
          .accessibilityIdentifier("top.lastPrice")
        Text(HeaderStats.priceChangeText(change: ticker?.priceChange, percent: pct, decimals: decimals))
          .font(.system(size: changeSize, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(stale || ticker?.priceChange == nil || pct == nil ? theme.ink3 : tint)
          .accessibilityIdentifier("top.changePercent")
      }
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      Spacer(minLength: 8)
      stats
    }
    // 换品种这一下整行不带任何动画（哪怕外面的事务带着）：旧那只的价当场拿掉，
    // 不留一帧淡出，涨跌与六格也直接换成新那只的数。
    .transaction(value: instrument) { $0.animation = nil }
  }

  /// 价格的小数位由品种自己说（`priceDecimals`，按 `tickSize` 推），极小的正价会自动多给几位，
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

  /// 「振幅」= 24h (高 − 低) / 低。高低价和价来自同一帧，价旧了它一起 `—`。
  private var amplitudeText: String? {
    HeaderStats.amplitudeText(high: ticker?.high, low: ticker?.low, fresh: !stale)
  }

  /// 每列按最宽的实值分配；间距固定，不缩字、不截字、不换行。
  private var stats: some View {
    HStack(alignment: .top, spacing: 14) {
      statColumn {
        statRow("仓", openInterestText, id: "top.openInterest")
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
                       tint: Color? = nil) -> some View {
    GridRow {
      statLabel(label)
      statValue(value ?? "—", missing: value == nil, id: id, tint: tint)
    }
  }

  /// 倒计时独立刷新，缺数与其它格一样显示破折号。
  private var settlementRow: some View {
    GridRow {
      statLabel("结算")
      TimelineView(.periodic(from: .now, by: 30)) { context in
        statValue(countdownText(now: context.date) ?? "—",
                  missing: countdownText(now: context.date) == nil, id: "top.settlement")
      }
      .gridColumnAlignment(.trailing)
    }
  }

  private func countdownText(now: Date) -> String? {
    guard !stale, fundingRate != nil else { return nil }
    return HeaderStats.fundingCountdownText(nextFundingTimeMs: nextFundingTimeMs, now: now)
  }

  /// 费率的正负是它唯一要读的信息，按涨跌色给，与价格和涨跌小字使用同两支色。
  private var frTint: Color? {
    guard !stale, let r = fundingRate, r.isFinite, r != 0 else { return nil }
    return r > 0 ? theme.up : theme.down
  }

  private func statLabel(_ text: String) -> some View {
    Text(text)
      .font(.system(size: labelSize))
      .foregroundStyle(theme.ink3)
      .gridColumnAlignment(.leading)
  }

  private func statValue(_ text: String, missing: Bool, id: String,
                         tint: Color? = nil) -> some View {
    Text(text)
      .font(.system(size: valueSize, weight: .semibold))
      .monospacedDigit()
      .foregroundStyle(missing || stale ? theme.ink3 : (tint ?? theme.ink))
      .gridColumnAlignment(.trailing)
      .accessibilityIdentifier(id)
  }
}
