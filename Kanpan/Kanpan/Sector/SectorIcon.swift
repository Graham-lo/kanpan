import SwiftUI
import KanpanCore

/// 板块记号的**画法**：上色、笔画、内缩与两枚视图。记号本身（id、身份色、路径）
/// 在 `SectorIconTable.swift`，那一份不吃 SwiftUI，`Kanpan/Sector` 测试壳在 mac 上对得了账。

// MARK: - 上色、笔画、内缩

/// 记号的三样度量，全是原型里那三个函数的移植。
enum SectorInk {
  /// 一对渐变端点。
  ///
  /// 原型的 `sectorTint()` 本来就是 `BadgeTint` 的一比一 JS 移植，所以这儿不再抄一遍，
  /// 直接把身份色喂回 `BadgeTint`——两处颜色永远是同一套算法，皮肤一改两处一起改。
  ///
  /// 原型里那张 `SECTOR_SKIN_ACCENT` 表（青苔 `#2E7D6B` / `#4FB69C`、陶土 `#B25735` /
  /// `#E2874F`…）在 Swift 这边就是 `PaletteSeed.accent` 本身，一个值都不用再写：
  /// 前两套逐字对得上。只有「经典」对不上——原型给它配了一支蓝，而 app 里经典那套种子
  /// 的强调色沿用青苔的墨绿。这儿以种子为准，理由有二：面板里不许写字面 hex；
  /// 而且真按原型那支蓝走，经典皮肤下整屏只有板块记号往一支别处不存在的蓝偏，
  /// 反倒是它自己跳出来。
  static func gradient(_ art: SectorIconArt, theme: PanelTheme) -> (top: Color, bottom: Color) {
    BadgeTint.gradient(from: Hex(art.from), to: Hex(art.to), seed: theme.seed)
  }

  /// 描边宽度：和徽章共用一条窄带（`BadgeLine`），`size` 是底板直径。
  static func weight(_ declared: Double, at size: CGFloat) -> Double {
    BadgeLine.weight(declared, at: size)
  }

  /// 记号占底板的比例，带一道光学修正。
  ///
  /// 和 `BadgeLine` 是一个道理：直径小于 20 时按比例缩会显得空，所以把记号放大最多一成，
  /// 把仅有的那几个像素全用在剪影上，上限 0.82（再往外就贴到底板的边了）。
  static func inset(_ base: CGFloat, at size: CGFloat) -> CGFloat {
    let k = min(max((20 - size) / 8, 0), 1)
    return min(base * (1 + 0.10 * k), 0.82)
  }
}

// MARK: - 视图

/// 记号视图：底板 + 记号。`size` 是外框边长（也就是底板直径）。
///
/// 用在板块列表的每一行和品种列表的头部。
struct SectorIconView: View {
  var art: SectorIconArt
  var size: CGFloat

  /// 上色要跟着当前皮肤走，所以得知道现在是哪一套。
  @Environment(\.panelTheme) private var theme

  var body: some View {
    let ink = SectorInk.gradient(art, theme: theme)
    return Circle()
      .fill(LinearGradient(colors: [ink.top, ink.bottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
      .frame(width: size, height: size)
      .overlay { SectorMark(art: art, size: size) }
      // 影子只是让它离纸面一点点，尺度照徽章那一枚（0.2 以内，在青苔那种极浅的底上
      // 才不会洇成一团彩色墨点）。
      .shadow(color: ink.bottom.opacity(theme.dark ? 0.26 : 0.18),
              radius: size * 0.17, x: 0, y: size * 0.1)
      .accessibilityHidden(true)
  }
}

/// 只画记号本身，不要底板。`size` 仍是底板直径——内缩和描边宽度都是按直径算的，
/// 传记号自己的边长会让这一枚和别处的粗细对不上。
struct SectorMark: View {
  var art: SectorIconArt
  var size: CGFloat
  /// 记号的颜色。默认白：它总是压在自己那块底板上。
  var ink: Color = .white

  var body: some View {
    let box = size * SectorInk.inset(art.inset, at: size)
    return ZStack {
      ForEach(Array(art.parts.enumerated()), id: \.offset) { _, part in
        if let width = part.stroke {
          SectorShape(paths: part.d)
            .stroke(ink, style: StrokeStyle(lineWidth: SectorInk.weight(width, at: size),
                                            lineCap: .round, lineJoin: .round))
        } else {
          SectorShape(paths: part.d).fill(ink, style: FillStyle(eoFill: part.eo))
        }
      }
    }
    .frame(width: box, height: box)
    .accessibilityHidden(true)
  }
}

/// 24×24 的 `viewBox` 原样拿来，等比缩到目标边长。解析走 `SVGPath.parsed` 的缓存，
/// 这儿只剩一次等比变换——和 `CoinBadge` 里那个 `CoinShape` 是同一件事。
private struct SectorShape: Shape {
  var paths: [String]

  func path(in rect: CGRect) -> Path {
    SVGPath.parsed(paths).applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
  }
}
