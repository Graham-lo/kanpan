import SwiftUI
import UIKit

/// 全 app 唯一的一条提示（P2.7）。
///
/// 以前有两套：宿主上的 `say`（`Toast`，带「撤销」），和面板里自己挂的 `PanelToast`。
/// 分成两套是因为宿主那条画在主界面上，一开半屏面板、复盘本、提醒总表就被盖在下面，
/// 面板只好自己再养一条。两条长得不一样、停留时间各算各的，面板开着时说的「撤销」
/// 和关着时说的还不是同一颗按钮。
///
/// 现在只剩这一条：它画在自己那扇透明的小窗里，窗口层级在所有 sheet /
/// fullScreenCover 之上，所以不管是谁说、说的时候上面盖着几层，都是同一个位置、同一颗按钮。
/// 窗口只在「带动作的那条提示」那一块接手势，其余地方一律穿透给底下的界面。
///
/// 规矩和原来的 `say` 一样：全屏同一时刻只有一句，新的直接顶掉旧的；
/// 没有动作的停 1.6 秒，带「撤销」的停 5 秒（`undoSeconds`）。
@MainActor @Observable
final class ToastCenter {
  static let shared = ToastCenter()

  /// 带「撤销」的提示停多久。要等这段时间过完才真正落地的操作（清缓存、作废记录）也按它算，
  /// 所以提示消失的那一刻就是撤销机会没了的那一刻。
  static let undoSeconds = 5.0

  struct Line: Equatable {
    var serial: Int
    var text: String
    var actionTitle: String
    var hasAction: Bool
  }

  private(set) var line: Line?
  /// 跟着宿主的皮肤走。宿主每说一句都会顺手更新；宿主以外的人说话时用最近一次的。
  var theme: PanelTheme?

  @ObservationIgnored private var action: (() -> Void)?
  @ObservationIgnored private var serial = 0
  @ObservationIgnored private var window: ToastWindow?
  /// 提示条在窗口里的位置。窗口只在这一块里接手势。
  @ObservationIgnored fileprivate var hitRect: CGRect = .null

  func say(_ text: String, actionTitle: String = "撤销", undo: (() -> Void)? = nil) {
    serial += 1
    let mine = serial
    action = undo
    installIfNeeded()
    window?.isHidden = false
    withAnimation(.easeOut(duration: 0.18)) {
      line = Line(serial: mine, text: text, actionTitle: actionTitle, hasAction: undo != nil)
    }
    let stay = undo == nil ? 1.6 : Self.undoSeconds
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(stay))
      guard let self, self.serial == mine else { return }
      self.dismiss()
    }
  }

  /// 点了右边那颗按钮：先做动作，再收起。
  func runAction() {
    let act = action
    act?()
    dismiss()
  }

  func dismiss() {
    action = nil
    hitRect = .null
    // 收完就把窗藏起来：一扇常驻的全屏窗哪怕是透明的，也会被系统当成「最上面那扇」
    // 去问转屏和状态栏——没话说的时候它不该在场。
    withAnimation(.easeOut(duration: 0.22)) { line = nil } completion: { [weak self] in
      guard let self, self.line == nil else { return }
      self.window?.isHidden = true
    }
  }

  // ---------------------------------------------------------------- 窗口

  private func installIfNeeded() {
    if let window, window.windowScene != nil { return }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    else { return }
    let w = ToastWindow(windowScene: scene)
    w.owner = self
    // sheet 和 fullScreenCover 都长在主窗口里；比主窗口高一级就压得住它们，
    // 又低于键盘和系统弹窗。
    w.windowLevel = .alert + 1
    w.backgroundColor = .clear
    let host = ToastHostController(rootView: ToastStage(center: self))
    host.view.backgroundColor = .clear
    w.rootViewController = host
    // 不 makeKey：键盘、第一响应者、读屏焦点都还留在主窗口。
    w.isHidden = false
    window = w
  }
}

/// 只在提示条那一块接手势的透明窗。
private final class ToastWindow: UIWindow {
  weak var owner: ToastCenter?

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard let owner, owner.line?.hasAction == true, owner.hitRect.contains(point) else { return nil }
    return super.hitTest(point, with: event)
  }
}

/// 状态栏样式和转向都听主窗口的：这扇窗只是压在上面的一层，不该替界面做这两个决定。
/// （转向只转交 `supportedInterfaceOrientations`：`shouldAutorotate` 从 iOS 16 起系统不再问，
/// 覆盖它只换来一条弃用警告，`make strict` 下就是错误。）
private final class ToastHostController: UIHostingController<ToastStage> {
  private var main: UIViewController? {
    guard let scene = view.window?.windowScene else { return nil }
    var top = scene.windows.first(where: { $0.windowLevel == .normal && !($0 is ToastWindow) })?.rootViewController
    while let next = top?.presentedViewController { top = next }
    return top
  }

  override var preferredStatusBarStyle: UIStatusBarStyle { main?.preferredStatusBarStyle ?? .default }
  override var prefersStatusBarHidden: Bool { main?.prefersStatusBarHidden ?? false }
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    main?.supportedInterfaceOrientations ?? .allButUpsideDown
  }
}

/// 窗口里唯一的内容：底下那条提示。位置和原来宿主上那条一样（离底 92pt，让开底栏）。
private struct ToastStage: View {
  let center: ToastCenter

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.clear
      if let line = center.line, let theme = center.theme {
        Toast(theme: theme, text: line.text, actionTitle: line.actionTitle,
              undo: line.hasAction ? { center.runAction() } : nil)
          .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { center.hitRect = $0 }
          .padding(.bottom, 92)
          .id(line.serial)
      }
    }
    .ignoresSafeArea(.keyboard)
    .animation(.easeOut(duration: 0.18), value: center.line)
  }
}
