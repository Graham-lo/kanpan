import CoreGraphics
import KanpanCore

/// 主图叠加线太多时的「焦点」：超过 `overlayCrowd` 条，非焦点线退到 `overlayFadedAlpha`。
///
/// 焦点按这个顺序定（2026-10-08）：
/// 1. 十字线停在主图上：读数离十字线价格最近的那一条（正在读的线）；
/// 2. 最近一次改过的那把指标（加进来、改参数、改颜色、显隐某条输出）的各条线；
/// 3. 都没有：排在前面的 `overlayCrowd` 条。
/// 不超过 `overlayCrowd` 条时一律不淡（`overlayFocus()` 返回 `nil`），默认布局一个像素不变。
public struct OverlayLineKey: Hashable, Sendable {
  public let id: IndicatorID
  public let k: Int
  public init(_ id: IndicatorID, _ k: Int) { self.id = id; self.k = k }
}

extension ChartRenderer {
  static let overlayCrowd = 6
  static let overlayFadedAlpha: CGFloat = 0.45

  /// 主图上此刻看得见的每条叠加线（按画的顺序）。
  func overlayLineKeys() -> [OverlayLineKey] {
    var keys: [OverlayLineKey] = []
    for id in state.overlays {
      guard let v = displayed(id) else { continue }
      switch id {
      case .ma, .ema:
        for k in v.lines.indices where outputVisible(id, k) { keys.append(OverlayLineKey(id, k)) }
      case .boll:
        guard v.lines.count >= 3 else { break }
        for k in [1, 0, 2] where outputVisible(id, k) { keys.append(OverlayLineKey(id, k)) }
      case .vwap, .supertrend, .sar:
        if !v.lines.isEmpty, outputVisible(id, 0) { keys.append(OverlayLineKey(id, 0)) }
      default: break
      }
    }
    return keys
  }

  /// 该画满的那几条；`nil` 表示不淡任何一条（不到 `overlayCrowd + 1` 条）。
  public func overlayFocus() -> Set<OverlayLineKey>? {
    let keys = overlayLineKeys()
    guard keys.count > Self.overlayCrowd else { return nil }
    if let c = state.crosshair, c.pane == nil, c.index >= 0, c.index < state.series.count {
      let price = c.price ?? state.series.close[c.index]
      var best: (OverlayLineKey, Double)?
      for key in keys {
        guard let a = displayed(key.id)?.lines[key.k], a.indices.contains(c.index), a[c.index].isFinite else { continue }
        let d = abs(a[c.index] - price)
        if best == nil || d < best!.1 { best = (key, d) }
      }
      if let best { return [best.0] }
    }
    if let edited = overlayEdited {
      let mine = keys.filter { $0.id == edited }
      if !mine.isEmpty { return Set(mine) }
    }
    return Set(keys.prefix(Self.overlayCrowd))
  }

  /// 两份 state 之间**只有一把**叠加指标被动过（新加、参数、颜色、显隐）时报它；
  /// 一次换整套布局（登录拉下来、换周期带进来）不算「编辑了某一把」。
  static func editedOverlay(from old: ChartState, to new: ChartState) -> IndicatorID? {
    let touched = new.overlays.filter { id in
      !old.overlays.contains(id) || old.params[id] != new.params[id]
        || old.indicatorColors[id] != new.indicatorColors[id] || old.hiddenOutputs[id] != new.hiddenOutputs[id]
    }
    return touched.count == 1 ? touched[0] : nil
  }

  /// 在 `body` 里画 `key` 这一条：不是焦点就压到 `overlayFadedAlpha`。
  func withOverlayFade(_ ctx: CGContext, _ focus: Set<OverlayLineKey>?, _ key: OverlayLineKey, _ body: () -> Void) {
    guard let focus, !focus.contains(key) else { body(); return }
    ctx.saveGState(); ctx.setAlpha(Self.overlayFadedAlpha)
    body()
    ctx.restoreGState()
  }
}
