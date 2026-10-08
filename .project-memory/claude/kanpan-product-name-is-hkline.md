# kanpan-product-name-is-hkline

**项目约定**：看盘的产品名是 Hkline，2026-09-18 起不再用 Hntcoin；工程名仍是 Kanpan

2026-09-18 用户让我把 app 的桌面显示名从 `Hntcoin` 改成 `Hkline`，并且补了一句
「不再使用 hntcoin」。

所以这个项目的产品名从此是 **Hkline**：桌面显示名、README / AGENTS.md /
`.project-memory/PROJECT.md` 这类活文档里的产品名、以后写的原型、交接说明、提交信息，
一律用 Hkline，不要再写 Hntcoin。

有两件事不跟着改：

- **工程名仍然是 Kanpan**。仓库目录 `/Users/mdd/zhk/kanpan`、远程
  `https://github.com/Graham-lo/kanpan`、workspace / scheme `Kanpan`、各 SPM 包
  `KanpanCore` / `KanpanData` / `KanpanNetwork`、bundle id `com.mdd.kanpan` 都不动。
  「Hkline」只是给人看的那个名字。
- **历史记录里的 Hntcoin 保留原样**。`.project-memory/HISTORY-*.md`、
  `docs/acceptance/` 下的验收日志与 JSON 都是当时的记录，改了就不是记录了。

显示名本身只在 `Kanpan/Kanpan.xcodeproj/project.pbxproj` 的
`INFOPLIST_KEY_CFBundleDisplayName` 上（Debug / Release 各一处），没有单独的 Info.plist。
