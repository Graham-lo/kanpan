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
  sort: { key: DrawerKey; dir: 1 | -1 }
  /** 第一次打开订单流时把小部件、梯子、抽屉摆出来，之后尊重用户的开合 */
  seeded: boolean
  /** 梯子：深度 / 变化（本机） */
  ladderMode: 'depth' | 'delta'
  /** 变化模式的窗口 */
  deltaWin: DeltaWin
  /** 「24 小时流动性」「24 小时成交」两块是 2026-09-29 后加的：已经开过订单流的也摆一次 */
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
  /** 大额成交的金额线（门槛 ÷ 5），图上打点的大小以它为 1 */
  bigTrade: 0,
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

/** 四种产品四个色相，买卖再各偏 ±12°（设计稿 2.3）。 */
export const PRODUCT_HEX: Record<Product, string> = { spot: '#06B6D4', usdtPerp: '#8B5CF6', coinPerp: '#F59E0B', delivery: '#EC4899' }
const cache = new Map<string, [number, number, number]>()
function hexToHsl(hex: string): [number, number, number] {
  const n = parseInt(hex.slice(1, 7), 16)
  const r = (n >> 16 & 255) / 255, g = (n >> 8 & 255) / 255, b = (n & 255) / 255
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2
  if (mx === mn) return [0, 0, l]
  const d = mx - mn, s = l > .5 ? d / (2 - mx - mn) : d / (mx + mn)
  const h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4
  return [h * 60, s, l]
}
/** dark = 深色皮肤：同一色相提亮、降一点饱和，免得在深底上发刺（浓淡另由 bands.ts 按皮肤定） */
export function bandColor(p: Product, side: 'bid' | 'ask', a: number, dark = false): string {
  const k = p + side
  let hsl = cache.get(k)
  if (!hsl) { const [h, s, l] = hexToHsl(PRODUCT_HEX[p]); hsl = [(h + (side === 'bid' ? -12 : 12) + 360) % 360, s, l]; cache.set(k, hsl) }
  const sat = dark ? hsl[1] * 0.78 : hsl[1], lig = dark ? Math.min(0.74, hsl[2] + 0.14) : hsl[2]
  return `hsla(${hsl[0].toFixed(0)},${(sat * 100).toFixed(0)}%,${(lig * 100).toFixed(0)}%,${a})`
}
/** 标签上的字：浅色皮肤压暗一点过对比度，深色皮肤提亮 */
export function bandInk(p: Product, side: 'bid' | 'ask', dark = false): string {
  bandColor(p, side, 1)
  const hsl = cache.get(p + side)!
  const lig = dark ? 0.8 : Math.max(0.3, hsl[2] - 0.14)
  return `hsl(${hsl[0].toFixed(0)},${(hsl[1] * (dark ? 0.7 : 0.9) * 100).toFixed(0)}%,${(lig * 100).toFixed(0)}%)`
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

/** 金额：K / M / B / T，一位小数（≥ 100 取整）。 */
export function amt(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return '—'
  const a = Math.abs(v)
  const [d, u] = a >= 1e12 ? [1e12, 'T'] : a >= 1e9 ? [1e9, 'B'] : a >= 1e6 ? [1e6, 'M'] : a >= 1e3 ? [1e3, 'K'] : [1, '']
  const x = v / d
  return (Math.abs(x) >= 100 || !u ? x.toFixed(0) : x.toFixed(1)) + u
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
