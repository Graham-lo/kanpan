# Hkline / 看盘：模型窗口入口

给任何在这个仓库里工作的模型窗口（Claude、Opus 子代理或其他）。先读本文，再读 `README.md`（现行界面、线路与目录）和 `.project-memory/PROJECT.md`（跨窗口快照）。`docs/账号复盘-实施进度.md` 只剩「账号 / 复盘还欠什么」那部分有效，它的行情线路一节是 09-15 自动切换时代的旧账。用户当前指示永远优先于本文和任何记忆。

## 谁在做什么

- **2026-09-22 起，仓库里所有还没做完的事一律由 Codex 实现**（`codex exec`，`gpt-6-astra`，推理挡位 `xhigh`），清单、禁做项与验收标准在 `docs/待办交接-Codex-2026-09-22.md`；此前单独交给 Codex 的「发给朋友·画线分享」已交付（`e058715`），方案在 `docs/发给朋友-画线分享-实施方案-2026-09-22.md`。Claude 窗口只设计、验收、打回，不再写代码。Codex 在这个仓库里遵守本文的全部约定。
- **`docs/不做清单.md` 是「不做什么」的唯一口径**（强平、CNY 换算、固定起点强弱比较、多交易所等）。其它任何文档、注释把这些写成「待办 / 建议 / 缓 / 预埋」都无效，不因为基建现成就顺手做；新判不做的项当场写进那份清单并把别处的待办措辞删掉。`docs/待办交接-Codex-2026-09-22.md` 是**唯一的待办来源**；`docs/` 下其余文档只能是现行规格（见 `docs/README.md` 索引），不是待办来源，不要从中翻出「建议 / 缓」来做。
- 之前另一个 Claude 窗口做「盘点第一节」留下的未提交改动（`KanpanNetwork/`、`KanpanCore/` 里的多空比 / 主动买卖比 / 基差开头）已随交接归 Codex 接管。
- 同一工作树经常有另一个窗口在改代码。开工前先看 `git status` 与 `git log`，只动自己任务范围内的文件，不清理、不覆盖别人的未提交改动，不顺手提交别人的文件。
- 流水线：原型定稿 → 实现 → 验收 → 装真机 → commit + push。改动要建立在 `origin/main` 最新提交之上。

## 稳定约定

- 实际项目 `/Users/mdd/zhk/kanpan`，远程 `https://github.com/Graham-lo/kanpan`，产品名 Hkline。父目录的 Scorebook 与 `/Users/mdd/zjh*` 是别的项目。
- iOS 原生，不走 WebView 或跨端；最低系统 iOS 26.0（2026-09-21 起，app 与各 SPM 包同步；iOS 27 也在支持范围内，26 以下不再维护）；iOS 26 真机是主要验证目标，模拟器与编译成功不算真机结果。
- 皮肤三套：青苔·冷（默认）、陶土·暖、经典（青苔换 AICoin 白底，2026-09-17 用户点名加的），不再自创色板；K 线造型只有 AICoin 一套，没有风格选择入口；图表底座与指标是复刻成果，不是设计对象。
- 底栏是常驻标签栏「画线 · 图表 · 自选 · 板块分类 · 设置」五格（`Main/TabBar.swift`），每格一整页，底栏没有自己的底；复盘在行情页顶栏、指标并进「图表设置」面板；横屏只为画线，点画线进、画完自动回；K 线画布上不浮任何控件（早先那颗可拖动的「记」按钮已撤）。
- 界面元素尺寸克制：大字号、粗字重会被判「廉价」；不放工程 / 状态字段；不堆解释文案；面板选完即收起。
- 行情：设置里「行情线路」两档由用户自己选（出厂默认直连只走币安，网关只走两台 VPS 的 OKX），**没有自动切换**，不混源；选择只记在本机这台设备上、不随账号同步（2026-09-19 按审查 B7 改）；正常出图不能被探测阻塞。两台 VPS 网关是线上服务，只做轻量只读探测，不压测、不改 Caddyfile 与网关配置。
- 账号是用户名 + 密码；个人数据隔离、草稿与待发队列不可丢；K 线不永久堆积。
- 手机可能经本机 Mac 的 Surge 网关上网。按真实网络路径排查，不改 Mac 的网关、代理与其他应用路由。
- 验证只跑受影响的一两条真机 UI 用例并开超时；纯视觉改动真机看一眼即可。

## 加 / 删一个同步字段

「哪些设置跟着人走、服务端认哪些键」母表只有一张：`Kanpan/Kanpan/Settings/Model/PrefsFieldPlan.swift` 的 `PrefsFieldPlan.table`。两边不再手抄，中间是一份生成物 `Backend/kanpan-api/contract/settings-fields.json`（**不要手改**）。

1. 改 `PrefsFieldPlan.table`（判据只有一条：用手改出来的习惯 → `.synced`；这台机器 / 这张网的属性 → `.deviceOnly`；自动累积的统计 → `.derivedLocal`）。
2. 仓库根跑 `make sync-contract` 重新生成契约。
3. 新增 `.synced` 字段还要去 `Backend/kanpan-api/src/sync.rs` 的 `SETTINGS_FIELDS` 加名字（长度不用改，它是切片），**并且**去 `src/sync_validation.rs` 的 `field` 加值规则——只进白名单不配值规则，`_=>false` 会让整条同步操作 400，那个字段就是毒丸。
4. 两边对账：`make app-logic-test` 与 `cd Backend/kanpan-api && cargo test --lib`。差在哪个键、该往哪边改，失败信息里写着。

**加一把画线工具或一个指标也走同一条路。** 同一份契约除了字段清单还捎带两份词表——
`drawingKinds`（`Drawing.Kind`）和 `indicatorIDs` / `overlayIndicatorIDs` / `subIndicatorIDs`
（`IndicatorID`，主图那几种排在副图前面，**顺序和主副分界都算数**）。改完 `KanpanCore` 里那两个枚举
照样跑 `make sync-contract`，然后 `cargo test --lib` 会点名告诉你服务端还差哪一条：
`sync_validation.rs` 顶上的 `KINDS` / `OVERLAY_INDICATORS` / `SUB_INDICATORS` 都是切片，
加名字不用改长度；新工具若不是两个锚点，还要在 `anchor_count` 里加一条（默认 `_=>2` 会把它整条拒掉）。

对不齐的代价是实打实的：提交 `a161bb0` 里服务端少认十九个字段，服务端对含未知字段的操作整条拒绝，那个账号的同步队列被一条永远推不上去的操作堵死。

## 文档维护

完成里程碑时更新 `.project-memory/PROJECT.md` 的状态与日期，区分「本地已改 / 已推送 / 已部署 / 已真机验收」，不把计划写成已完成。旧文档不要删，改用「历史」标注并指向现行文档。
