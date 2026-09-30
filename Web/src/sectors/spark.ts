/* Hkline Web · 板块迷你走势
 *
 * 一个板块的走势 = 它成交额最大的几个成员（每板块最多 6 只）各自的小时收盘，
 * 按同一根时间轴对齐后逐点取中位数——和板块涨跌幅同一个口径（中位数），只是画成一条线。
 * 今日：最近 24 小时；5 日：从 5 日基准那根日线收盘（asof − 4 的 UTC 零点）画到现在。
 *
 * 数据从哪来：
 *   · 首选看盘服务端 GET /v1/market/hourly-closes?symbols=A,B（同源，≤ 200 只一批，只含已收盘的小时，
 *     Cache-Control max-age=300）——不占币安的请求权重，板块页冷启动不再为走势线打几百次 K 线
 *   · 服务端没上线 / 404 / 5xx / 网络错：退回直连币安，每只一段 1 小时 K 线（走限流预算的后台那一截，
 *     同时最多 6 个在路上），取到的在本标签页的 sessionStorage 里留几分钟，刷新页面不重打
 * 跨板块去重、不再有「一轮最多 180 只」的上限（服务端一批 200 只，几批就全齐了）；
 * 每只 5 分钟内不重取（和服务端的 max-age 对齐）；只取当前市场正在看的那张表。
 */
import { klines } from '../market'
import { parseDay } from './aggregate'
import type { SectorWindow } from './aggregate'

export const PER_BOARD = 6
/** 服务端一批最多几只（契约上限） */
export const BATCH = 200
/** 进程内缓存多久（= 服务端 Cache-Control max-age） */
export const TTL_MS = 300_000
const CONCURRENCY = 6
const HOUR = 3_600_000
const LIMIT = 170 // 覆盖「asof 晚一天」时的 5 日窗口（≈ 6 天 × 24）；100–500 根同一档权重
/** 服务端能收的代号（契约：大写字母数字）；币安里中文名的合约走直连 */
const SERVER_SYMBOL = /^[A-Z0-9_]{1,40}$/
const SESSION_KEY = 'hkline-web-spark-v1'

interface Series { at: number; bars: Map<number, number>; direct?: boolean }
const cache = new Map<string, Series>()
const inflight = new Set<string>()
let queue: string[] = []
let running = 0
let notify: (() => void) | null = null
let notifyTimer: ReturnType<typeof setTimeout> | undefined
/** 服务端这段时间内不通（404 / 5xx / 网络错）：直接走直连，过了再试服务端 */
let serverDownUntil = 0
let sessionLoaded = false

function ping(): void {
  clearTimeout(notifyTimer)
  notifyTimer = setTimeout(() => notify?.(), 120)
}

const apiBase = (): string => {
  const b = (import.meta as { env?: { BASE_URL?: string } }).env?.BASE_URL ?? '/'
  return b.replace(/\/web\/$/, '/')
}

// ------------------------------------------------------------ 服务端
type HourlyBody = { asOf?: number; hours?: number; series?: Record<string, [number, number][]> }

/** 取一批；返回 false 表示服务端不可用（调用方退回直连） */
async function fromServer(batch: string[]): Promise<boolean> {
  let r: Response
  try {
    r = await fetch(`${apiBase()}v1/market/hourly-closes?symbols=${batch.join(',')}`)
  } catch { return false }
  if (!r.ok) return false
  let body: HourlyBody
  try { body = await r.json() as HourlyBody } catch { return false }
  const series = body && typeof body === 'object' && body.series && typeof body.series === 'object' ? body.series : null
  if (!series) return false
  const now = Date.now()
  for (const k of batch) {
    const rows = series[k]
    const m = new Map<number, number>()
    if (Array.isArray(rows)) for (const row of rows) {
      if (!Array.isArray(row)) continue
      const t = +row[0], c = +row[1]
      if (Number.isFinite(t) && Number.isFinite(c) && c > 0) m.set(t, c)
    }
    // 服务端省略的 = 它那里没有这只的数（新上架等）；这一轮就不画它，板块中位数由其余成员出
    cache.set(k, { at: now, bars: m })
  }
  return true
}

/**
 * 发给服务端的排队：同一时刻只有一趟在路上（一趟里 ≤ 200 只一批、几批并行）；在路上时再要的并进下一趟。
 * 板块页边渲染边要，零散地一轮轮发会变成好几个小请求，服务端没上线时还会在第一个 404 回来之前再撞几次。
 */
let serverQueue: string[] = []
let serverBusy = false
async function drainServer(): Promise<void> {
  if (serverBusy) return
  serverBusy = true
  try {
    while (serverQueue.length) {
      const list = serverQueue
      serverQueue = []
      if (Date.now() < serverDownUntil) { direct(list); continue }
      const batches: string[][] = []
      for (let i = 0; i < list.length; i += BATCH) batches.push(list.slice(i, i + BATCH))
      const oks = await Promise.all(batches.map(b => fromServer(b)))
      const failed: string[] = []
      batches.forEach((b, i) => { if (oks[i]) b.forEach(k => inflight.delete(k)); else failed.push(...b) })
      if (failed.length < list.length) ping()
      if (failed.length) { serverDownUntil = Date.now() + TTL_MS; direct(failed) }
    }
  } finally { serverBusy = false }
}

// ------------------------------------------------------------ 直连兜底
function loadSession(): void {
  if (sessionLoaded) return
  sessionLoaded = true
  try {
    const raw = globalThis.sessionStorage?.getItem(SESSION_KEY)
    if (!raw) return
    const saved = JSON.parse(raw) as Record<string, { at: number; bars: [number, number][] }>
    const now = Date.now()
    for (const [k, v] of Object.entries(saved)) {
      if (!v || !Array.isArray(v.bars) || !(now - v.at < TTL_MS)) continue
      if (!cache.has(k)) cache.set(k, { at: v.at, bars: new Map(v.bars) })
    }
  } catch { /* 坏了就当没有 */ }
}

let saveTimer: ReturnType<typeof setTimeout> | undefined
function saveSession(): void {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(() => {
    try {
      const now = Date.now(), out: Record<string, { at: number; bars: [number, number][] }> = {}
      for (const [k, v] of cache) if (v.direct && now - v.at < TTL_MS && v.bars.size) out[k] = { at: v.at, bars: [...v.bars] }
      globalThis.sessionStorage?.setItem(SESSION_KEY, JSON.stringify(out))
    } catch { /* 存不下就只留在内存里 */ }
  }, 500)
}

function direct(list: string[]): void {
  for (const k of list) if (!queue.includes(k)) queue.push(k)
  pump()
}

function pump(): void {
  while (running < CONCURRENCY && queue.length) {
    const k = queue.shift() as string
    running++
    klines(k, '1h', undefined, LIMIT, false, true).then(({ bars, ok }) => {
      if (ok && bars.length) { cache.set(k, { at: Date.now(), bars: new Map(bars.map(b => [b.t, b.c])), direct: true }); saveSession() }
      else cache.set(k, { at: Date.now() - TTL_MS + 60_000, bars: cache.get(k)?.bars ?? new Map() }) // 失败的一分钟后才再试
    }).catch(() => { /* 网络错当没有 */ }).finally(() => {
      running--
      inflight.delete(k)
      ping()
      pump()
    })
  }
}

// ------------------------------------------------------------ 入口
/** 这一轮要看的合约（按显示顺序给，前面的先取）；取到一批就回调 */
export function wantSparks(symbols: string[], onReady: () => void): void {
  notify = onReady
  loadSession()
  const now = Date.now()
  const seen = new Set<string>()
  const want: string[] = []
  for (const k of symbols) {
    if (seen.has(k)) continue
    seen.add(k)
    const c = cache.get(k)
    if ((!c || now - c.at >= TTL_MS) && !inflight.has(k)) want.push(k)
  }
  // 直连队列里上一轮剩下、这一轮不看了的，丢掉
  queue = queue.filter(k => seen.has(k) || (inflight.delete(k), false))
  if (!want.length) return
  want.forEach(k => inflight.add(k))
  const server = want.filter(k => SERVER_SYMBOL.test(k)), rest = want.filter(k => !SERVER_SYMBOL.test(k))
  if (rest.length) direct(rest)
  if (server.length) { serverQueue.push(...server); void drainServer() }
}
export function stopSparks(): void {
  for (const k of queue) inflight.delete(k)
  for (const k of serverQueue) inflight.delete(k)
  queue = []; serverQueue = []; notify = null
}

/** 测试用：清掉进程内状态 */
export function resetSparks(): void {
  cache.clear(); inflight.clear(); queue = []; serverQueue = []; serverBusy = false; running = 0; notify = null; serverDownUntil = 0; sessionLoaded = false
  clearTimeout(notifyTimer); clearTimeout(saveTimer)
}

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
