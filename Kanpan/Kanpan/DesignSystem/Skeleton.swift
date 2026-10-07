import SwiftUI

/// 内容还在路上时摆的骨架（体感优化 2026-10-07）。
///
/// 规矩：骨架胜过转圈、留旧内容胜过空白。骨架只是一块块和真行同位置的浅色块，
/// 不写「加载中」，也不带任何说明文字；它慢慢呼吸一下，表示「马上就来」，
/// 系统开了「减弱动态效果」就不动。
enum Skeleton {
  /// 呼吸的两端（不透明度）和半个周期。幅度刻意压小，只是一点点起伏，不是闪。
  static let dim: Double = 0.55
  static let period: Double = 1.1

  /// 第 `index` 行的几块各取多宽：同一页每次摆出来都一样（不随机，免得一刷新就跳），
  /// 但行与行之间错开，看着像一张真表而不是一排复印件。
  static func width(_ index: Int, base: CGFloat, spread: CGFloat) -> CGFloat {
    let steps: [CGFloat] = [0.55, 0.9, 0.35, 1.0, 0.7, 0.2, 0.8, 0.45]
    return base + spread * steps[((index % steps.count) + steps.count) % steps.count]
  }
}

/// 一块骨架。颜色由页面给（各页用自己那根分隔线的墨，深浅皮肤自然跟着走）。
struct SkeletonBlock: View {
  var width: CGFloat?
  var height: CGFloat
  var fill: Color
  var radius: CGFloat = Radius.xs

  var body: some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .fill(fill)
      .frame(width: width, height: height)
  }
}

/// 整组骨架一起慢慢呼吸。
struct SkeletonPulse: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var low = false

  func body(content: Content) -> some View {
    content
      .opacity(low && !reduceMotion ? Skeleton.dim : 1)
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: Skeleton.period).repeatForever(autoreverses: true)) { low = true }
      }
  }
}

extension View {
  func skeletonPulse() -> some View { modifier(SkeletonPulse()) }
}
