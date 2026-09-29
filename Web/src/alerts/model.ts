/* Hkline Web · 提醒模块（表与触发）
 *
 * st.alerts 的增删改、画线提醒对账、逐笔判定与「响一次就结束」。形状与纯函数在 shape.ts。
 * 这一层不碰 DOM：页面（pages/chart.ts）订阅 onAlertsChange 去刷新图与侧栏，订阅 onAlertFired 去弹通知。
 */
import { save, st } from '../app/store'
import type { Drawing } from '../chart/chart'
import { baseOf, cleanWebhook, drawingCanAlert, drawingIdOf, drawingLines, makeDrawingAlert, makePriceAlert, priceLabel, priceTitle, touchedBetween, type Alert } from './shape'
export * from './shape'

// ------------------------------------------------------------ 表（st.alerts）
const listeners = new Set<() => void>()
/** 提醒表变了（新建、删除、触发、拖动）就通知 */
export function onAlertsChange(fn: () => void): () => void { listeners.add(fn); return () => { listeners.delete(fn) } }
function changed(): void { save(); listeners.forEach(f => { try { f() } catch (e) { console.error(e) } }) }

/** 还在等的（触发过的、暂停的不展示） */
export const activeAlerts = (symbol?: string): Alert[] => st.alerts.filter(a => a.status === 'active' && (!symbol || a.symbol === symbol))

/** 行情层告诉提醒模块「这只品种现在多少」，没有就不建 */
let quote: (symbol: string) => { price: number | null; dec?: number } = () => ({ price: null })
export function setQuoteSource(fn: typeof quote): void { quote = fn }

/** 在价位 p 建一条价格提醒（图上拖价格轴、订单流梯子都走这里） */
export function createAlertAt(symbol: string, price: number, opts: { webhook?: string | null } = {}): Alert | null {
  if (!(price > 0) || !symbol) return null
  const q = quote(symbol)
  const a = makePriceAlert(symbol, price, q.price, { dec: q.dec, webhook: opts.webhook })
  st.alerts.push(a); changed()
  return a
}
export function addAlert(a: Alert): void { st.alerts.push(a); changed() }
export function deleteAlert(id: string): void {
  const n = st.alerts.length
  st.alerts = st.alerts.filter(a => a.id !== id)
  if (st.alerts.length !== n) changed()
}
/** 拖动一条价格提醒：换价位、重新从现在算起（标题跟着改） */
export function moveAlert(id: string, price: number): void {
  const a = st.alerts.find(x => x.id === id); if (!a || !(price > 0)) return
  const now = Date.now(), q = quote(a.symbol)
  if (a.kind === 'price') {
    a.lines = [{ points: [{ t: now, p: price }], extendLeft: true, extendRight: true }]
    a.title = priceTitle(a.symbol, price, q.price, q.dec)
  } else return
  a.armedAt = now
  changed()
}
export function setWebhook(id: string, url: string | null): void {
  const a = st.alerts.find(x => x.id === id); if (!a) return
  a.webhook = cleanWebhook(url); changed()
}

// ---- 画线提醒：跟着画线走
export const drawingAlertOf = (symbol: string, drawingId: string): Alert | undefined =>
  st.alerts.find(a => a.kind === 'drawing' && a.status === 'active' && a.drawingID === drawingIdOf(symbol, drawingId))
export function toggleDrawingAlert(symbol: string, d: Drawing): boolean {
  const cur = drawingAlertOf(symbol, d.id)
  if (cur) { st.alerts = st.alerts.filter(a => a !== cur); changed(); return false }
  if (!drawingCanAlert(d.type)) return false
  st.alerts.push(makeDrawingAlert(symbol, d)); changed(); return true
}
/** 画线挪动、删除之后对账：几何跟上，画线没了提醒也删 */
export function reconcileDrawingAlerts(symbol: string, drawings: Drawing[]): void {
  let dirty = false
  const byId = new Map(drawings.map(d => [drawingIdOf(symbol, d.id), d]))
  st.alerts = st.alerts.filter(a => {
    if (a.kind !== 'drawing' || a.symbol !== symbol || !a.drawingID) return true
    const d = byId.get(a.drawingID)
    if (!d) { dirty = true; return false }
    const lines = drawingLines(d)
    if (JSON.stringify(lines) !== JSON.stringify(a.lines)) { a.lines = lines; a.armedAt = Date.now(); dirty = true }
    return true
  })
  if (dirty) changed()
}
/** 第一阶段画线上的 alert 开关 → 画线提醒 */
export function migrateDrawingFlags(): void {
  let dirty = false
  for (const [symbol, ds] of Object.entries(st.drawings)) {
    for (const d of ds) {
      if (!d.alert) continue
      delete d.alert; dirty = true
      if (drawingCanAlert(d.type) && !drawingAlertOf(symbol, d.id)) st.alerts.push(makeDrawingAlert(symbol, d))
    }
  }
  if (dirty) changed()
}

// ---- 触发
export interface Fired { alert: Alert; price: number; level: number | null }
const fireHandlers = new Set<(f: Fired) => void>()
export function onAlertFired(fn: (f: Fired) => void): () => void { fireHandlers.add(fn); return () => { fireHandlers.delete(fn) } }
/** 响一次就结束：先从表里拿掉再通知，保证不会重复响 */
export function fire(a: Alert, price: number, level: number | null): void {
  if (!st.alerts.includes(a)) return
  st.alerts = st.alerts.filter(x => x !== a)
  a.status = 'fired'; a.firedAt = Date.now(); a.firedPrice = price
  changed()
  fireHandlers.forEach(f => { try { f({ alert: a, price, level }) } catch (e) { console.error(e) } })
}

/** 每只品种上一笔成交价（只记提醒创建之后看到的） */
const lastPx = new Map<string, { p: number; t: number }>()
/** 一笔新价进来：看这只品种的价格 / 画线提醒 */
export function checkPrice(symbol: string, price: number, now = Date.now()): void {
  const prev = lastPx.get(symbol)
  lastPx.set(symbol, { p: price, t: now })
  if (!prev) return
  for (const a of activeAlerts(symbol)) {
    if (prev.t < a.armedAt) continue
    const lv = touchedBetween(a, prev.p, price, now)
    if (lv != null) fire(a, price, lv)
  }
}
export function forgetPrices(): void { lastPx.clear() }

/** Webhook 那份 JSON（字段和服务端 webhook_body 一一对应） */
export function webhookBody(a: Alert, price: number, at: number, level: number | null): Record<string, unknown> {
  const time = new Date(at + 8 * 3600e3).toISOString().replace('T', ' ').slice(0, 19) + ' UTC+8'
  return {
    event: 'alert', alertId: a.id, symbol: a.symbol, market: a.market, name: baseOf(a.symbol), title: a.title,
    condition: a.condition, once: true, target: level ?? a.lines[0]?.points[0]?.p ?? null, price, firedAt: at, time,
    note: a.note || '', text: `${a.title}，现价 ${priceLabel(price)}`,
  }
}
