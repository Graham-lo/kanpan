/* 手机网页版 · 行情页的取数小件
 *
 * - 估值两项（预期净利润、营收）：从 market/meta.ts 那份 /v1/market/meta 的行里取（和总供应量同一次请求，
 *   不再自己另发一次），只留 forwardEarnings / revenue（总供应量由 meta.ts 写进 Sym.supply）。
 * - 主力订单流数据口：照 chart/orderflow.source.ts 的 createOrderFlowPort 包 OrderFlowSource，（③ 图上大单签另算一个理由，见 createPagePort）
 *   多两件事——① setOverride：「主力订单流」门槛改完立刻生效（createOrderFlowPort 对同一品种
 *   setWanted 直接 return，换不了门槛）；② 记下最新快照的生效门槛与默认值，给门槛编辑器用。
 */
import { S, on as onMarket, metaRow } from '../../../market'
import { OrderFlowSource } from '../../chart/orderflow.source'
import { stopWhenHiddenLong } from '../../../orderflow/idle'
import type { OrderFlowPort } from '../../chart'
import type { OrderFlowSnapshot } from '../../../orderflow/group'
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
  /** 图上大单签要不要逐笔（与挂单墙开关互不牵连）：只开签时数据层照跑、但快照不交给图（图上不画墙） */
  setSigns(on: boolean, symbol: string): void
  /** 最新快照的生效门槛 / 叠改动之前的默认门槛（还没到是 null） */
  readonly thresholds: Thresholds | null
  readonly defaults: Thresholds | null
  /** 最新一帧（墙开没开都记；「大单与爆仓」弹层的挂单墙药丸用）；没在订是 null */
  readonly snapshot: OrderFlowSnapshot | null
  /** 正在订那只的价位步长 / 最近一笔成交的本机时刻（0 = 还没进过） */
  readonly step: number | null
  readonly lastTradeMs: number
}

/**
 * 两个理由要数据层：挂单墙（图 setWanted）与图上大单签（setSigns）。任一个要就订；
 * 只有墙要时才把快照交给图——只开签时图上不画墙，墙关掉的那一刻交一个 null 清掉。
 */
export function createPagePort(push: (snap: OrderFlowSnapshot | null) => void, override: (sym: string) => Override | null, startSuspended = false): PagePort {
  let thresholds: Thresholds | null = null, defaults: Thresholds | null = null
  let last: OrderFlowSnapshot | null = null
  let walls = false, signs = false
  const src = new OrderFlowSource(snap => {
    if (snap) { thresholds = snap.thresholds; defaults = snap.defaults ?? null }
    last = snap
    if (walls) push(snap)
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
    thresholds = null; defaults = null; last = null
    src.start(sym, 0, { crypto: i.crypto, turnover24h: i.turnover24h, route: S.route, override: override(sym), precise: () => precise })
  }
  const off = onMarket(e => {
    if (!wanted || suspended || bg) return
    if (e.type === 'ws') src.setRoute(S.route)
    else if (e.type === 'universe' && !knewSymbol && info(wanted).known) { src.stop(true); start(wanted) }
  })
  // 整页藏到后台（锁屏、切到别的 app / 标签）一分钟：停掉订阅；回到前台按想要的品种重开（页内切走另由 suspend 管）
  let bg = false
  const offHidden = stopWhenHiddenLong(
    () => { bg = true; src.stop() },
    () => { bg = false; if (!wanted || suspended) return; start(wanted); if (seen) src.setVisible(seen[0], seen[1]) },
  )
  /** 两个理由合起来：要订哪只（null = 不订） */
  const want = (symbol: string): void => {
    const sym = symbol.toUpperCase()
    if (!walls && !signs) { wanted = null; last = null; src.stop(); return }
    if (sym !== wanted) seen = null
    if (suspended || bg) { wanted = sym; return }
    if (wanted === sym && src.current === sym) return
    wanted = sym
    start(sym)
  }
  return {
    setWanted(onOff, symbol) {
      const was = walls
      walls = onOff
      want(symbol)
      // 只关墙、签还在订：图上的墙清掉；只开墙、签早在订：手上的最新一帧马上交给图
      if (was && !walls && signs) push(null)
      else if (!was && walls && last && src.current === symbol.toUpperCase()) push(last)
    },
    setSigns(onOff, symbol) { signs = onOff; want(symbol) },
    noteView(view, series) {
      seen = [view.from, view.to + Math.max(0, series.step)]
      if (wanted && !suspended && !bg) src.setVisible(seen[0], seen[1])
    },
    setPrecise(on) { precise = on },
    dispose() { off(); offHidden(); wanted = null; last = null; src.stop() },
    suspend() {
      if (suspended) return
      suspended = true
      // 行情页切走（去自选挑一只再回来）：这只先留着（orderflow/keep.ts：最多两只、三分钟），回来不从头连；
      // 整页藏到后台满一分钟照旧全停（上面的 stopWhenHiddenLong）
      src.park()
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
    get snapshot() { return last },
    get step() { return src.step },
    get lastTradeMs() { return src.lastTradeMs },
  }
}
