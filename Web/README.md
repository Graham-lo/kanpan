# Hkline 网页版

看盘（Hkline）的网页端：Vite + TypeScript（strict），不用 UI 框架。视觉是网页版自己的一套（设计原型在 `prototype/web-2026-09-29/`），先按 27 寸 2K（2560×1440）屏设计。

线上：<https://kanpan.43-160-232-253.sslip.io/web/>（Caddy 把 `/var/www/kanpan/` 当静态目录，`/web/` 就是其中的子目录，不用改 Caddy。路由走 hash，比如 `#chart`、`#sectors`、`#review`、`#me`）

## 怎么跑

```sh
make web-install      # = cd Web && npm install
make web-dev          # 本机开发服务器 http://localhost:5178/web/
make web-test         # vitest（经 machine-guard 排队）
make web-build        # tsc --noEmit + vite build → Web/dist/
make web-deploy       # 构建并部署到线上；SKIP_BUILD=1 跳过构建
make web-verify       # 本机 Chrome 截验收图；WEB_URL=http://localhost:5178/web/ 可以对本机跑
```

- 本机开发时，`/v1/*`（市值元数据）和 `/market/stream`（网关线路的行情 WS）由 vite 代理到线上同一个域名，行为和线上同源一致（见 `vite.config.ts`）。
- 部署（`scripts/deploy.sh`）分两步：先 `scp` 到 VPS 的 `/tmp/kpweb-dist/`，再 `sudo cp` 进 `/var/www/kanpan/web/` 并 `chown caddy`。最后用 `curl` 核对线上 `index.html` 引用的脚本名和本地这次构建的一样。
- 验收截图（`scripts/verify.mjs`）：用 playwright-core 驱动本机 Chrome，2560×1440、DPR 1，截图默认放到 `docs/acceptance/网页版-2026-09-29/`。截的内容：三套皮肤 × 浅深、放大缩小、十字线、搜索、切周期（按钮和键盘）、四图、槽位开合、侧栏收起、板块、复盘、我的。同时检查两件事：最新价 10 秒内有没有变，控制台和网络有没有报错。有报错时退出码为 1。
- 地址栏参数（验收和分享用，都可以不带）：`s=BTCUSDT`、`i=1h`、`theme=light|dark`、`skin=sage|terra|classic`、`layout=1|2|2v|3|4|6|8|9|12|16`、`panel=watch|alerts|flow|notes|trades|none`、`ladder=0|1`、`drawer=0|1`。

## 目录

| 路径 | 内容 |
|---|---|
| `src/main.ts` | 入口：读地址栏参数 → 套主题 → 装外壳 → 各页 init → 图表 |
| `src/app/store.ts` | 状态 `st`（沿用原型的字段）：可以订阅，存在 localStorage `hkline-web-v1` |
| `src/app/shell.ts` | 顶栏、页面切换、主题、全局快捷键、各页之间的钩子 |
| `src/chart/` | K 线引擎（canvas）：`chart.ts` 绘制与交互，`calc.ts` 聚合与指标，`timeAxis.ts` 上海时区刻度 |
| `src/market/` | 行情：`rest.ts` 币安 REST，`stream.ts` WS 订阅与重连，`symbols.ts` 品种表与搜索排序，`meta.ts` 供应量，`state.ts` 实时状态 |
| `src/account/` | 账号会话：用户名 + 密码登录、令牌续期、同一类设备只留一台在线；`src/sync/` 跨设备同步 |
| `src/pages/` | `chart.ts` 图表页，`drawing.ts` 画线工具栏 / 选中快捷条 / 剪贴板，`sectors.ts` 板块，`review.ts` 复盘，`me.ts` 我的 |
| `src/chart/drawTools.ts` | 画线工具的几何、命中与绘制（锚定 VWAP、固定区间成交量分布、多空持仓、⇧ 吸 45°、每只品种上限） |
| `src/watch/` | 自选小部件（键盘、在第 N 格打开、宽侧栏资金费与持仓额、闪色）与 TradingView 导入 |
| `src/review/` | 复盘：`model.ts` 回合统计与 KPI，回放与图上叠加 |
| `src/ui/` | DOM 小工具、图标（描边 2.2）、浮层 / 提示 / 弹窗 |
| `src/util/format.ts` | 数额 K/M/B/T、价格精度、百分比 |
| `src/styles/app.css` | 设计令牌与三套皮肤（青苔 / 陶土 / 经典）× 浅深 |
| `src/data/sectors.json` | 板块成员表（和手机端同一份口径） |
| `tests/` | vitest：K 线聚合与指标、数额单位、上海时区刻度 |

## 数据从哪来

浏览器直接连币安 U 本位合约，不经过我们的服务端。只有市值用的供应量是从自家服务端取的。**不用 `*.binancefuture.com`（那是测试网）。**

- REST `https://fapi.binance.com`（这个域名本身就带 CORS 头）：
  - `/fapi/v1/exchangeInfo`、`/fapi/v1/ticker/24hr`、`/fapi/v1/premiumIndex`：品种表、24h 统计、资金费率 / 标记价 / 指数价，启动时各拉一次。
  - `/fapi/v1/klines`：K 线。往左拖到头会用 `endTime` 继续向前翻页。
  - `/fapi/v1/openInterest`、`/futures/data/openInterestHist`：持仓量。副图的「持仓量」用 `openInterestHist`，币安只给 30 天内的数据。
  - `/futures/data/globalLongShortAccountRatio`、`topLongShortPositionRatio`、`takerlongshortRatio`：三个比值，每分钟刷新一次。
- WS：直连 `wss://fstream.binance.com/market/stream`（默认）。网关线路走本站 `wss://<本站>/market/stream`，和手机的「网关」是同一个服务。线路只在「我的 → 通用」里手动切，不会自动切换。
  - 订阅用 SUBSCRIBE / UNSUBSCRIBE 增减，不重连。订的流有 `kline_<周期>`、`aggTrade`、`markPrice@1s`、`ticker`。
  - 断线后按 1 秒、2 秒、4 秒……重连，最长 15 秒。连上 8 秒还收不到第一帧、或者 30 秒没有任何消息，都当作断线。
  - 页面隐藏时只保留核心流（当前格子的 K 线和 ticker、提醒要盯的品种），重连间隔至少 10 秒；回到前台立刻重连并补订。
- 市值：`/v1/market/meta`（同源，kanpan-api）返回的 `totalSupply` × 现价。服务端没给供应量的品种（大宗等）不显示市值。
- 时间统一用上海时间（UTC+8），不能改；日线在北京时间 8:00 换日。数额一律用 K / M / B / T。
- 指标与叠加（2026-09-29，详见 `docs/网页版-吸收-指标-2026-09-29.md`）：主图「关键价位」一个开关（昨高低 / 上周高低 / 今开 / 裸昨控与昨值区，`src/chart/keyLevels.ts`）、VWAP、VPVR（≥ 4h 用 15m、≥ 1d 用 1h 细 K 线）、CVD（币安历史 + 三家实时、现货 / 合约分开）、副图「大单与散户累计量差」（实时三家逐笔 + 近 3 天服务端分钟历史 `GET /v1/market/orderflow/flow`）。
- 压测遗留项根因修复（2026-09-30，详见 `docs/网页版-深度压测-2026-09-29/A-图表布局画线指标.md`「压测遗留项的根因修复」）：板块走势线来自服务端小时收盘（`GET /v1/market/hourly-closes`，每批 ≤ 200 只、不设上限；服务端不通时退回直连币安，取到的在 sessionStorage 留 5 分钟，`src/sectors/spark.ts`）；行情推送与 K 线并行建连（K 线在路上时推来的先攒着、到了再并，`src/chart/pushBuffer.ts`）；换品种后详情五格、持仓量副图、关键价位、订单流深度快照等停稳约半秒再取（`src/market/settle.ts`），连切时中间划过的品种一笔不取；「找相似」找完为空时直接说为什么空。首屏计时 `node scripts/firstscreen.mjs <地址> cold|switch|sectors`。

### 侧栏详情十二格

| 格子 | 来源 | 什么时候显示「—」 |
|---|---|---|
| 持仓量 | `openInterest` × 最新价 | 接口没回（新上市、即将下架） |
| 持仓 24h | `openInterestHist` 1h × 25 首尾比 | 历史不到 24 小时 |
| 24h 成交额 | `ticker/24hr` + WS `ticker` | 没有成交 |
| 资金费率 | `premiumIndex` + WS `markPrice@1s` | 交割合约、没有资金费率的品种 |
| 下次结算 | `premiumIndex.nextFundingTime`，每秒倒数 | 同上 |
| 24h 笔数 | `ticker/24hr.count` + WS `ticker` | 没有成交 |
| 多空人数比 | `globalLongShortAccountRatio` 5m 最新一档 | 币安不给这个品种的统计（部分新品种、非加密品种） |
| 大户持仓比 | `topLongShortPositionRatio` 5m | 同上 |
| 主动买卖比 | `takerlongshortRatio` 5m | 同上 |
| 标记价 | WS `markPrice@1s` | 首帧到之前 |
| 指数价 | WS `markPrice@1s` | 同上 |
| 基差 | (标记价 − 指数价) / 指数价 | 标记价或指数价缺一个 |

详情头部的「市值」按上面的口径算，没有供应量时整段不显示。

## 要登录 / 要手机配合的部分（缺数据时显示空态，不放演示数据）

- **复盘**：需要登录；交易回合要先在手机上绑定交易所只读密钥（手机拉成交、传到服务端拼回合）。网页不存密钥、不直连交易所。
- **记一笔**：右键「在这根 K 线记一笔」写的判断登录后传到服务端（`POST /v1/native-review/records`，截图走 shot），复盘「观点记录」和手机上都能看到；没登录或离线时先存在本机草稿里（`src/notes/`），登录 / 联网后自动补传。
- **侧栏「成交」**（`src/trades/panel.ts`）：读服务端交易回合里的逐笔成交；没绑密钥时只显示「在手机上绑定交易所只读密钥后，成交会自动同步到这里」。**我的 → 交易所账号**是说明页，并列出服务端收到过哪家交易所的成交、最近一次上传时间（服务端没有单独的绑定状态接口，按回合推）。
- **提醒推送**：只在这个网页开着、而且浏览器允许通知时才弹通知。提醒响一次就结束。价格、资金费率、持仓量 1 小时变化、画线穿越这几种提醒都在本机判断。
- K 线接口失败时，格子里显示空态和「重试」按钮，不画假数据。

## 画线工具与快捷键

左侧工具栏按组排；单击组按钮选这一组上次用的那把，双击连续画（右键或 Esc 退出），小箭头展开整组。细节与同步字段对账见 `docs/网页版-吸收-画线-2026-09-29.md`。

| 组 | 工具 |
|---|---|
| 线 | 趋势线 Alt T · 射线 Alt J · 水平线 Alt H · 垂直线 Alt V |
| 形状 | 矩形 Alt ⇧ R |
| 斐波那契 | 斐波那契回撤 Alt F |
| 预测与测量 | 多空持仓（入场、目标，止损默认 1R；只算止盈止损 % 与盈亏比）· 测量（⇧ 拖） |
| 成交量 | 锚定 VWAP（点一根 K 线，±1σ / ±2σ 带）· 固定区间成交量分布（拖一段时间，控制点与 70% 价值区） |

选中一条画线，格子上沿出快捷条：颜色（加最近用过的两种）、粗细、线型、画线提醒、锁这一条、删除；同族工具记住上次的样式。每只品种最多 500 条 / 2 MB。复盘回放里画线只读。

| 快捷键 | 作用 |
|---|---|
| ⇧ 拖端点 / ⇧ 画 | 吸到 0° / 45° / 90° |
| 按住 ⌘ | 临时反过来用磁吸 |
| ⌘ 拖 | 复制一条拖走 |
| ⌘ C / ⌘ V | 复制 / 粘贴画线（同一只品种） |
| ← → ↑ ↓ | 微移选中的画线 1 px（⇧ 10 px） |
| Delete | 删除选中的画线 |
| ⌘ Z · ⌘ Y / ⌘ ⇧ Z | 撤销 · 重做 |
| ⌘ ⌥ H（或 ⌃ ⌥ H） | 隐藏 / 显示全部画线 |
| Alt N | 记一笔 |
| Alt ⇧ W | 开关侧栏 |
| ⇧ T | 布局 |
| ? | 快捷键表（能按功能或按键搜，alt / option / ⌥ 通用） |

工具栏最下面的垃圾桶：全部画线 / 全部指标 / 全部，带数量，⌘ Z 能撤销。

## 自选小部件、复盘 KPI、板块、找相似（2026-09-29，详见 `docs/网页版-吸收-复盘与自选-2026-09-29.md`）

- **自选**（`src/watch/`）：Home / End 跳首尾，Enter 打开，Delete 移出（⌘Z 撤回），空格取消收藏（淡着留在原位、再按空格收回，焦点离开或 Esc 后才消失），Esc 退出列表。多图布局下列表头和右键菜单写「在第 N 格打开」。列固定；侧栏宽 ≥ 400 时多「资金费 · 持仓额」两列，没有永续的品种写「—」、悬停提示「该品种没有永续」。价格变动闪色 150ms。
- **从 TradingView 导入**：我的 → 通用，粘贴或选 TradingView 导出的 .txt；按币安合约表匹配（认 `交易所:代号`、`.P`、不带 USDT、`1000` 前缀、GOLD/SILVER/WTI 这类俗名），品种进哪一类由它自己定，已在自选的不重复加，对不上的列出来。
- **复盘 KPI**（`src/review/model.ts`，前端算）：盈利因子没有亏损时写「—」；最大回撤按已实现资金曲线同时给金额和占峰值百分比（为 0 写「没有回撤」）；最大单笔占净盈亏 ≥ 50%、净盈亏 > 0、回合 ≥ 2 时提示「这段时间的盈利主要来自 1 笔」；做多 / 做空分开给净盈亏、回合、胜率。
- **板块**：不到 3 只有行情的板块（如 DeSci 只有 BIO）不算跑赢大盘，那一列写「—」并悬停说明原因，排在最后。
- **找相似**：1h / 4h / 1d 的候选窗口由服务端 worker 的 `market-index` 循环滚动维护（`Backend/kanpan-api/src/market_index.rs`）；相似度门槛按周期分（15m 0.60、1h 0.58、4h / 1d 0.56）。

## 给订单簿 / 订单流留的三个槽位

槽位的开合状态放在 `st.slots` 里（`src/app/store.ts`），以后跟账号一起同步。图表页的网格由 `layoutSlots()`（`src/pages/chart.ts`）按 `st.slots` 和侧栏开合用 JS 生成。

各区域的宽高能拖（梯子列、右侧面板、底部抽屉、主图与副图、侧栏各块、多图网格的列宽行高），双击分隔线回默认；尺寸只存本机 localStorage `hkline-web-sizes-v1`、不进账号同步，窗口变小时按比例收（`src/app/sizes.ts`、`src/pages/chartLayout.ts`、`src/ui/splitter.ts`）。

1. **深度梯子列** `#ladderSlot`：在价格轴和右侧栏之间，打开时宽 `--ladder-w`（240px），关上时是 0。和图表共用顶部工具条那一行。
2. **底部抽屉** `#drawerSlot`：在图表区下方，打开时高 `--drawer-h`（280px），关上时是 0。宽度横跨图表列和梯子列。
3. **侧栏小部件堆叠**：`st.slots.widgets` 是一个有序列表，现在是 `watch`（自选）、`detail`（详情），类型里已经留了 `book` / `tape` / `walls` / `alerts`。侧栏按这个顺序往下堆。

可以在顶栏中间的「原型」控制台里切换开合，也可以用地址栏参数 `ladder=1&drawer=1` 打开。

订单流吸收（2026-09-29）：梯子中列成交净差、深度 / 变化两种模式、双击回中间价，侧栏「24 小时流动性」「24 小时成交」两块，成交流 bps 与大单加高；说明见 `docs/网页版-吸收-订单流-2026-09-29.md`，回归段 `node scripts/regress.mjs <地址> flow`。

## 原型控制台

顶栏中间的「原型」按钮不属于产品界面，是给设计验收用的：切皮肤、深浅、涨跌色，开关两个槽位，切四图或一图，以及「恢复初始」（清掉这个网页在浏览器里存的全部状态）。

## 手机网页版（`/web/m/`，2026-09-29 起，详见 `docs/手机网页版-2026-09-29.md`）

装不了 iOS app 时的临时替代版：照 iOS app 逐屏复刻（三套皮肤、四格底栏、头部六格、周期条钉住与「更多」弹层、扫图、自选分类页、板块列表、我的、提醒、横屏画线台、记一笔、分享），不是 PC 网页版的手机断点。线上 <https://kanpan.43-160-232-253.sslip.io/web/m/>，Safari 分享 → 加到主屏幕即为独立 PWA（manifest `public/m/manifest.webmanifest`，`sw.js` 只缓存壳）。灵动岛、推送、震动、强制横屏不复刻；已接受的差别只有不能强制横屏（竖屏时给转屏引导）、没有震动、切后台要重连。

- 入口：`m/index.html` → `src/m/main.ts` → `src/m/boot.ts`；vite 第二个入口，与 PC 同一次 `make web-build` / `make web-deploy`。路由 `#chart #favorites #sectors #me`，深链 `?open=search|settings|alerts|account`，验收参数 `?skin=&theme=`。
- 共用：`src/market/`、`src/account/`（keyPrefix `hkline-m`，设备类别 phone）、`src/sync/`（同步引擎抽了状态适配器，PC 与手机各一份）、`src/util/format.ts`、`src/data/sectors.json`、`src/review/api.ts`。
- 自己的：`src/m/app/`（store `hkline-m-v1`、prefs 白名单、壳、同步适配 `sync.ts` / `syncCodec.ts`、画线本 `drawings.ts` / `drawCodec.ts`）、`src/m/styles/`（`tokens.css` 逐值照 iOS Palette.swift）、`src/m/ui/`、`src/m/chart/`（从 KanpanChart / KanpanCore 逐文件移植的 Canvas 2D 引擎，画线 41 种工具，见 `src/m/chart/README.md`）、`src/m/indicator/`、`src/m/model/`、`src/m/pages/`（页面契约见 `src/m/app/README.md`）。
- 实验台：`m/lab.html` 只挂引擎，验收用。测试：`tests/m-*.test.ts`。验收截图：`docs/acceptance/手机网页版-2026-09-29/`。
