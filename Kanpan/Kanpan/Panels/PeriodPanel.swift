import SwiftUI
import KanpanCore

/// 周期面板（A6.14）。
///
/// 十四档一条一行：左边中文名，右边小字是币安那边的 `interval`，当前那档是琥珀色。
/// 点一下就换，面板自己关掉——没有「确定」。右侧的图钉把这一档加进 / 移出顶上的常用行
/// （§10.6：常用行至少 1 档、最多 8 档）。
struct PeriodPanel: View {
  var store: PrefsStore
  /// 挑好了通知外面去重载。挂主界面那一步由调用方接。
  var onPick: ((Interval) -> Void)?

  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 横屏侧栏没有系统 `dismiss`，走主界面递进来的这一条（见 `PanelCloser`）。
  @Environment(\.panelDismiss) private var sideDismiss

  var body: some View {
    PanelSheet(title: "周期", subtitle: nil) {
      ForEach(Interval.allCases, id: \.self) { iv in
        let current = iv == store.prefs.interval
        PanelRow(name: iv.display,
                 meta: iv.rawValue,
                 highlighted: current,
                 onTap: {
                   store.update { $0.interval = iv }
                   onPick?(iv)
                   PanelCloser(side: sideDismiss, sheet: dismiss)()
                 },
                 // §10.6：长按加入 / 移出常用行。右边的图钉是同一件事的明面写法。
                 onLongPress: { store.attempt { $0.toggleQuick(iv) } }) {
          pin(iv)
            .accessibilityIdentifier("period.pin.\(iv.rawValue)")
        }
        .accessibilityIdentifier("period.row.\(iv.rawValue)")
      }

      PanelNote(markdown: "点图钉设为常用")
    }
    .panelToast(store)
  }

  private func pin(_ iv: Interval) -> some View {
    let on = store.prefs.quickIntervals.contains(iv)
    return Button {
      store.attempt { $0.toggleQuick(iv) }
    } label: {
      Image(systemName: on ? "pin.fill" : "pin")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(on ? t.amber : t.ink3)
        .frame(width: 36, height: 30)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(on ? "从常用行移除 \(iv.display)" : "加进常用行 \(iv.display)")
  }
}

#Preview("周期") {
  PanelPreviewHost { store in PeriodPanel(store: store) }
}
