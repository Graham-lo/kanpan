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
function onTrade(tr: Trade): void {
  const t = Math.floor(tr.t / 1e3) * 1e3, quote = tr.price * tr.qty
  let arr = secs.get(tr.symbol)
  if (!arr) { arr = []; secs.set(tr.symbol, arr) }
  const last = arr[arr.length - 1]
  if (last && last.t === t) {
    last.h = Math.max(last.h, tr.price); last.l = Math.min(last.l, tr.price); last.c = tr.price
    last.v += quote; last.bv = (last.bv ?? 0) + tr.qty; if (!tr.sell) last.tb = (last.tb ?? 0) + quote
  } else if (!last || t > last.t) {
    arr.push({ t, o: tr.price, h: tr.price, l: tr.price, c: tr.price, v: quote, bv: tr.qty, tb: tr.sell ? 0 : quote })
    if (arr.length > KEEP_1S * 1.1) arr.splice(0, arr.length - KEEP_1S)
  } else return // 乱序的旧成交不回改
  secListeners.forEach(f => { try { f(tr.symbol) } catch (e) { console.error(e) } })
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
  const a = secs.get(symbol); if (!a?.length) return null
  const ms = IV_MS[iv], t = Math.floor(a[a.length - 1].t / ms) * ms
  let k = a.length - 1
  while (k > 0 && a[k - 1].t >= t) k--
  return aggregate(a.slice(k), ms)[0] ?? null
}

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
