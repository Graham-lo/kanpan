import SwiftUI
import UIKit

/// 系统sheet之外的首个点击只关闭面板，原生控件确保不会穿透到图表或其他按钮。
struct PanelDismissShield: UIViewRepresentable {
  var onDismiss: () -> Void
  func makeUIView(context: Context) -> DismissSurface { DismissSurface() }
  func updateUIView(_ view: DismissSurface, context: Context) { view.action = onDismiss }

  final class DismissSurface: UIControl {
    var action: () -> Void = {}
    init() {
      super.init(frame: .zero)
      backgroundColor = .clear
      isAccessibilityElement = true
      accessibilityIdentifier = "panel.outside"
      accessibilityLabel = "收起面板"
      accessibilityTraits = .button
      addTarget(self, action: #selector(close), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("programmatic only") }
    @objc private func close() { action() }
  }
}
