# 看盘 · Codex 接手核验

> 本文是2026-09-14接手现场的历史快照。后续已完成代码实现、真机与模拟器验证；当前状态见 `docs/acceptance/AICoin-base/foundation/IMPLEMENTATION.md` 和 `compatibility/README.md`；后续配色/数据/新分类栏见 `docs/acceptance/护眼配色与数据完整性.md`。不要据下文恢复旧默认值、重启已停止的任务或重复实现。

核验时间：2026-09-14T21:41:00+08:00
本轮用户要求：同步 Claude 记忆，查看具体窗口，准备接手。已导入记忆、核验窗口与仓库；本轮未修改实现、运行构建测试、提交或安装 App。

## 工程与范围

- 真正仓库：`/Users/mdd/zhk/kanpan`，当前分支 `main`，HEAD `752ba4473b3fa9a915147a521dd2b52a85504fc3`。
- `/Users/mdd/kanpan` 是空的会话目录；本 Codex 任务 cwd `/Users/mdd/zjh-codex-p3` 是另一个工程。后续命令须显式使用 kanpan 仓库。
- Swift 6 / iOS 17+，SwiftUI 外壳 + UIKit/CoreGraphics 图表；零第三方依赖；币安 USDT 永续看盘，不做交易下单。
- 规格：`docs/实施任务书.md`、只读 `prototype/`；后补 AICoin 研究：`docs/AICoin-K线复刻规格.md`。后补研究与旧规格有冲突，应按用户最新要求与真机证据判断，不能默默混用。
- 根 README 中“Swift 实现还没开始”已过时。现已有 Core、Chart、Data、App、诊断与验收材料；M9 文档明确仍有真机性能/稳定性验收未完成。
- 旧工程默认 MA(7,25,99)、MACD+RSI 已被用户当前手机参数取代：MA(10,30,120,256)，VOL+OI+MACD(10,30,9)，对数轴。保留旧风格，AICoin为默认且共用交互底座。
- K线仅内存缓存及小型启动快照；单选面板选完收起、点图关闭；体验依据用户真机 AICoin。

## 现场窗口

- Claude「看盘任务实现」：额度限制，末条消息自述构建过、core/chart 测试被打断、改动未提交。仍显示两个等待类后台任务，本轮未停止。
- Claude「AICoin 安卓应用逆向分析」：额度限制；两项补充报告代理失败。界面显示 **Auto-continue when limits reset 已勾选，22:31 自动续跑**。本轮未改变设置或发消息；真正开始写入前需先协调，避免同时改同一工作树。
- iPhone 镜像：已经显示用户手机 AICoin「K线设置」页面，当前可看到对数、靠右、实心、选中价等选择。只核验画面，没有修改这些设置。旧记忆“镜像不可用”已过时。
- devicectl：iPhone 16 Pro available (paired)。
- Mac AiCoin：行情窗口正常，当前 SKHYNIX/USDT 永续 5分钟主图，下方 OI、MACD。
- QuickTime：当前是打开文件对话框，并非正在显示真机录像预览。
- 不修改 Mac 的 Surge 网关、Wi-Fi、路由或 DNS。

## 逆向材料与关键纠正

- `refs/aicoin/` 已存在（源码子集、资源、报告、真机截图），但当前仍未跟踪；用户要求保留以供接手。
- `refs/aicoin/README.md` 是索引，`live-capture/FINDINGS.md` 是真机记录。证据优先级：用户 iPhone 实测 > Mac 旁证 > 安卓源码 > 推断。
- **后续真机复核纠正：A恢复自动定标；⏮圆钮展开/收起侧栏，不是回到最新。** 主Y翻转开关为允许点击翻转。
- 单次Y缩放样本不能判定iOS数学公式；Android指数公式只作参考。
- 两份缺失报告现已补齐：REPORT-indicators.md、REPORT-candle-axis.md。新的用户参数和27张截图在 refs/aicoin/USER-CHART-PROFILE.json 与 live-capture/codex-2026-09-14。尚未覆盖全部图表交互，不能宣称全部1:1。

## 验收与当前未提交内容

- 改动涵盖图表面板与设置、图表布局/渲染、逐笔行情合成/REST 对表/重连补缺、设置测试与 UI 机型测试。未经本轮逐项复核，不视为已验收。
- 当前 `docs/acceptance/M8/ui-test/summary.txt` 是八行 PASS（每台 11 条），**包括 iPad Pro M5、缺 iPhone SE 3**；与主窗口“任务书八台全过，额外 iPad Pro 失败”自述不一致。后续查明机型清单和日志轮次；不能报告任务书八机型已全部验收。
- 测试入口：`make core-test`、`make data-test`、`make chart-test`、`make settings-test`、`make build`、`make ui-test`。运行前检查现有任务，保留所有未提交产物。

建议接手次序：先处理自动续跑协调；保护并审阅未提交改动；补齐逆向未交付的指标/蜡烛轴报告与语义证据；按真机最新结论推进实现，执行对应回归并补齐机型和真机验收。

## 同步的记忆

`.project-memory/claude/` 保存 16 份 Claude 原文，导入与过时项说明见 `IMPORT.md`。

## 核验时工作树（新增交接文件前）

```text
 M Kanpan/Kanpan/Main/ChartHost.swift
 M Kanpan/Kanpan/Main/IntervalBar.swift
 M Kanpan/Kanpan/Main/LandscapeChrome.swift
 M Kanpan/Kanpan/Main/MainScreen.swift
 M Kanpan/Kanpan/Main/MarketModel.swift
 M Kanpan/Kanpan/Main/VectorIcon.swift
 M Kanpan/Kanpan/Panels/PanelPresentation.swift
 M Kanpan/Kanpan/Settings/Model/Prefs.swift
 M Kanpan/Kanpan/Settings/Model/PrefsCodec.swift
 M Kanpan/Kanpan/Symbols/SymbolPickerView.swift
 M Kanpan/KanpanUITests/MainScreenUITests.swift
 M Kanpan/KanpanUITests/UITestSupport.swift
 M Kanpan/Settings/Tests/KanpanSettingsTests/PrefsDefaultsTests.swift
 M Kanpan/Settings/Tests/KanpanSettingsTests/PrefsPersistenceTests.swift
 M Kanpan/Settings/Tests/KanpanSettingsTests/PrefsToleranceTests.swift
 M KanpanChart/Sources/KanpanChart/ChartRenderer.swift
 M KanpanCore/Sources/KanpanCore/Geometry/Layout.swift
 M KanpanData/Sources/KanpanData/Binance/DTO.swift
 M KanpanData/Sources/KanpanData/Binance/Endpoints.swift
 M KanpanData/Sources/KanpanData/Feed/FeedComposer.swift
 M KanpanData/Sources/KanpanData/Feed/MarketFeed.swift
 M KanpanData/Sources/kanpan-feed/main.swift
 M KanpanData/Tests/KanpanDataTests/FeedReplayTests.swift
 M Tools/ui-test.sh
 M docs/acceptance/M6.md
 M docs/acceptance/M8/ui-test/build.log
 M docs/acceptance/M8/ui-test/iPhone-13-mini.log
 M docs/acceptance/M8/ui-test/iPhone-15.log
 M docs/acceptance/M8/ui-test/iPhone-16-Pro.log
 M docs/acceptance/M8/ui-test/summary.txt
?? .project-memory/
?? Kanpan/Kanpan/Panels/ChartPanel.swift
?? KanpanData/Tests/KanpanDataTests/TickFoldTests.swift
?? "docs/AICoin-K\347\272\277\345\244\215\345\210\273\350\247\204\346\240\274.md"
?? docs/acceptance/M8/ui-test/iPad-Pro-11-inch-M5.log
?? docs/acceptance/M8/ui-test/iPad-mini-A17-Pro.log
?? docs/acceptance/M8/ui-test/iPhone-16-Plus.log
?? docs/acceptance/M8/ui-test/iPhone-17-Pro-Max.log
?? docs/acceptance/M8/ui-test/iPhone-Air.log
?? refs/
```
