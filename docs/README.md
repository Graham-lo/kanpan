# Hkline 文档索引

更新：2026-09-22。开发工作仅来自四份交接书：[待办交接](待办交接-Codex-2026-09-22.md)（第一条 Codex 线程）与[多交易所-Coinbase 交接](多交易所-Coinbase-交接-Codex-2026-09-22.md)（第二条 Codex 线程，2026-09-22 用户拍板新增）、[对比K线交接](对比K线-交接-Codex-2026-09-22.md)、[提醒铃声交接](提醒铃声-交接-Codex-2026-09-22.md)（第三、四条，同日拍板）；排除项仅来自[不做清单](不做清单.md)。其它正文描述现行规格或有日期的参考数据，不生成行动项。旧审查、盘点、方案和提示词已删除，可从Git历史追溯。

## 现行文档

| 文件 | 性质 | 内容 |
| --- | --- | --- |
| [README.md](README.md) | 现行 | 本文：规格、数据和证据索引 |
| [不做清单.md](不做清单.md) | 现行 | 唯一排除口径 |
| [待办交接-Codex-2026-09-22.md](待办交接-Codex-2026-09-22.md) | 现行 | 第一条线程的工作清单、阶段顺序与验收要求 |
| [多交易所-Coinbase-交接-Codex-2026-09-22.md](多交易所-Coinbase-交接-Codex-2026-09-22.md) | 现行 | 第二条线程：多交易所抽象 + Coinbase 现货，模块边界、五阶段与验收 |
| [对比K线-交接-Codex-2026-09-22.md](对比K线-交接-Codex-2026-09-22.md) | 现行 | 第三条线程：对比 K 线（百分比叠加，最多 3 个） |
| [提醒铃声-交接-Codex-2026-09-22.md](提醒铃声-交接-Codex-2026-09-22.md) | 现行 | 第四条线程：提醒铃声（四档，随人走，服务端推送同声） |
| [使用手册-2026-09-21.md](使用手册-2026-09-21.md) | 现行 | 已实现界面与操作说明 |
| [AICoin-K线复刻规格.md](AICoin-K线复刻规格.md) | 现行 | 图表行为、视觉约束和原始参照边界 |
| [市值口径与数据来源-2026-09-18.md](市值口径与数据来源-2026-09-18.md) | 现行规格 / 参考数据 | 市值身份核验、数据来源与有效期；日期样本不作实时目录 |
| [账号系统方案.md](账号系统方案.md) | 现行 | 用户名账号、会话隔离、同步与已上线接口 |
| [testflight-uploads.md](testflight-uploads.md) | 参考台账 | 只追加实际成功上传，空表不是功能欠账 |

## 数据与验收证据

这些目录不参与P0.5正文重写。每份证据只证明其注明的提交、日期和环境；旧报告不作为功能清单。

| 文件 | 性质 | 内容 |
| --- | --- | --- |
| [acceptance/AICoin-base/IMPLEMENTATION.md](acceptance/AICoin-base/IMPLEMENTATION.md) | 参考 | AICoin 共用底座实施记录 |
| [acceptance/AICoin-base/compatibility/README.md](acceptance/AICoin-base/compatibility/README.md) | 参考 | 机型兼容验收 |
| [acceptance/AICoin-base/foundation/IMPLEMENTATION.md](acceptance/AICoin-base/foundation/IMPLEMENTATION.md) | 参考 | 图表底座增补实现与验收 |
| [acceptance/M0.md](acceptance/M0.md) | 参考 | M0 验收：工程骨架与环境 |
| [acceptance/M1.md](acceptance/M1.md) | 参考 | M1 KanpanCore —— 验收证据 |
| [acceptance/M2.md](acceptance/M2.md) | 参考 | M2 · 数据层验收证据 |
| [acceptance/M3/A3.1-差异记录.md](acceptance/M3/A3.1-差异记录.md) | 参考 | A3.1 / A3.6 原型并排对照 —— 差异记录 |
| [acceptance/M3/A3.12-cpu.md](acceptance/M3/A3.12-cpu.md) | 参考 | A3.12 [I] 静止时 DisplayLink 暂停，CPU 占用 < 1% |
| [acceptance/M3.md](acceptance/M3.md) | 参考 | M3 · 绘制层验收证据 |
| [acceptance/M4.md](acceptance/M4.md) | 参考 | M4 手势 · 验收证据 |
| [acceptance/M5/品种页.md](acceptance/M5/品种页.md) | 参考 | M5 · 品种整页（搜索 / 自选 / 最近 / 全部）取证 |
| [acceptance/M6.md](acceptance/M6.md) | 参考 | M6 设置与面板 —— 验收证据 |
| [acceptance/M7.md](acceptance/M7.md) | 参考 | M7 画线 · 验收证据 |
| [acceptance/M8/aicoin-对比.md](acceptance/M8/aicoin-对比.md) | 参考 | AiCoin 桌面版 ⇄ 看盘：图表细节逐项实测对比 |
| [acceptance/M9.md](acceptance/M9.md) | 参考 | M9 稳定性 / 性能 / 诊断 · 验收证据 |
| [acceptance/drawing-v2/DEVICE.md](acceptance/drawing-v2/DEVICE.md) | 参考 | 画线与均线颜色：真机验收 |
| [acceptance/drawing-v2/README.md](acceptance/drawing-v2/README.md) | 参考 | 画线 v2 与均线颜色 |
| [acceptance/eye-colors/VALIDATION-NOTES.md](acceptance/eye-colors/VALIDATION-NOTES.md) | 参考 | 验收轮次与失败保留 |
| [acceptance/share/主窗口独立验收-2026-09-22.md](acceptance/share/主窗口独立验收-2026-09-22.md) | 参考 | 「发给朋友」画线分享：主窗口独立验收（2026-09-22） |
| [acceptance/share/验收报告-2026-09-22.md](acceptance/share/验收报告-2026-09-22.md) | 参考 | 发给朋友·画线分享验收报告 |
| [acceptance/兼容-iPhone15+-iPad-iOS18-2026-09-18.md](acceptance/兼容-iPhone15+-iPad-iOS18-2026-09-18.md) | 参考 | 兼容一轮：iPhone 15 及以上 · 全 iPad 系列 · iOS 18 起 |
| [acceptance/待办交接-2026-09-22/P0.md](acceptance/待办交接-2026-09-22/P0.md) | 参考 | P0 · 行情页头部验收 |
| [acceptance/护眼配色与数据完整性.md](acceptance/护眼配色与数据完整性.md) | 参考 | 原生配色、行情数据完整性与性能审查 |
| [板块分类表-2026-09-18/README.md](板块分类表-2026-09-18/README.md) | 参考 | 板块气泡图 · 分类表（2026-09-18 定稿） |
| [板块分类表-2026-09-18/加密-板块定义.md](板块分类表-2026-09-18/加密-板块定义.md) | 参考 | 看盘 · 加密细分板块清单（固定 24 个，不得自创） |
| [acceptance/待办交接-2026-09-22/P0.5.md](acceptance/待办交接-2026-09-22/P0.5.md) | 参考 | 文档统一口径的逐份核对与验证 |
| [acceptance/待办交接-2026-09-22/P1.md](acceptance/待办交接-2026-09-22/P1.md) | 参考 | 外部统计指标、盘口与归档扩列验收 |

原始逆向素材位于本机 `../refs/aicoin/`；品牌资产与原始截图分别位于 `brand/`、`截图/`。这些素材保留，不是新增任务授权。
