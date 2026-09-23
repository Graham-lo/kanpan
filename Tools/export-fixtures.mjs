#!/usr/bin/env node
/* 从定版原型导出黄金值 fixture，供 KanpanCore 单测比对。
 *
 * 原型是规格：这里不重新实现任何算法，只把 prototype/src/ 里的 chart.js
 * 原样跑一遍，把输出写成 JSON。NaN 写成 null。
 *
 *   node Tools/export-fixtures.mjs
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const src = path.join(root, 'prototype', 'src')
const out = path.join(root, 'KanpanCore', 'Tests', 'KanpanCoreTests', 'Fixtures')
fs.mkdirSync(out, { recursive: true })

// ---------------------------------------------------------------- 载入原型
const win = {}
function run(file, transform) {
  let code = fs.readFileSync(path.join(src, file), 'utf8')
  if (transform) code = transform(code)
  new Function('window', 'global', code)(win, win)
}
run('data.js')
run('styles.js')
// chart.js 把大部分函数留在 IIFE 内部，这里在它导出那一行之前把内部函数也挂出来。
run('chart.js', (code) =>
  code.replace(
    '  global.Kanpan = {',
    '  global.KanpanInternal = { niceStep, timeStep, fmtTick, parts, tzOffsetMin, smaSkip, distSeg, MIN_BAR_SPACING, MAX_BAR_SPACING, TIME_STEPS }\n  global.Kanpan = {'
  ))

const K = win.Kanpan
const I = win.KanpanInternal
const D = win.KANPAN_DATA

const num = (x) => (Number.isFinite(x) ? x : null)
const arr = (a) => a.map(num)
const write = (name, obj) => {
  fs.writeFileSync(path.join(out, name), JSON.stringify(obj))
  console.log(name, (fs.statSync(path.join(out, name)).size / 1024).toFixed(1) + ' KB')
}

// ---------------------------------------------------------------- 指标黄金值
const SYMBOLS = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT']
const INTERVALS = ['1m', '15m', '1h', '4h', '1d']
const P = {
  MA: [7, 25, 99], EMA: [12, 26], BOLL: [20, 2], VOL: [5, 10],
  MACD: [12, 26, 9], RSI: [6, 12, 24], KDJ: [9, 3, 3], SRSI: [14, 14, 3, 3], ATR: [14],
}
const golden = { params: P, cases: [] }
for (const sym of SYMBOLS) {
  for (const iv of INTERVALS) {
    const b = D.series[sym + '|' + iv]
    if (!b) { console.warn('缺快照', sym, iv); continue }
    golden.cases.push({
      symbol: sym, interval: iv, t0: b.t0, step: b.step, p: b.p,
      open: b.o, high: b.h, low: b.l, close: b.c, volume: b.v,
      ma: P.MA.map((n) => arr(K.sma(b.c, n))),
      ema: P.EMA.map((n) => arr(K.ema(b.c, n))),
      boll: (() => { const r = K.boll(b.c, P.BOLL[0], P.BOLL[1]); return { mid: arr(r.mid), up: arr(r.up), dn: arr(r.dn) } })(),
      vol: P.VOL.map((n) => arr(K.sma(b.v, n))),
      macd: (() => { const r = K.macd(b.c, ...P.MACD); return { dif: arr(r.dif), dea: arr(r.dea), hist: arr(r.hist) } })(),
      rsi: P.RSI.map((n) => arr(K.rsi(b.c, n))),
      kdj: (() => { const r = K.kdj(b.h, b.l, b.c, ...P.KDJ); return { k: arr(r.K), d: arr(r.D), j: arr(r.J) } })(),
      srsi: (() => { const r = K.stochRsi(b.c, ...P.SRSI); return { k: arr(r.K), d: arr(r.D) } })(),
      atr: arr(K.atr(b.h, b.l, b.c, P.ATR[0])),
    })
  }
}
write('indicators.json', golden)

// ---------------------------------------------------------------- 根宽
// A1.3：dpr ∈ {1,2,3}，spacing 0.4→40 步进 0.1，11 款风格各自的 bodyR。
const widths = { rows: [] }
for (const st of win.KanpanStyles) {
  for (const dpr of [1, 2, 3]) {
    const body = [], wick = []
    for (let s = 4; s <= 400; s++) {
      const r = K.candleWidths(s / 10, dpr, true, st.geom.bodyR)
      body.push(r.body); wick.push(r.wick)
    }
    widths.rows.push({ style: st.id, bodyR: st.geom.bodyR, dpr, from: 0.4, to: 40, stepBy: 0.1, body, wick })
  }
}
write('candle-widths.json', widths)

// ---------------------------------------------------------------- 惯性
const fling = { tau: 325, maxMs: 1400, samples: [] }
for (const v of [-3, -1.4, -0.6, -0.2, 0.2, 0.35, 0.9, 1.7, 3]) {
  const row = { speed: v, points: [] }
  for (let i = 0; i <= 100; i++) {
    const t = (i / 100) * 1600
    const r = K.flingAt(v, t, 325)
    row.points.push([t, r.pastPx, r.done ? 1 : 0])
  }
  fling.samples.push(row)
}
write('fling.json', fling)

// ---------------------------------------------------------------- 刻度
const ticks = { nice: [], time: [] }
let seed = 12345
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff }
for (let i = 0; i < 200; i++) {
  const span = Math.pow(10, rnd() * 9 - 4) * (1 + rnd() * 9)
  const want = 2 + Math.floor(rnd() * 14)
  ticks.nice.push([span, want, I.niceStep(span, want)])
}
for (let i = 0; i < 200; i++) {
  const spanMs = Math.pow(10, 5 + rnd() * 5.5)
  const plotW = 120 + Math.floor(rnd() * 800)
  ticks.time.push([spanMs, plotW, 74, I.timeStep(spanMs, plotW, 74)])
}
// 时间轴标签：日内 / 跨日 / 跨年 × 三个时区
ticks.labels = []
for (const tz of ['local', 'utc', 'exchange']) {
  const off = I.tzOffsetMin(tz)
  for (const [ms, step] of [
    [1789300800000, 60e3], [1789300800000, 3600e3], [1789344000000, 3600e3],
    [1789300800000, 86400e3], [1789300800000, 180 * 86400e3], [1789300800000, 365 * 86400e3],
  ]) ticks.labels.push({ tz, off, ms, step, tick: I.fmtTick(ms, step, off), full: K.fmtFull(ms, off) })
}
ticks.timeSteps = I.TIME_STEPS
write('ticks.json', ticks)

// ---------------------------------------------------------------- 数字格式
// fmtVol 不再从原型导黄金值：2026-09-18 用户把成交额单位定为千进制 K/M/B/T，
// 原型的万/亿口径已作废，期望值改写在 FormatTests 里。
const fmt = { num: [] }
for (const [x, p] of [[76800, 2], [0.0001234, 8], [1.5, 1], [123456.789, 3], [-12.345, 2], [0, 0]])
  fmt.num.push([x, p, K.fmtNum(x, p)])
write('format.json', fmt)

// ---------------------------------------------------------------- 风格表与配色
// styles.json 不再从原型重导：它的明暗两套涨跌色、图区底色与网格已改成 AICoin 手机端实测值
// （真源是 KanpanCore/Style/Palette.swift），原型 styles.js 还停在旧色，重导会把黄金值打回去。
// 那份文件现在手工维护，改配色时跟着 Palette.swift 一起改。
console.log('styles.json 跳过（手工维护，真源是 Palette.swift）')

// ---------------------------------------------------------------- 画线命中
const seg = []
for (let i = 0; i < 120; i++) {
  const a = [rnd() * 300, rnd() * 300], b = [rnd() * 300, rnd() * 300], p = [rnd() * 300, rnd() * 300]
  seg.push([p[0], p[1], a[0], a[1], b[0], b[1], I.distSeg(p[0], p[1], a[0], a[1], b[0], b[1])])
}
write('distseg.json', { cases: seg })

console.log('fixtures →', out)
