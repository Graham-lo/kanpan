import KanpanCore
import KanpanData
import SwiftUI

/// 顶栏：品种按钮 · 自选星（§9.1）。
///
/// 搜索原来是这儿的一个放大镜。换品种一共有三个入口——顶栏品种名（半屏自选）、
/// 顶栏放大镜（全屏搜索）、底栏「自选」（全屏自选页）——三个入口三种界面，
/// 想换个币先要想「该点哪个」。现在只留品种名这一个：点开半屏弹层，搜索和完整
/// 自选页都是弹层里的第一屏（见 `FavoritesQuickPicker`）。
///
/// 字号、间距、图标都按原型 `style.css` 的 `.top` 那一段抄，别自己发挥——
/// 这一条和价格行是整个 app 里唯一常驻的文字，差一点点立刻显得不像同一个应用。
struct TopBar: View {
  @State private var iconTapCount = 0
  var theme: PanelTheme
  var symbol: String
  var starred: Bool
  /// 连接状态（§10.5「飞行模式 / 断网」）。绿实时、黄重连、灰离线。
  var status: FeedStatus
  var onSymbol: () -> Void
  /// 长按圆点：报一行当前状态（§10.5「状态圆点旁不写字；长按圆点弹一行」）。
  var onStatus: () -> Void = {}
  var onStar: () -> Void

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
      Button(action: onSymbol) {
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
            VectorIcon.chevron(9, w: 1.7)
              .foregroundStyle(theme.ink3)
              .padding(.leading, 1)
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
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("换品种，当前 \(symbol)")
      .accessibilityIdentifier("top.symbol")

      StatusDot(status: status, onLongPress: onStatus)

      Spacer(minLength: 0)

      iconButton(VectorIcon.star(15), label: starred ? "移出自选" : "加入自选", on: starred, action: onStar)
        .accessibilityIdentifier("top.star")
    }
  }

  /// 右上角的圆按钮：30pt 的托底 + 15pt 的线性图标（用户定过的尺度）。
  /// 选中的那颗用强调色的字配一层 15% 的强调底，不要整颗填满——它旁边就是价格，
  /// 填满会把视线从价格上抢走。
  private func iconButton(
    _ icon: VectorIcon, label: String, on: Bool, action: @escaping () -> Void
  ) -> some View {
    Button {
      iconTapCount += 1
      action()
    } label: {
      icon
        .foregroundStyle(on ? theme.amber : theme.ink2)
        .frame(width: 30, height: 30)
        .background(on ? theme.amberSoft : theme.raised, in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityValue(ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1"
      ? String(iconTapCount) : "")
  }
}


/// 价格块：一行大价 + 涨跌幅药丸，下面一行灰字（§9.1）。
///
/// 涨跌幅用币安 `ticker24h` 的 `P` 字段，不自己算（§4.4）；最新价的颜色跟着它走，
/// 和原型 `renderTop()` 一致——不是跟着「这一根的涨跌」走。
///
/// 价和涨跌幅永远是头部的主角：一屏看下来先看到的就该是「现在多少钱、今天涨没涨」。
/// 主角地位靠对比建立而不是靠字号——价停在 29pt 的等宽数字（跳数时行宽不动），
/// 涨跌幅做成填色药丸带方向箭头，这两样一起就够抢眼了，别再往大里加。
///
/// 底下只跟一行灰字：成交额、振幅。24h 高 / 低 不显示——用户看过之后说「高低其实
/// 没必要展示」，那两个数一天里几乎不动，摆在最新价旁边只是把视线分散掉。
/// 这一行也不要再装进小卡片里：四张等宽圆角卡试过，用户的评价是「方框有点太方了」，
/// 头部本来就该是一块干净的留白，加边框等于把两个配角也框成了主角。
struct PriceRow: View {
  var theme: PanelTheme
  var ticker: Ticker?
  var lastPrice: Double?
  var decimals: Int

  private var pct: Double? {
    guard let value = ticker?.changePercent, value.isFinite else { return nil }
    return value
  }
  private var tint: Color {
    guard let pct else { return theme.ink }
    return pct >= 0 ? theme.up : theme.down
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 9) {
        Text(lastText)
          .font(.system(size: 29, weight: .semibold, design: .monospaced))
          .foregroundStyle(lastPrice == nil ? theme.ink : tint)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .accessibilityIdentifier("top.lastPrice")
        pill
        Spacer(minLength: 0)
      }
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
        .font(.system(size: 12.5, weight: .semibold))
        .monospacedDigit()
    }
    .foregroundStyle(pct == nil ? theme.ink3 : theme.badgeInk)
    .padding(.horizontal, 7)
    .padding(.vertical, 3.5)
    .background(pct == nil ? theme.raised2 : theme.badgeFill(up: pct! >= 0),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    .accessibilityIdentifier("top.changePercent")
  }

  private var lastText: String {
    guard let p = lastPrice else { return "—" }
    return grouped(fmtNum(p, decimals))
  }

  /// 成交额、振幅：一行灰字，标签更淡、数值稍重，中间一个圆点隔开。不给底色、
  /// 不加边框——它们是配角，配角只要在那儿能查到就够了。
  private var stats: some View {
    HStack(spacing: 7) {
      stat("成交额", ticker.map { fmtVol($0.quoteVolume) })
      Text("·").font(.system(size: 11)).foregroundStyle(theme.ink3.opacity(0.6))
      stat("振幅", ticker?.amplitude24h.map { toFixed($0, 2) + "%" })
      Spacer(minLength: 0)
    }
    .lineLimit(1)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("top.stats")
  }

  private func stat(_ label: String, _ value: String?) -> some View {
    HStack(spacing: 4) {
      Text(label).font(.system(size: 11)).foregroundStyle(theme.ink3)
      Text(value ?? "—")
        .font(.system(size: 11.5, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(theme.ink2)
    }
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


/// 连接状态圆点（§10.5）。
///
/// 摆在品种名右边，**旁边不写字**——常驻文字只留品种和价格那两行。状态是
/// 「不出事就不该被注意到」的东西，所以只给一颗 7pt 的点；想知道细节长按它。
struct StatusDot: View {
  var status: FeedStatus
  var onLongPress: () -> Void
  @Environment(\.panelTheme) private var theme

  /// 连上的时候用**当前皮肤自己的强调色**，不是一颗固定的 `#22C55E`。
  ///
  /// 那颗绿是从别处抄来的通用绿，落在青苔的浅灰绿纸面上比整屏任何一处都跳，
  /// 换到陶土那套暖色里更像是画错了色号——它就挨着品种徽章，徽章的颜色都按皮肤
  /// 特调过了，旁边这一点却不认识皮肤。
  ///
  /// 「离线」同理，跟着皮肤的弱化文字色走。只有「重连中」保留那抹橙：它要的就是
  /// 「和平时不一样」，两套皮肤里都跟强调色分得开。
  private var color: Color {
    switch status {
    case .live: theme.amber
    case .reconnecting: Color(hex: "#F5A524")
    case .offline: theme.ink3
    }
  }

  private var label: String {
    switch status {
    case .live: "实时"
    case .reconnecting: "重连中"
    case .offline: "离线"
    }
  }

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 7, height: 7)
      // 7pt 的点手指够不着，撑到 28pt 再让它透出来。
      .frame(width: 28, height: 28)
      .contentShape(Rectangle())
      .onLongPressGesture(minimumDuration: 0.35, perform: onLongPress)
      .accessibilityLabel("连接状态：" + label)
      .accessibilityIdentifier("top.status")
  }
}
