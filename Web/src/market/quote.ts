/* Hkline Web · 别家的行情落进品种表（REST 整表行情与推送共用一份规矩）
 *
 * 和币安那条（rest.ts / stream.ts）同一条规矩：按交易所时间拒旧——价格一组看 pxAt、成交额看 statAt、
 * 标记价 / 指数价 / 费率看 markAt；晚到的旧数不覆盖手里更新的。没有的字段不动（Bybit tickers 的 delta、
 * OKX 的 mark-price 只带一半）。
 */
import { AHEAD_MS } from '../venues/common'
import type { Quote } from '../venues/common'
import type { Sym } from './symbols'

/** 交易所时间不像样（远在未来、不是正数）的当本机现在；手里已经记着这种时间的（以前写坏的一帧留下的）清掉。
 *  不然一帧写坏的时间戳之后，这只品种所有正常的行情都「比它旧」被拒，价格就此冻住（2026-10-08 解码模糊） */
function sane(s: Sym, at: number, now = Date.now()): number {
  const lim = now + AHEAD_MS
  if ((s.pxAt ?? 0) > lim) s.pxAt = 0
  if ((s.statAt ?? 0) > lim) s.statAt = 0
  if ((s.markAt ?? 0) > lim) s.markAt = 0
  return Number.isFinite(at) && at > 0 && at <= lim ? at : now
}

/** 一份行情落进这一行；返回价格方向（+1 / −1 / 0），价格这组被拒旧或没给价也回 0 */
export function applyQuote(s: Sym, q: Quote): number {
  const at = sane(s, q.at)
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
