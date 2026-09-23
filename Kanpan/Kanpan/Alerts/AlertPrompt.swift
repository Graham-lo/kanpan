import KanpanCore
import SwiftUI

/// 收下朋友发来的一组线时，问一句「他设了提醒的那几条，也给你设上？」。
///
/// 自己画线不再问（2026-09-23 起）：给线加提醒改成选中栏上的那枚胶囊
/// （`LineAlertChip`），任何时候点选中都能开。只剩这一处还问，是因为这是一次性地
/// 决定「要不要接受别人的设置」，错过了也没关系——线已经收下，想要提醒照样点胶囊。
///
/// 方案 2.3 第一条仍然成立：**不许挡住画布，也不许用系统弹窗**。竖屏占头部价格行，
/// 横屏在画线工具栏上方。十秒没动就等于「只留线」。
///
/// **「摆出来」和「开始数秒」是两件事**（2026-09-23）。从前 `offerBatch` 设好 `pending`
/// 当场就开始睡六秒；可弹条若是赶上转屏，转屏就吃掉一秒左右，露面时只剩四五秒。
/// 现在秒表只在弹条**真的出现在屏幕上**（`barAppeared`）、而且转屏已经转完
/// （方向锁那一拍放开，`Orientation.hasPendingRelease`）之后才开始走，耐心也从 6 秒放到 10 秒。
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

  /// 弹条露面之后等多久。原来是方案写死的 6 秒，2026-09-23 体验审查放到 10 秒：
  /// 收下一组线的人往往先看一眼线落在哪儿，再决定要不要跟着设提醒。
  static let patience: Duration = .seconds(10)

  /// 让出一轮 runloop 再改 `pending` 的那一小步（见 `offerBatch`）。
  private var presenting: Task<Void, Never>?
  /// 秒表：从弹条真正露面、转屏转完开始数 `patience`。
  private var countdown: Task<Void, Never>?

  /// 摆出一句新的问话。真正的计时起点是 `barAppeared`（弹条露面那一刻重新数）。
  ///
  /// 这儿也先起一只秒表，管两种弹条不会再 `onAppear` 的情形：上一句还没走、这一句
  /// 顶替它（同一条视图，不会再出现一次）；弹条压根没机会露面（换了页、切了后台）——
  /// 没有这一只，那一句就永远挂着。
  private func present(_ next: Pending) {
    presenting?.cancel()
    countdown?.cancel(); countdown = nil
    presenting = Task { [weak self] in
      guard let self, !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.18)) { self.pending = next }
      self.startClock()
    }
  }

  /// 弹条真的出现在屏幕上了（`AlertPromptBar` 的 `onAppear`）。从这一刻重新数。
  func barAppeared() {
    if pending != nil { startClock() }
  }

  /// 开始（或重新开始）数 `patience`。转屏还没转完时先等它转完：`Orientation.rotate`
  /// 排着的那一拍放锁（600ms，`OrientationBridge.swift` 的 `scheduleRelease`）落下之前，
  /// 屏幕还在转，那段时间不算人看得见的时间。最多等 1.5 秒，不会因为别的原因一直卡着。
  private func startClock() {
    countdown?.cancel()
    countdown = Task { [weak self] in
      var waited = 0
      while Orientation.hasPendingRelease, waited < 15, !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(100))
        waited += 1
      }
      guard !Task.isCancelled else { return }
      try? await Task.sleep(for: Self.patience)
      guard !Task.isCancelled else { return }
      self?.dismiss()
    }
  }

  /// **必须推到下一轮 runloop 才改 `pending`**：这条路常常是从别的发布回调里同步
  /// 回来的，SwiftUI 这一帧多半正开着事务；`@Published` 的通知是改之前发的，撞上就会
  /// 读到改之前的 `nil`，整场不再重画，问话出不来。让出一轮之后两件事分开（见 `present`）。
  func offerBatch(_ drawings: [Drawing], symbol: String, preferred: Set<String>, from sender: String) {
    let supported = drawings.filter { AlertGeometry.lines(for: $0) != nil }
    guard !supported.isEmpty, !symbol.isEmpty else { return }
    let defaults = supported.filter { preferred.contains($0.id) }
    let sentence = defaults.isEmpty
      ? "要在这 \(supported.count) 条线上提醒你吗？"
      : "\(sender) 在其中 \(defaults.count) 条上设了提醒，也给你设上？"
    let next = Pending(symbol: symbol, sentence: sentence,
                       batch: defaults.isEmpty ? supported : defaults)
    present(next)
  }

  func accept() {
    guard let pending else { return }
    dismiss()
    onAcceptBatch?(pending.batch, pending.symbol)
  }

  func dismiss() {
    presenting?.cancel(); presenting = nil
    countdown?.cancel(); countdown = nil
    guard pending != nil else { return }
    withAnimation(.easeOut(duration: 0.18)) { pending = nil }
  }
}

/// 那一条。整行高 36pt，字 13pt——它比周期条还轻一档。
///
/// 两个落脚点，内容一字不差：
/// - **竖屏在头部价格行那一行上**（`inHeader`，2026-09-21 改）。从前它是图**外面**
///   额外插的一行，于是画完线的那一瞬整张图被压矮一行、六秒后又弹回来，肉眼两次跳动。
///   现在它占的是「最新价 + 涨跌幅」那一行的位置：价格行照旧占着位（只是透明），
///   行高一个 pt 不变，图表尺寸一动不动。
/// - **横屏仍旧是图下面那一条**：横屏的头部只有一行小字，塞不下这一句，
///   而横屏画线台下沿本来就排着一条工具栏，它和那条并排（§2E5）。
struct AlertPromptBar: View {
  @ObservedObject var model: AlertPromptModel
  /// 摆在头部价格行的位置上（竖屏）。这一档不自己撑开一行，左右也不再外缩——
  /// 它由外面用 `overlay` 挂上去，**不参与头部定尺寸**。
  var inHeader = false
  @Environment(\.panelTheme) private var theme

  var body: some View {
    if let pending = model.pending {
      HStack(spacing: 8) {
        Image(systemName: "bell")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(theme.amber)
        Text(pending.sentence)
          .font(.scaled(13))
          .foregroundStyle(theme.ink)
          .lineLimit(2)
          .minimumScaleFactor(0.85)
        Spacer(minLength: 6)
        Button("只留线") { model.dismiss() }
          .buttonStyle(.plain)
          .font(.scaled(13))
          .foregroundStyle(theme.ink3)
          .accessibilityIdentifier("alert.prompt.dismiss")
        Button("加入提醒") { model.accept() }
          .buttonStyle(.plain)
          .font(.scaled(13, .semibold))
          .accessibilityIdentifier("alert.prompt.accept")
          .foregroundStyle(theme.badgeInk)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(Capsule().fill(theme.amber))
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity)
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
      .padding(.horizontal, inHeader ? 0 : 10)
      // 头部那一档只淡入淡出：它是挂在价格行上的 `overlay`，不受父视图裁剪，
      // 从下往上滑那一下会有一帧扫过 K 线——「画布上不浮控件」这条不留例外。
      .transition(inHeader ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
      // 秒表从这一刻开始数（转屏没转完就再等它转完），不是从 `offerBatch` 那一刻。
      .onAppear { model.barAppeared() }
    }
  }
}
