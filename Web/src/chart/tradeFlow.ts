/* Hkline Web · 三家逐笔成交的分桶（「累计量差」的实时段、「大单与散户累计量差」）
 *
 * 实时：主力订单流的数据层（orderflow/feed.ts）打开一只品种时连着币安、OKX、Coinbase 三家全部簿的逐笔成交，
 * 每一笔按成交时刻落进「秒」与「分钟」两种桶（秒桶留 6 小时、分钟桶留 3 天），分现货 / 合约 / 币安 U 本位这一只、
 * 大单（≥ 大单线）/ 散户（< 1 万美元）记主动买、主动卖的美元额。数据层每半秒一拍心跳（连接都开着才算），
 * 连续的心跳连成「覆盖区间」：一根 K 线整个落在覆盖区间里，才拿三家的数算，否则只有币安 K 线自带的主动买入。
 * 数据层只跟着活动格子的品种开，所以多图时只有活动格子有实时段。
 *
 * 历史：服务端（kanpan-api）对常驻跟踪的品种每分钟记一行 [分钟, 大买额, 大卖额, 小买额, 小卖额]，
 * 近 3 天（GET /v1/market/orderflow/flow）。没在跟的品种没有历史，从打开页面起算。只聚合，不判定。
 */
import type { Bar, Series, CalcEnv } from './calc'
import type { TradeEvent } from '../orderflow/feed'
import { baseOfSymbol } from '../orderflow/settings'

/** 散户线：一笔不到 1 万美元 */
export const SMALL_USD = 10_000
const SEC_KEEP_MS = 6 * 3_600_000
const MIN_KEEP_MS = 3 * 86_400_000
/** 两拍心跳隔这么久就算断了（覆盖区间另起一段） */
const GAP_MS = 10_000
/** 服务端历史多久增量拉一次；失败了多久再试 */
const POLL_MS = 60_000
const RETRY_MS = 30_000
const FETCH_TIMEOUT_MS = 12_000
/** 最多记几只品种（切来切去时旧的按最近活动淘汰） */
const MAX_SYMBOLS = 6

/** 一个桶：美元额 */
export interface Cell {
  /** 现货主动买 / 卖 */
  sb: number; ss: number
  /** 合约（三家全部合约）主动买 / 卖 */
  cb: number; cs: number
  /** 其中币安 U 本位这一只（和 K 线自带的主动买入是同一份成交） */
  ub: number; us: number
  /** 大单 / 散户 主动买 / 卖 */
  bb: number; bs: number
  rb: number; rs: number
}
const cell = (): Cell => ({ sb: 0, ss: 0, cb: 0, cs: 0, ub: 0, us: 0, bb: 0, bs: 0, rb: 0, rs: 0 })
function addCell(a: Cell, b: Cell): void {
  a.sb += b.sb; a.ss += b.ss; a.cb += b.cb; a.cs += b.cs; a.ub += b.ub; a.us += b.us; a.bb += b.bb; a.bs += b.bs; a.rb += b.rb; a.rs += b.rs
}

type Row = [number, number, number, number]
interface Server {
  rows: Map<number, Row>
  /** 服务端历史覆盖的分钟（含两端）；没有数据时 lo > hi */
  lo: number
  hi: number
  tracked: boolean | null
  bigUsd: number | null
  busy: boolean
  nextAt: number
}

export class SymbolFlow {
  sec = new Map<number, Cell>()
  min = new Map<number, Cell>()
  /** 覆盖区间 [起, 止]（本机时间），按时间排 */
  cover: [number, number][] = []
  srv: Server = { rows: new Map(), lo: Infinity, hi: -Infinity, tracked: null, bigUsd: null, busy: false, nextAt: 0 }
  /** 浏览器这边当下用的大单线（服务端的到了就用服务端的） */
  localCut: number | null = null
  touched = 0
  listeners = new Set<() => void>()
  constructor(readonly symbol: string) {}

  /** 这一段 [a, b) 是不是整个落在一个覆盖区间里；b 在未来（正在走的那根）时要求覆盖还没断 */
  covered(a: number, b: number, now: number): boolean {
    for (let k = this.cover.length - 1; k >= 0; k--) {
      const [s, e] = this.cover[k]
      if (s > a) continue
      if (b <= e) return true
      return b > now && now - e <= GAP_MS
    }
    return false
  }
  get cut(): number | null { return this.srv.bigUsd ?? this.localCut }
  notify(): void { for (const f of this.listeners) f() }
}

const flows = new Map<string, SymbolFlow>()
export function flowOf(symbol: string): SymbolFlow {
  const key = symbol.toUpperCase()
  let f = flows.get(key)
  if (!f) {
    f = new SymbolFlow(key); flows.set(key, f)
    if (flows.size > MAX_SYMBOLS) {
      const old = [...flows.values()].filter(x => x !== f).sort((a, b) => a.touched - b.touched)[0]
      if (old) flows.delete(old.symbol)
    }
  }
  return f
}
/** 测试用：清空 */
export function resetFlows(): void { flows.clear() }

// ------------------------------------------------------------ 记录（orderflow/index.ts 调）
/** 进一笔成交。cut 是浏览器这边的大单线（门槛 / 50），服务端给过就用服务端的，两边口径一致 */
export function recordTrade(symbol: string, ev: TradeEvent, cut: number | null): void {
  const f = flowOf(symbol)
  if (cut != null && cut > 0) f.localCut = cut
  const usd = ev.usd
  if (!(usd > 0)) return
  const t = ev.trade.timeMs || Date.now(), v = ev.book.venue, buy = ev.trade.hitSide === 'ask'
  const c = cell()
  if (v.product === 'spot') { if (buy) c.sb = usd; else c.ss = usd }
  else {
    if (buy) c.cb = usd; else c.cs = usd
    if (v.exchange === 'binance' && v.product === 'usdtPerp' && v.instrument.toUpperCase() === f.symbol) { if (buy) c.ub = usd; else c.us = usd }
  }
  const big = f.cut
  if (big != null && usd >= big) { if (buy) c.bb = usd; else c.bs = usd }
  if (usd < SMALL_USD) { if (buy) c.rb = usd; else c.rs = usd }
  bump(f.sec, Math.floor(t / 1000) * 1000, c)
  bump(f.min, Math.floor(t / 60_000) * 60_000, c)
  f.touched = Date.now()
}
function bump(m: Map<number, Cell>, k: number, c: Cell): void {
  let x = m.get(k)
  if (!x) { x = cell(); m.set(k, x) }
  addCell(x, c)
}

/** 数据层每拍一次：连接都开着就把覆盖区间往后接（断了 10 秒以上另起一段）；顺手清掉过期的桶 */
export function beat(symbol: string, now: number, ok: boolean): void {
  const f = flowOf(symbol)
  f.touched = now
  if (ok) {
    const last = f.cover[f.cover.length - 1]
    if (last && now - last[1] <= GAP_MS) last[1] = now
    else f.cover.push([now, now])
  }
  prune(f.sec, now - SEC_KEEP_MS)
  prune(f.min, now - MIN_KEEP_MS)
  while (f.cover.length && f.cover[0][1] < now - MIN_KEEP_MS) f.cover.shift()
}
function prune(m: Map<number, Cell>, cutoff: number): void {
  for (const k of m.keys()) { if (k >= cutoff) break; m.delete(k) }
}

// ------------------------------------------------------------ 服务端历史
/** 解 /v1/market/orderflow/flow 的答复 */
export function parseFlow(body: unknown): { tracked: boolean; bigUsd: number | null; rows: [number, ...Row][] } | null {
  if (!body || typeof body !== 'object') return null
  const b = body as Record<string, unknown>
  if (!Array.isArray(b.rows)) return null
  const rows: [number, ...Row][] = []
  for (const r of b.rows) {
    if (!Array.isArray(r) || r.length < 5 || !r.every(x => typeof x === 'number' && Number.isFinite(x))) continue
    rows.push([r[0], r[1], r[2], r[3], r[4]])
  }
  const big = typeof b.bigUsd === 'number' && b.bigUsd > 0 ? b.bigUsd : null
  return { tracked: b.tracked === true, bigUsd: big, rows }
}

async function fetchServer(f: SymbolFlow, now: number): Promise<void> {
  const s = f.srv
  s.busy = true
  const from = s.hi > 0 ? s.hi : now - MIN_KEEP_MS
  const url = `/v1/market/orderflow/flow?base=${encodeURIComponent(baseOfSymbol(f.symbol).base)}&from=${Math.floor(from)}&to=${Math.floor(now)}`
  const ctl = new AbortController(), timer = setTimeout(() => ctl.abort(), FETCH_TIMEOUT_MS)
  try {
    const r = await fetch(url, { signal: ctl.signal, referrerPolicy: 'no-referrer', cache: 'no-store' })
    const p = r.ok ? parseFlow(await r.json()) : null
    if (!p) { s.nextAt = Date.now() + RETRY_MS; return }
    s.tracked = p.tracked
    if (p.bigUsd != null) s.bigUsd = p.bigUsd
    for (const [t, bb, bs, sb, ss] of p.rows) {
      s.rows.set(t, [bb, bs, sb, ss])
      if (t < s.lo) s.lo = t
      if (t > s.hi) s.hi = t
    }
    const cutoff = Date.now() - MIN_KEEP_MS
    for (const k of [...s.rows.keys()]) if (k < cutoff) s.rows.delete(k)
    if (s.lo < cutoff) s.lo = s.rows.size ? Math.min(...s.rows.keys()) : Infinity
    s.nextAt = Date.now() + POLL_MS
    f.notify()
  } catch {
    s.nextAt = Date.now() + RETRY_MS
  } finally { clearTimeout(timer); s.busy = false }
}

/** 算指标时调：到点了就在后台增量拉一次（不等，到了叫 invalidate 重算） */
function ensureServer(f: SymbolFlow, env: CalcEnv | undefined, now: number): void {
  if (!env) return
  f.listeners.add(env.invalidate)
  if (f.srv.busy || now < f.srv.nextAt || typeof fetch === 'undefined') return
  void fetchServer(f, now)
}

// ------------------------------------------------------------ 指标
function sumRange(m: Map<number, Cell>, a: number, b: number, step: number): Cell {
  const out = cell()
  for (let k = a; k < b; k += step) { const x = m.get(k); if (x) addCell(out, x) }
  return out
}
function barDeltaBinance(b: Bar): number {
  if (b.venueDelta) { let s = 0; for (const v of Object.values(b.venueDelta)) s += v || 0; return s }
  return b.tb == null || !isFinite(b.tb) ? 0 : 2 * b.tb - b.v
}

/** 累计量差：[合计, 现货, 合约]。
 *  整根落在覆盖区间里的 K 线（实时段）：合计 = 币安 U 本位（K 线自带的 2 × 主动买入 − 成交额）+ 三家其余的现货与合约；
 *  现货、合约两条线只在实时段有值，从进入实时段前一根的合计处分叉出来。其余的 K 线（历史段）只有币安。 */
export function cvdFlow(bars: Bar[], iv: number, f: SymbolFlow | null, now = Date.now()): Series[] {
  const n = bars.length
  const tot: Series = new Array(n).fill(null), spot: Series = new Array(n).fill(null), con: Series = new Array(n).fill(null)
  let s = 0, sp = 0, cn = 0, live = false
  const fine = iv < 60_000, step = fine ? 1000 : 60_000
  const firstCover = f && f.cover.length ? f.cover[0][0] : Infinity
  for (let i = 0; i < n; i++) {
    const b = bars[i], d0 = barDeltaBinance(b)
    const inCover = !!f && !b.venueDelta && b.t >= firstCover && iv % step === 0 && f.covered(b.t, b.t + iv, now)
    if (!inCover) { s += d0; tot[i] = s; live = false; continue }
    const c = sumRange(fine ? f!.sec : f!.min, b.t, b.t + iv, step)
    const dSpot = c.sb - c.ss, dCon = d0 + (c.cb - c.cs) - (c.ub - c.us)
    if (!live) {
      live = true; sp = s; cn = s
      if (i > 0) { spot[i - 1] = s; con[i - 1] = s }
    }
    sp += dSpot; cn += dCon; s += dSpot + dCon
    tot[i] = s; spot[i] = sp; con[i] = cn
  }
  return [tot, spot, con]
}

/** 大单与散户累计量差：[大单, 散户]，各自 = 主动买额 − 主动卖额 逐根累加，从第一根有数据的 K 线起。
 *  一分钟的数据取哪份：整分钟都在覆盖区间里用浏览器的；否则服务端有这一行用服务端的；服务端在跟、这一分钟落在它的历史里却没有行 = 这一分钟没成交；
 *  再不然用浏览器攒到的那一部分。秒级周期只有浏览器的（服务端按分钟记）。 */
export function whaleFlow(bars: Bar[], iv: number, f: SymbolFlow | null, now = Date.now()): Series[] {
  const n = bars.length
  const big: Series = new Array(n).fill(null), small: Series = new Array(n).fill(null)
  if (!f || !n) return [big, small]
  const fine = iv < 60_000, step = fine ? 1000 : 60_000
  if (iv % step !== 0) return [big, small]
  const src = fine ? f.sec : f.min, srv = f.srv
  let start = Infinity
  for (const k of src.keys()) { start = k; break }
  if (!fine && srv.tracked && srv.lo < start) start = srv.lo
  if (!isFinite(start)) return [big, small]
  let sb = 0, ss = 0, on = false
  const firstCover = f.cover.length ? f.cover[0][0] : Infinity
  for (let i = 0; i < n; i++) {
    const b = bars[i], end = b.t + iv
    if (end <= start) continue
    let db = 0, ds = 0, has = false
    for (let m = Math.max(b.t, Math.floor(start / step) * step); m < end && m <= now; m += step) {
      const x = src.get(m)
      if (m >= firstCover && f.covered(m, m + step, now)) { has = true; if (x) { db += x.bb - x.bs; ds += x.rb - x.rs } continue }
      if (!fine) {
        const r = srv.rows.get(m)
        if (r) { has = true; db += r[0] - r[1]; ds += r[2] - r[3]; continue }
        if (srv.tracked && m >= srv.lo && m <= srv.hi) { has = true; continue }
      }
      if (x) { has = true; db += x.bb - x.bs; ds += x.rb - x.rs }
    }
    if (has) on = true
    if (!on) continue
    sb += db; ss += ds
    big[i] = sb; small[i] = ss
  }
  return [big, small]
}

/** 金额短写：100000 → 100K、1500000 → 1.5M */
export function shortUsd(v: number): string {
  const u: [number, string][] = [[1e12, 'T'], [1e9, 'B'], [1e6, 'M'], [1e3, 'K']]
  for (const [k, s] of u) if (Math.abs(v) >= k) return `${+(v / k).toFixed(2)}${s}`
  return `${Math.round(v)}`
}

// ------------------------------------------------------------ 并进 EXTRA_CALC 的两个入口
const CVD_TIP = '虚线左边只有币安 U 本位（K 线自带的主动买入）；右边是打开页面以后浏览器收到的币安、OKX、Coinbase 三家现货加合约，并拆成现货、合约两条'

export function calcCvd(bars: Bar[], env?: CalcEnv): Series[] {
  const now = Date.now()
  const f = env?.symbol ? flowOf(env.symbol) : null
  if (f && env) f.listeners.add(env.invalidate)
  env?.note('cvd', '币安 · 三家', CVD_TIP)
  return cvdFlow(bars, env?.iv || 0, f, now)
}

export function calcWhale(bars: Bar[], env?: CalcEnv): Series[] {
  const now = Date.now()
  const f = env?.symbol ? flowOf(env.symbol) : null
  if (f) ensureServer(f, env, now)
  if (env) {
    const cut = f?.cut, head = `大单 ≥ ${cut ? shortUsd(cut) : '门槛 / 50'} · 散户 < ${shortUsd(SMALL_USD)}`
    const tracked = f?.srv.tracked
    if (tracked === false) env.note('whale', `${head} · 从打开起`, '服务端只给常驻跟踪的品种记分钟历史（近 3 天）；这只没在跟，从打开页面、连上三家成交起算')
    else env.note('whale', head, '一笔成交 ≥ 大单线（订单流门槛的 1/50）算大单，< 1 万美元算散户；主动买额减主动卖额逐根累加。三家现货加合约；近 3 天历史来自服务端常驻跟踪')
  }
  return whaleFlow(bars, env?.iv || 0, f, now)
}
