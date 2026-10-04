import ReviewDomain
import SwiftUI

// ============================================================ 交易回放（自动复盘 3d）的几块小件
//
// 页头、回放条都在 app 里，可字号、间距、圆角只认复盘这一套令牌（`ReviewType` / `ReviewSpace` /
// `ReviewRadius`），所以这几块做在包里、公开出去，由 app 挂上并灌进 `reviewTheme`。

/// 持仓那一段挂在回放页头时刻行尾的浮动盈亏：`+1.23%`。
///
/// 等宽数字、带正负号；底是涨跌色一成五、字是涨跌色本身；高 20、左右 8、整颗圆。
/// 只做 0.2 秒的颜色过渡，数字不滚——每走一根都在变，滚起来反而看不清。
public struct TradeReplayCapsule: View {
  public var value: Double
  @Environment(\.reviewTheme) private var t
  public init(value: Double) { self.value = value }

  public static func text(_ value: Double) -> String {
    let percent = (value * 100 * 100).rounded() / 100
    let body = String(format: "%.2f%%", abs(percent))
    return (percent < 0 ? "-" : "+") + body
  }

  /// 涨跌色跟着**摆出来的那个数**走：+1 涨色、-1 跌色、0 中性。
  ///
  /// 原来颜色看的是没取整的原值：浮盈 -0.004% 摆成「+0.00%」却涂跌色，+0.004%
  /// 摆成「+0.00%」又涂涨色——同一个「+0.00%」两种颜色，正负号和颜色对不上。
  public static func tone(_ value: Double) -> Int {
    let percent = (value * 100 * 100).rounded() / 100
    return percent > 0 ? 1 : percent < 0 ? -1 : 0
  }

  public var body: some View {
    let text = Self.text(value)
    let tone = Self.tone(value)
    let color = tone > 0 ? t.up : tone < 0 ? t.down : t.ink2
    Text(text)
      .font(ReviewType.caption)
      .monospacedDigit()
      .lineLimit(1)
      .fixedSize()
      .foregroundStyle(color)
      .padding(.horizontal, ReviewSpace.s)
      .frame(minHeight: ReviewSpace.xl)
      .background(color.opacity(0.15), in: Capsule())
      .contentTransition(.identity)
      .animation(.easeOut(duration: 0.2), value: tone)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("持仓浮盈 " + text)
      .accessibilityIdentifier("review.replay.pnl")
  }
}

/// 走到开仓那根停下的 1.2 秒里，页头下面浮出的一行「当时怎么想」原文。
///
/// 不加引号、不加「当时怎么想：」前缀；一行、放不下截尾；0.2 秒淡入淡出，
/// 系统开了「减弱动态效果」就直接出现、直接消失。这笔没写过就什么都没有。
/// 这一行的高度是留好的（只在这笔有笔记时留），字出来时 K 线不会被往下推一下。
public struct TradeReplayCaption: View {
  public var text: String?
  @Environment(\.reviewTheme) private var t
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  public init(text: String?) { self.text = text }

  public var body: some View {
    ZStack(alignment: .leading) {
      // 撑出一行字的高度：跟着动态字号一起长，不写死数字。
      Text(" ").font(ReviewType.caption).hidden()
      if let text, !text.isEmpty {
        Text(text)
          .font(ReviewType.caption)
          .foregroundStyle(t.ink2)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
          .transition(.opacity)
          .accessibilityIdentifier("review.replay.caption")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: text)
  }
}

/// 交易详情图正中那颗播放圆片：44 圆、`ultraThinMaterial` 底、accent 三角。
/// 持仓中的回合没有它（还没平仓，谈不上回放）。
struct TradeReplayPlayDisc: View {
  var action: () -> Void
  @Environment(\.reviewTheme) private var t

  var body: some View {
    Button(action: action) {
      Image(systemName: "play.fill")
        .font(ReviewType.heading)
        .foregroundStyle(t.accent)
        .frame(width: ReviewControl.hit, height: ReviewControl.hit)
        .background(.ultraThinMaterial, in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("回放这笔交易")
    .accessibilityIdentifier("trade.detail.replay")
  }
}
