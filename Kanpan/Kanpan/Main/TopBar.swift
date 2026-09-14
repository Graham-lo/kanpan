import KanpanCore
import KanpanData
import SwiftUI

/// 顶栏：品种按钮 · 搜索 · 自选星（§9.1）。
///
/// 字号、间距、图标都按原型 `style.css` 的 `.top` 那一段抄，别自己发挥——
/// 这一条和价格行是整个 app 里唯一常驻的文字，差一点点立刻显得不像同一个应用。
struct TopBar: View {
  var theme: PanelTheme
  var symbol: String
  var starred: Bool
  /// 连接状态（§10.5「飞行模式 / 断网」）。绿实时、黄重连、灰离线。
  var status: FeedStatus
  var onSymbol: () -> Void
  /// 长按圆点：报一行当前状态（§10.5「状态圆点旁不写字；长按圆点弹一行」）。
  var onStatus: () -> Void = {}
  var onSearch: () -> Void
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

      iconButton(VectorIcon.search(), label: "搜索品种", on: false, action: onSearch)
        .accessibilityIdentifier("top.search")
      iconButton(VectorIcon.star(), label: starred ? "移出自选" : "加入自选", on: starred, action: onStar)
        .accessibilityIdentifier("top.star")
    }
  }

  private func iconButton(
    _ icon: VectorIcon, label: String, on: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      icon
        .foregroundStyle(on ? theme.amber : theme.ink2)
        .frame(width: 32, height: 32)
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}

/// 价格行：最新价大字 + 涨跌幅 + 右边 24h 三项（§9.1）。
///
/// 涨跌幅用币安 `ticker24h` 的 `P` 字段，不自己算（§4.4）；最新价的颜色跟着它走，
/// 和原型 `renderTop()` 一致——不是跟着「这一根的涨跌」走。
struct PriceRow: View {
  var theme: PanelTheme
  var ticker: Ticker?
  var lastPrice: Double?
  var decimals: Int

  private var pct: Double { ticker?.changePercent ?? 0 }
  private var tint: Color { pct >= 0 ? theme.up : theme.down }

  var body: some View {
    HStack(alignment: .bottom, spacing: 10) {
      Text(lastText)
        .font(.system(size: 27, weight: .medium, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(lastPrice == nil ? theme.ink : tint)
      Text(ticker == nil ? "—" : (pct >= 0 ? "+" : "") + toFixed(pct, 2) + "%")
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(ticker == nil ? theme.ink3 : tint)
      Spacer(minLength: 0)
      stats
    }
    .padding(.top, 5)
  }

  private var lastText: String {
    guard let p = lastPrice else { return "—" }
    return fmtNum(p, decimals)
  }

  private var stats: some View {
    Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 1) {
      row("24h 高", ticker.map { fmtNum($0.high, decimals) })
      row("24h 低", ticker.map { fmtNum($0.low, decimals) })
      row("24h 额", ticker.map { fmtVol($0.quoteVolume) })
    }
  }

  private func row(_ label: String, _ value: String?) -> some View {
    GridRow {
      Text(label)
        .font(.system(size: 10.5))
        .foregroundStyle(theme.ink3)
      Text(value ?? "—")
        .font(.system(size: 10.5, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(theme.ink2)
    }
  }
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
