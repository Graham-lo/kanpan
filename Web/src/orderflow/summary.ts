/* Hkline Web · 主力订单流 · 底部抽屉「大单列表」的摘要算法（2026-10-08，替掉逐单明细表）
 *
 * 为什么：逐单一行一行列出来（几千行、带筛选排序）没人真去翻，用户要的是「这根 / 这一小时 / 今天大单到底是买多还是卖多、
 * 落在哪几个价、离最近的墙多远」。这里只放纯算法（不碰 DOM），抽屉 drawer.ts 拿结果画图，测试直接测这里。
 *
 * 规则：
 *   · 三个窗口：本根（当前周期正在走的那根）、近 1 小时（滚动）、今日（北京时间 0 点起）。金额来自 tradeFlow 的分钟桶
 *     （浏览器记的 + 服务端历史，取法同 bigTags.sumBig）；笔数只有整段都来自浏览器时才有。
 *   · 现货 / 合约、三家的占比只拿浏览器近 1 小时记到的大单算（服务端历史没有这几项），一笔都没有就不画。
 *   · 价位：近 1 小时浏览器记到的大单按订单流的细步长分桶，买、卖各取金额最大的三档。
 *   · 最近的墙：模型里挂着（live）的大单，同一价位桶几家合计；卖墙取现价以上最近的一档、买墙取现价以下最近的一档，
 *     挂了多久从这一档最早出现的那一单算。
 * 只聚合、门槛过滤、展示，不做判定。
 */
import type { SymbolFlow } from '../chart/tradeFlow'
import type { BigOrder } from './types'
import { sumBig } from './bigTags'

export const HOUR = 3_600_000
export const DAY = 86_400_000
const TZ8 = 8 * HOUR

/** 北京时间当天 0 点（毫秒） */
export function dayStart8(now: number): number { return Math.floor((now + TZ8) / DAY) * DAY - TZ8 }

export interface WinSum { bb: number; bs: number; bn: number | null; sn: number | null; has: boolean }

/** [a, b) 的大单合计；fine = 秒级周期的「本根」走秒桶 */
export function windowSum(f: SymbolFlow, a: number, b: number, now: number, fine = false): WinSum {
  const { c, exact, has } = sumBig(f, a, b, now, fine)
  return { bb: c.bb, bs: c.bs, bn: exact ? c.bn : null, sn: exact ? c.sn : null, has }
}

export interface Windows { bar: WinSum; hour: WinSum; today: WinSum }
/** 三个窗口；barT0 / barT1 = 当前这根的起止 */
export function windows(f: SymbolFlow, barT0: number, barT1: number, now: number): Windows {
  return {
    bar: windowSum(f, barT0, barT1, now, barT1 - barT0 < 60_000),
    hour: windowSum(f, now - HOUR, now + 1, now),
    today: windowSum(f, dayStart8(now), now + 1, now),
  }
}

export interface Shares { total: number; spot: number; contract: number; ex: [number, number, number] }
/** 近 1 小时浏览器记到的大单：现货 / 合约、三家各占多少（只用本机的分钟桶）。一笔都没有给 null */
export function liveShares(f: SymbolFlow, now: number): Shares | null {
  const from = Math.floor((now - HOUR) / 60_000) * 60_000
  let total = 0, spot = 0
  const ex: [number, number, number] = [0, 0, 0]
  for (const [k, c] of f.min) {
    if (k < from) continue
    if (k > now) break
    total += c.bb + c.bs; spot += c.bsb + c.bss
    ex[0] += c.bx[0]; ex[1] += c.bx[1]; ex[2] += c.bx[2]
  }
  return total > 0 ? { total, spot, contract: Math.max(0, total - spot), ex } : null
}

export interface Level { price: number; usd: number; n: number }
/** 近 1 小时的大单按价位桶并，买 / 卖各取金额最大的 k 档 */
export function priceLevels(f: SymbolFlow, step: number, now: number, k = 3): { buy: Level[]; sell: Level[] } {
  const buy = new Map<number, Level>(), sell = new Map<number, Level>()
  if (!(step > 0)) return { buy: [], sell: [] }
  const from = now - HOUR
  for (let i = f.prints.length - 1; i >= 0; i--) {
    const p = f.prints[i]
    if (p.t < from) break
    const b = Math.floor(p.price / step + 1e-9) * step
    const m = p.buy ? buy : sell
    const l = m.get(b)
    if (l) { l.usd += p.usd; l.n++ } else m.set(b, { price: b, usd: p.usd, n: 1 })
  }
  const top = (m: Map<number, Level>): Level[] => [...m.values()].sort((a, b) => b.usd - a.usd).slice(0, k)
  return { buy: top(buy), sell: top(sell) }
}

export interface Wall { price: number; usd: number; since: number; n: number; first: BigOrder }
/** 现价上方最近的卖墙、下方最近的买墙（只看还挂着的；同一价位桶几家合计） */
export function nearestWalls(orders: readonly BigOrder[], mid: number): { ask: Wall | null; bid: Wall | null } {
  const ask = new Map<number, Wall>(), bid = new Map<number, Wall>()
  for (const o of orders) {
    if (o.status !== 'live') continue
    const isAsk = o.side === 'ask'
    if (isAsk ? o.price < mid : o.price > mid) continue
    const m = isAsk ? ask : bid
    const w = m.get(o.bucket)
    if (w) { w.usd += o.notional; if (o.firstSeenMs < w.since) { w.since = o.firstSeenMs; w.first = o } w.n++; if (isAsk ? o.price < w.price : o.price > w.price) w.price = o.price }
    else m.set(o.bucket, { price: o.price, usd: o.notional, since: o.firstSeenMs, n: 1, first: o })
  }
  const near = (m: Map<number, Wall>, up: boolean): Wall | null => {
    let best: Wall | null = null
    for (const w of m.values()) if (!best || (up ? w.price < best.price : w.price > best.price)) best = w
    return best
  }
  return { ask: near(ask, true), bid: near(bid, false) }
}
