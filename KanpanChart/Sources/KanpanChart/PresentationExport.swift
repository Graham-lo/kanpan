// 图表的公开接口本身就是用配色说话的：`ChartState.paletteSeed` 收一套 `PaletteSeed`，
// `ChartState.colors` 交出 `ChartColors`。这两个类型在审查 24 里从 KanpanCore 搬进了
// KanpanPresentation，所以这里把它一并转出去——用图表的地方（app、图表的测试）拿到
// `ChartState` 就能直接写 `Palette.terraSeed`，不必每个文件再补一行 import。
@_exported import KanpanPresentation
