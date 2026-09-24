import KanpanCore

extension WidgetSnapshot.Colors {
  /// 从一套皮肤种子取小组件要的那几支色。快照本身（`WidgetSnapshot`，在 Core）只存
  /// 十六进制串，不认识皮肤；「哪套皮肤出哪几支色」是展示层的事，所以这条构造放在这儿。
  public init(seed: PaletteSeed, redUp: Bool) {
    // 小组件上的涨跌只染文字（涨跌幅、价格），取图外文字用的那支（`Palette.inkUp` / `inkDown`），
    // 浅色下比蜡烛色深一档、对底色够 4.5:1（UI 审查 2026-09-24 §四）。
    self.init(ground: seed.app.value, ink: seed.ink.value, ink2: seed.ink2.value, ink3: seed.ink3.value,
              line: seed.line.value, accent: seed.accent.value,
              up: Palette.inkUp(seed, redUp: redUp).value, down: Palette.inkDown(seed, redUp: redUp).value)
  }
}
