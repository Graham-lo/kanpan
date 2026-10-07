import CoreGraphics
import KanpanCore
import KanpanPresentation

/// 画线的那支笔：颜色与浓淡全部从当前皮肤派生（2026-10-08 视觉整改）。
///
/// **一支笔。** 线、填充、手柄描边、端点、选中框、读数胶囊的底、斐波那契刻度的字，
/// 一条线上所有的墨都出自 `color(of:_:)` 这一个颜色（填充、底板只是它的透明度阶）。
/// 从前没挑过颜色的线走 `band`（蓝），手柄却是 `amber`（棕金），一条线上两种墨。
///
/// **跟皮肤。** `Drawing.color == nil` 就是「跟皮肤」：画的时候取这一刻皮肤的强调色 `accent`（青苔墨绿、陶土赤陶……；`amber` 三套几乎同一支金棕，分不出皮肤，不用它），
/// 换皮肤、切深浅色线跟着变。存档里不再写死任何默认色；老线存着的显式色照旧按那支色画，
/// 存档格式不变、不迁移。
///
/// **色板。** 五格全部从皮肤来：跟皮肤（强调色）、强调色浅一阶、涨、跌、墨。第一格存 `nil`，
/// 其余存挑的那一刻的色值（存档仍是一支 `Hex`）。
public enum DrawPen {
  /// 没在编辑的线画多浓：不选中时整条线（线、填充、字）按这个不透明度退后一步，
  /// 让 K 线是主角；选中的那条与正在画 / 拖的那条是 1。系统「降低透明度」打开时一律 1。
  public static let restAlpha: CGFloat = 0.7

  /// 这条线用哪支色。
  public static func color(of d: Drawing, _ t: ChartColors) -> Hex { color(d.color, t) }
  public static func color(_ stored: Hex?, _ t: ChartColors) -> Hex { stored ?? t.accent }

  /// 强调色浅一阶：往白里掺三成。深浅两版都往「亮」走——深色底上它更跳，浅色底上仍读得出。
  public static func lighter(_ t: ChartColors) -> Hex {
    Palette.mix(t.accent, "#FFFFFF", amount: 0.7)
  }

  /// 色板的一格。`stored` 是选它之后写进 `Drawing.color` 的值（`nil` = 跟皮肤）。
  public struct Swatch: Equatable, Sendable {
    public var role: String
    public var name: String
    public var stored: Hex?
    public var shown: Hex
  }

  /// 色板，顺序固定：跟皮肤、浅一阶、涨、跌、墨。
  ///
  /// 和前面某一格同色的那格不摆（深色青苔的强调色就是涨色），免得两格看着一样、选了却是两回事。
  public static func swatches(_ t: ChartColors) -> [Swatch] {
    let light = lighter(t)
    let all = [
      Swatch(role: "skin", name: "跟皮肤", stored: nil, shown: t.accent),
      Swatch(role: "light", name: "浅色", stored: light, shown: light),
      Swatch(role: "up", name: "涨色", stored: t.up, shown: t.up),
      Swatch(role: "down", name: "跌色", stored: t.down, shown: t.down),
      Swatch(role: "ink", name: "墨色", stored: t.ink, shown: t.ink),
    ]
    var out: [Swatch] = []
    for s in all where !out.contains(where: { $0.shown.value.uppercased() == s.shown.value.uppercased() }) {
      out.append(s)
    }
    return out
  }

  /// 一条线此刻画多浓。
  ///
  /// - 系统「降低透明度」打开：一律 1。
  /// - 选中的那条：1；其余（包括画线台里没选中的）：`restAlpha`。
  public static func alpha(for id: String, selected: String?, reduceTransparency: Bool) -> CGFloat {
    if reduceTransparency || id == selected { return 1 }
    return restAlpha
  }
}
