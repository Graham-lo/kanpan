# 网页版深度审查：bug / 性能 / 压测，各模块各操作细节（2026-10-05）

用户：「现在对 web 端也做同样的审查」（接 iOS 的 `docs/acceptance/深度审查-2026-10-04/`）。
范围：`Web/` 全部——PC 网页版（`src/` 除 `m/`）与手机网页版 PWA（`src/m/`），以及它们依赖的服务端接口（`Backend/kanpan-api`）。

每条线先只读审查出清单，再逐条复核、从根因修掉、配回归用例（vitest / Playwright），只提交自己动过的文件，直接进 main。
每条线的清单、结论（含判为非 bug 的理由）、测试数都在本目录 `<线>/报告.md`。

| 线 | 范围 |
|---|---|
| A | PC 图表引擎与图表页：`src/chart/`、`src/pages/chart.ts`、`src/pages/drawing.ts`、多图布局、指标与叠加、画线、时间轴 |
| B | PC 其余页面与模块：`src/app/`、`src/pages/{sectors,review,me}.ts`、`src/watch/`、`src/alerts/`、`src/notes/`、`src/trades/`、`src/review/`、`src/sectors/`、`src/ui/`、`src/util/` |
| C | 行情数据、线路与同步（两端共用）：`src/market/`、`src/account/`、`src/sync/`、`src/orderflow/` 的取数与 WS、限流、重连、前后台 |
| D | 手机网页版图表引擎与指标：`src/m/chart/`、`src/m/indicator/` |
| E | 手机网页版壳、页面、模型、PWA：`src/m/app/`、`src/m/pages/`、`src/m/model/`、`src/m/ui/`、`m/index.html`、SW |
| F | 性能与压测（Playwright/Chromium，PC 与手机两端）：冷启、内存、长时间挂机、高频切换、大规模数据、断网 |
| G | 交易员走查：把两端线上/本地跑起来，以交易员身份带着真实任务把每个操作走一遍 |
