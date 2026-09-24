import KanpanChart
import KanpanCore
import UIKit

/// 画线顶上那一行提示的字（§10.8）。
///
/// 从图表包搬出来的（审查 23.2）：中文文案是产品的事，图只报「手上是哪把工具、已经
/// 落了几个点」（`ChartView.drawTool` / `placedDrawAnchors`），怎么说由 app 定。
/// 字一个都没改，和搬家前 `ChartView.drawHint` 逐字相同。
enum DrawingHints {
  static func text(for tool: DrawingStore.Tool, placed: Int) -> String {
    if tool.pointCount == 1 { return "按住放置" + tool.title }
    switch tool {
    // 三点工具各有各的说法，统一说「选择终点」等于什么都没说。
    case .position: return ["按住放置入场价", "选择目标价", "选择止损价"][min(placed, 2)]
    case .fibExtension: return ["按住拖动画起点 A", "选择回调点 B", "选择起算点 C"][min(placed, 2)]
    case .channel: return placed == 2 ? "选择通道宽度" : (placed == 0 ? "按住拖动画" + tool.title : "选择终点")
    case .regression: return placed == 0 ? "圈住要拟合的那一段" : "选择这一段的终点"
    // 形态类点数多，一路数下去比「选择终点」有用：用户照着字母摆点就行。
    case .xabcd: return ["按住放置 X 点", "选择 A 点", "选择 B 点", "选择 C 点", "选择 D 点"][min(placed, 4)]
    case .abcd: return ["按住放置 A 点", "选择 B 点", "选择 C 点", "选择 D 点"][min(placed, 3)]
    case .headShoulders:
      return ["按住放置起点", "选择左肩", "选择左颈线点", "选择头部", "选择右颈线点", "选择右肩", "选择终点"][min(placed, 6)]
    case .elliottImpulse: return placed == 0 ? "按住放置 0 点" : "选择 \(placed) 浪终点"
    case .elliottCorrection: return ["按住放置 0 点", "选择 A 浪终点", "选择 B 浪终点", "选择 C 浪终点"][min(placed, 3)]
    case .pitchfork: return ["按住放置柄部 A", "选择枢轴 B", "选择枢轴 C"][min(placed, 2)]
    case .fibChannel: return ["按住拖动画基线起点", "选择基线终点", "选择通道宽度"][min(placed, 2)]
    case .triangle: return ["按住放置第一个角", "选择第二个角", "选择第三个角"][min(placed, 2)]
    case .curve: return ["按住放置起点", "选择终点", "拉出弯曲方向"][min(placed, 2)]
    case .callout: return placed == 0 ? "按住指向要标注的位置" : "选择气泡落点"
    default: return placed == 0 ? "按住拖动画" + tool.title : "选择终点"
    }
  }
}

/// 画线那几下震动（审查 23.2：触觉是产品策略，不住在图表包里）。
///
/// 图只说发生了什么（`DrawingFeedback`），震法和搬家前 `ChartHaptics` 里那几下一样：
/// 落点吸住 = selection，没落成 = rigid 0.7，拿掉了线 = warning。
@MainActor
enum DrawingHaptics {
  private static let rigid = UIImpactFeedbackGenerator(style: .rigid)

  static func play(_ feedback: DrawingFeedback) {
    switch feedback {
    case .snapped: Haptics.step()
    case .rejected: rigid.prepare(); rigid.impactOccurred(intensity: 0.7)
    case .removed: Haptics.warning()
    }
  }
}
