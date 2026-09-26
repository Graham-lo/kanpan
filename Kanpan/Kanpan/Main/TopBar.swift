import KanpanCore
import KanpanData
import ReviewUI
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
/// 2026-09-24（审查 U6）它的记号从借来的「指标」折线换成专属的 `ReviewGlyph`（一本带书签的
/// 复盘本）。这颗只负责**进复盘本**；「记一笔」只留两处：图表设置里的那一行、复盘本右上角的「+」。
///
/// 字号、间距、图标一律取 `DesignTokens` 的令牌（UI 审查 2026-09-24 §4.3 #4–#12），别自己发挥——
/// 这一条和价格行是整个 app 里唯一常驻的文字，差一点点立刻显得不像同一个应用。
/// 层级：品种名 16 semibold（`TypeScale.heading`，不用 bold——它不该比 22 的价格更「黑」）
/// > 计价币 12 regular 次墨色 > 「永续」角标 11。
struct TopBar: View {
  @State private var iconTapCount = 0
  var theme: PanelTheme
  var symbol: String
  /// 复盘本：角标画它还欠着答案的条数，0 就不画。传的是整只 feature 而不是算好的数——
  /// 数由下面的 `ReviewCountBadge` 自己在它的 body 里读，见那边的注释。
  var review: ReviewFeature?
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
    HStack(spacing: Space.s) {
      if let onBack {
        backButton(onBack)
      }
      HStack(spacing: Space.s) {
        CoinBadge(base: base, size: ControlMetrics.badge)
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
          Text(base)
            .font(TypeScale.heading)
            .foregroundStyle(theme.ink)
          if !quote.isEmpty {
            Text("/" + quote)
              .font(TypeScale.caption)
              .foregroundStyle(theme.ink3)
          }
          // 这儿原来还有一个 ▾。弹层没了，箭头就不能留——一个点不动的控件画着
          // 「点我展开」的记号，比没有记号更糟。
          Text(InstrumentID(symbol).productLabel)
            // 11pt 是 HIG 的文字下限（原来 10）；纯符号不在此列。
            .font(TypeScale.caption2Emph)
            .foregroundStyle(theme.ink3)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, Space.xxs)
            .background(theme.raised2, in: RoundedRectangle(cornerRadius: Radius.xs))
            .padding(.leading, Space.xs)
        }
        .lineLimit(1)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("当前品种 \(InstrumentID(symbol).display)")
      .accessibilityIdentifier("top.symbol")

      Spacer(minLength: 0)

      // 右上角这两颗单独成一组，间距 12 不是 8。
      //
      // 托底 32pt（`ControlMetrics.iconDisc`，UI 审查 2026-09-24 从 30 调上来），命中区撑到
      // 44×44（见 `iconButton`）。两颗之间的**步距**必须 ≥44 才不会让两块命中区叠在一起——
      // 叠上了就会出现「明明点的是搜索，开的是复盘」这种谁也说不清的一下。32 + 12 = 44，
      // 正好首尾相接：缝里没有点不着的死区，也没有归属不清的重叠带。
      HStack(spacing: Space.m) {
        if let onReview {
          iconButton(ReviewGlyph(theme: theme), label: "复盘", action: onReview)
            .accessibilityIdentifier("top.review")
            .overlay(alignment: .topTrailing) {
              if let review { ReviewCountBadge(review: review, theme: theme) }
            }
        }

        iconButton(VectorIcon.search(16), label: "搜索品种", action: onSearch)
          .accessibilityIdentifier("top.search")
      }
    }
  }

  /// 最左边那颗返回。和右上角两颗圆按钮同一副托底（32pt `raised` 圆 + 二级墨色），
  /// 箭头 16pt semibold（UI 审查 2026-09-24 §4.3 #12）。
  private func backButton(_ action: @escaping () -> Void) -> some View {
    Button {
      iconTapCount += 1
      action()
    } label: {
      Image(systemName: "chevron.left")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(theme.ink2)
        .frame(width: ControlMetrics.iconDisc, height: ControlMetrics.iconDisc)
        .background(theme.raised, in: Circle())
        .frame(width: Hit.min, height: Hit.min)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(Self.hitOverhang)
    .accessibilityLabel("返回")
    .accessibilityIdentifier("top.back")
  }

  /// 命中区 44 比托底 32 多出来的那一圈，用负边距从版面里收回去。
  private static let hitOverhang = -(Hit.min - ControlMetrics.iconDisc) / 2

  /// 右上角的圆按钮：32pt 的托底 + 16pt 的线性图标。
  /// 图标用二级墨色配一层中性托底，不要用强调色填满——它旁边就是价格，
  /// 填满会把视线从价格上抢走。
  private func iconButton<Icon: View>(
    _ icon: Icon, label: String, action: @escaping () -> Void
  ) -> some View {
    Button {
      iconTapCount += 1
      action()
    } label: {
      icon
        .foregroundStyle(theme.ink2)
        .frame(width: ControlMetrics.iconDisc, height: ControlMetrics.iconDisc)
        .background(theme.raised, in: Circle())
        // 画出来的是 32pt，手指够得着的是 44×44。
        //
        // 放大只能写在 `label` 里面：`Button` 认的是标签自己的 `contentShape`，
        // 套在按钮外面的 `frame` 它一点都不认。外面那句 `hitOverhang`（-6）再把**版面**收回 32×32，
        // 顶栏一个点都没变高——多出来的那一圈竖着落在顶栏与价格行之间那 8pt 的空隙里，
        // 够不到价格行上那个横滑换品种的手势（`MainScreen.header`）。
        .frame(width: Hit.min, height: Hit.min)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(Self.hitOverhang)
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
///
/// 字号全取 `TypeScale`（UI 审查 2026-09-24 §4.3 #13–#21），五档都在 HIG 阶梯上：
/// 最新价 22 medium（`.title2`）> 涨跌行 13 medium（`.footnote`）> 六格的值 12 medium
/// 等宽数字（`.caption`）> 六格标签 11 regular 次墨色（`.caption2`）。原来涨跌行和六格的值
/// 都是 13 semibold，右边六个墨色粗数压过了浅色的价格，眼睛先落到右边。
struct PriceRow: View {
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
  /// 第六格（估值）要的：这只是什么，以及股票的两项估值底数（美元）。
  /// 规则在 `HeaderStats.valuationCell`。
  var asset: SymbolClassification.Asset = .other
  var forwardEarnings: Double?
  var revenue: Double?
  /// 下一次资金费率结算的时刻（`MarkPriceTick.nextFundingTime`）。「结算」那一格
  /// 读它；没有就显示破折号（见 `HeaderStats.fundingCountdownText`）。
  var nextFundingTimeMs: Int64?
  /// 这口价不能当「现在的价」看：上一条线路留下的，或者这个品种已经不在交易了。
  /// 灰显，不改字号也不加任何说明文字——「为什么是灰的」不需要解释，新数据到了
  /// 它自己就亮回来（§2B #54）。
  ///
  /// 除了灰显，它还会把「额 / 市值 / 费率」几格压成 `—`（审查 B.8）：那几个数
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
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(lastText)
          .font(TypeScale.price)
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
          .font(TypeScale.footnoteEmph)
          .monospacedDigit()
          .foregroundStyle(stale || ticker?.priceChange == nil || pct == nil ? theme.ink3 : tint)
          .accessibilityIdentifier("top.changePercent")
      }
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      Spacer(minLength: Space.l)
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

  private var valuationCell: (label: String, value: String?)? {
    HeaderStats.valuationCell(asset: asset, openInterest: openInterest, totalSupply: totalSupply,
                              price: lastPrice, forwardEarnings: forwardEarnings,
                              revenue: revenue, fresh: !stale)
  }

  /// 每列按最宽的实值分配；间距固定，不缩字、不截字、不换行。
  /// 列距 16、标签↔值 8、行距 2：三行总高约 47pt（原来 53），不向图表借高度。
  /// 六格：左列仓 / 市值 / 结算，右列额 / 费率 / 估值（振幅 2026-09-25 去掉，
  /// 同日用户要把第六格补成估值：币 OI/MC，股票 Fwd PE 或 P/S，别的类别没有这一格）。
  private var stats: some View {
    HStack(alignment: .top, spacing: Space.l) {
      statColumn {
        statRow("仓", openInterestText, id: "top.openInterest")
        statRow("市值", marketCapText, id: "top.marketCap")
        settlementRow
      }
      statColumn {
        statRow("额", turnoverText, id: "top.turnover")
        statRow("费率", fundingText, id: "top.funding", tint: frTint)
        if let cell = valuationCell {
          statRow(cell.label, cell.value, id: "top.valuation")
        }
      }
    }
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("top.stats")
  }

  private func statColumn<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
    Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: Space.xxs) { rows() }
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
      .font(TypeScale.caption2)
      .foregroundStyle(theme.ink3)
      .gridColumnAlignment(.leading)
  }

  private func statValue(_ text: String, missing: Bool, id: String,
                         tint: Color? = nil) -> some View {
    Text(text)
      .font(TypeScale.captionEmph)
      .monospacedDigit()
      .foregroundStyle(missing || stale ? theme.ink3 : (tint ?? theme.ink))
      .gridColumnAlignment(.trailing)
      .accessibilityIdentifier(id)
  }
}

/// 复盘按钮上的角标。单独成一个视图，是为了让「数欠着几条」这件事只跟着复盘记录走：
/// `pendingCount` 每读一次都要把全部记录过滤一遍（几千条），原来是顶栏在自己的 body 里
/// 读好再传下来，而顶栏跟着逐笔成交一秒重画好几次——每一跳都白扫一遍复盘本。
/// 现在顶栏只把 feature 这个引用递下来：引用没变，SwiftUI 不重跑这里的 body；
/// 这里的 body 只登记了 `records`，记录真变了才重数。
struct ReviewCountBadge: View {
  let review: ReviewFeature
  let theme: PanelTheme
  #if DEBUG
    /// 测试用：这块 body 一共求值了几次。
    static var bodies = 0
  #endif

  var body: some View {
    #if DEBUG
      let _ = Self.bodies += 1
    #endif
    let count = review.pendingCount
    if count > 0 {
      Text("\(min(count, 99))")
        // 角标里也是字，一样守 11pt 这个下限。
        .font(TypeScale.caption2Emph)
        .foregroundStyle(theme.badgeInk)
        .padding(.horizontal, Space.xs).padding(.vertical, Space.xxs)
        .background(theme.amber, in: Capsule())
        .offset(x: 5, y: -3)
        .allowsHitTesting(false)
    }
  }
}
