/* Hkline Web · 逐笔成交的旁路
 *
 * 行情层收到 aggTrade 时先交到这里，再去做「价没变就不发 ticker」那一步——
 * 秒级 K 线要每一笔都算量，价没变的那一笔也要。谁想要逐笔就 tapTrade 挂一个回调。
 */
export interface Trade {
  symbol: string
  price: number
  /** 成交量（基础币计） */
  qty: number
  /** 成交时刻（ms） */
  t: number
  /** 买方是挂单方 = 这一笔是主动卖出 */
  sell: boolean
}

const taps = new Set<(t: Trade) => void>()

export function tapTrade(fn: (t: Trade) => void): () => void { taps.add(fn); return () => { taps.delete(fn) } }

export function emitTrade(symbol: string, price: number, qty: number, t: number, buyerIsMaker: boolean): void {
  if (!taps.size || !(price > 0) || !(qty > 0)) return
  const tr: Trade = { symbol, price, qty, t, sell: buyerIsMaker }
  taps.forEach(fn => { try { fn(tr) } catch (e) { console.error(e) } })
}
