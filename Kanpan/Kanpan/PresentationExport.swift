// 皮肤与配色（`Skin` / `PaletteSeed` / `Palette` / `ChartColors`）和几处档位名
// （`TZChoice.display`、`ChangeBasis.title`…）在审查 24 里从 KanpanCore 搬进了 KanpanPresentation。
// app 里几十个视图文件都在用它们，这里一次引进来，不必每个文件各补一行 import。
@_exported import KanpanPresentation
