import SwiftUI
import KanpanCore

/// M0 的空壳首屏：纯色 + 「看盘」两字（§13 A0.3）。
/// 颜色取自 `KanpanCore` 的靛配色，顺带验证 app target 确实链上了 Core。
struct LaunchScreen: View {
  @Environment(\.panelTheme) private var theme

  private var seed: PaletteSeed { theme.seed }

  var body: some View {
    ZStack {
      Color(hex: seed.app).ignoresSafeArea()
      Text("看盘")
        .font(.system(size: 44, weight: .semibold))
        .kerning(6)
        .foregroundStyle(Color(hex: seed.ink))
    }
  }
}

extension Color {
  /// `Hex` → SwiftUI `Color`。Theme 层做好之前先放这儿。
  init(hex: Hex) {
    let c = hex.rgba
    self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
  }
}

#Preview { LaunchScreen() }
