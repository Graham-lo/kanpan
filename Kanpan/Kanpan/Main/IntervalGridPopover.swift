import KanpanCore
import SwiftUI

/// 「更多」拉开的那张周期网格：十四档摊成五列，当前那一档高亮，每格右上角一颗图钉。
///
/// 竖屏挂在图的上沿、盖在图上（`IntervalPopoverLayer`），横屏放进侧栏（`IntervalGridPanel`），
/// 两边是同一只视图。
///
/// **钉满六档时换档是一步**（2026-09-23）：原来钉满之后其余图钉一律灰掉，底下一行
/// 「已满六档」，想换一档得先拔一颗、再钉一颗。现在点没钉住的那颗图钉就进入
/// 「挑一档换掉」：六个已钉的格子描上一圈虚线，点哪一格就换掉哪一格；点别处（别的格、
/// 同一颗图钉、网格空白处）就取消。整个过程没有一句解释文案——虚线本身就是那句话。
struct IntervalGridPopover: View {
  var theme: PanelTheme
  var quick: [Interval]
  var current: Interval
  /// 点一格：切到这一档。收不收起由外面定（竖屏收起弹层，横屏关侧栏）。
  var onPick: (Interval) -> Void
  /// 钉 / 取消钉（`Prefs.toggleQuick`），没钉满时用。
  var onPin: (Interval) -> Void
  /// 钉满时换档（`Prefs.replaceQuick`）：换掉 `old`，钉上 `new`。
  var onReplace: (_ old: Interval, _ new: Interval) -> Void

  /// 正在找位置的那一档（点了它的图钉、还没挑换掉谁）。`nil` 就是平常状态。
  @State private var replacing: Interval?

  private var pinFull: Bool { quick.count >= Prefs.maxQuick }

  var body: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
              spacing: 8) {
      ForEach(Interval.allCases, id: \.self) { cell($0) }
    }
    // 五列 `.flexible()` 会把整行宽度平分：iPad 上一格能摊到两百来点宽、还是 44pt 高，
    // 一排横躺的长条。封一个和手机相当的上限，网格照旧从左边起排。
    .frame(maxWidth: 520, alignment: .leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    // 网格空白处也算「别处」：点了就取消换档。
    .contentShape(Rectangle())
    .onTapGesture { cancelReplace() }
    // 外面改了钉位（别的入口、同步回来的）就别再拿着旧的选择。
    .onChange(of: quick) { _, _ in replacing = nil }
  }

  private func cancelReplace() {
    guard replacing != nil else { return }
    withAnimation(.easeOut(duration: 0.15)) { replacing = nil }
  }

  private func cell(_ iv: Interval) -> some View {
    let on = iv == current
    let pinned = quick.contains(iv)
    let target = replacing != nil && pinned          // 这一格可以被换掉
    let chosen = replacing == iv                     // 正要钉进来的那一档
    return ZStack(alignment: .topTrailing) {
      Button {
        if let incoming = replacing {
          if pinned {
            onReplace(iv, incoming)
            Haptics.step()
          }
          withAnimation(.easeOut(duration: 0.15)) { replacing = nil }
          return
        }
        onPick(iv)
      } label: {
        Text(iv.display)
          .font(.system(size: 12.5, weight: on ? .semibold : .medium))
          .foregroundStyle(on || chosen ? theme.amber : theme.ink2)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .frame(maxWidth: .infinity)
          .frame(height: 44)
          // 当前那一格：10% 淡底 + 强调色字（和周期条上当前档一个规矩）。
          .background(on ? AnyShapeStyle(theme.amberSoft) : AnyShapeStyle(theme.raised2),
                      in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .overlay {
            // 可以被换掉的六格描虚线；正要钉进来的那一档描实线。
            if target || chosen {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.amber, style: StrokeStyle(
                  lineWidth: 1.2, dash: target ? [4, 3] : []))
            }
          }
          .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("period.row.\(iv.rawValue)")
      .accessibilityLabel(target ? "换掉 \(iv.display)" : iv.display)
      .accessibilityAddTraits(on ? [.isSelected] : [])

      // 图钉压在格子右上角：钉住的实心，没钉的是个空壳。点它只钉不切档。
      Button {
        if replacing != nil {
          // 同一颗图钉再点一次、或者点了别的图钉：都算取消。
          withAnimation(.easeOut(duration: 0.15)) { replacing = nil }
        } else if !pinned, pinFull {
          withAnimation(.easeOut(duration: 0.15)) { replacing = iv }
          Haptics.step()
        } else {
          onPin(iv)
        }
      } label: {
        Image(systemName: pinned || chosen ? "pin.fill" : "pin")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(pinned || chosen ? theme.amber : theme.ink3)
          .frame(width: 24, height: 20)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("period.pin.\(iv.rawValue)")
      .accessibilityLabel(pinned ? "从常用行移除 \(iv.display)" : "加进常用行 \(iv.display)")
      .accessibilityValue(chosen ? "正在挑一档换掉" : "")
    }
  }
}

/// 竖屏「更多」那一层：从周期条下沿往下展开的网格 + 盖住图其余部分的遮罩。
///
/// 从前网格是周期条自己 VStack 里的一段，一展开就把图压扁一半；现在它挂在图上
/// （`MainScreen.chartPage` 里图的 `overlay`），图的尺寸一个 pt 都不动。
/// 收起的三条路：点遮罩、再点一次「更多」、在面板上下滑。
///
/// 材质照抄侧栏面板（`SidePanelLayer`）：`raised` 的面、`line` 的描边、18% 黑的遮罩，
/// 遮罩上那层 `PanelDismissShield` 吞掉「点外面」那一下，不让它漏到图上去点出十字线。
struct IntervalPopoverLayer: View {
  var theme: PanelTheme
  var quick: [Interval]
  var current: Interval
  @Binding var open: Bool
  var onPick: (Interval) -> Void
  var onPin: (Interval) -> Void
  var onReplace: (Interval, Interval) -> Void

  var body: some View {
    ZStack(alignment: .top) {
      if open {
        Color.black.opacity(0.18)
          .overlay { PanelDismissShield(onDismiss: close) }
          .transition(.opacity)
        IntervalGridPopover(
          theme: theme, quick: quick, current: current,
          onPick: { iv in onPick(iv); close() },
          onPin: onPin, onReplace: onReplace)
          .background(theme.raised)
          .overlay(alignment: .bottom) {
            Rectangle().fill(theme.line).frame(height: 1)
          }
          .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
          // 上下滑都收：往上推是「塞回周期条」，往下拉是 AICoin 那种扫开。
          .gesture(DragGesture(minimumDistance: 14).onEnded { g in
            let dy = g.translation.height, dx = g.translation.width
            guard abs(dy) > 28, abs(dy) > abs(dx) else { return }
            close()
          })
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("interval.grid")
          .transition(.move(edge: .top))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    // 从周期条下沿「长出来」：进出场的那一段不许画到条上面去。
    .clipped()
  }

  private func close() {
    withAnimation(.easeOut(duration: 0.2)) { open = false }
  }
}
