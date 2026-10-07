/* Hkline Web · 交易所不给的周期：秒级（1 秒 / 5 秒 / 15 秒）与自定义分钟
 *
 * 秒级：币安合约没有秒级 K 线，拿逐笔成交（aggTrade）自己攒——所以只有「打开页面以后」的那一段，
 *   每只品种在内存里留最近约 6 小时的 1 秒线，5 秒、15 秒从 1 秒线现并。
 * 自定义分钟（例如 7 分、45 分、90 分）：取能整除它的最大原生周期去拉，再按 floor(t / N) · N 并起来；
 *   实时跟着那个原生周期的 K 线流走，当前这一格用它里面的几根原生线现算。
 *
 * 注册的做法是往 IV_MS / IV_LABEL / IV_SHORT 里补键（只加不改），INTERVALS（原生周期表）不动，
 * 所以钉周期、右键菜单、范围按钮这些只认原生周期的地方都不受影响。
 */
import { IV_MS } from '../util/format'
import { IV_LABEL, IV_SHORT } from '../market/symbols'
import { klines } from '../market/rest'
import { tapTrade, type Trade } from '../market/trades'
import { S, on } from '../market/state'
import type { Bar } from './calc'

export const SECOND_IVS = ['1s', '5s', '15s'] as const
const SEC_LABEL: Record<string, [string, string]> = { '1s': ['1秒', '1秒'], '5s': ['5秒', '5秒'], '15s': ['15秒', '15秒'] }
for (const iv of SECOND_IVS) { IV_MS[iv] = +iv.slice(0, -1) * 1e3; IV_LABEL[iv] = SEC_LABEL[iv][0]; IV_SHORT[iv] = SEC_LABEL[iv][1] }

/** 原生分钟 / 小时周期（能当自定义分钟的底） */
const NATIVE_BASES = ['12h', '8h', '6h', '4h', '2h', '1h', '30m', '15m', '5m', '3m', '1m']
const isNative = (iv: string) => NATIVE_BASES.includes(iv) || iv === '1d' || iv === '1w' || iv === '1M'

export const isSecondIv = (iv: string): boolean => (SECOND_IVS as readonly string[]).includes(iv)
/** 自定义分钟：N 分（2 ≤ N ≤ 1440，且不是原生周期） */
export function isCustomIv(iv: string): boolean {
  const m = /^(\d+)m$/.exec(iv); if (!m) return false
  const n = +m[1]
  return n >= 2 && n <= 1440 && !isNative(iv) && !NATIVE_BASES.some(b => IV_MS[b] === n * 60e3)
}
/** 分钟数 → 周期键：原生的给原生键，否则给「N m」 */
export function minutesIv(n: number): string | null {
  if (!Number.isInteger(n) || n < 1 || n > 1440) return null
  const nat = NATIVE_BASES.find(b => IV_MS[b] === n * 60e3) || (n === 1440 ? '1d' : null)
  return nat || `${n}m`
}
/** 自定义分钟的底：能整除它的最大原生周期 */
export function customBase(iv: string): string {
  const ms = IV_MS[iv] ?? (+iv.slice(0, -1) * 60e3)
  return NATIVE_BASES.find(b => ms % IV_MS[b] === 0) || '1m'
}
export function customLabel(iv: string): string {
  const n = +iv.slice(0, -1)
  return n % 60 === 0 ? `${n / 60}小时` : `${n}分`
}
/** 把自定义分钟挂进周期表（重复挂没事） */
export function registerCustomIv(iv: string): boolean {
  if (!isCustomIv(iv)) return false
  const n = +iv.slice(0, -1)
  IV_MS[iv] = n * 60e3
  IV_LABEL[iv] = customLabel(iv)
  IV_SHORT[iv] = n % 60 === 0 ? `${n / 60}时` : `${n}分`
  return true
}
/** 这个周期要订哪个原生 K 线流（秒级不订 K 线流，订逐笔） */
export function streamIvOf(iv: string): string | null {
  if (isSecondIv(iv)) return null
  if (isCustomIv(iv)) return customBase(iv)
  return iv
}

// ------------------------------------------------------------ 并线（纯函数）
function merge(into: Bar, b: Bar): void {
  into.h = Math.max(into.h, b.h); into.l = Math.min(into.l, b.l); into.c = b.c
  into.v += b.v
  if (b.tb != null) into.tb = (into.tb ?? 0) + b.tb
  if (b.bv != null) into.bv = (into.bv ?? 0) + b.bv
  if (b.oi != null) into.oi = b.oi
}
const copy = (b: Bar, t: number): Bar => ({ t, o: b.o, h: b.h, l: b.l, c: b.c, v: b.v, ...(b.tb != null ? { tb: b.tb } : {}), ...(b.bv != null ? { bv: b.bv } : {}), ...(b.oi != null ? { oi: b.oi } : {}) })
/** 按 ms 对齐（从 1970 起算，和交易所的分钟线一样对齐 UTC）并线；输入按时间升序 */
export function aggregate(bars: Bar[], ms: number): Bar[] {
  const out: Bar[] = []
  for (const b of bars) {
    const t = Math.floor(b.t / ms) * ms
    const last = out[out.length - 1]
    if (last && last.t === t) merge(last, b)
    else out.push(copy(b, t))
  }
  return out
}

// ------------------------------------------------------------ 秒级：逐笔攒 1 秒线
const KEEP_1S = 6 * 3600
const secs = new Map<string, Bar[]>()
const secListeners = new Set<(symbol: string) => void>()
let tapped = false
const notify = (symbol: string) => secListeners.forEach(f => { try { f(symbol) } catch (e) { console.error(e) } })
function trim(arr: Bar[]): void { if (arr.length > KEEP_1S * 1.1) arr.splice(0, arr.length - KEEP_1S) }
function onTrade(tr: Trade): void {
  const t = Math.floor(tr.t / 1e3) * 1e3, quote = tr.price * tr.qty
  let arr = secs.get(tr.symbol)
  if (!arr) { arr = []; secs.set(tr.symbol, arr) }
  const last = arr[arr.length - 1]
  if (last && last.t === t) {
    // 这一秒先被补成了平的（成交晚到）：第一笔成交按真的开盘算
    if (last.v === 0 && !last.bv) { last.o = last.h = last.l = tr.price }
    last.h = Math.max(last.h, tr.price); last.l = Math.min(last.l, tr.price); last.c = tr.price
    last.v += quote; last.bv = (last.bv ?? 0) + tr.qty; if (!tr.sell) last.tb = (last.tb ?? 0) + quote
  } else if (!last || t > last.t) {
    padArr(arr, tr.symbol, t)   // 上一笔到这一笔之间没成交的秒先补平
    arr.push({ t, o: tr.price, h: tr.price, l: tr.price, c: tr.price, v: quote, bv: tr.qty, tb: tr.sell ? 0 : quote })
    trim(arr)
  } else return // 乱序的旧成交不回改
  notify(tr.symbol)
}
/** 开始攒（页面一启动就调；只会攒到已订逐笔流的品种） */
export function startSeconds(): void { if (!tapped) { tapped = true; tapTrade(onTrade) } }
export function onSecondsTick(fn: (symbol: string) => void): () => void { secListeners.add(fn); return () => { secListeners.delete(fn) } }
/** 某只品种在某个秒级周期上的全部 K 线 */
export function secondBars(symbol: string, iv: string): Bar[] {
  const a = secs.get(symbol) || []
  return iv === '1s' ? a.map(b => ({ ...b })) : aggregate(a, IV_MS[iv])
}
/** 当前这一格（给实时更新） */
export function secondLastBar(symbol: string, iv: string): Bar | null {
  return secondBarsSince(symbol, iv, Infinity)[0] ?? null
}
/** 从 t 所在那一格起到最新的各格（图上最后一根之后补上来的几秒一起给；t = Infinity 只给当前格） */
export function secondBarsSince(symbol: string, iv: string, t: number): Bar[] {
  const a = secs.get(symbol); if (!a?.length) return []
  const ms = IV_MS[iv] || 1e3, lastT = Math.floor(a[a.length - 1].t / ms) * ms
  const from = Math.min(lastT, Math.floor(t / ms) * ms)
  let k = a.length - 1
  while (k > 0 && a[k - 1].t >= from) k--
  return aggregate(a.slice(k), ms)
}

/* ------------------------------------------------------------ 秒级：没成交的秒补平（2026-10-07）
 * 一秒里没有成交，逐笔就不来，图上那一秒就是个缺口。照交易所 / TradingView 的秒线：这一秒过完（再等 PAD_GRACE_MS 让晚到的成交落位）
 * 还没成交，补一根开高低收都等于上一根收盘、量 0 的平线；5 秒 / 15 秒由 1 秒并出来，自然一样。
 * 只在「确实一直在收这只的逐笔」时补：WS 断着、页面藏到后台而这只的逐笔被退订（只有当前格的逐笔是核心流）时停补，
 * 恢复后从下一笔真成交起接着补，断掉那一段不编平线——由页面重取一次服务端秒线历史把它拼回来（resumed 回调）。
 * 页面在后台时定时器会被浏览器节流：回前台立刻把睡掉的秒一次补齐（一直在收逐笔的那只）。 */
export const PAD_GRACE_MS = 500
const watched = new Set<string>()
const dead = new Set<string>()
/** 收着收着断了的（刚开始看、还没连上的不算）：恢复时要页面补一次历史 */
const broke = new Set<string>()
/** 这一秒之前的不补（刚开始看、断流恢复的时刻）：最后一根早于它就等下一笔真成交再接着补 */
const breakAt = new Map<string, number>()
const secOf = (t: number) => Math.floor(t / 1e3) * 1e3
const flat = (t: number, c: number): Bar => ({ t, o: c, h: c, l: c, c, v: 0, bv: 0, tb: 0 })
/** 往 arr 末尾补平线到 until（不含）；返回补了几根 */
function padArr(arr: Bar[], symbol: string, until: number): number {
  const last = arr[arr.length - 1]
  if (!last || !watched.has(symbol) || dead.has(symbol) || last.t < (breakAt.get(symbol) ?? Infinity)) return 0
  let t = Math.max(last.t + 1e3, until - KEEP_1S * 1e3), n = 0
  for (; t < until; t += 1e3, n++) arr.push(flat(t, last.c))
  if (n) trim(arr)
  return n
}
/** 把这只品种补到「now 往前 PAD_GRACE_MS 已经过完的那一秒」；补了就照常通知图上去并 */
export function padSeconds(symbol: string, now = Date.now()): number {
  const arr = secs.get(symbol); if (!arr?.length) return 0
  const n = padArr(arr, symbol, secOf(now - PAD_GRACE_MS))
  if (n) notify(symbol)
  return n
}
/** 服务端历史拼好后，把历史最后一根（已补平到「现在」）接到逐笔的内存里，补平从它接着走 */
export function seedSeconds(symbol: string, b: Bar): void {
  let arr = secs.get(symbol)
  if (!arr) { arr = []; secs.set(symbol, arr) }
  const last = arr[arr.length - 1]
  if (last && last.t >= b.t) return
  arr.push({ ...b }); trim(arr)
  if (!watched.has(symbol)) { watched.add(symbol); breakAt.set(symbol, b.t) }
  else if ((breakAt.get(symbol) ?? 0) > b.t && !dead.has(symbol)) breakAt.set(symbol, b.t)
}
export interface SecondsPadHost {
  /** 现在摆在秒级格子里的品种 */
  symbols(): string[]
  /** 页面藏到后台时这只的逐笔还订着（当前格的） */
  keepsWhenHidden(symbol: string): boolean
  /** 断流后又在收了：页面重取这只的秒线历史，把断掉的那段拼回来 */
  resumed(symbol: string): void
}
let padHost: SecondsPadHost | null = null
const pageHidden = () => typeof document !== 'undefined' && document.visibilityState === 'hidden'
/** 对一遍账：谁在看、谁在收；返回恢复了的品种 */
export function reconcileSeconds(now = Date.now(), wsOpen = S.wsState === 'open', hidden = pageHidden()): string[] {
  if (!padHost) return []
  const want = new Set(padHost.symbols()), back: string[] = []
  for (const k of [...watched]) if (!want.has(k)) { watched.delete(k); dead.delete(k); broke.delete(k); breakAt.delete(k) }
  for (const k of want) {
    const wasLive = watched.has(k) && !dead.has(k)
    if (!watched.has(k)) { watched.add(k); breakAt.set(k, secOf(now)) }
    const live = wsOpen && (!hidden || padHost.keepsWhenHidden(k))
    if (!live) { if (wasLive) broke.add(k); dead.add(k) }
    else if (dead.has(k)) { dead.delete(k); breakAt.set(k, secOf(now)); if (broke.delete(k)) back.push(k) }
  }
  return back
}
function padTick(now = Date.now()): void {
  if (!padHost) return
  const back = reconcileSeconds(now)
  for (const k of watched) padSeconds(k, now)
  for (const k of back) { try { padHost.resumed(k) } catch (e) { console.error(e) } }
}
/** 页面启动时调一次：每秒到点补平、WS 断连 / 前后台切换时对账 */
export function startSecondsPadding(host: SecondsPadHost): void {
  const first = !padHost
  padHost = host
  if (!first) return
  const loop = () => { padTick(); setTimeout(loop, 1e3 - (Date.now() % 1e3) + PAD_GRACE_MS) }
  setTimeout(loop, 1e3 - (Date.now() % 1e3) + PAD_GRACE_MS)
  on(e => { if (e.type === 'ws') padTick() })
  if (typeof document !== 'undefined') document.addEventListener('visibilitychange', () => padTick())
}
/** 测试用 */
export function resetSeconds(): void { secs.clear(); watched.clear(); dead.clear(); broke.clear(); breakAt.clear(); padHost = null }
export function setSecondsPadHost(h: SecondsPadHost | null): void { padHost = h }
export function feedTrade(tr: Trade): void { onTrade(tr) }

// ------------------------------------------------------------ 自定义分钟：取数与实时
/** 当前那一格里的原生线（按「品种|周期」记） */
const tails = new Map<string, Map<number, Bar>>()
export async function customKlines(symbol: string, iv: string, endTime?: number, alive?: () => boolean): Promise<{ bars: Bar[]; ok: boolean; error?: string }> {
  const base = customBase(iv), ms = IV_MS[iv], per = ms / IV_MS[base]
  const limit = Math.min(1500, Math.max(200, Math.ceil(per * 500)))
  const r = await klines(symbol, base, endTime, limit, false, false, alive)
  if (!r.ok || !r.bars.length) return r
  let out = aggregate(r.bars, ms)
  // 第一格若是从半截开始的就丢掉（往前翻页时下一页会补全）
  if (out.length > 1 && r.bars[0].t !== out[0].t) out = out.slice(1)
  if (!endTime) {
    const last = out[out.length - 1], m = new Map<number, Bar>()
    for (const b of r.bars) if (b.t >= last.t) m.set(b.t, { ...b })
    tails.set(`${symbol}|${iv}`, m)
  }
  return { bars: out, ok: true }
}
/** 原生线来了一根：并出这个自定义周期的当前格 */
export function customTick(symbol: string, iv: string, baseBar: Bar): Bar {
  const ms = IV_MS[iv], t = Math.floor(baseBar.t / ms) * ms, key = `${symbol}|${iv}`
  let m = tails.get(key)
  if (!m) { m = new Map(); tails.set(key, m) }
  for (const k of m.keys()) if (k < t) m.delete(k)
  m.set(baseBar.t, { ...baseBar })
  return aggregate([...m.values()].sort((a, b) => a.t - b.t), ms)[0]
}
