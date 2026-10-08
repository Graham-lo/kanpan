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

/** 别家（不是币安的）品种表的状态：live 拉到过 / false 这一次没拉到（error 写为什么）/ null 还没拉 */
export interface VenueState { live: boolean | null; error: string; at: number }

export const S = {
  /** 所有交易所的品种（键 = 身份键，见 market/identity.ts）；币安与美元指数由 loadUniverse 给，别家由 loadVenue 懒拉 */
  symbols: new Map<string, Sym>(),
  /** 别家品种表的状态（按 venue 键）；币安的状态是下面的 live / error / limited */
  venues: {} as Record<string, VenueState>,
  /** 币安全市场表是否已从交易所拉到 */
  live: null as boolean | null,
  error: '' as string,
  /** 全市场表没取到是因为币安限流（冷却完会自动重试），不是网络不通 */
  limited: false,
  /** 全市场表（含 premiumIndex 整表的资金费）上一次取到的本机时刻；侧栏资金费列一分钟一刷，刚取过就不再整表重取 */
  universeAt: 0,
  wsState: 'idle' as WsState,
  route: 'direct' as Route,
  lastMsg: 0,
}

const listeners = new Set<(e: MarketEvent) => void>()
export function emit(e: MarketEvent): void { listeners.forEach(fn => { try { fn(e) } catch (err) { console.error(err) } }) }
export function on(fn: (e: MarketEvent) => void): () => void { listeners.add(fn); return () => { listeners.delete(fn) } }

/** 推送连接状态由几部分合成（币安连接池、别家各一份）：有一部分断着 = 断；全开着 = 开；全没订 = idle；其余在连 */
const wsParts = new Map<string, WsState>()
export function setWsPart(part: string, st: WsState): void {
  if (st === 'idle') wsParts.delete(part); else wsParts.set(part, st)
  const v = [...wsParts.values()]
  const next: WsState = !v.length ? 'idle' : v.includes('closed') ? 'closed' : v.every(x => x === 'open') ? 'open' : 'connecting'
  if (S.wsState !== next) { S.wsState = next; emit({ type: 'ws' }) }
}
