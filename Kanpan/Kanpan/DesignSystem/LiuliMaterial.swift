import KanpanCore
import KanpanPresentation
import SwiftUI
import UIKit

/// 「琉璃」页面材质：自选页定稿的那一层底（光斑 + 同色收敛 + 颗粒）和玻璃，抽成全 app 共用的一份。
///
/// 来历：自选页（`FavoritesView` 里的 `LiuliSkin` / `AuroraBackdrop`）是用户自己定稿的那一页，
/// 我的、账号、板块、图表弹层原来各自垫一块 `app` / `raised2` 的实色，和自选页不是一种材料。
/// 这里把那套数值原样搬出来（基线和 `LiuliSkin` 一个数都不差），再给三套皮肤各补一笔签名，
/// 让皮肤之间一眼分得开：
///
/// | 皮肤 | 底 | 光斑 | 玻璃 |
/// |---|---|---|---|
/// | 经典 | 种子 `ground`（AICoin 白） | **不画** | 极淡灰白 + 1/3pt 墨色细线 |
/// | 青苔 | `#E9F3F1` | 天青 · **冷绿** · 薄荷 | 白玻璃 |
/// | 陶土 | `#F4EFEA` | 原三团 | 暖白玻璃 + 暖调纸纹（颗粒 0.06） |
/// | 深色 | 种子 `ground` | **不画** | 原深色玻璃 |
///
/// 和自选页的差异只在这三笔签名上：经典原来借青苔三团光斑、青苔第二团是 `#BFEFD6`、
/// 陶土颗粒是 0.035。自选页本身不归这一份管（它的文件只读），要对齐时让它改用 `LiuliMaterial` 即可。
///
/// 只读主题，不存状态，随用随建（和 `PanelTheme` 一样便宜）。
struct LiuliMaterial: Equatable {
  let theme: PanelTheme

  init(theme: PanelTheme) { self.theme = theme }
  init(_ theme: PanelTheme) { self.theme = theme }

  var seed: PaletteSeed { theme.seed }
  var dark: Bool { theme.dark }
  var isClassic: Bool { Palette.isClassic(seed) }
  var isWarm: Bool { Palette.isWarm(seed) }

  // MARK: 底

  static let sageGround: Hex = "#E9F3F1"
  static let terraGround: Hex = "#F4EFEA"
  /// 青苔：天青 · 冷绿 · 薄荷。第二团比自选页原来的 `#BFEFD6` 饱和一档（同一支冷绿），
  /// 好和经典的白底分开，又不发脏。
  static let sageLobes: [Hex] = ["#A9DDF3", "#9FE6C8", "#DCEFF6"]
  static let terraLobes: [Hex] = ["#B5D9F1", "#F5D8C3", "#D3EDE0"]

  /// 整页的底色。底栏身后那道渐变也收在它上面（`TabBar.fade`）。
  var ground: Color { Color(hex: groundHex) }

  /// 底色的原始值（对比度测试、要拿 `Hex` 混色的地方用）。
  var groundHex: Hex {
    if dark || isClassic { return seed.ground }
    return isWarm ? Self.terraGround : Self.sageGround
  }

  /// 画不画光斑：只有青苔 / 陶土的浅色画。经典是一张白纸，深色下用户点名去掉过。
  var showsLobes: Bool { !dark && !isClassic }

  /// 三团光斑的颜色。`showsLobes == false` 时也给一组（深色借强调色，经典借青苔），
  /// 只是不画——留着是为了老调用方按下标取色不越界。
  var lobes: [Color] {
    if dark { return [accent, accentLift, Color(hex: seed.amber)] }
    return (isWarm ? Self.terraLobes : Self.sageLobes).map { Color(hex: $0) }
  }

  /// 光斑峰值不透明度。列表直接压在光上，整体收 30%（同自选页）。
  func lobeOpacity(_ index: Int) -> Double {
    guard dark else { return 0.9 * 0.7 }
    return (index == 2 ? 0.34 : 0.55) * 0.7
  }

  /// 底部同色收敛：从 22% 高度起往下回到底色，到底盖住七成。
  var washStrength: Double { 0.7 }

  /// 颗粒。陶土浅色加重成一层纸纹（0.06），其余照自选页。
  var grainOpacity: Double {
    if dark { return 0.05 }
    return isWarm ? 0.06 : 0.035
  }

  /// 颗粒的染色：陶土浅色给一点暖褐，让噪点读成纸纹而不是屏幕脏；其余不染（灰噪点）。
  var grainTint: Color? { (!dark && isWarm) ? Color(hex: "#C9A07A") : nil }

  // MARK: 强调色

  var accent: Color { Color(hex: seed.accent) }
  var accentLift: Color { Self.lift(seed.accent, 0.42) }
  /// 液态药丸：acc2 → acc。
  var accentGradient: LinearGradient {
    LinearGradient(colors: [accentLift, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  // MARK: 玻璃

  /// 玻璃的「料」：深色借近白的墨色；陶土借暖白；青苔 / 经典借 `raised`（都是白）。
  var pane: Color {
    if dark { return Color(hex: seed.ink) }
    if isWarm { return Color(hex: "#FFFAF4") }
    return Color(hex: seed.raised)
  }

  /// 卡片玻璃。经典是白纸上的一片极淡灰白（`raised2` 七成），靠细线立住；其余同自选页。
  var glass: Color {
    if dark { return pane.opacity(0.065) }
    if isClassic { return Color(hex: seed.raised2).opacity(0.7) }
    return pane.opacity(0.64)
  }

  /// 薄一档的玻璃（输入框、胶囊底、二级卡）。
  var glassThin: Color {
    if dark { return pane.opacity(0.045) }
    if isClassic { return Color(hex: seed.raised2).opacity(0.45) }
    return pane.opacity(0.46)
  }

  /// 玻璃边上那一圈柔光（浅色是白边，深色是墨色边）。
  var edgeSoft: Color { pane.opacity(dark ? 0.12 : 0.62) }

  /// 分隔线 / 细线的墨色。
  var rule: Color { Color(hex: seed.ink).opacity(dark ? 0.11 : 0.09) }

  /// 凹槽：分段控件的槽、开关的轨这类「往下压一层」的底（墨色薄纱，深色稍重）。
  var well: Color { Color(hex: seed.ink).opacity(dark ? 0.12 : 0.06) }

  /// 卡片描边：经典是 1/3pt 墨色细线（白纸上没有光可借，靠线分层）；其余是柔光白边。
  var cardEdge: Color { (isClassic && !dark) ? Color(hex: seed.ink).opacity(0.1) : edgeSoft }

  /// 细线宽度：1/3pt（三倍屏上正好一个物理像素）。
  static let hairline: CGFloat = 1.0 / 3.0

  // MARK: 墨

  var ink: Color { Color(hex: seed.ink) }
  var ink2: Color { Color(hex: seed.ink2) }
  var ink3: Color { Color(hex: seed.ink3) }
  /// 比 ink3 再弱一档，给上标数字、单位、微标签。
  var ink4: Color { Color(hex: seed.ink3).opacity(0.7) }

  /// 玻璃顶上那一线高光。
  func topHighlight(inset: CGFloat) -> some View {
    Capsule().fill(pane.opacity(dark ? 0.3 : 0.9))
      .frame(height: 1).padding(.horizontal, inset)
  }

  func lift(_ hex: Hex, _ amount: Double) -> Color { Self.lift(hex, amount) }

  /// 往亮里提一档：色相不动，饱和收一点、明度往上走——原型里 acc2 和 acc 的关系。
  static func lift(_ hex: Hex, _ amount: Double) -> Color {
    let rgba = hex.rgba
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: 1)
      .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return Color(hue: Double(h), saturation: Double(s) * (1 - amount * 0.6),
                 brightness: Double(b) + (1 - Double(b)) * amount)
  }
}

// MARK: - 底：三团会动的光

/// 整页的琉璃底：底色 + 三团慢慢漂的光斑（只在青苔 / 陶土浅色）+ 同色收敛 + 颗粒。
///
/// 用法：`.background { LiuliBackdrop() }`，或 `LiuliBackdrop(material:)` 显式传。
/// 不吃点按、自己 `ignoresSafeArea`，铺满整页。
struct LiuliBackdrop: View {
  /// 传了就用它；不传就从环境里的主题现建。
  var material: LiuliMaterial?
  /// 弹层用：只要底色 + 颗粒，不要光斑（`PanelPresentation`）。
  var lobes = true

  @Environment(\.panelTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var drift = false

  init(material: LiuliMaterial? = nil, lobes: Bool = true) {
    self.material = material
    self.lobes = lobes
  }

  private var m: LiuliMaterial { material ?? LiuliMaterial(theme) }

  var body: some View {
    let m = m
    GeometryReader { geometry in
      let width = geometry.size.width, height = geometry.size.height
      ZStack(alignment: .topLeading) {
        m.ground
        if lobes && m.showsLobes {
          lobe(m, 0, size: 300, x: -95, y: -80, seconds: 22)
          lobe(m, 1, size: 250, x: width - 170, y: 240, seconds: 27)
          lobe(m, 2, size: 280, x: -70, y: height - 230, seconds: 31)
          LinearGradient(stops: [
            .init(color: m.ground.opacity(0), location: 0.22),
            .init(color: m.ground.opacity(m.washStrength), location: 1)],
            startPoint: .top, endPoint: .bottom)
            .frame(width: width, height: height)
        }
        if let grain = LiuliGrain.image {
          if let tint = m.grainTint {
            grain.resizable(resizingMode: .tile).colorMultiply(tint).opacity(m.grainOpacity)
          } else {
            grain.resizable(resizingMode: .tile).opacity(m.grainOpacity)
          }
        }
      }
      .frame(width: width, height: height)
      .clipped()
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onAppear { if !reduceMotion { drift = true } }
  }

  /// 漂移只动 `offset` / `scale`，交给渲染线程去跑，不会让列表每帧重建。
  private func lobe(_ m: LiuliMaterial, _ index: Int, size: CGFloat, x: CGFloat, y: CGFloat,
                    seconds: Double) -> some View {
    let color = m.lobes[index]
    let peak = m.lobeOpacity(index)
    return RadialGradient(
      gradient: Gradient(stops: [
        .init(color: color.opacity(peak), location: 0),
        .init(color: color.opacity(peak * 0.55), location: 0.45),
        .init(color: color.opacity(0), location: 1)]),
      center: .center, startRadius: 0, endRadius: size / 2)
      .frame(width: size, height: size)
      .scaleEffect(drift ? 1.08 : 1)
      .offset(x: x + (drift ? 18 : 0), y: y + (drift ? -26 : 0))
      .animation(reduceMotion ? nil
                 : .easeInOut(duration: seconds).repeatForever(autoreverses: true), value: drift)
  }
}

/// 一张 96×96 的灰噪点，平铺当颗粒。只生成一次（种子与自选页同一个，纹理一模一样）。
@MainActor enum LiuliGrain {
  static let image: Image? = {
    let side = 96
    var bytes = [UInt8](repeating: 0, count: side * side)
    var state: UInt64 = 0x2545_F491_4F6C_DD1D
    for index in bytes.indices {
      state ^= state << 13; state ^= state >> 7; state ^= state << 17
      bytes[index] = UInt8(truncatingIfNeeded: state >> 33)
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                              bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false,
                              intent: .defaultIntent) else { return nil }
    return Image(decorative: image, scale: 1)
  }()
}

// MARK: - 玻璃卡

/// 琉璃玻璃卡：玻璃填充 + 1/3pt 描边（经典墨线 / 其余柔光白边）+ 顶上一线高光。
private struct LiuliCardModifier: ViewModifier {
  var radius: CGFloat
  var thin: Bool
  var highlight: Bool
  @Environment(\.panelTheme) private var theme

  func body(content: Content) -> some View {
    let m = LiuliMaterial(theme)
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    content
      .background {
        shape.fill(thin ? m.glassThin : m.glass)
          .overlay(shape.strokeBorder(m.cardEdge, lineWidth: LiuliMaterial.hairline))
          .overlay(alignment: .top) {
            if highlight && !m.isClassic { m.topHighlight(inset: radius) }
          }
      }
  }
}

extension View {
  /// 把这块内容垫成一张琉璃玻璃卡（圆角默认 `Radius.m`）。只画底，不加内边距。
  func liuliCard(radius: CGFloat = Radius.m, thin: Bool = false, highlight: Bool = true) -> some View {
    modifier(LiuliCardModifier(radius: radius, thin: thin, highlight: highlight))
  }

  /// 整页铺琉璃底（带光斑）。等价于 `.background { LiuliBackdrop() }`。
  func liuliBackdrop(lobes: Bool = true) -> some View {
    background { LiuliBackdrop(lobes: lobes) }
  }
}

// MARK: - 液态药丸

/// 液态药丸：强调色渐变 + 顶上一线高光 + 同色投影。用在一页唯一的主操作上
/// （「登录 / 注册」「重试」这类），字是白的。
struct LiuliPill: View {
  let title: String
  var systemImage: String?
  var fill = true
  let action: () -> Void
  @Environment(\.panelTheme) private var theme

  init(_ title: String, systemImage: String? = nil, fill: Bool = true, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.fill = fill
    self.action = action
  }

  var body: some View {
    let m = LiuliMaterial(theme)
    Button(action: action) {
      HStack(spacing: Space.xs) {
        if let systemImage { Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)) }
        Text(title).font(TypeScale.bodyEmph)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, Space.xl)
      .frame(minHeight: Hit.min)
      .frame(maxWidth: fill ? .infinity : nil)
      .background {
        Capsule().fill(m.accentGradient)
          .overlay(alignment: .top) { m.topHighlight(inset: Space.l).padding(.top, 1) }
          .shadow(color: m.accent.opacity(m.dark ? 0.25 : 0.35), radius: 10, y: 6)
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}
