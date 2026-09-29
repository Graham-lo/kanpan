# 手机网页版 · K 线图表引擎（`src/m/chart`）

把 iOS 的 KanpanChart / KanpanCore 逐文件移植到 Canvas 2D：常量、分区、手势阈值、配色、指标算法与手机端一致。
不复用 PC 版 `src/chart/`。零运行时依赖，指针事件手写（`touch-action: none`），按 DPR 画并对齐到 1 物理像素。

## 文件对照

| TS | 移植自 |
|---|---|
| `series.ts` | KanpanCore BarSeries / Interval / ExternalSeries |
| `geometry.ts` | KanpanCore Geometry（ViewWindow、Clamp、ViewMath、PriceScale、Ticks、Layout、AICoinBehavior、ChartContentLayout、SubPaneResize、ChartGestureRoute） |
| `format.ts` | KanpanCore Format |
| `paint.ts` | KanpanChart Paint + Palette（颜色读 CSS 变量 `--k-*` / `--of-*`） |
| `state.ts` | KanpanChart ChartState（input / viewport / overlay 三层不可变） |
| `renderer*.ts` | ChartRenderer（+Sub、+Compare、+Probe、+OrderFlow） |
| `orderflowGroup.ts` | OrderFlowGroup |
| `gesture.ts` | ChartGesture + ChartView+Gesture |
| `view.ts` / `view.parts.ts` | ChartView（三层画布 + 画线盖层、rAF 脏标记） |
| `drawing.ts` / `draw/**` | KanpanCore Drawing + ChartView+Drawing |
| `compare.source.ts` | CompareFeed + CompareModel（对比品种取数、往左补齐、退避、按主序列对齐） |
| `depth.source.ts` | MarketFeed 的 depth5 那一支（盘口五档，直连独立小连接） |
| `external.source.ts` | 主界面 OISource（近 30 天 REST：持仓量、多空比、主动买卖比、基差） |
| `orderflow.source.ts` | 主力订单流数据口（包 `src/orderflow/feed.ts`） |
| `index.ts` | 主界面 ChartHost（ViewIntent、状态合并、副图拖高 / 换序）+ ChartSession（compose、心跳） |
| `beat.ts` | 心跳开关 ChartBeat：页面露着且宿主没 pause 才每秒一拍，回来立刻补一拍、离开超 5 秒补缺口 |

## 对外 API

```ts
import { createChart } from './m/chart'

const chart = createChart(host, {
  symbol: 'BTCUSDT', interval: '1h',
  overlays: ['MA'], subs: ['VOL', 'OI', 'MACD'],     // 副图最多 3 个，多的丢掉
  barSpacing: prefs.barSpacing,                        // 上次捏到的根宽，缺省 4
  streams: names => setStreams([...pageStreams, ...names]), // 图要订的推送流，由页面合并后交给 market
  orderFlowSource: push => myPort,                     // 可选：主力订单流数据口；不传用默认 createOrderFlowPort（三家聚合，品种类型 / 24h 额取全市场表，线路跟 S.route），传 null 不订
  compareSymbols: prefs.compareSymbols,                // 可选：对比品种键（binance/usd_m/ETHUSDT），最多三只
  depth: prefs.depth,                                  // 可选：盘口五档
  priceMode: 'percent',                                // log / linear / percent
})
```

`host` 是一个定好宽高的容器；图在里面放一个纵向滚动容器（副图多时内容比视口高，高度照 `ChartContentLayout`）。

| 方法 | 说明 |
|---|---|
| `setSymbol(sym)` / `setInterval(iv)` | 换品种（清十字线、视野复位）/ 换周期（按旧根宽，跟着最新则右缘贴最新，否则锚在原右缘）；新数据到之前留着旧图不闪空 |
| `setIndicators(main, subs, params?)` | 主图叠加与副图；`ORDERFLOW` 放在 main 里等于 `setOrderFlow(true)` |
| `setCandleStyle(p)` | `ChartOptions` 的任意子集 + `priceMode`（log / linear / percent）+ `mainInverted` |
| `setCompare(keys)` | 对比品种（偏好里的整串键，顺序决定配色槽位）；传 `[]` 关掉 |
| `setDepth(on)` | 盘口五档开关 |
| `pause()` / `resume()` | 宿主页藏起 / 露出：停 / 开心跳（按视野补外部数据、倒计时、覆盖层重算）；resume 立刻补一拍，离开超过 5 秒重拉末页与对比。推送、盘口、订单流仍由宿主各自收 |
| `setLook(p)` | 其余样式：参数、颜色覆写、隐藏输出、副图倍率、强弱上下轨等 |
| `setOrderFlow(on, display?)` | 主力订单流开关与显示设置 |
| `setDrawings(list)` | 本品种画线（只读展示用；装了画线控制器之后线从 `DrawingBook` 投影，用控制器的 `setDrawings` / `bindDrawings`） |
| `setLandscape(on)` | 横屏画线台：只留原始 K 线（不画主图副图指标、不画订单流），退出时恢复 |
| `showWindow(from, to)` | 把视野铺到这段时间（扫图 / 复盘跳转） |
| `scrollToLatest()` / `clearCrosshair()` / `resetPriceScale()` | |
| `redrawNow()` | 立刻画完脏层（截图用） |
| `destroy()` | 退订推送（`streams([])`）、停心跳、摘监听、移除 DOM |

只读：`el`、`view`（底层 ChartView）、`symbol`、`interval`、`state`、`isAtLatest`。

### 事件 `chart.on(name, fn) → off`

| 事件 | 载荷 | 用途 |
|---|---|---|
| `crosshair` | `{ crosshair, bar }` | 头部开高低收读数（`dataDisplay: 'top'`） |
| `scale` | `{ barSpacing }` | 用户捏合 / 平移后落盘根宽 |
| `visibleRange` | `{ from, to, atLatest }` | 「回到最新」按钮显隐 |
| `select` | `{ kind: 'orderFlow', focus }` | 点中订单流墙（focus 带详情卡摆放：below / leading / top / maxHeight / maxWidth / compact；卡片由页面画）。画线的选中不走这里，看下节控制器的 `selected` / `onState` |
| `inversion` | `{ main, subs }` | 双击翻转后落盘 |
| `subScale` | `{ id, scale }` | 拖副图分隔线后落盘 |
| `subOrder` | `IndicatorID[]` | 长按副图换序后落盘 |
| `status` | `{ loading, error, bars }` | 首屏加载 / 取不到数据 |
| `tap` / `notice` / `interaction` | | 单击图、图上轻提示、手指按下 / 抬起 |

### 对比、盘口、百分比轴（宿主接法）

照 iOS ChartSession.compose 与 MarketFeed：

- **对比** `compareSymbols` / `setCompare(keys)`：直接把 `Prefs.compareSymbols` 整串交进来，引擎自己去掉主图那只、去重、最多三只；
  只认 `binance/usd_m/<代号>` 与裸代号（网页版只有币安合约行情），别家的键留在偏好里但不取不画。有可画的对比时：
  主图换成百分比轴（基准 = 可见区首根收盘，跟着平移走）、主图叠加 / 订单流 / 画线 / 盘口都不画（`options.drawings = false`），
  图例写「主图 + 各对比品种的涨跌」，颜色取调色板第 `槽位 % 数量` 个（槽位 = 键在偏好里的位置）；横屏画线台暂停对比。
  数据：先拉最新一页，再往左补到主序列起点（主图往左翻，对比跟着补）；推送与主图共用 kline 流（引擎自己把对比代号并进 `streams` 回调）；
  取不到 2 s·2ⁿ 退避、最长 30 s；推送跳根 / 断线重连 / 从后台回来超过 5 s 都重拉末页补缺口；发布按 100 ms 合批。
  **宿主须知**：iOS 在「预览朋友分享的画线」（`draw.previewing`）与复盘画面上不开对比——那时请 `setCompare([])`，结束后再交回偏好。
- **盘口** `depth` / `setDepth(on)`：币安合约 `<代号>@depth5@100ms`，直连 `wss://fstream.binance.com/public/stream` 单独一条小连接
  （每帧就是完整五档，不是增量）。只在直连线路上连：线路判断默认 `S.route !== 'gateway'`，可用 `isDirectRoute` 覆写，
  网关线路（iOS 的 hasMicrostructure = false；网页网关的 `/public/stream` 也不转深度）不画不连。换线路时 market 发的 `ws` 事件引擎自己接住。
  对比中、横屏画线台、页面切后台都断开并清掉；乱序帧不收；首帧 8 s / 静默 10 s 当断线，1 s·2ⁿ（最长 15 s）重连。
  测试或自带数据源时传 `depthSource: push => port`（`DepthPort`：`setWanted(on, symbol, direct)` / `setVisible` / `dispose`），传 `null` 不订。
- **百分比轴** `priceMode: 'percent'`：单品种也能用（刻度 `+1.2%`，基准同上）；不需要再在宿主里把 percent 映射成 linear。

实验台：`lab.html?cmp=ETHUSDT,SOLUSDT`、`?depth=1&iv=1m&pm=linear`、`?pm=percent`。

## 画线控制器（`view.drawing.ts` + `draw/`）

画线是宿主层接的：引擎的 renderer / view / gesture 已留好挂点，不用改。

```ts
import { attachDrawing } from './chart/view.drawing'
import { DrawingBook } from './chart/draw/book'

const c = attachDrawing(chart.view)    // 接好投影、投影键、换键回调、盖层绘制五个挂点，盖层接触摸
c.bindDrawings(book)                   // 共享的一本线（DrawingBook，按品种分桶、各自撤销史）；之后线只从本里来
c.editable = drawingMode               // 不在画线态时收手：点中旧线也不选中
c.setTool('trendLine')                 // DrawTool = DrawingKind；null 退出工具
c.onChanged = items => save(items)     // 线变了（落成、拖动、删除、撤销，以及同步 / setDrawings 整桶换进来）就交出最终的线
c.onFull = () => toast('本品种画线已满')
c.onFeedback = k => toast(k)           // 'snapped' | 'rejected' | 'removed' | 'locked' | 'unlocked'
```

| 成员 | 说明 |
|---|---|
| `attachDrawing(view)` / `c.detach()` | 装上 / 摘下（`teardown()` 只清手势与临时态） |
| `bindDrawings(book)` / `book` | 接共享的 `DrawingBook`；不接时用控制器自己的一本 |
| `editable` / `interactive` | 画线态开关 / 盖层是否接触摸 |
| `setTool(tool)` / `tool` / `continuous` / `magnet` | 当前工具、连续画、磁吸（默认开） |
| `selected` | 选中的线 id（可读写）；变化经 `onState` 通知 |
| `setDrawings(items)` / `updateDrawing(d)` / `duplicateSelected()` / `deleteSelected()` / `clear()` / `setAllHidden(h)` | 改线 |
| `addHorizontalLine(price, t?)` | 从十字线「画水平线」 |
| `undo()` / `redo()` / `endDrawing()` | 撤销、重做、结束当前这笔 |
| `alerted` | 带提醒的线 id 集合（画提醒记号） |
| `onChanged` / `onState` / `onCommitted` / `onDragged` / `onFull` / `onFeedback` | 回调：线集合变了 / 工具与选中等状态变了 / 落成一条 / 拖完一条 / 满额 / 吸附与拒绝等轻反馈 |

## 行为要点

- 默认开关照手机 `Prefs.chartOptions`：网格随皮肤（经典不画、青苔 / 陶土画淡网格）、本根倒计时常开、十字线读数写在头部、双击翻转主 / 副轴、图例折行让位。
- 颜色来自 `<html>` 上的 CSS 变量；`data-skin` / `data-theme` / `data-updown` 或系统深浅一变就重读。
- 数据：首屏一页 1500 根（量是币量、主动买是 takerBuyBaseVolume，与手机同口径）；贴左缘向左翻页；推送来的根先推视野再原地 upsert；回前台、推送重连、推送跳根时拉最新一页补缺口；最近 8 个品种 × 周期留快照，换回来立刻有图。
- 副图：分隔线上下 8 pt 竖拖改高度（倍率随人）；副图里长按 350 ms 拖动换序（抢在十字线 400 ms 之前）。
- 时区固定上海（UTC+8）。

## 开发

- 实验台：`npm run dev` 后打开 `/web/m/lab.html?skin=sage&theme=dark&subs=VOL,OI,MACD&of=1&cross=0.6`（仅开发，不进产物；`cmp` / `depth` / `pm` 见上文）。
- 测试：`tests/m-chart-*.test.ts`、`tests/m-indicator*.test.ts`（移植自 Swift 的数值用例）。
