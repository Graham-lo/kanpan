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
/// 字号、间距、图标都按原型 `style.css` 的 `.top` 那一段抄，别自己发挥——
/// 这一条和价格行是整个 app 里唯一常驻的文字，差一点点立刻显得不像同一个应用。
struct TopBar: View {
  @State private var iconTapCount = 0
  var theme: PanelTheme
  var symbol: String
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
            .font(.system(size: 9.5, weight: .medium))
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

      iconButton(VectorIcon.search(15), label: "搜索品种", action: onSearch)
        .accessibilityIdentifier("top.search")
    }
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
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityValue(ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1"
      ? String(iconTapCount) : "")
  }
}


/// 价格块：左边一列「大价 + 涨跌幅药丸」，右边 2×2 四格（§9.1，2026-09-18 改版）。
///
/// 涨跌幅用币安 `ticker24h` 的 `P` 字段，不自己算（§4.4）；最新价的颜色跟着它走，
/// 和原型 `renderTop()` 一致——不是跟着「这一根的涨跌」走。
///
/// 价和涨跌幅永远是头部的主角：一屏看下来先看到的就该是「现在多少钱、今天涨没涨」。
/// 主角地位靠对比建立而不是靠字号——价停在 22pt 的等宽数字（跳数时行宽不动），
/// 涨跌幅做成填色药丸带方向箭头，这两样一起就够抢眼了，别再往大里加。
///
/// 右边四格是 AICoin 头部块（`ui_ticker_include_detail_price_block.xml`）的标签习惯：
/// **仓 / 额 / 市值 / 费率**，标签在左、数值在右，两列基线对齐。AICoin 自己那格写的是
/// 单字 `FR`，这儿按用户 2026-09-18 的定稿写「费率」——右列最宽的一格就是它。AICoin 实测是
/// 数值 13sp、标签 11sp，落到这儿降到 11.5 / 10——它那块整体比我们大一档（主价 26sp），
/// 照搬会把配角做得和主价一样响。持仓那一格按 AICoin 的样子重一档字重。
///
/// 原来底下那行「成交额 · 振幅」的灰字取消了：成交额进了右侧四格，振幅不再显示
/// （用户 2026-09-18 决定，右边就这四个，不要再多）。
/// 拿不到的格子一律 `--`，不解释、不弹提示。
struct PriceRow: View {
  var theme: PanelTheme
  var ticker: Ticker?
  var lastPrice: Double?
  var decimals: Int
  /// 成交额的单位由外面按品种钉住（见 `MarketModel.volumeUnit`），这儿不自己挑。
  var volumeUnit: VolUnit?
  /// 持仓量（美元名义优先，没有名义就是币本位数量）和它钉住的单位。
  var openInterest: Double?
  var openInterestUnit: VolUnit?
  /// 总供应量（后端给）。市值在这儿乘出来，乘的就是上面那口正在显示的价，
  /// 不会出现「价已经跳了、市值还是上一口算的」。
  var totalSupply: Double?
  /// 资金费率，已经是小数（`0.0001` = 0.01%）。
  var fundingRate: Double?
  /// 这口价是上一条线路留下的。灰显，不改字号也不加任何说明文字——
  /// 「为什么是灰的」不需要解释，新数据到了它自己就亮回来（§2B #54）。
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
    HStack(alignment: .top, spacing: 12) {
      // 价和药丸还是原来那一行、原来的顺序和间距，一个像素都不挪；
      // 这一轮只是把右边空出来的地方交给四格（原来那行灰字撤掉之后空出来的）。
      HStack(alignment: .firstTextBaseline, spacing: 9) {
        Text(lastText)
          .font(.system(size: 22, weight: .medium))
          .monospacedDigit()
          .foregroundStyle(lastPrice == nil ? theme.ink : (stale ? theme.ink3 : tint))
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .accessibilityIdentifier("top.lastPrice")
        pill
      }
      Spacer(minLength: 0)
      stats
    }
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
    .foregroundStyle(pct == nil || stale ? theme.ink3 : theme.badgeInk)
    .padding(.horizontal, 7)
    .padding(.vertical, 3.5)
    .background(pct == nil || stale ? theme.raised2 : theme.badgeFill(up: pct! >= 0),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    .accessibilityIdentifier("top.changePercent")
  }

  private var lastText: String {
    guard let p = lastPrice else { return "—" }
    return grouped(fmtNum(p, decimals))
  }

  // ---------------------------------------------------------------- 右侧四格

  private var turnoverText: String? {
    guard let v = ticker?.quoteVolume, v.isFinite else { return nil }
    return fmtVol(v, unit: pinned(volumeUnit, for: v))
  }

  private var openInterestText: String? {
    guard let v = openInterest, v.isFinite else { return nil }
    return fmtVol(v, unit: pinned(openInterestUnit, for: v))
  }

  /// 单位由外面按品种钉住（§2B #53），这儿只在还没钉上时按眼前这个数认一次。
  private func pinned(_ unit: VolUnit?, for value: Double) -> VolUnit {
    unit ?? volUnit(value)
  }

  private var marketCapText: String? {
    guard let supply = totalSupply, supply.isFinite, supply > 0,
          let price = lastPrice, price.isFinite, price > 0 else { return nil }
    return fmtVol(supply * price)
  }

  /// 2×2：上排 仓 / 额，下排 市值 / 费率。宽度写死，否则数字一长一短两列会来回抖。
  /// 184 是在真机上量出来的：两个汉字的标签 +「-0.1327%」这种最长的费率两列都塞得下，
  /// 同时左边那行「76,585.10 ▲+1.15%」还留着余量——那一行是主角，不能因为四格而缩字。
  private var stats: some View {
    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
      GridRow {
        cell("仓", openInterestText, heavy: true)
        cell("额", turnoverText)
      }
      GridRow {
        cell("市值", marketCapText)
        cell("费率", fundingRate.map { fmtFundingRate($0) }, tint: frTint)
      }
    }
    .frame(width: 184)
    .lineLimit(1)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("top.stats")
  }

  /// 费率的正负是它唯一要读的信息，按涨跌色给——和药丸、自选表用的是同两支色。
  private var frTint: Color? {
    guard !stale, let r = fundingRate, r.isFinite, r != 0 else { return nil }
    return r > 0 ? theme.up : theme.down
  }

  private func cell(_ label: String, _ value: String?, heavy: Bool = false,
                    tint: Color? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(label)
        .font(.system(size: 10))
        .foregroundStyle(theme.ink3)
      Spacer(minLength: 0)
      Text(value ?? "--")
        .font(.system(size: 11.5, weight: heavy ? .semibold : .medium))
        .monospacedDigit()
        .foregroundStyle(value == nil || stale ? theme.ink3 : (tint ?? theme.ink2))
        .minimumScaleFactor(0.85)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
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



