import KanpanCore

extension WidgetSnapshot.Colors {
  /// 从一套皮肤种子取小组件要的那几支色。快照本身（`WidgetSnapshot`，在 Core）只存
  /// 十六进制串，不认识皮肤；「哪套皮肤出哪几支色」是展示层的事，所以这条构造放在这儿。
  public init(seed: PaletteSeed, redUp: Bool) {
    let chart = Palette.chart(seed, redUp: redUp)
    self.init(ground: seed.app.value, ink: seed.ink.value, ink2: seed.ink2.value, ink3: seed.ink3.value,
              line: seed.line.value, accent: seed.accent.value, up: chart.up.value, down: chart.down.value)
  }
}
