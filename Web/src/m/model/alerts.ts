/* 手机网页版 · 提醒表（照 iOS AlertStore / AlertWatcher / AlertRecordRow）
 *
 * 形状共用 Web/src/alerts/shape.ts（与手机、服务端同步的 alerts 对象一字不差）。
 * 表先存在本机 localStorage「hkline-m-alerts-v1」；等 m/app/store 加上 alerts 字段并接同步，
 * 这里的 load / persist 换成读写 st.alerts 即可，其余不动。
 *
 * 规矩：只响一次（响完就删，没有重复提醒）；手机端只建「价格达到」这一种。
 */
import { alertLevel, makePriceAlert, migrateAlert, priceLabel, touchedBetween, baseOf, type Alert } from '../../alerts/shape'
import { grouped } from './rowText'
export type { Alert } from '../../alerts/shape'

export const ALERTS_KEY = 'hkline-m-alerts-v1'

export interface KV { getItem(k: string): string | null; setItem(k: string, v: string): void }
function kv(): KV | null { try { return (globalThis as { localStorage?: KV }).localStorage ?? null } catch { return null } }

let table: Alert[] | null = null
let store: KV | null | undefined
/** 测试用：换一个存储（并清掉内存里的表） */
export function useStore(s: KV | null): void { store = s; table = null; lastPx.clear() }
const backing = (): KV | null => store === undefined ? kv() : store

function all(): Alert[] {
  if (table) return table
  let raw: unknown = []
  try { raw = JSON.parse(backing()?.getItem(ALERTS_KEY) || '[]') } catch { raw = [] }
  table = (Array.isArray(raw) ? raw : []).map(migrateAlert).filter((a): a is Alert => !!a)
  return table
}
function persist(): void { try { backing()?.setItem(ALERTS_KEY, JSON.stringify(all())) } catch { /* 满了就算了 */ } }

const listeners = new Set<() => void>()
export function onAlertsChange(fn: () => void): () => void { listeners.add(fn); return () => { listeners.delete(fn) } }
function changed(): void { persist(); listeners.forEach(f => { try { f() } catch (e) { console.error(e) } }) }

/** 还在等的（触发过的不展示），新建的在前 */
export const activeAlerts = (symbol?: string): Alert[] =>
  all().filter(a => a.status === 'active' && (!symbol || a.symbol === symbol)).sort((a, b) => b.created - a.created)
export const liveCount = (): number => activeAlerts().length
/** 有提醒挂着的品种（常驻监听要订它们的 ticker） */
export const watchedSymbols = (): string[] => [...new Set(activeAlerts().filter(a => a.kind === 'price' || a.kind === 'drawing').map(a => a.symbol))]

export function addPriceAlert(symbol: string, target: number, current: number | null, dec?: number, webhook?: string | null, now = Date.now()): Alert | null {
  if (!symbol || !(target > 0) || !isFinite(target)) return null
  const a = makePriceAlert(symbol, target, current, { now, dec, webhook })
  all().push(a); changed()
  return a
}
/** 编辑一条价格提醒（「当前提醒」里点进去改价 / 改 Webhook）：id、建立时间不变，重新从此刻起算 */
export function updatePriceAlert(id: string, target: number, current: number | null, dec?: number, webhook?: string | null, now = Date.now()): Alert | null {
  const a = all().find(x => x.id === id && x.kind === 'price' && x.status === 'active')
  if (!a || !(target > 0) || !isFinite(target)) return null
  const next = makePriceAlert(a.symbol, target, current, { now, dec, webhook })
  a.lines = next.lines; a.title = next.title; a.webhook = next.webhook; a.armedAt = now
  changed()
  return a
}
export function deleteAlert(id: string): Alert | null {
  const list = all(), i = list.findIndex(a => a.id === id)
  if (i < 0) return null
  const [gone] = list.splice(i, 1); changed()
  return gone
}
/** 撤销删除：原样放回 */
export function restoreAlert(a: Alert): void {
  if (all().some(x => x.id === a.id)) return
  all().push(a); changed()
}

// ------------------------------------------------------------ 触发
export interface Fired { alert: Alert; price: number; level: number | null }
const fireHandlers = new Set<(f: Fired) => void>()
export function onAlertFired(fn: (f: Fired) => void): () => void { fireHandlers.add(fn); return () => { fireHandlers.delete(fn) } }

/** 响一次就结束：标成已触发 → 报给人 → 从表里删掉 */
export function fire(a: Alert, price: number, level: number | null, now = Date.now()): void {
  const list = all()
  if (!list.includes(a) || a.status !== 'active') return
  a.status = 'fired'; a.firedAt = now; a.firedPrice = price
  fireHandlers.forEach(h => { try { h({ alert: a, price, level }) } catch (e) { console.error(e) } })
  table = list.filter(x => x !== a)
  changed()
}

const lastPx = new Map<string, { p: number; t: number }>()
/** 一笔新价进来：这只品种上的价格 / 画线提醒碰到了就响（提醒建之前看到的价不算） */
export function checkPrice(symbol: string, price: number | null | undefined, now = Date.now()): void {
  if (price == null || !isFinite(price) || price <= 0) return
  const prev = lastPx.get(symbol)
  lastPx.set(symbol, { p: price, t: now })
  if (!prev) return
  for (const a of activeAlerts(symbol)) {
    if (prev.t < a.armedAt) continue
    const lv = touchedBetween(a, prev.p, price, now)
    if (lv != null) fire(a, price, lv, now)
  }
}

/** Webhook 那份 JSON（字段和服务端 webhook_body 一一对应，照 PC alerts/model.ts） */
export function webhookBody(a: Alert, price: number, at: number, level: number | null): Record<string, unknown> {
  const time = new Date(at + 8 * 3600e3).toISOString().replace('T', ' ').slice(0, 19) + ' UTC+8'
  return {
    event: 'alert', alertId: a.id, symbol: a.symbol, market: a.market, name: baseOf(a.symbol), title: a.title,
    condition: a.condition, once: true, target: level ?? a.lines[0]?.points[0]?.p ?? null, price, firedAt: at, time,
    note: a.note || '', text: `${a.title}，现价 ${priceLabel(price)}`,
  }
}

// ------------------------------------------------------------ 展示（AlertListPage / AlertRecordRow）
export interface AlertGroup { symbol: string; alerts: Alert[] }
export interface AlertSection { id: 'price' | 'drawing'; title: string; groups: AlertGroup[]; count: number }

function groupBySymbol(list: Alert[]): AlertGroup[] {
  const out: AlertGroup[] = []
  const at = new Map<string, AlertGroup>()
  for (const a of list) {
    let g = at.get(a.symbol)
    if (!g) { g = { symbol: a.symbol, alerts: [] }; at.set(a.symbol, g); out.push(g) }
    g.alerts.push(a)
  }
  return out
}
/** 全部预警：分「价格」「画线」两类，各自按品种分组（组按最新一条排，组内新的在前） */
export function sections(): AlertSection[] {
  const live = activeAlerts()
  const price = live.filter(a => a.kind === 'price')
  const drawing = live.filter(a => a.kind === 'drawing')
  return [
    { id: 'price', title: '价格提醒', groups: groupBySymbol(price), count: price.length },
    { id: 'drawing', title: '画线提醒', groups: groupBySymbol(drawing), count: drawing.length },
  ]
}
/** 创建提醒页底下那张表：只列这只品种还没触发的价格提醒 */
export const records = (symbol: string): Alert[] => activeAlerts(symbol).filter(a => a.kind === 'price')

/** 行上的标题：价格提醒写价位（带千分位），画线提醒写线名 */
export function recordTitle(a: Alert, withSymbol = false): string {
  const head = withSymbol ? baseOf(a.symbol) + ' ' : ''
  if (a.kind === 'price') {
    const p = alertLevel(a)
    if (p == null) return head + '—'
    const verb = /(涨到|跌到)/.exec(a.title)?.[1] ?? '到'
    return head + verb + ' ' + grouped(priceLabel(p))
  }
  return withSymbol ? a.title : a.title.replace(new RegExp('^' + baseOf(a.symbol) + '\\s*'), '')
}
/** 目标价在现价的哪一边（行首圆点的颜色）：上方 = 涨到，下方 = 跌到 */
export function direction(a: Alert, current: number | null | undefined): 'up' | 'down' | null {
  const p = alertLevel(a)
  if (p == null || current == null || !isFinite(current)) return a.title.includes('涨到') ? 'up' : a.title.includes('跌到') ? 'down' : null
  return p >= current ? 'up' : 'down'
}
