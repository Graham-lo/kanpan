#!/usr/bin/env node
/* 从定版原型导出绘制层取证要用的三份 fixture（M3 / A3.1–A3.4）。
 *
 * 和 `export-fixtures.mjs` 一个规矩：这里不重新实现任何算法。原型的 `Chart` 类
 * 原样跑，只给它套一层最小的 DOM 壳（canvas / ResizeObserver / rAF 全是空壳），
 * 然后问它 `layout()` / `barSpacing()` / `priceRange()` 要数——几何口径永远是原型的。
 *
 *   node Tools/export-chart-fixtures.mjs
 *
 * 产物（`KanpanChart/Tests/KanpanChartTests/Fixtures/`）：
 *   snapshot.json   BTCUSDT 1h 定版快照 + OI + 品种元信息（取证一律用它，不碰网络）
 *   geometry.json   A3.2 的 7 项几何 × 11 款风格（iPhone 16 Pro / 浅色 / @3x）
 *   colors.json     A3.3 的 7 个取色点 × 11 款风格 × 明暗两套的定版色值
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const src = path.join(root, 'prototype', 'src')
const out = path.join(root, 'KanpanChart', 'Tests', 'KanpanChartTests', 'Fixtures')
fs.mkdirSync(out, { recursive: true })

// ---------------------------------------------------------------- 最小 DOM 壳
//
// 原型的 Chart 构造函数要建两张 canvas、绑指针事件、挂 ResizeObserver、起 rAF。
// 取证只问几何，一笔都不画，所以这些全给空实现即可——关键是别去改原型代码。

function fakeCanvas() {
  return {
    width: 0, height: 0, className: '',
    clientWidth: 0, clientHeight: 0,
    style: {},
    addEventListener() {},
    removeEventListener() {},
    setPointerCapture() {},
    releasePointerCapture() {},
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 0, height: 0 }),
    getContext: () => ({
      setTransform() {}, save() {}, restore() {}, beginPath() {}, closePath() {},
      moveTo() {}, lineTo() {}, arcTo() {}, arc() {}, rect() {}, clip() {},
      fill() {}, stroke() {}, fillRect() {}, strokeRect() {}, clearRect() {},
      fillText() {}, setLineDash() {}, createLinearGradient: () => ({ addColorStop() {} }),
      measureText: (s) => ({ width: String(s).length * 6 }),
    }),
  }
}

function fakeRoot(w, h) {
  return {
    clientWidth: w, clientHeight: h,
    appendChild() {},
    getBoundingClientRect: () => ({ left: 0, top: 0, width: w, height: h }),
  }
}

// ---------------------------------------------------------------- 载入原型
const win = {
  devicePixelRatio: 3,
  document: { createElement: () => fakeCanvas() },
  ResizeObserver: class { observe() {} disconnect() {} },
  requestAnimationFrame: () => 0,
  addEventListener() {},
}
function run(file, transform) {
  let code = fs.readFileSync(path.join(src, file), 'utf8')
  if (transform) code = transform(code)
  new Function('window', 'global', 'document', 'ResizeObserver', 'requestAnimationFrame', code)(
    win, win, win.document, win.ResizeObserver, win.requestAnimationFrame)
}
run('data.js')
run('styles.js')
run('chart.js')

const K = win.Kanpan
const D = win.KANPAN_DATA
const STYLES = win.KanpanStyles
const PAL = win.KanpanPalette

const write = (name, obj) => {
  fs.writeFileSync(path.join(out, name), JSON.stringify(obj, null, name === 'snapshot.json' ? 0 : 2))
  console.log(name, (fs.statSync(path.join(out, name)).size / 1024).toFixed(1) + ' KB')
}

// ---------------------------------------------------------------- 取证用的固定条件
//
// 取证一律 BTCUSDT 1h：1000 根、@3x、两个副图（MACD + RSI）、主图叠 MA。
// 这几项一改，176 张基线和 77 个几何数就全变了，所以写死在这儿。
const SYMBOL = 'BTCUSDT'
const INTERVAL = '1h'
const BARS = D.series[SYMBOL + '|' + INTERVAL]
const OI = D.series['OI|' + SYMBOL + '|' + INTERVAL]
const CAT = D.catalog.find((r) => r[0] === SYMBOL)
const OVERLAYS = ['MA']
const SUBS = ['MACD', 'RSI']
// A3.2 指定的量化机型：iPhone 16 Pro，浅色，@3x。
const GEOM_W = 402, GEOM_H = 874, GEOM_DPR = 3

// ---------------------------------------------------------------- ① 定版快照
write('snapshot.json', {
  note: '定版快照，取自 prototype/src/data.js（' + D.takenAt + '）。取证不碰网络。',
  symbol: SYMBOL, interval: INTERVAL,
  t0: BARS.t0, step: BARS.step, p: BARS.p,
  open: BARS.o, high: BARS.h, low: BARS.l, close: BARS.c, volume: BARS.v,
  oi: { t0: OI.t0, step: OI.step, values: OI.v },
  meta: { base: CAT[1], quote: CAT[2], pricePrecision: CAT[3], tickSize: Number(CAT[4]) },
  quote: D.quote[SYMBOL] || null,
})

// 原型里图表主题 = `expand(t).chart` 再由 app.js 的 `applyColors()` 压上涨跌色
// （`T.green` / `T.red`，redUp 时对调）和两个成交量柱的派生色。照抄这一步，
// 否则 `theme.up` 是 undefined。
function chartTheme(dark, redUp = false) {
  const T = dark ? PAL.D : PAL.L
  const theme = JSON.parse(JSON.stringify(T.chart))
  theme.up = redUp ? T.red : T.green
  theme.down = redUp ? T.green : T.red
  theme.volUp = theme.up + '66'
  theme.volDn = theme.down + '66'
  return theme
}

// ---------------------------------------------------------------- 造一个原型实例
function makeChart(style, dark, { w = GEOM_W, h = GEOM_H, dpr = GEOM_DPR, subs = SUBS } = {}) {
  win.devicePixelRatio = dpr
  const theme = chartTheme(dark)
  const c = new K.Chart(fakeRoot(w, h), { theme, style: JSON.parse(JSON.stringify(style.geom)) })
  c.subs = subs.slice()
  c.overlays = OVERLAYS.slice()
  c.mobile = true
  c.setSeries(BARS, OI, { key: SYMBOL + '|' + INTERVAL, p: BARS.p })
  return c
}

// ---------------------------------------------------------------- ② 7 项几何 × 11 款
//
// 口径（全部按 A3.2 那一行的顺序）：
//   axisW  右轴宽      = L.W - L.plotW
//   timeH  时间轴高    = L.H - L.timeY
//   subH   副图高      = L.subH（注意会被 (H - timeH) * 0.3 压住，不一定等于风格表的值）
//   spacing 根间距     = chart.barSpacing()，视野按 resetView()
//   bodyW  实体宽      = candleWidths(...).body / dpr
//   wickW  影线宽      = max(0.5, style.wick) / dpr
//   padTop 上留白比例  = (yOf(可见最高价) - pane.y) / pane.h
// 单位一律 pt；比对时乘 dpr 换成设备像素，容差 ±1。
const geometry = {
  note: 'A3.2：7 项几何 × 11 款风格，原型 chart.js 直接算出来的黄金值。',
  device: 'iPhone 16 Pro', width: GEOM_W, height: GEOM_H, scale: GEOM_DPR,
  theme: 'light', symbol: SYMBOL, interval: INTERVAL,
  overlays: OVERLAYS, subs: SUBS,
  metrics: ['axisW', 'timeH', 'subH', 'spacing', 'bodyW', 'wickW', 'padTop'],
  styles: {},
}
for (const s of STYLES) {
  const c = makeChart(s, false)
  const L = c.layout()
  const pane = L.panes[0]
  const r = c.priceRange()
  const spacing = c.barSpacing()
  const w = K.candleWidths(spacing, GEOM_DPR, true, s.geom.bodyR)
  // 可见区间的最高价：和 priceRange 的入口同一口径（K 线 high 并入 MA）
  const { lo, hi } = c.visible()
  let hiP = -Infinity
  for (let i = lo; i <= hi; i++) if (BARS.h[i] > hiP) hiP = BARS.h[i]
  const v = c.calc()
  for (const a of v.MA) for (let i = lo; i <= hi; i++) if (Number.isFinite(a[i]) && a[i] > hiP) hiP = a[i]
  geometry.styles[s.id] = {
    axisW: L.W - L.plotW,
    timeH: L.H - L.timeY,
    subH: L.subH,
    spacing,
    bodyW: w.body / GEOM_DPR,
    wickW: Math.max(0.5, s.geom.wick) / GEOM_DPR,
    padTop: (c.yOf(hiP, pane, r) - pane.y) / pane.h,
    // 参考值，比对时不判定，写出来方便人看
    view: { from: c.view.from, to: c.view.to },
    range: { lo: r.lo, hi: r.hi, base: r.base },
    visible: { lo, hi },
    mainH: L.mainH, plotW: L.plotW, thin: spacing < 1.3,
  }
}
write('geometry.json', geometry)

// ---------------------------------------------------------------- ③ 7 个取色点 × 11 款 × 明暗
//
// A3.3 的七个点：涨实体、跌实体、影线（tint 后）、网格、底色、最新价线、轴文字。
// 这里只导出**期望色值**——它们全部是 §6 配色表加风格表算出来的，和数据无关；
// 实际像素由 Swift 侧的 ColorSampleTests 在渲染结果上取。
const lastUp = BARS.c[BARS.c.length - 1] >= BARS.o[BARS.o.length - 1]
const colors = {
  note: 'A3.3：7 个取色点 × 11 款风格 × 明暗两套，原型 styles.js 的定版色值。',
  points: ['upBody', 'downBody', 'wick', 'grid', 'bg', 'lastLine', 'axisText'],
  lastBarUp: lastUp,
  themes: {},
}
for (const dark of [false, true]) {
  const t = chartTheme(dark)
  const per = {}
  for (const s of STYLES) {
    const g = s.geom
    const tint = (col) => (g.wickTint < 1 ? K.mixHex(t.bg, col, g.wickTint) : col)
    per[s.id] = {
      upBody: t.up,
      downBody: t.down,
      wick: tint(t.up),
      wickDown: tint(t.down),
      grid: t.grid,
      bg: t.bg,
      lastLine: lastUp ? t.up : t.down,
      axisText: t.dim,
      // 取样时要知道这几件事才知道该往哪儿找、能不能全覆盖
      gridMode: g.grid,
      shape: g.shape,
      wickDevicePx: Math.max(0.5, g.wick),
      outlineDevicePx: Math.max(1, Math.round(GEOM_DPR * 0.9)),
      lastDash: g.lastDash,
    }
  }
  colors.themes[dark ? 'dark' : 'light'] = per
}
// colors.json 不再从原型重导（2026-09-18 起）：它记的是出厂配色「青苔」的 Palette 定版值，
// 原型 styles.js 没有那批 AICoin 真机采样色，重导只会把它打回旧色。真源是
// KanpanCore/Style/Palette.swift，那份文件手工维护。上面的计算留着，只是不落盘。
void colors
console.log('colors.json 跳过（手工维护，真源是 Palette.swift）')

console.log('\n口径：' + SYMBOL + ' ' + INTERVAL + '，' + BARS.c.length + ' 根，'
  + GEOM_W + '×' + GEOM_H + ' @' + GEOM_DPR + 'x，叠加 ' + OVERLAYS.join('/')
  + '，副图 ' + SUBS.join('/'))
