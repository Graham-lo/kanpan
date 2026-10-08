/* Hkline Web · 别家的行情落进品种表（REST 整表行情与推送共用一份规矩）
 *
 * 和币安那条（rest.ts / stream.ts）同一条规矩：按交易所时间拒旧——价格一组看 pxAt、成交额看 statAt、
 * 标记价 / 指数价 / 费率看 markAt；晚到的旧数不覆盖手里更新的。没有的字段不动（Bybit tickers 的 delta、
 * OKX 的 mark-price 只带一半）。
 */
import type { Quote } from '../venues/common'
import type { Sym } from './symbols'

/** 一份行情落进这一行；返回价格方向（+1 / −1 / 0），价格这组被拒旧或没给价也回 0 */
export function applyQuote(s: Sym, q: Quote): number {
  const at = q.at
  let dir = 0
  if (q.price != null && !(at < (s.pxAt ?? 0))) {
    const prev = s.price
    s.price = q.price; s.pxAt = at
    if (q.open != null) s.open = q.open
    if (q.hi != null) s.hi = q.hi
    if (q.lo != null) s.lo = q.lo
    if (q.pct != null) s.pct = q.pct
    else if (s.open) s.pct = (q.price / s.open - 1) * 100
    if (q.chg != null) s.chg = q.chg
    else if (s.open) s.chg = q.price - s.open
    if (s.hi != null && q.price > s.hi) s.hi = q.price
    if (s.lo != null && q.price < s.lo) s.lo = q.price
    dir = prev == null ? 0 : Math.sign(q.price - prev)
  }
  if ((q.vol != null || q.count != null) && !(at < (s.statAt ?? 0))) {
    if (q.vol != null) s.vol = q.vol
    if (q.count != null) s.count = q.count
    s.statAt = at
  }
  if ((q.mark != null || q.index != null || q.fr !== undefined || q.nextFunding !== undefined || q.oi != null) && !(at < (s.markAt ?? 0))) {
    if (q.mark != null) s.mark = q.mark
    if (q.index != null) s.index = q.index
    if (q.fr !== undefined) s.fr = q.fr
    if (q.nextFunding !== undefined) s.nextFunding = q.nextFunding
    if (q.oi != null) s.oi = q.oi
    s.markAt = at
  }
  return dir
}
