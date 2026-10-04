/* Hkline Web · 品种元数据（总供应量、美股的预期盈利 / 营收），来自看盘自己的服务端 /v1/market/meta
 *
 * 同源取（线上页面就挂在同一个域名下）；本地开发时由 vite 代理转到线上。
 * 市值 = 总供应量 × 现价；服务端没给供应量的品种（大宗等）不显示市值。
 *
 * 一只品种全程只要一次：各处（PC 详情格、手机行情页头部的估值格、品种预览）都走这里，200 ms 内的合成一批；
 * 取失败（断网、服务端 5xx）的那批两分钟后允许再取——原来失败也记成「要过了」，市值整场空着。
 */
import { S, emit } from './state'

export interface MetaRow { totalSupply?: number | string; forwardEarnings?: unknown; revenue?: unknown }

/** 失败后多久允许再取 */
export const META_RETRY_MS = 120_000
const BATCH = 60

const requested = new Set<string>()
/** 取到了的行；null = 服务端没有这只 */
const rows = new Map<string, MetaRow | null>()
/** 等这一只结果的人（undefined = 这次没取到） */
const waiters = new Map<string, ((r: MetaRow | null | undefined) => void)[]>()
let queue: string[] = []
let timer: ReturnType<typeof setTimeout> | null = null

export function wantMeta(symbols: string[]): void {
  for (const k of symbols) if (!requested.has(k)) { requested.add(k); queue.push(k) }
  if (queue.length && !timer) timer = setTimeout(flush, 200)
}

/** 这一只的元数据行：已有就直接给；否则排进下一批。null = 服务端没有这只，undefined = 这次没取到（两分钟后可再要） */
export function metaRow(symbol: string): Promise<MetaRow | null | undefined> {
  if (rows.has(symbol)) return Promise.resolve(rows.get(symbol))
  return new Promise(res => {
    const w = waiters.get(symbol)
    if (w) w.push(res); else waiters.set(symbol, [res])
    wantMeta([symbol])
  })
}

/** 已取到的总供应量（全市场表晚于元数据到时，loadUniverse 用它补上） */
export function supplyOf(symbol: string): number | undefined {
  const v = rows.get(symbol)?.totalSupply
  const n = v != null ? +v : NaN
  return isFinite(n) && n > 0 ? n : undefined
}

function settle(k: string, r: MetaRow | null | undefined): void {
  const w = waiters.get(k)
  if (!w) return
  waiters.delete(k)
  for (const f of w) f(r)
}

async function flush(): Promise<void> {
  timer = null
  const batch = queue.splice(0, BATCH)
  if (!batch.length) return
  let ok = false
  try {
    const r = await fetch(`${import.meta.env.BASE_URL.replace(/\/web\/(m\/)?$/, '/')}v1/market/meta?symbols=${batch.map(encodeURIComponent).join(',')}`, { cache: 'no-store' })
    if (r.ok) {
      const body = await r.json() as { data?: Record<string, MetaRow> }
      ok = true
      let hit = false
      for (const k of batch) {
        const row = body?.data?.[k] ?? null
        rows.set(k, row)
        const sup = supplyOf(k), s = S.symbols.get(k)
        if (s && sup != null && s.supply !== sup) { s.supply = sup; hit = true }
        settle(k, row)
      }
      // 等 metaRow 的等候者先把自己的结果记下（估值格），再让各页重画
      await null
      if (hit || batch.some(k => rows.get(k))) emit({ type: 'meta' })
    }
  } catch { /* 服务端不通：这一批两分钟后可再取 */ }
  if (!ok) {
    for (const k of batch) settle(k, undefined)
    setTimeout(() => { for (const k of batch) if (!rows.has(k)) requested.delete(k) }, META_RETRY_MS)
  }
  if (queue.length) timer = setTimeout(flush, 200)
}

export function marketCap(symbol: string): number | null {
  const s = S.symbols.get(symbol)
  return s?.supply && s.price ? s.supply * s.price : null
}
