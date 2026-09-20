import KanpanCore
import SwiftUI

/// 刚画完一条线，问一句「要不要提醒」。
///
/// 方案 2.3 第一条：**不许挡住画布，也不许用系统弹窗**。用户刚落下这条线，
/// 眼睛还在线上；一张居中的系统 alert 会把他刚画的东西盖住，还得先答完才能看。
/// 所以它是图**外面**那一条——竖屏在周期条下面、标签栏上面，横屏在横屏工具栏那一行。
///
/// 六秒没动就等于「只画线」。默认不是「加提醒」：用户画线大多数时候只是画线，
/// 沉默要落在代价小的那一边。
@MainActor
final class AlertPromptModel: ObservableObject {
  struct Pending: Equatable {
    var drawing: Drawing
    var symbol: String
    var sentence: String
  }

  @Published private(set) var pending: Pending?
  /// 用户按了「加入提醒」。
  var onAccept: ((Drawing, String) -> Void)?

  /// 六秒。方案里写死的那个数。
  static let patience: Duration = .seconds(6)

  private var countdown: Task<Void, Never>?

  /// 刚画完一条线。摊不出线的种类（文字、图形标注那些）直接不问。
  ///
  /// **这一句必须推到下一轮 runloop 才改 `pending`**，不能在原地改。原因是这条路是
  /// 从 UIKit 的触摸回调里同步回来的（`ChartView.commit` → `ChartHost` → 这儿），
  /// 而同一微秒之前那条线自己刚落过盘、发过一轮通知，SwiftUI 这一帧多半正开着事务；
  /// `@Published` 的通知是**改之前**发的（`willSet`），撞上这一帧就会被当场同步重画一次，
  /// 视图读到的还是改之前的 `nil`，而真正的赋值发生在重画之后——于是这一整场都不再重画，
  /// 那句问话再也不出来。实测四成的概率（日志里是「bar eval pending=0」夹在
  /// 「offer」和「offer pending set」中间那一条）。让出一轮之后两件事分开，没再复现过。
  func offer(_ drawing: Drawing, symbol: String) {
    guard !symbol.isEmpty, AlertGeometry.supports(drawing.kind) else { return }
    let next = Pending(drawing: drawing, symbol: symbol,
                       sentence: "要在这条\(drawing.kind.title)上提醒你吗？")
    countdown?.cancel()
    countdown = Task { [weak self] in
      guard let self, !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.18)) { self.pending = next }
      try? await Task.sleep(for: Self.patience)
      guard !Task.isCancelled else { return }
      self.dismiss()
    }
  }

  func accept() {
    guard let pending else { return }
    dismiss()
    onAccept?(pending.drawing, pending.symbol)
  }

  func dismiss() {
    countdown?.cancel(); countdown = nil
    guard pending != nil else { return }
    withAnimation(.easeOut(duration: 0.18)) { pending = nil }
  }
}

/// 那一条。整行高 36pt，字 13pt——它和周期条并排，比周期条还轻一档。
struct AlertPromptBar: View {
  @ObservedObject var model: AlertPromptModel
  @Environment(\.panelTheme) private var theme

  var body: some View {
    if let pending = model.pending {
      HStack(spacing: 8) {
        Image(systemName: "bell")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(theme.amber)
        Text(pending.sentence)
          .font(.system(size: 13))
          .foregroundStyle(theme.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Spacer(minLength: 6)
        Button("只画线") { model.dismiss() }
          .buttonStyle(.plain)
          .font(.system(size: 13))
          .foregroundStyle(theme.ink3)
          .accessibilityIdentifier("alert.prompt.dismiss")
        Button("加入提醒") { model.accept() }
          .buttonStyle(.plain)
          .font(.system(size: 13, weight: .semibold))
          .accessibilityIdentifier("alert.prompt.accept")
          .foregroundStyle(theme.badgeInk)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(Capsule().fill(theme.amber))
      }
      .padding(.horizontal, 12)
      .frame(height: 36)
      // `children: .contain` 是这儿的关键：只写 identifier 的话，它会顺着这一行
      // 盖到里面每个元素头上，两颗按钮自己的 identifier 就被顶掉了（用例里
      // 「没有「加入提醒」」就是这么来的）。改成容器之后这一行有自己的 frame
      // （用例拿它量「不压在画布上」），按钮各自的 identifier 也还在。
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("alert.prompt")
      .background(
        // 底栏没有自己的底，这一条也一样：底下那张材料照常穿过去，
        // 只借一层极轻的强调色把它托起来。
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(theme.amberSoft)
          .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.amberLine, lineWidth: 0.5))
      )
      .padding(.horizontal, 10)
      .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
  }
}
