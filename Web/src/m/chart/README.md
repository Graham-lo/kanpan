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
| `external.source.ts` | 主界面 OISource（近 30 天 REST：持仓量、多空比、主动买卖比、基差） |
| `orderflow.source.ts` | 主力订单流数据口（包 `src/orderflow/feed.ts`） |
| `index.ts` | 主界面 ChartHost（ViewIntent、状态合并、副图拖高 / 换序）+ ChartSession（compose、心跳） |

## 对外 API

```ts
import { createChart } from './m/chart'

const chart = createChart(host, {
  symbol: 'BTCUSDT', interval: '1h',
  overlays: ['MA'], subs: ['VOL', 'OI', 'MACD'],     // 副图最多 3 个，多的丢掉
  barSpacing: prefs.barSpacing,                        // 上次捏到的根宽，缺省 4
  streams: names => setStreams([...pageStreams, ...names]), // 图要订的推送流，由页面合并后交给 market
  orderFlowSource: push => myPort,                     // 可选：主力订单流数据口；不传用默认 createOrderFlowPort（三家聚合，品种类型 / 24h 额取全市场表，线路跟 S.route），传 null 不订
})
```

`host` 是一个定好宽高的容器；图在里面放一个纵向滚动容器（副图多时内容比视口高，高度照 `ChartContentLayout`）。

| 方法 | 说明 |
|---|---|
| `setSymbol(sym)` / `setInterval(iv)` | 换品种（清十字线、视野复位）/ 换周期（按旧根宽，跟着最新则右缘贴最新，否则锚在原右缘）；新数据到之前留着旧图不闪空 |
| `setIndicators(main, subs, params?)` | 主图叠加与副图；`ORDERFLOW` 放在 main 里等于 `setOrderFlow(true)` |
| `setCandleStyle(p)` | `ChartOptions` 的任意子集 + `priceMode`（log / linear）+ `mainInverted` |
| `setLook(p)` | 其余样式：参数、颜色覆写、隐藏输出、副图倍率、强弱上下轨等 |
| `setOrderFlow(on, display?)` | 主力订单流开关与显示设置 |
| `setDrawings(list)` | 本品种画线 |
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
| `select` | `{ kind: 'orderFlow', focus }` / `{ kind: 'drawing', id }` | 点中订单流墙 / 画线 |
| `inversion` | `{ main, subs }` | 双击翻转后落盘 |
| `subScale` | `{ id, scale }` | 拖副图分隔线后落盘 |
| `subOrder` | `IndicatorID[]` | 长按副图换序后落盘 |
| `status` | `{ loading, error, bars }` | 首屏加载 / 取不到数据 |
| `tap` / `notice` / `interaction` | | 单击图、图上轻提示、手指按下 / 抬起 |

## 行为要点

- 默认开关照手机 `Prefs.chartOptions`：网格随皮肤（经典不画、青苔 / 陶土画淡网格）、本根倒计时常开、十字线读数写在头部、双击翻转主 / 副轴、图例折行让位。
- 颜色来自 `<html>` 上的 CSS 变量；`data-skin` / `data-theme` / `data-updown` 或系统深浅一变就重读。
- 数据：首屏一页 1500 根（量是币量、主动买是 takerBuyBaseVolume，与手机同口径）；贴左缘向左翻页；推送来的根先推视野再原地 upsert；回前台、推送重连、推送跳根时拉最新一页补缺口；最近 8 个品种 × 周期留快照，换回来立刻有图。
- 副图：分隔线上下 8 pt 竖拖改高度（倍率随人）；副图里长按 350 ms 拖动换序（抢在十字线 400 ms 之前）。
- 时区固定上海（UTC+8）。

## 开发

- 实验台：`npm run dev` 后打开 `/web/m/lab.html?skin=sage&theme=dark&subs=VOL,OI,MACD&of=1&cross=0.6`（仅开发，不进产物）。
- 测试：`tests/m-chart-*.test.ts`、`tests/m-indicator*.test.ts`（移植自 Swift 的数值用例）。
