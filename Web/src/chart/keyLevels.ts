/* Hkline Web · 主图「关键价位」
 *
 * 交易员每天开盘前在图上手画的那几条线，一个开关自动画好：
 *   昨高 / 昨低 / 今开（日），上周高 / 上周低（周）；
 *   昨控（昨天成交最集中的价位）、昨值上 / 昨值下（昨天七成成交落在的区间上下沿）——这三条是「裸」的：
 *   今天价格第一次回到那个价位时线就停在那根 K 线上（变淡、不再上价格轴），没回到之前一直画到右边。
 *
 * 口径：
 *   - 日界是上海 8:00（= UTC 0 点，币安日线的切换点），周界是上海周一 8:00（= 币安周线的切换点）；只用走完了的日 / 周。
 *   - 昨高 / 昨低 / 今开 / 上周高低 取币安 U 本位永续的日线（一次要 16 根，够盖住上一整周）。
 *   - 昨控与七成价值区用成交量分布（overlays.ts 的 vpvr，和主图「成交量分布」同一个算法）算昨天的 5 分钟 K 线：
 *     当前就是 5 分钟周期、而且已经加载的 K 线盖住了昨天整天就直接用，否则向币安要一次昨天那 288 根。
 *     所有周期看到的是同一组数（不随周期变）。
 *   - 1 天到 1 周以下的周期只画上周高低（日线级的线在日线上没意义），1 周及以上什么都不画。
 * 缓存：按品种、按 UTC 日记一份，一天只要一次；要失败了 60 秒后再试；要回来置脏重画，画的那一帧从不等它。
 *
 * 颜色是网页皮肤里的两级：--kl-day（日）与 --kl-week（周）。
 */
import type { Bar } from './calc'
import type { Pane, PriceRange, TVChart } from './chart'
import { vpvr } from './overlays'
import { klines } from '../market/rest'
import { fmtAxis, hexA } from '../util/format'

const DAY = 864e5
const WEEK = 7 * DAY
const RETRY_MS = 60_000
const VP_ROWS = 100
const KEEP = 12

export type KeyTier = 'day' | 'week'
export interface KeyLevel {
  key: string
  label: string
  price: number
  tier: KeyTier
  /** 线从哪个时间起（今天 0 点 UTC / 本周一 0 点 UTC） */
  from: number
  /** 裸线：今天第一次回到这个价位时停下 */
  naked: boolean
}

/** 今天（UTC 日）起点 */
export function dayStartOf(now: number): number { return Math.floor(now / DAY) * DAY }
/** 本周一 0 点 UTC（1970-01-01 是周四） */
export function weekStartOf(now: number): number {
  const d = Math.floor(now / DAY)
  return (d - (d + 3) % 7) * DAY
}

/** 日线 → 昨高、昨低、今开、上周高低（缺哪条就不出哪条） */
export function dailyLevels(daily: readonly Bar[], now: number): KeyLevel[] {
  const today = dayStartOf(now), week = weekStartOf(now), out: KeyLevel[] = []
  const y = daily.find(b => b.t === today - DAY)
  if (y) {
    out.push({ key: 'yh', label: '昨高', price: y.h, tier: 'day', from: today, naked: false })
    out.push({ key: 'yl', label: '昨低', price: y.l, tier: 'day', from: today, naked: false })
  }
  const t = daily.find(b => b.t === today)
  if (t) out.push({ key: 'to', label: '今开', price: t.o, tier: 'day', from: today, naked: false })
  const lw = daily.filter(b => b.t >= week - WEEK && b.t < week)
  if (lw.length) {
    out.push({ key: 'wh', label: '上周高', price: Math.max(...lw.map(b => b.h)), tier: 'week', from: week, naked: false })
    out.push({ key: 'wl', label: '上周低', price: Math.min(...lw.map(b => b.l)), tier: 'week', from: week, naked: false })
  }
  return out
}

/** 昨天的 5 分钟 K 线 → 昨控、昨值上、昨值下；昨天没盖住九成就不出 */
export function profileLevels(bars: readonly Bar[], now: number): KeyLevel[] {
  const today = dayStartOf(now), ys = today - DAY
  const day = bars.filter(b => b.t >= ys && b.t < today)
  if (day.length < 288 * 0.9) return []
  const v = vpvr(day as Bar[], 0, day.length - 1, VP_ROWS)
  if (!v || !v.total) return []
  return [
    { key: 'poc', label: '昨控', price: v.lo + (v.poc + 0.5) * v.step, tier: 'day', from: today, naked: true },
    { key: 'vah', label: '昨值上', price: v.lo + (v.vaHi + 1) * v.step, tier: 'day', from: today, naked: true },
    { key: 'val', label: '昨值下', price: v.lo + v.vaLo * v.step, tier: 'day', from: today, naked: true },
  ]
}

/** 裸线第一次被碰到的那根 K 线（l ≤ 价 ≤ h）；没碰到回 -1。只看 from 之后的 K 线 */
export function touchIndex(bars: readonly Bar[], price: number, from: number): number {
  let i = bars.length - 1
  while (i > 0 && bars[i - 1].t >= from) i--
  for (; i < bars.length; i++) { const b = bars[i]; if (b.t >= from && b.l <= price && price <= b.h) return i }
  return -1
}

/** 这个周期画哪些：1 天以下全画，1 天到 1 周以下只画周，1 周及以上不画 */
export function levelsForInterval(all: readonly KeyLevel[], iv: number): KeyLevel[] {
  if (iv >= WEEK) return []
  if (iv >= DAY) return all.filter(l => l.tier === 'week')
  return all.slice()
}

// ------------------------------------------------------------ 取数与缓存
interface Entry { day: number; daily: KeyLevel[] | null; prof: KeyLevel[] | null; busyD: boolean; busyP: boolean; failD: number; failP: number }
const cache = new Map<string, Entry>()
const waiting = new Set<TVChart>()

function wake(): void {
  for (const ch of waiting) if (!ch.dead) ch.dirty = true
  waiting.clear()
}

/** 这只品种今天的全部关键价位（没到齐的先不出，后台去要） */
export function keyLevelsOf(ch: TVChart, now = Date.now()): KeyLevel[] {
  const sym = ch.meta.symbol
  if (!sym) return []
  const today = dayStartOf(now)
  let e = cache.get(sym)
  if (!e || e.day !== today) {
    e = { day: today, daily: null, prof: null, busyD: false, busyP: false, failD: 0, failP: 0 }
    cache.delete(sym); cache.set(sym, e)
    while (cache.size > KEEP) { const k = cache.keys().next().value; if (k == null) break; cache.delete(k) }
  }
  const entry = e
  if (!entry.daily && !entry.busyD && now - entry.failD > RETRY_MS) {
    entry.busyD = true
    void klines(sym, '1d', undefined, 16, false).then(r => {
      entry.busyD = false
      if (r.ok && r.bars.length) { entry.daily = dailyLevels(r.bars, now); wake() } else entry.failD = Date.now()
    })
  }
  if (!entry.prof && ch.iv < DAY) {
    // 当前就是 5 分钟、已经盖住了昨天：不用再要
    if (ch.iv === 5 * 60e3) { const p = profileLevels(ch.bars, now); if (p.length) entry.prof = p }
    if (!entry.prof && !entry.busyP && now - entry.failP > RETRY_MS) {
      entry.busyP = true
      void klines(sym, '5m', today, 288, false).then(r => {
        entry.busyP = false
        const p = r.ok ? profileLevels(r.bars, now) : []
        if (p.length) { entry.prof = p; wake() } else entry.failP = Date.now()
      })
    }
  }
  if (!entry.daily || (!entry.prof && ch.iv < DAY)) waiting.add(ch)
  return [...(entry.daily || []), ...(entry.prof || [])]
}

/** 测试用 */
export function resetKeyLevels(): void { cache.clear(); waiting.clear() }

// ------------------------------------------------------------ 绘制
interface Placed { l: KeyLevel; y: number; x0: number; x1: number; touched: boolean; col: string }

function colorsOf(ch: TVChart): Record<KeyTier, string> {
  const cs = getComputedStyle(ch.host)
  return { day: cs.getPropertyValue('--kl-day').trim() || '#7C6CF0', week: cs.getPropertyValue('--kl-week').trim() || '#1E9AA8' }
}

/** 线从哪根 K 线起：第一根开盘时间 ≥ from 的（没加载到那么早就从最左边那根起） */
function firstIndexAt(bars: readonly Bar[], t: number): number {
  let lo = 0, hi = bars.length
  while (lo < hi) { const m = (lo + hi) >> 1; if (bars[m].t < t) lo = m + 1; else hi = m }
  return lo
}

const lastPlaced = new WeakMap<TVChart, Placed[]>()

function place(ch: TVChart, p: Pane, r: PriceRange): Placed[] {
  const bars = ch.bars
  if (!bars.length) return []
  const all = levelsForInterval(keyLevelsOf(ch), ch.iv)
  const cols = colorsOf(ch), PW = ch.plotW(), out: Placed[] = []
  for (const l of all) {
    const y = Math.round(ch.priceToY(l.price, p, r)) + .5
    if (y < p.y || y > p.y + p.h) continue
    const i0 = firstIndexAt(bars, l.from)
    if (i0 >= bars.length) continue
    const x0 = Math.max(0, ch.indexToX(i0) - ch.spacing / 2)
    if (x0 > PW) continue
    let x1 = PW, touched = false
    if (l.naked) {
      const k = touchIndex(bars, l.price, l.from)
      if (k >= 0) { touched = true; x1 = Math.min(PW, ch.indexToX(k)) }
    }
    if (x1 <= x0) continue
    out.push({ l, y, x0, x1, touched, col: cols[l.tier] })
  }
  return out
}

/** 主图上画线与右端小字（在 K 线之前画，线垫在蜡烛下面） */
export function drawKeyLevels(ch: TVChart, p: Pane, r: PriceRange, _from: number, _to: number): void {
  const c = ch.ctx, PW = ch.plotW()
  const placed = place(ch, p, r)
  lastPlaced.set(ch, placed)
  if (!placed.length) return
  c.save()
  c.beginPath(); c.rect(0, p.y, PW, p.h); c.clip()
  c.lineWidth = 1
  for (const q of placed) {
    const dash = q.l.key === 'to' ? [2, 3] : q.l.naked ? [] : [6, 4]
    c.setLineDash(dash)
    c.strokeStyle = hexA(q.col, q.touched ? 0.35 : 0.85)
    c.beginPath(); c.moveTo(q.x0, q.y); c.lineTo(q.x1, q.y); c.stroke()
  }
  c.setLineDash([])
  // 右端小字：没被碰到的线在最右边写名字；互相挤着时往上下让开
  const fam = ch.font.split('px ')[1] || 'sans-serif'
  c.font = `500 11px ${fam}`; c.textAlign = 'right'; c.textBaseline = 'bottom'
  const tags = placed.filter(q => !q.touched).sort((a, b) => a.y - b.y)
  let prev = -Infinity
  for (const q of tags) {
    let ty = Math.max(q.y - 2, prev + 13)
    ty = Math.min(ty, p.y + p.h - 2)
    prev = ty
    c.fillStyle = q.col
    c.fillText(q.l.label, PW - 6, ty)
  }
  c.restore()
}

/** 价格轴上同色的小片（不含被碰过的裸线）；在最新价标签之前画，最新价压在最上面 */
export function drawKeyAxis(ch: TVChart, p: Pane, _r: PriceRange): void {
  const chips = (lastPlaced.get(ch) || []).filter(q => !q.touched).sort((a, b) => a.y - b.y)
  if (!chips.length) return
  const c = ch.ctx, PW = ch.plotW(), H = 18
  let prev = -Infinity
  c.save()
  c.textAlign = 'left'; c.textBaseline = 'middle'; c.font = ch.font
  for (const q of chips) {
    let top = Math.max(q.y - H / 2, prev + H + 1)
    top = Math.min(top, p.y + p.h - H)
    prev = top
    c.fillStyle = q.col
    c.beginPath(); c.roundRect(PW + 1, top, ch.aw - 2, H, 3); c.fill()
    c.fillStyle = '#fff'
    c.fillText(fmtAxis(q.l.price, ch.meta.dec), PW + 8, top + H / 2 + 0.5)
  }
  c.restore()
}

/** 回归脚本读：这一帧画了哪些关键价位（名字、价、是否被碰过） */
export function keyLevelsShown(ch: TVChart): { label: string; price: number; touched: boolean; tier: KeyTier }[] {
  return (lastPlaced.get(ch) || []).map(q => ({ label: q.l.label, price: q.l.price, touched: q.touched, tier: q.l.tier }))
}
