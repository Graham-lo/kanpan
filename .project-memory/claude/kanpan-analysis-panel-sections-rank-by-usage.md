# kanpan-analysis-panel-sections-rank-by-usage

**项目约定**：看盘「分析」面板四节 2026-10-08 起按使用频率动态排位，出厂顺序画线 → 主力订单流 → 指标 → 对比；用户说常用的要有位置权重、要用项目已有的使用频率记录

2026-10-08 用户：「主力订单流、大单列表和爆仓放在分析的靠后位置，应该放到画线下面；重要的常用的应该有位置权重，项目记录了使用频率，结合起来动态调整位置。」

定稿：「分析」面板（iOS `IndicatorPage` 与手机网页 `m/pages/chart/panels.ts`）四节按同步字段 `analysisUsage`（键 draw / orderFlow / indicators / compare，每用一次 +1，总和过 256 减半，和画线工具条 `drawToolUsage` 同一套机制）排序；出厂顺序画线 → 主力订单流 → 指标 → 对比；面板打开那一刻定一次顺序，开着期间不重排；「恢复默认指标」永远最后。

**Why:** 用户要常用功能有位置权重，并且要复用项目已有的频率记录，不另起一套。
**How to apply:** 以后再往这张面板加节，默认序放进 `AnalysisSectionRank.defaultOrder`、键进服务端 `sync_validation::analysis_usage` 白名单；别做成让用户手动排的设置（见 `kanpan-minimal-settings-surface`、`kanpan-drawing-bar-shows-few-frequent-tools`）。
