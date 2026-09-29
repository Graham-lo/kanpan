/* 手机网页版 · 行情页的取数小件
 *
 * - 估值两项（预期净利润、营收）：market/meta.ts 只存总供应量，这里按品种单取一次 /v1/market/meta，
 *   只留 forwardEarnings / revenue（总供应量仍由 meta.ts 写进 Sym.supply）。
 * - 主力订单流数据口：照 chart/orderflow.source.ts 的 createOrderFlowPort 包 OrderFlowSource，
 *   多两件事——① setOverride：「主力订单流」门槛改完立刻生效（createOrderFlowPort 对同一品种
 *   setWanted 直接 return，换不了门槛）；② 记下最新快照的生效门槛与默认值，给门槛编辑器用。
 */
import { S, on as onMarket, wantMeta } from '../../../market'
import { OrderFlowSource } from '../../chart/orderflow.source'
import type { OrderFlowPort } from '../../chart'
import type { OrderFlowSnapshot } from '../../chart/orderflowGroup'
import type { Override } from '../../../orderflow/settings'
import type { Thresholds } from '../../../orderflow/types'

// ───────────────────────────── 估值

export interface Valuation { forwardEarnings: number | null; revenue: number | null }
const valuations = new Map<string, Valuation>()
const pending = new Map<string, Promise<Valuation | null>>()
export const valuationOf = (sym: string): Valuation | undefined => valuations.get(sym)

/** 取一次（失败两分钟后才再取）；拿到后 resolve */
export function fetchValuation(sym: string): Promise<Valuation | null> {
  const have = valuations.get(sym)
  if (have) return Promise.resolve(have)
  const p0 = pending.get(sym)
  if (p0) return p0
  wantMeta([sym])
  const url = `${import.meta.env.BASE_URL.replace(/\/web\/(m\/)?$/, '/')}v1/market/meta?symbols=${encodeURIComponent(sym)}`
  const num = (v: unknown): number | null => { const n = v == null ? NaN : +(v as number); return Number.isFinite(n) && n > 0 ? n : null }
  const p = fetch(url, { cache: 'no-store' })
    .then(r => (r.ok ? r.json() : null))
    .then((body: { data?: Record<string, { totalSupply?: unknown; forwardEarnings?: unknown; revenue?: unknown }> } | null) => {
      const row = body?.data?.[sym]
      if (!body) throw new Error('meta')
      const v: Valuation = { forwardEarnings: num(row?.forwardEarnings), revenue: num(row?.revenue) }
      const sup = num(row?.totalSupply)
      const s = S.symbols.get(sym)
      if (s && sup != null && !s.supply) s.supply = sup
      valuations.set(sym, v)
      pending.delete(sym)
      return v
    })
    .catch(() => { setTimeout(() => pending.delete(sym), 120_000); return null })
  pending.set(sym, p)
  return p
}

// ───────────────────────────── 主力订单流

export interface PagePort extends OrderFlowPort {
  setOverride(o: Override | null): void
  /** 最新快照的生效门槛 / 叠改动之前的默认门槛（还没到是 null） */
  readonly thresholds: Thresholds | null
  readonly defaults: Thresholds | null
}

export function createPagePort(push: (snap: OrderFlowSnapshot | null) => void, override: (sym: string) => Override | null): PagePort {
  let thresholds: Thresholds | null = null, defaults: Thresholds | null = null
  const src = new OrderFlowSource(snap => {
    if (snap) { thresholds = snap.thresholds; defaults = snap.defaults ?? null }
    push(snap)
  })
  let wanted: string | null = null, knewSymbol = false
  const info = (sym: string) => {
    const m = S.symbols.get(sym)
    return { known: !!m, crypto: (m?.kind ?? 'crypto') === 'crypto', turnover24h: m?.vol ?? null }
  }
  const start = (sym: string): void => {
    const i = info(sym)
    knewSymbol = i.known
    thresholds = null; defaults = null
    src.start(sym, 0, { crypto: i.crypto, turnover24h: i.turnover24h, route: S.route, override: override(sym) })
  }
  const off = onMarket(e => {
    if (!wanted) return
    if (e.type === 'ws') src.setRoute(S.route)
    else if (e.type === 'universe' && !knewSymbol && info(wanted).known) { src.stop(); start(wanted) }
  })
  return {
    setWanted(onOff, symbol) {
      const sym = symbol.toUpperCase()
      if (!onOff) { wanted = null; src.stop(); return }
      if (wanted === sym && src.current === sym) return
      wanted = sym
      start(sym)
    },
    noteView(view, series) {
      if (wanted) src.setVisible(view.from, view.to + Math.max(0, series.step))
    },
    dispose() { off(); wanted = null; src.stop() },
    setOverride(o) { if (wanted) src.setOverride(o) },
    get thresholds() { return thresholds },
    get defaults() { return defaults },
  }
}
