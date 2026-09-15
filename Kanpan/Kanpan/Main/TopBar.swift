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

  var body: some View {
    HStack(spacing: 8) {
      Button(action: onSymbol) {
        HStack(spacing: 6) {
          Text(symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(theme.ink)
          Text("永续")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.ink3)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.line, lineWidth: 1))
          VectorIcon.chevron()
            .foregroundStyle(theme.ink.opacity(0.55))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("换品种，当前 \(symbol)")
      .accessibilityIdentifier("top.symbol")

      StatusDot(status: status, onLongPress: onStatus)

      Spacer(minLength: 0)

      iconButton(VectorIcon.star(), label: starred ? "移出自选" : "加入自选", on: starred, action: onStar)
        .accessibilityIdentifier("top.star")
    }
  }

  private func iconButton(
    _ icon: VectorIcon, label: String, on: Bool, action: @escaping () -> Void
  ) -> some View {
    Button {
      iconTapCount += 1
      action()
    } label: {
      icon
        .foregroundStyle(on ? theme.amber : theme.ink2)
        .frame(width: 32, height: 32)
        .background(theme.app)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityValue(ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1"
      ? String(iconTapCount) : "")
  }
}

/// 价格行：左边一个价 + 涨跌幅，右边 24h 高/低/额（§9.1）。
///
/// 涨跌幅用币安 `ticker24h` 的 `P` 字段，不自己算（§4.4）；最新价的颜色跟着它走，
/// 和原型 `renderTop()` 一致——不是跟着「这一根的涨跌」走。
///
/// 左边这一格是**这个品种的展示价**，它和涨跌幅永远是头部的主角：一屏看下来
/// 先看到的就该是「现在多少钱、今天涨没涨」。24h 高/低/额是背景信息，
/// 压到右边、用小一号的字，把原本空着的右半边填上，但不抢主角的位置。
///
/// 字号从原来的 22pt 降到 18pt 并换成等宽数字：22pt 那版又大又糙，数字一跳整行
/// 宽度跟着变。降一档、锁住字宽，跳数的时候行不动，右边那三项也就有地方站。
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
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(lastText)
        .font(.system(size: 18, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(lastPrice == nil ? theme.ink : tint)
        .accessibilityIdentifier("top.lastPrice")
      Text(pct.map { ($0 >= 0 ? "+" : "") + toFixed($0, 2) + "%" } ?? "—")
        .font(.system(size: 12.5, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(pct == nil ? theme.ink3 : tint)
        .accessibilityIdentifier("top.changePercent")
      Spacer(minLength: 10)
      stats
    }
    .lineLimit(1)
    .padding(.top, 3)
  }

  private var lastText: String {
    guard let p = lastPrice else { return "—" }
    return grouped(fmtNum(p, decimals))
  }

  /// 24h 高 / 低 / 额：贴右横排，标签 10.5pt 次级色、数值 11pt 等宽数字。
  ///
  /// 挤不下的时候**整项整项地让**，不截断：先去掉「24h」那两个字（高/低/额 这三个
  /// 词本来就只有 24h 这一个口径），再去掉成交额（VOL 副图里一直画着）。
  /// 截断出来的「7957…」比没有还糟——一个看不全的价位会让人读错一档。
  private var stats: some View {
    ViewThatFits(in: .horizontal) {
      statRow(prefixed: true, volume: true)
      statRow(prefixed: false, volume: true)
      statRow(prefixed: false, volume: false)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("top.stats")
  }

  private func statRow(prefixed: Bool, volume: Bool) -> some View {
    HStack(spacing: 8) {
      stat(prefixed ? "24h 高" : "高", ticker.map { fmtNum($0.high, decimals) })
      stat("低", ticker.map { fmtNum($0.low, decimals) })
      if volume { stat("额", ticker.map { fmtVol($0.quoteVolume) }) }
    }
    .fixedSize()
  }

  private func stat(_ label: String, _ value: String?) -> some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.system(size: 10.5))
        .foregroundStyle(theme.ink3)
      Text(value ?? "—")
        .font(.system(size: 11))
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

  private var color: Color {
    switch status {
    case .live: Color(hex: "#22C55E")
    case .reconnecting: Color(hex: "#F5A524")
    case .offline: Color(hex: "#9AA0A6")
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
