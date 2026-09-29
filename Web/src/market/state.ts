/* Hkline Web · 行情状态与事件 */
import type { Bar } from '../chart/calc'
import type { Sym } from './symbols'

export type WsState = 'idle' | 'connecting' | 'open' | 'closed'
export type Route = 'direct' | 'gateway'

export type MarketEvent =
  | { type: 'universe' }
  | { type: 'ticker'; symbol: string; dir: number }
  | { type: 'kline'; symbol: string; iv: string; bar: Bar }
  | { type: 'mark'; symbol: string }
  | { type: 'oi'; symbol: string; iv: string }
  | { type: 'detail'; symbol: string }
  | { type: 'meta' }
  | { type: 'ws' }

export const S = {
  symbols: new Map<string, Sym>(),
  /** 全市场表是否已从交易所拉到 */
  live: null as boolean | null,
  error: '' as string,
  wsState: 'idle' as WsState,
  route: 'direct' as Route,
  lastMsg: 0,
}

const listeners = new Set<(e: MarketEvent) => void>()
export function emit(e: MarketEvent): void { listeners.forEach(fn => { try { fn(e) } catch (err) { console.error(err) } }) }
export function on(fn: (e: MarketEvent) => void): () => void { listeners.add(fn); return () => { listeners.delete(fn) } }
