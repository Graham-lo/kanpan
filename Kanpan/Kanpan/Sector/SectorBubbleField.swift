import CoreGraphics
import Foundation
import KanpanCore
import SwiftUI

/// 釉珠可调参数，默认值 = 原型 S 的默认值。
struct SectorFieldKnobs: Equatable {
  var rmax = 62.0, rmin = 18.0, pad = 5.0, fill = 60.0, split = 46.0
  var rim = 62.0, rimL = 74.0, glow = 52.0, depth = 70.0, shadow = 72.0
  var icon = 40.0, amp = 32.0, spd = 60.0
  static let `default` = SectorFieldKnobs()
}

/// 版面与配方的缓存。
///
/// `relax(420)` 是 O(n²)×420，绝不能逐帧跑；27 颗球 × 7 层渐变的 `CGGradient`
/// 也不能逐帧建。这里按三档脏值分别处理：
///
/// - **上场名单／尺寸／滑杆变了** → 整场重排（冷启动 420 轮）+ 重算配方。
/// - **只是行情跳了一下** → 原地换半径和读数，从当前位置热松弛 30 轮 + 重算配方。
/// - **只是换了皮肤或深浅** → 只重算配方，版面一动不动。
///
/// 逐帧剩下的就只有呼吸和漂移两个正弦。
@MainActor final class SectorFieldStore {
  /// 和原型 `performance.now()` 对齐的那把钟（毫秒从这里起算）。
  let start = Date()
  private(set) var layout = SectorLayout()
  private(set) var paints: [SectorBubblePaint] = []
  /// 大球先画、小球后画。
  private(set) var order: [Int] = []

  private var ready = false
  private var signature: [String] = []
  private var size: CGSize = .zero
  private var knobs = SectorFieldKnobs.default
  private var selection = SectorSelection.empty
  private var theme: PanelTheme?

  nonisolated init() {}

  func sync(selection: SectorSelection, size: CGSize,
            knobs: SectorFieldKnobs, theme: PanelTheme) {
    let sig = SectorLayout.signature(selection)
    if !ready || sig != signature || size != self.size || knobs != self.knobs {
      layout = SectorLayout(selection: selection, size: size, knobs: knobs)
      ready = true
      signature = sig
      self.size = size
      self.knobs = knobs
      self.selection = selection
      self.theme = theme
      rebuild(theme: theme)
      return
    }
    var dirty = false
    if selection != self.selection {
      layout.retune(selection)
      self.selection = selection
      dirty = true
    }
    if theme != self.theme {
      self.theme = theme
      dirty = true
    }
    if dirty { rebuild(theme: theme) }
  }

  private func rebuild(theme: PanelTheme) {
    let renderer = SectorBubbleRenderer(theme: theme, knobs: knobs)
    paints = layout.bubbles.map { renderer.paint(for: $0) }
    order = layout.paintOrder
  }
}

/// 釉珠球场：一屏几十颗烧过的珠子，大小讲幅度、位置讲强弱两头。
///
/// 移植自定版原型 `proto2/app.js` 的 `layout()` / `relax()` / `drawBubble()` / `frame()`。
/// 形态已经定稿（见记忆 `kanpan-bubble-body-is-its-own-design-object` 的「2026-09-18 定稿」），
/// 这里只搬不改：要调的是 `SectorFieldKnobs` 里的滑杆，不是形态。
///
/// 动效只有极轻微的呼吸（±1.2%）、漂移（默认 ±2.2pt）和环光的缓慢游走；
/// 不弹跳、不抖动、不互相碰撞弹开、不循环闪烁，并且跟随「减弱动态效果」。
struct SectorBubbleField: View {
  var selection: SectorSelection
  var knobs: SectorFieldKnobs = .default
  var redUp: Bool
  var onPick: (SectorPick) -> Void

  @Environment(\.panelTheme) private var panelTheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var store = SectorFieldStore()

  var body: some View {
    // 环境里那份主题的涨跌色可能已经按设置换过位。这里拿同一颗皮肤种子、
    // 按契约传进来的 redUp 重建一次，保证这个参数是唯一权威，也不会被换两遍。
    let theme = PanelTheme(seed: panelTheme.seed, redUp: redUp)
    TimelineView(.animation(paused: reduceMotion)) { timeline in
      Canvas(opaque: false, rendersAsynchronously: false) { context, size in
        store.sync(selection: selection, size: size, knobs: knobs, theme: theme)
        guard store.paints.count == store.layout.bubbles.count else { return }

        let renderer = SectorBubbleRenderer(theme: theme, knobs: knobs)
        let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(store.start) * 1000
        let amp = knobs.amp / 100 * 7
        let w = (knobs.spd / 100) * 0.00055 + 0.00006

        for index in store.order {
          let bubble = store.layout.bubbles[index]
          let breathe = 1 + sin(t * w * 1.7 + bubble.phase) * 0.012 * (knobs.amp / 100)
          let center = CGPoint(x: Double(bubble.center.x) + sin(t * w + bubble.phase) * amp,
                               y: Double(bubble.center.y) + cos(t * w * 0.83 + bubble.phase2) * amp * 0.8)
          renderer.draw(bubble, paint: store.paints[index],
                        center: center, radius: bubble.radius * breathe,
                        time: t, into: &context)
        }
      }
    }
    .contentShape(Rectangle())
    .gesture(
      SpatialTapGesture().onEnded { value in
        // 命中的是静止位置：漂移默认只有 ±2.2pt，按静止位置判反而比追着动画判稳。
        if let pick = store.layout.hit(value.location) { onPick(pick) }
      }
    )
  }
}
