import SwiftUI

/// 复盘这几页的用色。
///
/// `ReviewUI` 是独立的包，看不到 app 里那份 `PanelTheme`，所以这儿只留一组口子，
/// 由 app 在挂这几个视图时把当前配色（青苔 / 陶土，浅 / 深）灌进来
/// ——见 `MainScreen` 里的 `.environment(\.reviewTheme, theme.review)`。
///
/// 不灌也能跑：默认是一套中性浅色，只会出现在 `#Preview` 里。这儿**不要**再写
/// 具体的品牌色（原来这几页钉死了橙色，换了配色只有复盘还是橙的，像是另一个 app）。
public struct ReviewTheme: Sendable, Equatable {
  public var app: Color
  public var raised: Color
  public var raised2: Color
  public var line: Color
  public var ink: Color
  public var ink2: Color
  public var ink3: Color
  /// 强调色：动作字、选中段、主按钮。
  public var accent: Color
  /// 强调色的淡底（选中格、标签）。
  public var accentSoft: Color
  /// 压在强调色上的字色。
  public var onAccent: Color
  public var up: Color
  public var down: Color
  /// 警示：作废、删除这类「不可逆」的动作字。
  ///
  /// **别拿 `down` 当它使。** 出厂是红涨绿跌，跌色是绿的，于是「作废记录」会变成
  /// 一个绿按钮，读起来像「确认」，而且还跟着一个和作废毫无关系的设置翻来翻去。
  /// app 那边对应的是 `PanelTheme.danger`（`PaletteSeed.danger`），
  /// 由 `ReviewThemeBridge` 灌进来——复盘这边一支色都不自己定。
  public var danger: Color
  /// 分段控件里选中那一档的底（app 那边是 `PanelTheme.segOn`）。
  public var segOn: Color
  /// 行的左划动作由 app 那份唯一实现来画（`DesignSystem/SwipeToDelete`，砖底和字都跟皮肤走）。
  ///
  /// 复盘包看不到它，只能由桥（`ReviewThemeBridge`）顺着配色一起递进来；不递（`#Preview`）
  /// 就退回系统 `.swipeActions`。它不参与 `==`：换皮肤比的是颜色，不是这支闭包。
  public var swipe: ReviewSwipeProvider?

  public init(app: Color, raised: Color, raised2: Color, line: Color,
              ink: Color, ink2: Color, ink3: Color,
              accent: Color, accentSoft: Color, onAccent: Color,
              up: Color, down: Color, danger: Color,
              segOn: Color? = nil, swipe: ReviewSwipeProvider? = nil) {
    self.app = app; self.raised = raised; self.raised2 = raised2; self.line = line
    self.ink = ink; self.ink2 = ink2; self.ink3 = ink3
    self.accent = accent; self.accentSoft = accentSoft; self.onAccent = onAccent
    self.up = up; self.down = down; self.danger = danger
    self.segOn = segOn ?? raised; self.swipe = swipe
  }

  public static func == (a: ReviewTheme, b: ReviewTheme) -> Bool {
    a.app == b.app && a.raised == b.raised && a.raised2 == b.raised2 && a.line == b.line
      && a.ink == b.ink && a.ink2 == b.ink2 && a.ink3 == b.ink3
      && a.accent == b.accent && a.accentSoft == b.accentSoft && a.onAccent == b.onAccent
      && a.up == b.up && a.down == b.down && a.danger == b.danger && a.segOn == b.segOn
  }

  public static let neutral = ReviewTheme(
    app: Color(red: 0.96, green: 0.97, blue: 0.96),
    raised: .white,
    raised2: Color(red: 0.93, green: 0.95, blue: 0.94),
    line: Color(red: 0.86, green: 0.89, blue: 0.87),
    ink: Color(red: 0.09, green: 0.12, blue: 0.10),
    ink2: Color(red: 0.33, green: 0.38, blue: 0.35),
    ink3: Color(red: 0.53, green: 0.58, blue: 0.55),
    accent: Color(red: 0.18, green: 0.49, blue: 0.42),
    accentSoft: Color(red: 0.18, green: 0.49, blue: 0.42).opacity(0.12),
    onAccent: .white,
    up: Color(red: 0.13, green: 0.60, blue: 0.42),
    down: Color(red: 0.80, green: 0.27, blue: 0.27),
    danger: Color(red: 0.725, green: 0.227, blue: 0.180))
}

private struct ReviewThemeKey: EnvironmentKey {
  static let defaultValue = ReviewTheme.neutral
}

extension EnvironmentValues {
  public var reviewTheme: ReviewTheme {
    get { self[ReviewThemeKey.self] }
    set { self[ReviewThemeKey.self] = newValue }
  }
}
