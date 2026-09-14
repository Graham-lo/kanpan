# 原型

`看盘原型.html` 是单文件版：内嵌 2026-09-14 的币安合约真实快照（BTC / ETH / SOL × 1m 5m 15m 1h 4h 1d，加 OI、exchangeInfo、24h 行情），断网就能打开。桌面浏览器打开会套一个手机机身并给出「机型 / 外观 / 风格」三排按钮；窗口宽度 ≤ 560px（或真手机）时机身消失，直接全屏。

## 运行

- 直接双击 `看盘原型.html`；或
- 改源码后：`cd src && python3 -m http.server 8000`，浏览器开 `http://localhost:8000/`；改完用 `python3 ../tools/bundle.py` 重新打成单文件（脚本按自身位置找 `src/`，在哪儿跑都行）。
- `tools/fetch.sh` 重新从币安抓一份快照生成 `data.js`（需要能直连 fapi.binance.com）。

## 文件 → 任务书章节

| 文件 | 内容 | 对应任务书 |
|---|---|---|
| `src/chart.js` | 图表引擎：`BarSeries`、视野 `{from,to}`、`clamp`、`layout`、`candleWidths`、`niceStep`、`TIME_STEPS`、惯性 `flingAt`、捏合快照、十字线、价格模式（线性/对数/百分比）、指标绘制、画线 | §5 图表引擎、§7 手势、§8 指标 |
| `src/styles.js` | 11 款风格的几何表（实体占比、影线粗细、圆角、间距、上下留白、副图/时间轴高度）+ 靛配色浅深两版 hex | §6 风格表与配色 |
| `src/app.js` | 外壳：顶栏、周期条（14 档 + 常用 6 档）、品种页、指标面板、设置、画线工具条、横屏、本地存档 `kanpan.v3` | §9 界面、§10 交互与体验 |
| `src/style.css` | 布局与动效（面板升起、胶囊跳动、周期下划线滑动等） | §10.9 动效系统 |
| `src/index.html` | DOM 骨架 | §9 |
| `src/data.js` | 快照数据（只是原型用，app 不内嵌数据） | §4 数据层的字段参考 |

## 和 Swift 的对应关系

任务书里 `KanpanCore` 的类型名、函数名尽量和 `chart.js` 同名（`BarSeries`、`clamp`、`layout`、`candleWidths`、`niceStep`、`flingAt`……），移植时逐函数对照。指标数学以 `chart.js` 的实现为准，Swift 单测用 `src/data.js` 里的同一份快照做 fixture，结果差 ≤ 1e-9。
