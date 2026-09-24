import KanpanCore
import SwiftUI

/// 收下朋友发来的一组线时，问一句「他设了提醒的那几条，也给你设上？」。
///
/// 自己画线不再问（2026-09-23 起）：给线加提醒改成选中栏上的那枚胶囊
/// （`LineAlertChip`），任何时候点选中都能开。只剩这一处还问，是因为这是一次性地
/// 决定「要不要接受别人的设置」，错过了也没关系——线已经收下，想要提醒照样点胶囊。
///
/// 方案 2.3 第一条仍然成立：**不许挡住画布，也不许用系统弹窗**。竖屏占头部价格行，
/// 横屏在画线工具栏上方。六秒没动就等于「只留线」。
@MainActor
final class AlertPromptModel: ObservableObject {
  struct Pending: Equatable {
    var symbol: String
    var sentence: String
    var batch: [Drawing]
  }

  @Published private(set) var pending: Pending?
  /// 用户按了「加入提醒」。
  var onAcceptBatch: (([Drawing], String) -> Void)?

  /// 六秒。方案里写死的那个数。
  static let patience: Duration = .seconds(6)

  private var countdown: Task<Void, Never>?

  /// **必须推到下一轮 runloop 才改 `pending`**：这条路常常是从别的发布回调里同步
  /// 回来的，SwiftUI 这一帧多半正开着事务；`@Published` 的通知是改之前发的，撞上就会
  /// 读到改之前的 `nil`，整场不再重画，问话出不来。让出一轮之后两件事分开。
  func offerBatch(_ drawings: [Drawing], symbol: String, preferred: Set<String>, from sender: String) {
    let supported = drawings.filter { AlertGeometry.lines(for: $0) != nil }
    guard !supported.isEmpty, !symbol.isEmpty else { return }
    let defaults = supported.filter { preferred.contains($0.id) }
    let sentence = defaults.isEmpty
      ? "要在这 \(supported.count) 条线上提醒你吗？"
      : "\(sender) 在其中 \(defaults.count) 条上设了提醒，也给你设上？"
    let next = Pending(symbol: symbol, sentence: sentence,
                       batch: defaults.isEmpty ? supported : defaults)
    countdown?.cancel()
    countdown = Task { [weak self] in
      guard let self, !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.18)) { pending = next }
      try? await Task.sleep(for: Self.patience)
      guard !Task.isCancelled else { return }
      dismiss()
    }
  }

  func accept() {
    guard let pending else { return }
    dismiss()
    onAcceptBatch?(pending.batch, pending.symbol)
  }

  func dismiss() {
    countdown?.cancel(); countdown = nil
    guard pending != nil else { return }
    withAnimation(.easeOut(duration: 0.18)) { pending = nil }
  }
}

private extension View {
  /// 提醒条里的按钮：点击区 44×44，布局高度不超过条高。
  func promptHit() -> some View {
    hitTarget().padding(.vertical, -(Hit.min - AlertPromptBar.height) / 2)
  }
}

/// 那一条。整行高 36pt，字 13pt——它比周期条还轻一档。
///
/// 两个落脚点，内容一字不差：
/// - **竖屏在头部价格行那一行上**（`inHeader`，2026-09-21 改）。从前它是图**外面**
///   额外插的一行，于是画完线的那一瞬整张图被压矮一行、六秒后又弹回来，肉眼两次跳动。
///   现在它占的是「最新价 + 涨跌幅」那一行的位置：价格行照旧占着位（只是透明），
///   行高一个 pt 不变，图表尺寸一动不动。让位的做法和十字线活着时那三颗动作
///   （`HiddenWhileCrosshairReads` / `CrosshairReadoutRow`）是同一套。
/// - **横屏仍旧是图下面那一条**：横屏的头部只有一行小字，塞不下这一句，
///   而横屏画线台下沿本来就排着一条工具栏，它和那条并排（§2E5）。
struct AlertPromptBar: View {
  @ObservedObject var model: AlertPromptModel
  /// 摆在头部价格行的位置上（竖屏）。这一档不自己撑开一行，左右也不再外缩——
  /// 它由外面用 `overlay` 挂上去，**不参与头部定尺寸**。
  var inHeader = false
  @Environment(\.panelTheme) private var theme

  /// 条高 36：竖屏它盖在头部价格行上，不能比那一行高（高了会扫到 K 线上）。
  static let height: CGFloat = Hit.min - Space.s

  var body: some View {
    if let pending = model.pending {
      HStack(spacing: Space.s) {
        Image(systemName: "bell")
          .font(TypeScale.captionEmph)
          .foregroundStyle(theme.amber)
        Text(pending.sentence)
          .font(TypeScale.footnote)
          .foregroundStyle(theme.ink)
          .lineLimit(2)
          .minimumScaleFactor(0.85)
        Spacer(minLength: Space.xs)
        // 两颗按钮画面不变（「只留线」是字、「加入提醒」是 28 高的药丸），点击区各撑到 44×44；
        // 比这一条高出来的那几 pt 用负边距还给布局，条本身的高度一个 pt 不变。
        Button { model.dismiss() } label: {
          Text("只留线").font(TypeScale.footnote).foregroundStyle(theme.ink3).promptHit()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("alert.prompt.dismiss")
        Button { model.accept() } label: {
          Text("加入提醒")
            .font(TypeScale.controlOn)
            .foregroundStyle(theme.badgeInk)
            .padding(.horizontal, Space.m)
            .frame(minHeight: ControlMetrics.pillHeight)
            .background(Capsule().fill(theme.amber))
            .promptHit()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("alert.prompt.accept")
      }
      .padding(.horizontal, Space.m)
      .frame(maxWidth: .infinity)
      .frame(height: Self.height)
      // `children: .contain` 是这儿的关键：只写 identifier 的话，它会顺着这一行
      // 盖到里面每个元素头上，两颗按钮自己的 identifier 就被顶掉了（用例里
      // 「没有「加入提醒」」就是这么来的）。改成容器之后这一行有自己的 frame
      // （用例拿它量「不压在画布上」），按钮各自的 identifier 也还在。
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("alert.prompt")
      .background(
        // 底栏没有自己的底，这一条也一样：底下那张材料照常穿过去，
        // 只借一层极轻的强调色把它托起来。
        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
          .fill(theme.amberSoft)
          .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(theme.amberLine, lineWidth: 0.5))
      )
      .padding(.horizontal, inHeader ? 0 : Space.s)
      // 头部那一档只淡入淡出：它是挂在价格行上的 `overlay`，不受父视图裁剪，
      // 从下往上滑那一下会有一帧扫过 K 线——「画布上不浮控件」这条不留例外。
      .transition(inHeader ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
    }
  }
}
