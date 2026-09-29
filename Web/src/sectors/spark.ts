/* Hkline Web · 板块迷你走势
 *
 * 一个板块的走势 = 它成交额最大的几个成员（每板块最多 6 只）各自的小时收盘，
 * 按同一根时间轴对齐后逐点取中位数——和板块涨跌幅同一个口径（中位数），只是画成一条线。
 * 今日：最近 24 小时；5 日：从 5 日基准那根日线收盘（asof − 4 的 UTC 零点）画到现在。
 *
 * 请求量有上限：每板块 6 只、跨板块去重、一轮最多 SPARK_CAP 只、同时最多 6 个请求在路上、
 * 每只 10 分钟内不重取；只取当前市场正在看的那张表；走限流预算的后台那一截（market/limit.ts），不和图表抢。
 */
import { klines } from '../market'
import { parseDay } from './aggregate'
import type { SectorWindow } from './aggregate'

export const PER_BOARD = 6
export const SPARK_CAP = 180
const CONCURRENCY = 6
const TTL_MS = 10 * 60_000
const HOUR = 3_600_000
const LIMIT = 170 // 覆盖「asof 晚一天」时的 5 日窗口（≈ 6 天 × 24）；100–500 根同一档权重

interface Series { at: number; bars: Map<number, number> }
const cache = new Map<string, Series>()
let queue: string[] = []
let running = 0
let notify: (() => void) | null = null
let notifyTimer: ReturnType<typeof setTimeout> | undefined

function pump(): void {
  while (running < CONCURRENCY && queue.length) {
    const k = queue.shift() as string
    running++
    klines(k, '1h', undefined, LIMIT, false, true).then(({ bars, ok }) => {
      if (ok && bars.length) cache.set(k, { at: Date.now(), bars: new Map(bars.map(b => [b.t, b.c])) })
      else cache.set(k, { at: Date.now() - TTL_MS + 60_000, bars: cache.get(k)?.bars ?? new Map() }) // 失败的一分钟后才再试
    }).catch(() => { /* 网络错当没有 */ }).finally(() => {
      running--
      clearTimeout(notifyTimer)
      notifyTimer = setTimeout(() => notify?.(), 120)
      pump()
    })
  }
}

/** 这一轮要看的合约（按显示顺序给，前面的先取）；取到一批就回调 */
export function wantSparks(symbols: string[], onReady: () => void): void {
  notify = onReady
  const now = Date.now()
  const seen = new Set<string>()
  queue = []
  for (const k of symbols) {
    if (seen.has(k)) continue
    seen.add(k)
    if (seen.size > SPARK_CAP) break
    const c = cache.get(k)
    if (!c || now - c.at >= TTL_MS) queue.push(k)
  }
  pump()
}
export function stopSparks(): void { queue = []; notify = null }

/** 这段窗口的时间轴（每根 1 小时 K 线的开盘时刻），第一根是基准 */
function grid(window: SectorWindow, asof: string, now = Date.now()): number[] {
  const last = Math.floor(now / HOUR) * HOUR
  let start = last - 24 * HOUR
  if (window === 'd5') {
    const day = parseDay(asof); if (day == null) return []
    start = day - 4 * 86_400_000 - HOUR // 收在 asof − 4 零点的那根，它的收盘就是 5 日基准
  }
  const out: number[] = []
  for (let t = start; t <= last; t += HOUR) out.push(t)
  return out
}

const med = (a: number[]): number => { const s = a.slice().sort((x, y) => x - y), n = s.length; return n % 2 ? s[n >> 1] : (s[n / 2 - 1] + s[n / 2]) / 2 }

/** 板块走势（百分数），缺数返回 null */
export function boardPath(symbols: string[], window: SectorWindow, asof: string): number[] | null {
  const ts = grid(window, asof)
  if (ts.length < 3) return null
  const series: number[][] = []
  for (const k of symbols) {
    const c = cache.get(k); if (!c || !c.bars.size) continue
    let base: number | undefined
    for (const t of ts) { const v = c.bars.get(t); if (v != null && v > 0) { base = v; break } }
    if (base == null) continue
    series.push(ts.map(t => { const v = c.bars.get(t); return v != null && v > 0 ? (v / base! - 1) * 100 : NaN }))
  }
  if (!series.length) return null
  const out: number[] = []
  let prev = 0
  for (let i = 0; i < ts.length; i++) {
    const vals = series.map(s => s[i]).filter(Number.isFinite)
    prev = vals.length ? med(vals) : prev
    out.push(prev)
  }
  return out
}

/** 画成 SVG 内容（viewBox 0 0 W H）；零线淡淡一条 */
export function sparkSVG(path: number[] | null, tone: 'up' | 'down' | '', w = 160, h = 32): string {
  if (!path || path.length < 2) return ''
  let lo = Math.min(0, ...path), hi = Math.max(0, ...path)
  if (hi - lo < 0.2) { const m = (hi + lo) / 2; lo = m - 0.1; hi = m + 0.1 }
  const pad = 3
  const y = (v: number): number => pad + (hi - v) / (hi - lo) * (h - pad * 2)
  const x = (i: number): number => 1 + i / (path.length - 1) * (w - 2)
  const pts = path.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(' ')
  const color = tone === 'up' ? 'var(--up)' : tone === 'down' ? 'var(--down)' : 'var(--text-3)'
  const z = y(0).toFixed(1)
  return `<line x1="0" x2="${w}" y1="${z}" y2="${z}" class="sec-zero"/><polyline points="${pts}" fill="none" stroke="${color}" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>`
}
