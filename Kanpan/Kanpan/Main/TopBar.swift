import KanpanCore
import KanpanData
import KanpanNetwork
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
/// 2026-09-18 到 09-26 右上角还有一颗「复盘」（带待判定角标）。2026-09-27 撤了（方案
/// `docs/方案-我的-自动复盘-周期分组指标-2026-09-27.md` §1.4）：复盘本是「我的」页里的一块，
/// 角标挂到底栏「我的」记号上；「记一笔」仍在图表设置「这张图」与复盘本右上角的「+」，
/// 深链 `hkline://review/<id>` 和到点通知的去处不变。顶栏只剩徽章 + 品种名 + 放大镜。
///
/// 2026-09-28（乙方案）右上角变成一簇三颗圆片，从左到右「记一笔 · 分享 · 搜索」：
/// 用户的话是「记一笔」「分享」不该藏在图表设置里，它们是看着这张图时才会做的动作，
/// 就放在这张图的顶上。记一笔用早先顶栏那本带书签的复盘本记号（`ReviewGlyph`），
/// 分享用系统的分享符号。图表设置里原来那一节「这张图」整节撤掉。三颗步距 12
/// （32 + 12 = 44，命中区首尾相接，缝里没有死区）。左侧只剩返回圆片和品种名，
/// 品种名仍然不是按钮。
///
/// 2026-10-05 照 TradingView 手机版再加两颗，右上角变成一簇五颗，从左到右
/// 「对比＋ · 提醒铃 · 记一笔 · 分享 · 搜索」：对比从「分析」面板那一节搬上来（加号开搜索页的
/// 对比模式，集合里有品种时加号亮强调色），铃开「提醒」那张表（列表 / 日志），角上一颗数字
/// 是这只还没响的提醒条数，0 条不画。五颗步距从 12 收到 8：32 × 5 + 8 × 4 = 192
/// （步距 12 要 208，16 Pro 有返回时品种块只剩 106pt，「BTC/USDT」都放不下）；命中区 44
/// 相邻两颗叠 4pt，缝里同样没有死区。品种块放不下「永续」角标时先把角标收掉（`ViewThatFits`）。
///
/// 2026-10-08 右上角从五颗收成三颗「提醒铃 · ⋯ · 搜索」。用户的原话：「分享和记一笔用的极少，
/// 我觉得可以放到二级菜单里」。「⋯」是一颗和铃、放大镜同一副托底（32pt `raised` 圆、二级墨色）的
/// 省略号圆片，点开一个系统菜单（`Menu`），从上到下「添加对比 · 记一笔 · 分享」——对比也一起收进去：
/// 它在「分析」面板里本来就有一处入口（10-06 用户定的必须保留，两处开同一张对比模式搜索页），
/// 顶栏这一颗是重复的；常驻在外面的只剩真天天点的提醒和搜索。对比满三只时「添加对比」那一项禁用；
/// 加号「有对比时亮强调色」那套跟着撤了——图上的图例已经写着在对比哪几只。三项全是 nil（复盘回放、
/// 画线预览、看朋友分享的线）时「⋯」整颗不画。
/// 宽度算术（16 Pro 402pt，两侧页边 16，可用 370）：步距回到 `Space.m`（12），簇宽 32 × 3 + 12 × 2 = 120，
/// 命中区 44 正好首尾相接；簇和品种块之间隔着 Spacer，两道 `Space.s`（8 × 2）。没返回键时品种块
/// 370 − 120 − 16 = 234pt，有返回键再让出返回圆片 32 + 8，剩 194pt——「徽章 BTC/USDT 永续」约 143pt，
/// 带返回键也整行放得下，长名字（PUMPBTC）才会走到 `ViewThatFits` 的后几档。
///
/// 字号、间距、图标一律取 `DesignTokens` 的令牌（UI 审查 2026-09-24 §4.3 #4–#12），别自己发挥——
/// 这一条和价格行是整个 app 里唯一常驻的文字，差一点点立刻显得不像同一个应用。
/// 层级：品种名 16 semibold（`TypeScale.heading`，不用 bold——它不该比 22 的价格更「黑」）
/// > 角标 11（交易所小标 + 「USDT 永续」，2026-10-08 起计价币不再单列 12pt 那一截）。
struct TopBar: View {
  @State private var iconTapCount = 0
  var theme: PanelTheme
  var symbol: String
  /// 有来路就有返回。非 nil 时最左边多一颗返回箭头，回到把人送进这张图的那一页
  /// （板块下钻、自选行）。从底栏直接点进来的「图表」没有来路，这颗就不画——
  /// 常驻标签栏那一格自己就是家，返回无处可去。
  var onBack: (() -> Void)?
  /// 「⋯」菜单里的「记一笔」：把这张图存进复盘本。复盘回放、画线预览这类没有「这张图」可记的时候传 nil，那一项不排。
  var onNote: (() -> Void)? = nil
  /// 「⋯」菜单里的「分享」：这张图的图片或画线（两种都能用时弹二选一）。没有可分享的时候传 nil，那一项不排。
  var onShare: (() -> Void)? = nil
  /// 「⋯」菜单里的「添加对比」：开搜索页的对比模式。没有「这张图」可对比的时候（复盘回放、画线预览）传 nil，那一项不排。
  /// 三项全是 nil 时「⋯」整颗不画。
  var onCompare: (() -> Void)? = nil
  /// 对比集合已满三只（`CompareSearchMode.isFull`）：「添加对比」那一项禁用。
  var compareFull = false
  /// 「提醒」：开提醒那张表（列表 / 日志）。传 nil 不画。
  var onAlerts: (() -> Void)? = nil
  /// 这只还没响的提醒有几条（`AlertRecordText.records`）。0 不画角标。
  var alertCount = 0
  var onSearch: () -> Void

  /// 「BTCUSDT」拆成「BTC」+「USDT」：品种名只写基础币（正文色），计价币进角标小字
  /// （2026-10-08 用户定：「不再显示 DOGE/USDT，直接显示 DOGE，然后 USDT 永续小字」）。
  private var base: String {
    SymbolInfo.placeholder(symbol: symbol).base
  }
  private var quote: String { SymbolInfo.placeholder(symbol: symbol).quote }

  var body: some View {
    HStack(spacing: Space.s) {
      if let onBack {
        backButton(onBack)
      }
      // 品种块先让右边三颗圆片：三颗固定 32 × 3 + 12 × 2 = 120，余下的全归品种名
      // （16 Pro 402pt，页边 16、品种块两侧各一道 `Space.s`：没返回时 370 − 120 − 16 = 234pt；
      // 有返回时再让出返回圆片 32 + 8，剩 194pt，`徽章 BTC/USDT 永续`（约 143pt）也整行放得下）。
      //
      // 「永续 / 现货」角标**不许被挤掉**（2026-10-08 走查）：自选里现货和永续挨着放，
      // 从自选点进来带着返回键一路横滑扫图，扫到哪一只是现货、哪一只是永续全靠它；
      // 原来先收角标，一出返回键角标就没了，看着像换了一种品种。
      // 现在放不下时先收币种徽章（左边已经有返回键顶着，少一颗圆不显空），再收计价币，
      // 最后才截基础币——角标一直在。`layoutPriority` 让它比右边的 Spacer 先拿宽度。
      // 2026-10-08 用户定：品种名只写基础币（`DOGE`），不再写 `/USDT`；计价币并进角标写成
      // 「USDT 永续」小字，角标前面是交易所的小标。放不下时先收徽章，再截基础币，角标一直在。
      ViewThatFits(in: .horizontal) {
        symbolBlock(badge: true)
        symbolBlock(badge: false)
        symbolBlock(badge: false).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
      }
      .layoutPriority(1)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("当前品种 \(InstrumentID(symbol).display)")
      .accessibilityIdentifier("top.symbol")

      Spacer(minLength: 0)

      // 右上角一簇三颗：提醒 · ⋯ · 搜索（2026-10-08）。托底 32pt（`ControlMetrics.iconDisc`），
      // 命中区撑到 44×44（见 `iconButton`），步距 12，相邻两颗的命中区首尾相接。
      HStack(spacing: Self.clusterSpacing) {
        if let onAlerts {
          // 角标对读屏是隐藏的，条数念在标签里（「提醒 2」）。
          iconButton(TopBarGlyph.bell(17), label: alertCount > 0 ? "提醒 \(alertCount)" : "提醒", action: onAlerts)
            .accessibilityIdentifier("top.alerts")
            .overlay(alignment: .topTrailing) {
              if alertCount > 0 { AlertCountBadge(count: alertCount, theme: theme) }
            }
        }
        if onCompare != nil || onNote != nil || onShare != nil {
          moreMenu
        }
        iconButton(VectorIcon.search(16), label: "搜索品种", action: onSearch)
          .accessibilityIdentifier("top.search")
      }
    }
  }

  /// 「⋯」：用得少的三件收在这儿（2026-10-08），从上到下「添加对比 · 记一笔 · 分享」。
  /// 菜单项沿用原来三颗圆片的 id（`top.compare` / `top.note` / `top.share`），哪个闭包是 nil 就不排哪一项。
  private var moreMenu: some View {
    Menu {
      if let onCompare {
        Button {
          iconTapCount += 1
          onCompare()
        } label: {
          Label("添加对比", systemImage: "plus")
        }
        .disabled(compareFull)
        .accessibilityIdentifier("top.compare")
      }
      if let onNote {
        Button {
          iconTapCount += 1
          onNote()
        } label: {
          Label("记一笔", systemImage: "square.and.pencil")
        }
        .accessibilityIdentifier("top.note")
      }
      if let onShare {
        Button {
          iconTapCount += 1
          onShare()
        } label: {
          Label("分享", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("top.share")
      }
    } label: {
      disc(TopBarGlyph.more(16))
    }
    // 菜单从圆片下沿展开，项的顺序就按上面写的来，不让系统按弹出方向倒排。
    .menuOrder(.fixed)
    .menuStyle(.button)
    .buttonStyle(.plain)
    .padding(Self.hitOverhang)
    .accessibilityLabel("更多")
    .accessibilityValue(diagnosticsValue)
    .accessibilityIdentifier("top.more")
  }

  /// 右上角那簇圆片的步距（见文件头 2026-10-08 那段的算术）：12，32 + 12 = 44，命中区首尾相接。
  static let clusterSpacing = Space.m

  /// （放得下时）徽章 + 基础币名 + 角标「交易所小标 · 计价币 永续 / 现货」（总在）。
  private func symbolBlock(badge: Bool) -> some View {
    HStack(spacing: Space.s) {
      if badge { CoinBadge(base: base, size: ControlMetrics.badge) }
      HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
        Text(base)
          .font(TypeScale.heading)
          .foregroundStyle(theme.ink)
          // 最后那一档放不下时只截基础币，角标不让。
          .layoutPriority(-1)
        // 这儿原来还有一个 ▾。弹层没了，箭头就不能留——一个点不动的控件画着
        // 「点我展开」的记号，比没有记号更糟。
        // 角标文字 = 交易所缩写 + 计价币 + 产品（「币安 USDT 永续」「CB USD 现货」「HL USDC 永续」）；
        // 没有缩写、没有计价币的（美元指数）只剩「指数」。用户 2026-10-08：品种按交易所分了，
        // 行情页要带上交易所，用文字缩写（币安 / OKX / Bybit / HL / CB），不用图标。
        let tag = [VenueRegistry.descriptor(forSymbol: symbol).shortName, quote, InstrumentID(symbol).productLabel]
          .filter { !$0.isEmpty }.joined(separator: " ")
        if !tag.isEmpty {
          Text(tag)
            // 11pt 是 HIG 的文字下限（原来 10）；纯符号不在此列。
            .font(TypeScale.caption2Emph)
            .foregroundStyle(theme.ink3)
            .fixedSize()
            .padding(.horizontal, Space.xs)
            .padding(.vertical, Space.xxs)
            .background(theme.raised2, in: RoundedRectangle(cornerRadius: Radius.xs))
            .padding(.leading, Space.xs)
        }
      }
      .lineLimit(1)
    }
  }

  /// 最左边那颗返回。和右上角放大镜同一副托底（32pt `raised` 圆 + 二级墨色），
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
      disc(icon)
    }
    .buttonStyle(.plain)
    .padding(Self.hitOverhang)
    .accessibilityLabel(label)
    // 点击计数只给 UI 用例读，**只在 DEBUG 构建里挂上去**（审查 C-02）：
    // 正式包的读屏不该因为一个环境变量多念一串数字。
    .accessibilityValue(diagnosticsValue)
  }

  /// 圆片本身：32pt 托底 + 图标，命中区 44×44。铃、「⋯」、放大镜共用这一副。
  private func disc<Icon: View>(_ icon: Icon) -> some View {
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

  private var diagnosticsValue: String {
    #if DEBUG
    return ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1" ? String(iconTapCount) : ""
    #else
    return ""
    #endif
  }
}


/// 顶栏铃铛角上那颗数字：照底栏「我的」那颗待判定角标（`ReviewCountBadge`）的画法——
/// 11 等宽数字、强调色胶囊、最窄 16，超过 99 写 99。不吃点击，点到的仍是铃铛。
struct AlertCountBadge: View {
  let count: Int
  let theme: PanelTheme

  var body: some View {
    Text("\(min(count, 99))")
      .font(TypeScale.caption2Emph)
      .monospacedDigit()
      .foregroundStyle(theme.badgeInk)
      .padding(.horizontal, Space.xs)
      .padding(.vertical, Space.xxs)
      .frame(minWidth: 16)
      .background(theme.amber, in: Capsule())
      // 圆片托底 32、命中区 44（外面收回 -6），角标钉在托底右上角外沿。
      .offset(x: 4, y: -4)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

/// 顶栏（与自选行）用的几颗记号：实心、圆头（记忆 kanpan-icons-are-not-wireframes），
/// 坐标照 `VectorIcon` 的写法给 `viewBox` 与 `d=` 串，只是 `.fill` 不描边。
enum TopBarGlyph {
  /// 加号：两根 2.5 粗、圆头的横竖条（16 框）。
  static func plus(_ size: CGFloat) -> some View {
    IconShape(box: 16, items: [
      .rect(x: 6.75, y: 2, w: 2.5, h: 12, r: 1.25),
      .rect(x: 2, y: 6.75, w: 12, h: 2.5, r: 1.25),
    ])
    .fill(style: FillStyle(eoFill: false))
    .frame(width: size, height: size)
  }

  /// 「⋯」：三颗实心圆点（16 框，点径 3.6、中心距 5.2），横向跨 14，和铃、放大镜一样的分量。
  static func more(_ size: CGFloat) -> some View {
    IconShape(box: 16, items: [
      .circle(x: 2.8, y: 8, r: 1.8),
      .circle(x: 8, y: 8, r: 1.8),
      .circle(x: 13.2, y: 8, r: 1.8),
    ])
    .fill()
    .frame(width: size, height: size)
  }

  /// 铃铛：实心钟身 + 底下一颗铃舌（18 框）。
  static func bell(_ size: CGFloat) -> some View {
    IconShape(box: 18, items: [
      .path("M9 2.2c-2.9 0-5 2.3-5 5.1v3.2L2.6 12.6c-.4.5 0 1.2.6 1.2h11.6c.6 0 1-.7.6-1.2L14 10.5V7.3c0-2.8-2.1-5.1-5-5.1z"),
      .path("M7.1 14.6h3.8a1.9 1.9 0 0 1-3.8 0z"),
    ])
    .fill()
    .frame(width: size, height: size)
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
  /// 这家一期费率多长（`ProviderCapabilities.fundingPeriod`）：结算刚过、下一帧没到那几秒，倒计时按它往后滚。
  var fundingPeriod: TimeInterval = HeaderStats.fundingPeriod
  /// 这口价不能当「现在的价」看：上一条线路留下的、断流超过宽限，或者这个品种已经不在交易了。
  /// 最新价和涨跌小字换成 `staleInk`（比 `ink3` 再淡一档，2026-09-28），不改字号也不加任何说明文字——「为什么是灰的」不需要解释，新数据到了
  /// 它自己就亮回来（§2B #54）。
  ///
  /// 除了灰显，它还会把「额 / 市值 / 费率」几格压成 `—`（审查 B.8）：那几个数
  /// 和价来自同一帧，价已经判定为旧的，它们摆在那儿只会让人当成现在的数。
  var stale = false
  /// 右侧那块摆不摆。一格都给不出数的品种（美元指数）整块不摆，规则在
  /// `InstrumentSurfaces.showsHeaderStats`；左边价格区照常，图表把这块高度收回去。
  var showsStats = true

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
        if skeleton(.price, hasValue: lastPrice != nil) {
          headlineSkeleton(width: 120, height: 18, font: TypeScale.price, id: "top.lastPrice")
        } else {
          lastPriceText
        }
        if skeleton(.change, hasValue: ticker?.priceChange != nil && pct != nil) {
          headlineSkeleton(width: 96, height: 11, font: TypeScale.footnoteEmph, id: "top.changePercent")
        } else {
          changeText
        }
      }
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      Spacer(minLength: Space.l)
      if showsStats { stats }
    }
    // 换品种这一下整行不带任何动画（哪怕外面的事务带着）：旧那只的价当场拿掉，
    // 不留一帧淡出，涨跌与六格也直接换成新那只的数。
    .transaction(value: instrument) { $0.animation = nil }
  }

  /// 价与涨跌还在路上时的骨架条：行高由隐藏的同字号字符撑着，数到了整行高度不跳。
  private func headlineSkeleton(width: CGFloat, height: CGFloat, font: ScaledFont, id: String) -> some View {
    Text(verbatim: "0").font(font).hidden()
      .frame(width: width, alignment: .leading)
      .overlay(RoundedRectangle(cornerRadius: Radius.xs).fill(SymbolRowInk.rule(theme)).frame(height: height))
      .accessibilityIdentifier(id)
      .accessibilityLabel("载入中")
  }

  private var lastPriceText: some View {
    Text(lastText)
      .font(TypeScale.price)
      .monospacedDigit()
      .foregroundStyle(lastPrice == nil ? theme.ink3 : stale ? theme.staleInk : tint)
      // 跳价时逐位滚过去（P2.8），只动变了的那几位；「减少动效」下直接换字。
      .contentTransition(reduceMotion ? .identity : .numericText(value: lastPrice ?? 0))
      .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: lastText)
      // 逐位滚动只在**同一只**里做。换品种（横滑扫图、搜索、自选 / 板块点进）时
      // 视图身份跟着完整品种键换掉：新的那只的价直接落（有种子就是种子，没有就是「—」），
      // 不从上一只的数滚过来——否则标题已经是 ETH，底下还闪过一串 BTC 量级的数。
      .id(instrument)
      .transition(.identity)
      .accessibilityIdentifier("top.lastPrice")
  }

  private var changeText: some View {
    Text(HeaderStats.priceChangeText(change: ticker?.priceChange, percent: pct, decimals: decimals))
      .font(TypeScale.footnoteEmph)
      .monospacedDigit()
      .foregroundStyle(ticker?.priceChange == nil || pct == nil ? theme.ink3 : stale ? theme.staleInk : tint)
      .accessibilityIdentifier("top.changePercent")
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
  /// 同日用户要把第六格补成估值：币 O/M，股票 FPE 或 P/S，别的类别没有这一格）。
  private var stats: some View {
    HStack(alignment: .top, spacing: Space.l) {
      statColumn {
        statRow("仓", openInterestText, cell: .openInterest, id: "top.openInterest", term: .openInterest)
        statRow("市值", marketCapText, cell: .marketCap, id: "top.marketCap")
        settlementRow
      }
      statColumn {
        statRow("额", turnoverText, cell: .turnover, id: "top.turnover", term: .turnover)
        statRow("费率", fundingText, cell: .funding, id: "top.funding", tint: frTint)
        if let cell = valuationCell {
          statRow(cell.label, cell.value, cell: .valuation, id: "top.valuation", term: Self.valuationTerm(cell.label))
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

  private func statRow(_ label: String, _ value: String?, cell: ArrivalBoard.HeaderCell, id: String,
                       tint: Color? = nil, term: GlossaryTerm? = nil) -> some View {
    GridRow {
      statLabel(label, term: term)
      if skeleton(cell, hasValue: value != nil) {
        skeletonBar(id: id)
      } else {
        statValue(value ?? "—", missing: value == nil, id: id, tint: tint)
      }
    }
  }

  /// 冷切过来、这一格的数还在路上：画自选行那种骨架条，不画「—」。
  /// 「—」只留给真没有的（这家没有持仓量、后端说没有供应量、等过了 `ArrivalBoard.deadline`）。
  private var pending: ArrivalBoard.HeaderPending { ArrivalBoard.live.header(for: instrument) }

  private func skeleton(_ cell: ArrivalBoard.HeaderCell, hasValue: Bool) -> Bool {
    ArrivalBoard.showsSkeleton(cell, hasValue: hasValue, pending: pending, hasPrice: lastPrice != nil)
  }

  private func skeletonBar(id: String) -> some View {
    // 高度借一个隐藏的同字号字符撑出来：骨架换成数的那一下，行高一点不变。
    Text(verbatim: "0").font(TypeScale.captionEmph).hidden()
      .frame(width: 40)
      .overlay(RoundedRectangle(cornerRadius: Radius.xs).fill(SymbolRowInk.rule(theme)).frame(height: 11))
      .gridColumnAlignment(.trailing)
      .accessibilityIdentifier(id)
      .accessibilityLabel("载入中")
  }

  /// 倒计时独立刷新，缺数与其它格一样显示破折号。
  private var settlementRow: some View {
    GridRow {
      statLabel("结算")
      TimelineView(.periodic(from: .now, by: 30)) { context in
        let text = countdownText(now: context.date)
        if skeleton(.settlement, hasValue: text != nil) {
          skeletonBar(id: "top.settlement")
        } else {
          statValue(text ?? "—", missing: text == nil, id: "top.settlement")
        }
      }
      .gridColumnAlignment(.trailing)
    }
  }

  private func countdownText(now: Date) -> String? {
    guard !stale, fundingRate != nil else { return nil }
    return HeaderStats.fundingCountdownText(nextFundingTimeMs: nextFundingTimeMs, period: fundingPeriod, now: now)
  }

  /// 费率的正负是它唯一要读的信息，按涨跌色给，与价格和涨跌小字使用同两支色。
  private var frTint: Color? {
    guard !stale, let r = fundingRate, r.isFinite, r != 0 else { return nil }
    return r > 0 ? theme.up : theme.down
  }

  /// 标签后面可以挂一颗术语问号（`TermMark`）：颜色跟着标签、命中区 32 但不撑大这一行。
  /// 「市值」一看就懂，不挂。
  private func statLabel(_ text: String, term: GlossaryTerm? = nil) -> some View {
    HStack(spacing: 0) {
      Text(text)
      if let term { TermMark(term, theme: theme) }
    }
    .font(TypeScale.caption2)
    .foregroundStyle(theme.ink3)
    .gridColumnAlignment(.leading)
  }

  /// 第六格的标签是哪一种估值，就挂哪一条解释。
  static func valuationTerm(_ label: String) -> GlossaryTerm? {
    switch label {
    case "O/M": .oiToMarketCap
    case "FPE": .forwardPE
    case "P/S": .priceToSales
    default: nil
    }
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
