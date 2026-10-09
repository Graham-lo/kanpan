/* 盘口洞察：真实大额成交价区、主图所属簿、同所分钟价动；缺数据时保留未知。 */
import { parseKey } from '../../../market/identity'
import { baseOfSymbol } from '../../../orderflow/settings'
import type { BigOrder, Product } from '../../../orderflow/types'
import type { Bar } from '../../../chart/calc'
import type { LiqRow } from '../../../orderflow/liquidation'
import { sumLiq } from '../../../orderflow/liquidation'
import { orderFlowAmount as amount } from '../../chart/renderer.orderflow'
import { INSIGHT as L } from './insightLabels'

export interface InsightSource { venueID: string; exchange: string; product: Product; buyUsd: number; sellUsd: number }
export interface InsightZone extends InsightSource { low: number; high: number; recentBuyUsd: number; recentSellUsd: number; firstMs: number; lastMs: number }
export interface InsightBody {
  base: string; generatedAtMs: number; dayStartMs: number; tracked: boolean; coverageSinceMs: number | null; lastTradeMs: number | null; bigUsd: number | null
  windows: { minutes: 5 | 15 | 60; sources: InsightSource[] }[]; zones: InsightZone[]
}
export type InsightStatus = 'loading' | 'ready' | 'error'
export interface InsightRow { id: string; title: string; value?: string; detail: string; note?: string; time?: number; price?: number; tone?: 'up' | 'down'; main?: boolean }
export interface InsightSection { id: string; title: string; subtitle?: string; empty?: string; rows: InsightRow[]; evidence: string }
export interface InsightView { status: string; note: string; sections: InsightSection[] }
const M = 60_000, DAY = 86_400_000
export const beijingDayStart = (now: number): number => Math.floor((now + 480 * M) / DAY) * DAY - 480 * M
export const insightTime = (ms: number): string => new Date(ms + 480 * M).toISOString().slice(11, 16)
const product = (p: Product): string => p === 'spot' ? '现货' : p === 'coinPerp' ? '币本位' : '永续'
const num = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)
const record = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object'
const validSource = (v: unknown): v is InsightSource => record(v) && typeof v.venueID === 'string' && typeof v.exchange === 'string'
  && ['spot', 'usdtPerp', 'coinPerp'].includes(String(v.product)) && num(v.buyUsd) && v.buyUsd >= 0 && num(v.sellUsd) && v.sellUsd >= 0 && Number.isFinite(v.buyUsd + v.sellUsd)
export function parseInsights(raw: unknown, base: string): InsightBody | null {
  if (!record(raw) || raw.base !== base || !num(raw.generatedAtMs) || !num(raw.dayStartMs) || typeof raw.tracked !== 'boolean'
    || !Array.isArray(raw.windows) || !Array.isArray(raw.zones)) return null
  for (const k of ['coverageSinceMs', 'lastTradeMs', 'bigUsd']) if (raw[k] !== null && (!num(raw[k]) || (raw[k] as number) < 0)) return null
  if (raw.generatedAtMs <= 0 || raw.dayStartMs !== beijingDayStart(raw.generatedAtMs)) return null
  for (const k of ['coverageSinceMs', 'lastTradeMs']) if (num(raw[k]) && (raw[k] as number) > raw.generatedAtMs) return null
  // A malformed source is a coverage failure, never an implicit zero.
  if (raw.windows.some(w => !record(w) || ![5, 15, 60].includes(w.minutes as number) || !Array.isArray(w.sources) || !w.sources.every(validSource))) return null
  if (raw.zones.some(z => !validSource(z) || !record(z) || ![z.low, z.high, z.recentBuyUsd, z.recentSellUsd, z.firstMs, z.lastMs].every(num)
    || (z.low as number) <= 0 || (z.high as number) < (z.low as number) || (z.recentBuyUsd as number) < 0 || (z.recentSellUsd as number) < 0
    || (z.firstMs as number) < (raw.dayStartMs as number) || (z.lastMs as number) > (raw.generatedAtMs as number) + 3000 || (z.lastMs as number) < (z.firstMs as number)
    || !Number.isFinite((z.recentBuyUsd as number) + (z.recentSellUsd as number)))) return null
  return raw as unknown as InsightBody
}

/** 精确匹配交易所、产品及规范合约，不把同交易所其他报价币混成主图。 */
export function matchesChart(venueID: string, symbol: string): boolean {
  const k = parseKey(symbol), [venue, p, ...instrument] = venueID.split(':')
  const expected = k.market === 'spot' || /-USD$/.test(k.symbol) ? 'spot' : k.market === 'coin_m' ? 'coinPerp' : 'usdtPerp'
  const norm = (s: string): string => s.toUpperCase().replace(/-SWAP$/, '').replace(/[-_]/g, '')
  return venue === k.venue && p === expected && norm(instrument.join(':')) === norm(k.symbol)
}
export function priceReaction(bars: readonly Bar[], from: number, to: number): number | null {
  const rows = bars.filter(b => b.t >= from && b.t + M <= to).sort((a, b) => a.t - b.t)
  if (rows.length < 2 || rows[0].t !== from || rows.at(-1)!.t + M !== to) return null
  if (rows.some(b => ![b.t, b.o, b.h, b.l, b.c].every(Number.isFinite) || Math.min(b.o, b.h, b.l, b.c) <= 0
    || b.h < Math.max(b.o, b.c) || b.l > Math.min(b.o, b.c) || b.l > b.h)) return null
  for (let i = 1; i < rows.length; i++) if (rows[i].t - rows[i - 1].t !== M) return null
  return rows[0].o > 0 && rows.at(-1)!.c > 0 ? (rows.at(-1)!.c / rows[0].o - 1) * 100 : null
}
export function flowObservation(buy: number, sell: number, move: number | null): string {
  if (move == null) return L.noPrices
  const total = buy + sell
  if (!(total > 0)) return '覆盖时段内未记录到大额主动成交'
  const share = buy / total
  if (share < .6 && share > .4) return '主动买卖相对均衡'
  const side = share >= .6 ? '买入' : '卖出', direction = move > 0 ? '上移' : '下移'
  if (Math.abs(move) < .05) return `主动${side}偏多，价格暂未推进`
  return (share >= .6 ? move > 0 : move < 0) ? `主动${side}伴随价格${direction}` : `主动${side}偏多，价格仍${direction}`
}
export function nearestInsightOrders(orders: readonly BigOrder[], symbol: string, mid: number): BigOrder[] {
  if (!(mid > 0)) return []
  const own = orders.filter(o => o.status === 'live' && o.notional > 0 && matchesChart(o.venueID, symbol))
  return (['ask', 'bid'] as const).flatMap(side => own.filter(o => o.side === side && (side === 'ask' ? o.price >= mid : o.price <= mid))
    .sort((a, b) => Math.abs(a.price - mid) - Math.abs(b.price - mid) || b.notional - a.notional).slice(0, 1))
}
export function shouldOpenInsightSwipe(dx: number, dy: number, ms: number, startX: number, width: number): boolean {
  return startX >= 24 && startX <= width - 24 && dy <= -48 && Math.abs(dy) > Math.abs(dx) * 1.8 && ms <= 900
}

export interface InsightInput {
  symbol: string; now: number; mid: number; dec: number; orders: readonly BigOrder[]; snapshotReady: boolean
  body: InsightBody | null; state: InsightStatus; prices: readonly Bar[]; stale: boolean
  liq: { tracked: boolean | null; rows: Map<number, LiqRow>; updatedAtMs?: number; failed?: boolean } | null
}
export function buildInsights(i: InsightInput): InsightView {
  const { body: b, now, symbol } = i, scale = baseOfSymbol(symbol).scale
  const fmtPrice = (p: number): string => p.toFixed(i.dec)
  const sections: InsightSection[] = []
  const wallRows = (i.snapshotReady ? nearestInsightOrders(i.orders, symbol, i.mid) : []).map(o => ({
    id: `${o.venueID}:${o.side}:${o.bucket}:${o.firstSeenMs}`, title: `${o.side === 'ask' ? '上方卖单' : '下方买单'} · ${fmtPrice(o.price)}`,
    value: `$${amount(o.notional)}`, detail: `距现价 ${i.mid > 0 ? ((o.price / i.mid - 1) * 100).toFixed(2) : '—'}% · 持续 ${Math.max(0, Math.floor((now - o.firstSeenMs) / M))} 分钟`,
    note: `已匹配成交 $${amount(o.filledNotional)} · ${o.exchange} ${product(o.product)}`, time: now, price: o.price, tone: o.side === 'ask' ? 'down' as const : 'up' as const, main: true,
  }))
  sections.push({ id: 'walls', title: L.walls, subtitle: L.mainVenue, empty: i.snapshotReady ? L.noWall : '当前盘口仍在获取', rows: wallRows,
    evidence: '仅取主图所属品种、现价上下最近的有效挂单。金额是剩余名义额；已匹配成交是同一挂单生命周期内观测到的成交，不代表所有成交。挂单可以变化，不能单凭挂单判断支撑或压力。' })
  const currentDay = b?.dayStartMs === beijingDayStart(now)
  const covered = !!b?.tracked && currentDay && b.coverageSinceMs != null
  const fresh = !!b && now >= b.generatedAtMs - 3000 && now - b.generatedAtMs <= 90_000 && i.state !== 'error' && !i.stale
  const zRows = covered ? [...b!.zones].sort((a, z) => z.buyUsd + z.sellUsd - a.buyUsd - a.sellUsd).slice(0, 3).map(z => ({
    id: `${z.venueID}:${z.low}:${z.high}`, title: `${fmtPrice(z.low * scale)}${z.high !== z.low ? `–${fmtPrice(z.high * scale)}` : ''}`, value: `$${amount(z.buyUsd + z.sellUsd)}`,
    detail: `${z.exchange} ${product(z.product)} · 主动买 ${z.buyUsd + z.sellUsd > 0 ? Math.round(z.buyUsd / (z.buyUsd + z.sellUsd) * 100) : '—'}%`,
    note: `${fresh ? '' : `截至 ${insightTime(b!.generatedAtMs)} 的`}近 15 分钟 $${amount(z.recentBuyUsd + z.recentSellUsd)} · ${insightTime(z.firstMs)}–${insightTime(z.lastMs)}`, time: z.lastMs, price: (z.low + z.high) / 2 * scale, main: matchesChart(z.venueID, symbol),
  })) : []
  sections.push({ id: 'zones', title: L.zones, subtitle: covered ? b!.coverageSinceMs! > b!.dayStartMs ? `今日 · 部分覆盖 · 从 ${insightTime(b!.coverageSinceMs!)} 起` : L.today : L.noCoverage,
    rows: zRows, empty: i.state === 'loading' ? L.loading : i.state === 'error' ? L.unavailable : !b?.tracked ? L.untracked : covered ? L.noZones : L.noCoverage,
    evidence: `${L.coverage}按真实成交价分交易所、产品聚合；金额达到当时大单门槛才入账。${b?.bigUsd != null ? `当前基准门槛 $${amount(b.bigUsd)}。` : ''}${b ? `更新于 ${insightTime(b.generatedAtMs)}。` : ''}` })
  let status: string = i.state === 'loading' ? L.loading : !fresh ? i.state === 'error' ? L.unavailable : L.stale : L.inspect
  const currentWindowEnd = Math.floor((now - 3000) / M) * M
  const windowEnd = b ? Math.floor((b.generatedAtMs - 3000) / M) * M : currentWindowEnd
  const flowRows: InsightRow[] = ([5, 15] as const).map(minutes => {
    const from = windowEnd - minutes * M, source = b?.windows.find(w => w.minutes === minutes)?.sources.find(s => matchesChart(s.venueID, symbol))
    const has = fresh && covered && b!.coverageSinceMs! <= from && !!source
    const move = has ? priceReaction(i.prices, from, windowEnd) : null
    const observation = has ? flowObservation(source!.buyUsd, source!.sellUsd, move) : L.noFlow
    if (minutes === 15 && has && move != null) status = observation
    return { id: `flow-${minutes}`, title: `近 ${minutes} 分钟`, value: has && move != null ? `${move >= 0 ? '+' : ''}${move.toFixed(2)}%` : undefined,
      detail: observation, note: has ? `主动买 $${amount(source!.buyUsd)} · 主动卖 $${amount(source!.sellUsd)} · ${insightTime(from)}–${insightTime(windowEnd)}` : undefined }
  })
  const observed = fresh ? b?.windows.find(w => w.minutes === 15)?.sources ?? [] : []
  for (const spot of [true, false]) {
    const source = observed.filter(s => (s.product === 'spot') === spot), buy = source.reduce((n, s) => n + s.buyUsd, 0), sell = source.reduce((n, s) => n + s.sellUsd, 0)
    if (buy + sell > 0) flowRows.push({ id: spot ? 'observed-spot' : 'observed-contract', title: `已观测${spot ? '现货' : '合约'}大单 · 近 15 分钟`, value: undefined,
      detail: `主动差 ${buy >= sell ? '+' : '−'}$${amount(Math.abs(buy - sell))}`, note: `多所聚合 · 主动买 $${amount(buy)} / 主动卖 $${amount(sell)}；不代表全部市场参与` })
  }
  sections.push({ id: 'activity', title: L.activity, subtitle: L.mainVenue, rows: flowRows, evidence: L.flowEvidence })
  if (parseKey(symbol).market !== 'spot' && !/-USD$/.test(parseKey(symbol).symbol)) {
    const usable = i.liq?.tracked === true && !i.liq.failed && !!i.liq.updatedAtMs && now - i.liq.updatedAtMs < 90_000
    const rows = [...(i.liq?.rows.values() ?? [])]
    // 爆仓有独立刷新时钟；价区接口失败后不能把新爆仓放进旧窗口还称“近15分钟”。
    const liquidationEnd = fresh ? windowEnd : currentWindowEnd
    const liqRows = ([5, 15] as const).map(minutes => {
      const s = usable ? sumLiq(rows, liquidationEnd - minutes * M, liquidationEnd) : null
      const after = s?.max ? s.max[0] + M : null
      const move = after != null ? priceReaction(i.prices, after, liquidationEnd) : null
      return { id: `liq-${minutes}`, title: `近 ${minutes} 分钟`, detail: s ? `多头爆仓 $${amount(s.long)} · 空头爆仓 $${amount(s.short)}` : L.noLiq,
        note: s ? s.long + s.short === 0 ? '该时段未观测到爆仓' : `${s.long > s.short ? '多头' : s.short > s.long ? '空头' : '多空'}被动退出${s.long === s.short ? '相近' : '偏多'}；${move == null ? '后续分钟行情不足，继续观察' : `最大爆仓分钟结束后 ${insightTime(after!)}–${insightTime(liquidationEnd)}，主图价格 ${move >= 0 ? '+' : ''}${move.toFixed(2)}%`}` : undefined }
    })
    sections.push({ id: 'liquidation', title: L.liquidation, subtitle: L.allVenues, rows: liqRows, evidence: L.liqEvidence })
  }
  const events = i.orders.filter(o => o.endMs != null && o.endMs >= now - 15 * M && o.endMs <= now).sort((a, z) => z.endMs! - a.endMs!).slice(0, 4).map(o => ({
    id: `${o.venueID}:${o.firstSeenMs}:${o.endMs}`, title: `${o.status === 'filled' ? '挂单被成交消耗' : o.status === 'cancelled' ? '挂单明显减少' : '挂单状态未知'} · ${fmtPrice(o.price)}`,
    detail: `${o.exchange} ${product(o.product)} · ${o.side === 'bid' ? '买单' : '卖单'} · ${insightTime(o.endMs!)}`, note: o.status === 'lost' ? '连接中断，不能判断撤单' : `已匹配成交 $${amount(o.filledNotional)}`, time: o.endMs!, price: o.price, main: matchesChart(o.venueID, symbol),
  }))
  sections.push({ id: 'events', title: L.events, rows: events, empty: L.noEvents, evidence: '来自已观测挂单的生命周期。连接中断或失联记为未知；挂单减少不等于诱骗，成交消耗不保证后续方向。' })
  return { status, note: !fresh && b ? `最近更新 ${insightTime(b.generatedAtMs)}` : '价格判断只用当前交易所；跨所成交与爆仓分别展示', sections }
}

/** 只在洞察可见时轮询；关闭、切币、后台取消，序号挡住忽略 abort 的旧响应。 */
export class InsightPoller {
  private key = ''; private active = false; private generation = 0; private timer: ReturnType<typeof setTimeout> | null = null; private abort: AbortController | null = null
  constructor(private fetcher: (base: string, signal: AbortSignal) => Promise<unknown>, private update: (body: InsightBody | null, state: InsightStatus) => void) {}
  start(base: string): void { if (this.active && this.key === base) return; this.stop(); this.active = true; this.key = base; this.update(null, 'loading'); void this.pull(this.generation) }
  stop(): void { this.active = false; this.generation++; this.abort?.abort(); this.abort = null; if (this.timer) clearTimeout(this.timer); this.timer = null }
  private async pull(g: number): Promise<void> {
    if (!this.active || g !== this.generation) return
    const ctl = this.abort = new AbortController(), base = this.key
    const timeout = setTimeout(() => ctl.abort(), 8000)
    try { const b = parseInsights(await this.fetcher(base, ctl.signal), base); if (!b) throw new Error('invalid insights'); if (g === this.generation && this.active) this.update(b, 'ready') }
    catch { if (g === this.generation && this.active) this.update(null, 'error') }
    finally { clearTimeout(timeout); if (g === this.generation && this.active) this.timer = setTimeout(() => void this.pull(g), 30_000) }
  }
}
