/* Hkline Web · 多交易所 · K 线周期的对齐与并线（各家共用，纯函数）
 *
 * 网页的周期全按 UTC 对齐（和币安一样）：分钟 / 小时 / 日线从 1970 起整除；周线从周一 00:00 UTC 起
 * （1970-01-05 是周一）；月线按自然月。某一家没有的周期（OKX / Bybit 没有 8 时、Hyperliquid 没有 6 时、
 * Coinbase 没有 3 分 / 8 时 / 12 时 / 周 / 月）由注册表 marketKlines 拿原生档并出来。
 */
import type { Bar } from '../chart/calc'
import { IV_MS } from '../util/format'

/** 1970-01-05（周一）相对纪元的偏移 */
export const WEEK_OFFSET = 4 * 864e5

/** 这根（开盘 t）落在周期 iv 的哪一格（格头时刻） */
export function bucketOf(t: number, iv: string): number {
  if (iv === '1M') { const d = new Date(t); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1) }
  const ms = IV_MS[iv]
  if (iv === '1w') return Math.floor((t - WEEK_OFFSET) / ms) * ms + WEEK_OFFSET
  return Math.floor(t / ms) * ms
}
/** 这一格的下一格格头 */
export function nextBucket(t: number, iv: string): number {
  if (iv === '1M') { const d = new Date(t); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1) }
  return bucketOf(t, iv) + IV_MS[iv]
}

/** 原生档并成 iv（输入升序）：开取第一根、收取最后一根、高低取极值、量相加；格头按 bucketOf */
export function aggregateBars(bars: readonly Bar[], iv: string): Bar[] {
  const out: Bar[] = []
  for (const b of bars) {
    const t = bucketOf(b.t, iv)
    const last = out[out.length - 1]
    if (last && last.t === t) {
      last.h = Math.max(last.h, b.h); last.l = Math.min(last.l, b.l); last.c = b.c; last.v += b.v
      if (b.tb != null) last.tb = (last.tb ?? 0) + b.tb
      if (b.bv != null) last.bv = (last.bv ?? 0) + b.bv
    } else {
      const x: Bar = { t, o: b.o, h: b.h, l: b.l, c: b.c, v: b.v }
      if (b.tb != null) x.tb = b.tb
      if (b.bv != null) x.bv = b.bv
      out.push(x)
    }
  }
  return out
}

/** 一格 iv 大约是几根原生档 base（月线按 31 天算，宁多取一点） */
export function ratioOf(iv: string, base: string): number {
  const ms = iv === '1M' ? 31 * 864e5 : IV_MS[iv]
  return Math.max(1, Math.ceil(ms / IV_MS[base]))
}

/** 开盘时刻最多比本机晚多久还算数（K 线开盘时刻不会在未来；本机时钟慢一点的照常用） */
const BAR_AHEAD_MS = 2 * 86_400_000
/** 一根 K 线能不能用（各家解码共用的最后一道）：开盘时刻是不在遥远未来的非负有限数；开高低收都是正的有限数——
 *  有一个不像样（缺字段、"NaN"、负价、1e400）整根丢；高低不包住开收的撑开；量 / 额不像样记 0、主动买 / 币量不像样不给。
 *  原来只看了时刻和收盘：OKX / Bybit 的开高低缺了是 NaN、负价照收，画出来一根竖到天上的针（2026-10-08 解码模糊） */
export function cleanBar(b: Bar): Bar | null {
  const { t, o, h, l, c } = b
  if (!Number.isFinite(t) || t < 0 || t > Date.now() + BAR_AHEAD_MS) return null
  if (!(o > 0 && h > 0 && l > 0 && c > 0) || !Number.isFinite(o + h + l + c)) return null
  const x: Bar = { ...b, h: Math.max(h, o, c), l: Math.min(l, o, c), v: Number.isFinite(b.v) && b.v >= 0 ? b.v : 0 }
  if (x.bv != null && !(Number.isFinite(x.bv) && x.bv >= 0)) delete x.bv
  if (x.tb != null && !(Number.isFinite(x.tb) && x.tb >= 0)) delete x.tb
  return x
}

/** 交易所给的行过 cleanBar、按开盘时间去重、升序 */
export function sortBars(bars: Bar[]): Bar[] {
  const m = new Map<number, Bar>()
  for (const b of bars) { const x = cleanBar(b); if (x) m.set(x.t, x) }
  return [...m.values()].sort((a, b) => a.t - b.t)
}
