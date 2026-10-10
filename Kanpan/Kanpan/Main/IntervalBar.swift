import KanpanChart
import KanpanCore
import SwiftUI
import UIKit

/// 周期条：常用周期与「更多 ▾ · 分析 · 图表设置」全部等宽，整行无间隔铺满。
/// 2026-10-11 用户按 AICoin 定稿：撤掉竖线与药丸，当前格用整格淡底。
/// 固定六个周期槽 + 三个动作槽，格宽只取决于当前可用行宽。
struct IntervalBar: View {
  @Environment(\.dynamicTypeSize) private var systemTypeSize
  private var textSize: CGFloat {
    let capped = min(systemTypeSize, MarketChrome.typeCap)
    let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(capped))
    return UIFontMetrics(forTextStyle: .footnote).scaledValue(for: TypeScale.control.size, compatibleWith: traits)
  }
  var theme: PanelTheme
  var quick: [Interval]
  var current: Interval
  @Binding var gridOpen: Bool
  var onPick: (Interval) -> Void
  var onPin: (Interval) -> Void
  var onIndicators: () -> Void
  var onChart: () -> Void

  /// 只排用户钉住的最多六档，始终从短到长；非常用周期由「更多」格显示。
  private var list: [Interval] {
    let order = Interval.allCases
    func rank(_ iv: Interval) -> Int { order.firstIndex(of: iv) ?? order.count }
    return Array(quick.sorted { rank($0) < rank($1) }.prefix(Prefs.maxQuick))
  }

  private var currentOffBar: Bool { !list.contains(current) }
  private var moreTitle: String { currentOffBar ? current.shortLabel : "更多" }

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width / CGFloat(Prefs.maxQuick + 3)
      HStack(spacing: 0) {
        chips(width: width)
        tail(moreTitle, width: width, chevron: true,
             on: gridOpen || currentOffBar, flipped: gridOpen) {
          withAnimation(.easeOut(duration: 0.2)) { gridOpen.toggle() }
        }
        .accessibilityIdentifier("interval.more")
        .accessibilityLabel(currentOffBar ? "更多周期，当前 \(current.display)" : "更多周期")
        .accessibilityAddTraits(currentOffBar ? [.isSelected] : [])
        tail("分析", width: width) {
          if gridOpen { withAnimation(.easeOut(duration: 0.2)) { gridOpen = false } }
          onIndicators()
        }
        .accessibilityIdentifier("interval.indicators")
        .accessibilityLabel("分析")
        slot(width: width, on: false, action: onChart) { VectorIcon.adjust() }
          .accessibilityIdentifier("interval.chart")
          .accessibilityLabel("图表设置")
      }
    }
    // AICoin 的周期行按整屏分格，不跟头部文字的页面内边距缩进。
    .frame(height: Hit.min)
    .dynamicTypeSize(...MarketChrome.typeCap)
  }

  private func chips(width: CGFloat) -> some View {
    HStack(spacing: 0) {
      ForEach(list, id: \.self) { iv in
        slot(width: width, on: iv == current, action: { onPick(iv) }) {
          Text(iv.shortLabel)
            .font(.system(size: textSize, weight: iv == current ? .semibold : .medium))
            .lineLimit(1)
        }
        .onLongPressGesture(minimumDuration: 0.45) { onPin(iv) }
        .accessibilityIdentifier("interval.chip.\(iv.rawValue)")
        .accessibilityLabel(iv.display)
        .accessibilityAddTraits(iv == current ? [.isSelected] : [])
      }
      // 兼容旧偏好中不足六档的情况，保留周期槽，三个入口的位置始终不变。
      ForEach(list.count..<Prefs.maxQuick, id: \.self) { _ in
        Color.clear.frame(width: width, height: Hit.min).accessibilityHidden(true)
      }
    }
    .frame(width: width * CGFloat(Prefs.maxQuick), height: Hit.min)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("interval.quick")
    #if DEBUG
    .accessibilityValue(layoutReport(width: width))
    #endif
  }

  /// 视觉与点击范围都是同一个完整格子，无负内距、外伸命中区或文字宽度补偿。
  private func slot<Label: View>(
    width: CGFloat, on: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label
  ) -> some View {
    Button(action: action) {
      label()
        .foregroundStyle(on ? theme.amber : theme.ink2)
        .frame(width: width, height: Hit.min)
        .background { if on { Rectangle().fill(theme.amberSoft) } }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func tail(
    _ title: String, width: CGFloat, chevron: Bool = false,
    on: Bool = false, flipped: Bool = false, action: @escaping () -> Void
  ) -> some View {
    slot(width: width, on: on, action: action) {
      HStack(spacing: 3) {
        Text(title)
          .font(.system(size: textSize, weight: on ? .semibold : .medium))
          .lineLimit(1)
        if chevron {
          VectorIcon.chevron(9, w: 1.7).rotationEffect(.degrees(flipped ? 180 : 0))
        }
      }
    }
  }

  #if DEBUG
  private func layoutReport(width: CGFloat) -> String {
    let font = UIFont.systemFont(ofSize: textSize, weight: .semibold)
    func textWidth(_ text: String) -> CGFloat {
      (text as NSString).size(withAttributes: [.font: font]).width
    }
    let widest = max(list.map { textWidth($0.shortLabel) }.max() ?? 0,
                     textWidth(moreTitle) + 3 + 9, textWidth("分析"))
    return String(format: "余量 %.2f · 格宽 %.2f · 条宽 %.1f",
                  width - widest, width, width * CGFloat(Prefs.maxQuick + 3))
  }
  #endif
}

/// 横屏侧栏那一版「更多」。
///
/// 横屏没有周期条（右侧是 `IntervalRail`），所以在侧栏里摆同一张网格
/// （`IntervalGridPopover`），换档、钉、钉满换档都和竖屏一模一样。
struct IntervalGridPanel: View {
  var store: PrefsStore
  var onPick: ((Interval) -> Void)?

  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  @Environment(\.panelDismiss) private var sideDismiss

  var body: some View {
    PanelSheet(title: "周期", subtitle: nil) {
      IntervalGridPopover(
        theme: t, quick: store.prefs.quickIntervals, current: store.prefs.interval,
        onPick: { iv in
          store.update { $0.interval = iv }
          onPick?(iv)
          PanelCloser(side: sideDismiss, sheet: dismiss)()
        },
        onPin: { iv in store.attempt { $0.toggleQuick(iv) } },
        onReplace: { old, new in store.update { $0.replaceQuick(old: old, new: new) } })
      .frame(maxWidth: .infinity)
    }
  }
}

/// 竖屏周期条那一行：平时是周期条，十字线活着时整行换成那颗「创建提醒」。
///
/// 独立成非泛型 struct 有两个原因：一是把这几层从 `MainScreen.chartPage` 的类型嵌套里
/// 摘出去（见 `MainScreen.swift` 文件头那条层数上限）；二是只有这一层去观察十字线——
/// 让位靠 `YieldsToCrosshair`，按钮自己观察 `readout`，主屏 body 不因手指移动重算。
struct IntervalRow: View {
  var theme: PanelTheme
  var quick: [Interval]
  var current: Interval
  @Binding var gridOpen: Bool
  var onPick: (Interval) -> Void
  var onPin: (Interval) -> Void
  var onIndicators: () -> Void
  var onChart: () -> Void
  let readout: CrosshairReadout
  let context: CrosshairContext
  /// 十字线那颗「创建提醒」点了。
  var onAlert: (Double) -> Void

  var body: some View {
    ZStack {
      IntervalBar(
        theme: theme, quick: quick, current: current,
        gridOpen: $gridOpen, onPick: onPick, onPin: onPin,
        onIndicators: onIndicators, onChart: onChart)
        .modifier(YieldsToCrosshair(readout: readout, context: context, gridOpen: $gridOpen))
      CrosshairActionBar(readout: readout, context: context, theme: theme, onAlert: onAlert)
    }
    .frame(height: 44)
    .background(theme.app)
  }
}
