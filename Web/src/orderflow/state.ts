/* Hkline Web · 主力订单流 · 共享状态、网页本机偏好、配色与浮层卡片
 *
 * 各展示模块（图上层、梯子、小部件、抽屉）只读这里的状态，控制器（index.ts）负责写。
 * 网页本机偏好（六个显示开关、热力开关、成交带下限、小部件折叠……）存 localStorage，不随账号同步；
 * 门槛与步长走 st.orderFlowOverrides（同步）。
 */
import type { TVChart, ChartGeometry } from '../chart/chart'
import type { Alert } from '../app/store'
import type { BigOrder, Product } from './types'
import type { Snapshot } from './model'
import type { OrderFlowFeed } from './feed'
import type { FineBook } from './aggregate'
import type { HeatStore } from './heat'
import { Tape } from './tape'
import { TradeLadder } from './tradeLadder'
import { DeltaSource, type DeltaWin } from './depthDelta'
import { LiqSource, VolSource, TpsMeter } from './stats'
import { DISPLAY_ALL, type Display } from './settings'
import { mergeFactor, intervalMultiplier } from './bucket'
import { clamp, sh, pad, fmt } from '../util/format'

/** 图表页交给订单流模块的几个口子（避免反过来 import 图表页）。 */
export interface Api {
  activeChart(): { chart: TVChart; symbol: string; iv: string; host: HTMLElement } | null
  charts(): { chart: TVChart; symbol: string; iv: string }[]
  openAlert(price?: number): void
  addHline(price: number): void
  alertsFor(symbol: string): Alert[]
  alertDesc(a: Alert): string
  deleteAlert(id: string): void
  renderPanel(): void
  layoutSlots(): void
  renderToolbar(): void
  dec(symbol: string): number
  crypto(symbol: string): boolean
  turnover(symbol: string): number | null
}

export type BookUnit = 'usd' | 'coin'
export type DrawerKey = 'first' | 'end' | 'age' | 'side' | 'exchange' | 'product' | 'price' | 'peak' | 'filled' | 'outcome'

export interface Prefs {
  display: Display
  heat: boolean
  /** base → 成交带下限（美元）；没设的用门槛 ÷ 50 */
  tapeMin: Record<string, number>
  collapsed: string[]
  bookUnit: BookUnit
  band: number
  /** 旧抽屉（逐单表格）的排序；2026-10-08 抽屉改成汇总后不再读，留着字段免得老档解析出错 */
  sort: { key: DrawerKey; dir: 1 | -1 }
  /** 2026-10-08 起不再读：原来第一次打开「图上订单流」时把梯子、抽屉、小部件一起摆出来，
   *  现在四个开关（图上订单流 / 深度梯子 / 大单列表 / 深度热力）各管各的，谁也不替谁打开。字段留着兼容老档 */
  seeded: boolean
  /** 梯子：深度 / 变化（本机） */
  ladderMode: 'depth' | 'delta'
  /** 变化模式的窗口 */
  deltaWin: DeltaWin
  /** 2026-10-08 起不再读（同 seeded） */
  seededStats: boolean
}

const PREFS_KEY = 'hkline-web-of-v1'
function defaults(): Prefs {
  return { display: { ...DISPLAY_ALL }, heat: false, tapeMin: {}, collapsed: [], bookUnit: 'usd', band: 1, sort: { key: 'first', dir: -1 }, seeded: false, ladderMode: 'depth', deltaWin: '1h', seededStats: false }
}
function loadPrefs(): Prefs {
  const d = defaults()
  try {
    const raw = JSON.parse(localStorage.getItem(PREFS_KEY) || '{}') as Partial<Prefs>
    const p = { ...d, ...raw }
    p.display = { ...DISPLAY_ALL, ...(raw.display || {}) }
    if (typeof p.heat !== 'boolean') p.heat = false
    if (!p.tapeMin || typeof p.tapeMin !== 'object') p.tapeMin = {}
    if (!Array.isArray(p.collapsed)) p.collapsed = []
    if (p.bookUnit !== 'coin') p.bookUnit = 'usd'
    if (![1, 2, 5].includes(p.band)) p.band = 1
    if (!p.sort || typeof p.sort.key !== 'string') p.sort = d.sort
    if (p.ladderMode !== 'delta') p.ladderMode = 'depth'
    if (p.deltaWin !== '1d') p.deltaWin = '1h'
    if (typeof p.seededStats !== 'boolean') p.seededStats = false
    return p
  } catch { return d }
}
export function savePrefs(): void { try { localStorage.setItem(PREFS_KEY, JSON.stringify(OF.prefs)) } catch { /* 隐私模式存不了就只在本页生效 */ } }

export const OF = {
  api: null as Api | null,
  feed: null as OrderFlowFeed | null,
  /** 想接盘口、在等品种停稳（约半秒）：空态写「正在接盘口…」 */
  pending: false,
  snap: null as Snapshot | null,
  fine: null as FineBook | null,
  heat: null as HeatStore | null,
  tape: new Tape(),
  /** 梯子中列：从打开这只品种起的主动买 / 主动卖（按细桶） */
  trades: new TradeLadder(),
  /** 梯子「变化」模式的数据（实时环 + 服务端快照） */
  delta: new DeltaSource(),
  /** 侧栏「24 小时流动性」「24 小时成交」、详情里的每秒成交 */
  liq: new LiqSource(),
  vol: new VolSource(),
  tps: new TpsMeter(),
  peaks: new Map<string, number>(),
  prefs: loadPrefs(),
  /** 当前活动格子最近一次重绘时的坐标映射（梯子对齐用） */
  geo: null as ChartGeometry | null,
  /** 活动格子的周期字符串 */
  iv: '1h',
  /** 抽屉里高亮的一单 */
  highlight: null as string | null,
  /** 梯子悬停的行（图上跟着描一条细带） */
  hoverRow: null as { low: number; high: number } | null,
  version: 0,
  /** 图上点了一条大单带：抽屉滚到那一行 */
  reveal: null as null | ((id: string) => void),
  /** 大单成交带 / 大单列表里点了一行：图挪过去 */
  focus: null as null | ((o: BigOrder) => void),
  /** 活动格子画完一帧（梯子跟着重画，保证与价格轴对齐） */
  onChartDrawn: null as null | ((chart: TVChart, g: ChartGeometry) => void),
  /** 大额成交的金额线（门槛 ÷ 5），图上气泡两级金额线的绝对下限 */
  bigTrade: 0,
  /** 图上气泡点了 / 抽屉里点了一行：那一根的泡亮 1.5 秒（symbol 大写、t = 那根的开盘时间） */
  barHi: null as null | { symbol: string; t: number; until: number },
  /** 图上点了一枚气泡：抽屉开着就滚到那一根并高亮，没开就打开 */
  revealBar: null as null | ((symbol: string, t: number) => void),
  /** 活动格子十字线所在那根的开盘时间（抽屉按根表同步高亮，drawer.ts 跟着指针移动读出来）；不在图上为 null */
  crossT: null as number | null,
  /** 抽屉「每根」里点选的那一根（再点一次取消；换品种 / 周期清掉）：活动格子在那根上铺一道强调色竖带 */
  selBar: null as null | { symbol: string; iv: number; t: number },
}

/** 数据层还没起来时各处空态的那句话：在等品种停稳就是「正在接」，否则是没打开 */
export const feedIdleText = (off = '打开指标「主力订单流」后显示'): string => OF.pending ? '正在接盘口…' : off

// ------------------------------------------------------------------ 行高

/** 细桶 → 行的倍数 k = 周期倍数 × 合并倍数（行高不到 6 px 就 2 / 5 / 10 倍地并）。 */
export function rowsPerLine(g: ChartGeometry, step: number, iv: string): number {
  const mult = intervalMultiplier(iv)
  const ref = g.last ?? (g.range.min + g.range.max) / 2
  const px = Math.abs(g.priceToY(ref) - g.priceToY(ref + step * mult))
  return mult * mergeFactor(px)
}

// ------------------------------------------------------------------ 配色

/** 品类分类色（docs/design/电脑网页UI规范-2026-10-08.md §2）：同明度、同饱和度的 OKLCH，只上小记号
 *  （带左缘细条、圆点、图例），不铺大面积。买卖方向不靠它分，靠 bandColor 的涨跌色。 */
export const PRODUCT_HUE: Record<Product, number> = { spot: 190, usdtPerp: 280, coinPerp: 88, delivery: 330 }
export function productColor(p: Product, dark = false): string {
  return dark ? `oklch(0.76 0.10 ${PRODUCT_HUE[p]})` : `oklch(0.60 0.12 ${PRODUCT_HUE[p]})`
}
/** 涨跌色从页面变量取（跟着皮肤、深浅色与「红涨 / 绿涨」走）；三个开关不变就不重读样式 */
let dirKey = ''
let dir = { up: [8, 153, 129], down: [242, 54, 69], upText: '#04705E', downText: '#BC2434', surface: '#F8F9FA' } as { up: number[]; down: number[]; upText: string; downText: string; surface: string }
function dirColors(): typeof dir {
  if (typeof document === 'undefined') return dir
  const r = document.documentElement, k = `${r.dataset.theme}|${r.dataset.skin}|${r.dataset.updown}`
  if (k === dirKey) return dir
  const cs = getComputedStyle(r), v = (n: string) => cs.getPropertyValue(n).trim()
  const up = v('--up'), down = v('--down')
  if (up && down) dir = { up: rgbOf(up), down: rgbOf(down), upText: v('--up-text') || up, downText: v('--down-text') || down, surface: v('--surface') || dir.surface }
  dirKey = k
  return dir
}
/** 大单带的颜色：挂买 = 涨色、挂卖 = 跌色（规范 §2 订单流）。p、dark 留着给调用方不改签名，深浅由透明度定 */
export function bandColor(_p: Product, side: 'bid' | 'ask', a: number, _dark = false): string {
  const [r, g, b] = side === 'bid' ? dirColors().up : dirColors().down
  return `rgba(${r},${g},${b},${a})`
}
/** 卡片底色：半透明方向底下面先垫它，别让底下的字透出来 */
export function surfaceColor(): string { return dirColors().surface }
/** 带上的字：涨跌文字色（面板与卡片上都 ≥ 4.5:1） */
export function bandInk(_p: Product, side: 'bid' | 'ask', _dark = false): string {
  return side === 'bid' ? dirColors().upText : dirColors().downText
}
/** 底色是不是深色（相对亮度 < 0.35） */
export function isDarkBg(bg: string): boolean {
  const [r, g, b] = rgbOf(bg)
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 < 0.35
}
/** #RRGGBB → [r,g,b] */
export function rgbOf(hex: string): [number, number, number] {
  if (hex.startsWith('rgb')) { const m = hex.match(/[\d.]+/g) || ['0', '0', '0']; return [+m[0], +m[1], +m[2]] }
  const h = hex.length === 4 ? hex.slice(1).split('').map(c => c + c).join('') : hex.slice(1, 7)
  const n = parseInt(h, 16)
  return [n >> 16 & 255, n >> 8 & 255, n & 255]
}

// ------------------------------------------------------------------ 浮层卡片

let tipEl: HTMLElement | null = null
export function showCard(html: string, x: number, y: number): void {
  if (!tipEl) { tipEl = document.createElement('div'); tipEl.className = 'of-card'; tipEl.setAttribute('role', 'tooltip'); document.body.appendChild(tipEl) }
  if (tipEl.dataset.html !== html) { tipEl.innerHTML = html; tipEl.dataset.html = html }
  tipEl.classList.add('show')
  const w = tipEl.offsetWidth, h = tipEl.offsetHeight
  const left = x + 16 + w > innerWidth - 8 ? x - 16 - w : x + 16
  const top = clamp(y - h / 2, 8, innerHeight - h - 8)
  tipEl.style.transform = `translate(${Math.round(left)}px,${Math.round(top)}px)`
}
export function hideCard(): void { tipEl?.classList.remove('show') }

// ------------------------------------------------------------------ 大单的一些展示量

export function peak(o: BigOrder, id: string): number {
  const p = Math.max(o.initialNotional, o.notional, OF.peaks.get(id) ?? 0)
  OF.peaks.set(id, p)
  return p
}

// ------------------------------------------------------------------ 文字

/** 金额：K / M / B / T，一位小数（≥ 100 取整）。单位按舍入之后的样子挑：999,999 是「1.0M」不是「1000K」，
 *  999.6 是「1.0K」不是「1000」（与 util/format.ts fmtCompact、手机网页 volUnit 同一口径） */
const AMT_UNITS: readonly [number, string][] = [[1, ''], [1e3, 'K'], [1e6, 'M'], [1e9, 'B'], [1e12, 'T']]
export function amt(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return '—'
  const a = Math.abs(v)
  let i = AMT_UNITS.length - 1
  while (i > 0 && a < AMT_UNITS[i][0]) i--
  for (; i < AMT_UNITS.length; i++) {
    const [d, u] = AMT_UNITS[i], x = v / d
    const t = Math.abs(x) >= 100 || !u ? x.toFixed(0) : x.toFixed(1)
    if (Math.abs(+t) < 1000 || i === AMT_UNITS.length - 1) return (+t === 0 ? t.replace('-', '') : t) + u
  }
  return '—'
}
/** 上海时间 时:分:秒 */
export function hms(t: number): string { const d = sh(t); return `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}` }
/** 上海时间 时:分 */
export function hm(t: number): string { const d = sh(t); return `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}` }
/** 上海时间 月-日 时:分 */
export function mdhm(t: number): string { const d = sh(t); return `${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}` }
/** 时长的短写：45秒 / 12分钟 / 3.5小时 / 2天 */
export function durShort(ms: number): string {
  const s = Math.max(0, ms) / 1000
  if (s < 60) return `${Math.round(s)}秒`
  const m = s / 60; if (m < 60) return `${Math.round(m)}分钟`
  const h = m / 60; if (h < 48) return `${+h.toFixed(1)}小时`
  return `${+(h / 24).toFixed(1)}天`
}
export const PRODUCT_FULL: Record<Product, string> = { spot: '现货', usdtPerp: 'U 本位永续', coinPerp: '币本位永续', delivery: '交割' }
/** 价格按步长需要的小数位（至少 dec 位）。 */
export function decFor(step: number, dec: number): number {
  if (!(step > 0)) return dec
  const s = step.toFixed(10).replace(/0+$/, '')
  const i = s.indexOf('.')
  return Math.max(dec, i < 0 ? 0 : s.length - i - 1)
}
/** 同 fmt（缓存的格式器，梯子每 100 毫秒重画几十行，别每格新建一个 Intl.NumberFormat）；非有限数照旧原样转 */
export function px(v: number, dec: number): string {
  return isFinite(v) ? fmt(v, dec) : v.toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec })
}

let family = ''
/** 画布用的字体（跟页面同一套，取一次） */
export function canvasFont(size: number, weight = 400): string {
  if (!family) family = getComputedStyle(document.body).fontFamily || 'system-ui'
  return `${weight} ${size}px ${family}`
}
