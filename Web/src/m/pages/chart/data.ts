/* 手机网页版 · 行情页的取数小件
 *
 * - 估值两项（预期净利润、营收）：从 market/meta.ts 那份 /v1/market/meta 的行里取（和总供应量同一次请求，
 *   不再自己另发一次），只留 forwardEarnings / revenue（总供应量由 meta.ts 写进 Sym.supply）。
 * - 主力订单流数据口：照 chart/orderflow.source.ts 的 createOrderFlowPort 包 OrderFlowSource，
 *   多两件事——① setOverride：「主力订单流」门槛改完立刻生效（createOrderFlowPort 对同一品种
 *   setWanted 直接 return，换不了门槛）；② 记下最新快照的生效门槛与默认值，给门槛编辑器用。
 */
import { S, on as onMarket, metaRow } from '../../../market'
import { OrderFlowSource } from '../../chart/orderflow.source'
import { stopWhenHiddenLong } from '../../../orderflow/idle'
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
  const num = (v: unknown): number | null => { const n = v == null ? NaN : +(v as number); return Number.isFinite(n) && n > 0 ? n : null }
  const p = metaRow(sym).then(row => {
    if (row === undefined) { setTimeout(() => pending.delete(sym), 120_000); return null }
    const v: Valuation = { forwardEarnings: num(row?.forwardEarnings), revenue: num(row?.revenue) }
    valuations.set(sym, v)
    pending.delete(sym)
    return v
  })
  pending.set(sym, p)
  return p
}

// ───────────────────────────── 主力订单流

export interface PagePort extends OrderFlowPort {
  setOverride(o: Override | null): void
  /** 行情页藏起来时停掉订阅（簿与成交的几条 WS、500ms 评估），记住想要的品种；resume 再按它重开 */
  suspend(): void
  resume(): void
  /** 最新快照的生效门槛 / 叠改动之前的默认门槛（还没到是 null） */
  readonly thresholds: Thresholds | null
  readonly defaults: Thresholds | null
}

export function createPagePort(push: (snap: OrderFlowSnapshot | null) => void, override: (sym: string) => Override | null, startSuspended = false): PagePort {
  let thresholds: Thresholds | null = null, defaults: Thresholds | null = null
  const src = new OrderFlowSource(snap => {
    if (snap) { thresholds = snap.thresholds; defaults = snap.defaults ?? null }
    push(snap)
  })
  let wanted: string | null = null, knewSymbol = false, suspended = startSuspended
  let seen: [number | null, number | null] | null = null
  let precise = false
  const info = (sym: string) => {
    const m = S.symbols.get(sym)
    return { known: !!m, crypto: (m?.kind ?? 'crypto') === 'crypto', turnover24h: m?.vol ?? null }
  }
  const start = (sym: string): void => {
    const i = info(sym)
    knewSymbol = i.known
    thresholds = null; defaults = null
    src.start(sym, 0, { crypto: i.crypto, turnover24h: i.turnover24h, route: S.route, override: override(sym), precise: () => precise })
  }
  const off = onMarket(e => {
    if (!wanted || suspended || bg) return
    if (e.type === 'ws') src.setRoute(S.route)
    else if (e.type === 'universe' && !knewSymbol && info(wanted).known) { src.stop(); start(wanted) }
  })
  // 整页藏到后台（锁屏、切到别的 app / 标签）一分钟：停掉订阅；回到前台按想要的品种重开（页内切走另由 suspend 管）
  let bg = false
  const offHidden = stopWhenHiddenLong(
    () => { bg = true; src.stop() },
    () => { bg = false; if (!wanted || suspended) return; start(wanted); if (seen) src.setVisible(seen[0], seen[1]) },
  )
  return {
    setWanted(onOff, symbol) {
      const sym = symbol.toUpperCase()
      if (!onOff) { wanted = null; src.stop(); return }
      if (sym !== wanted) seen = null
      if (suspended || bg) { wanted = sym; return }
      if (wanted === sym && src.current === sym) return
      wanted = sym
      start(sym)
    },
    noteView(view, series) {
      seen = [view.from, view.to + Math.max(0, series.step)]
      if (wanted && !suspended && !bg) src.setVisible(seen[0], seen[1])
    },
    setPrecise(on) { precise = on },
    dispose() { off(); offHidden(); wanted = null; src.stop() },
    suspend() {
      if (suspended) return
      suspended = true
      src.stop()
    },
    resume() {
      if (!suspended) return
      suspended = false
      if (!wanted || bg) return
      start(wanted)
      if (seen) src.setVisible(seen[0], seen[1])
    },
    setOverride(o) { if (wanted && !suspended && !bg) src.setOverride(o) },
    get thresholds() { return thresholds },
    get defaults() { return defaults },
  }
}
