/* Hkline Web · 品种元数据（总供应量等），来自看盘自己的服务端 /v1/market/meta
 *
 * 同源取（线上页面就挂在同一个域名下）；本地开发时由 vite 代理转到线上。
 * 市值 = 总供应量 × 现价；服务端没给供应量的品种（大宗等）不显示市值。
 */
import { S, emit } from './state'

const requested = new Set<string>()
let queue: string[] = []
let timer: ReturnType<typeof setTimeout> | null = null

export function wantMeta(symbols: string[]): void {
  for (const k of symbols) if (!requested.has(k)) { requested.add(k); queue.push(k) }
  if (queue.length && !timer) timer = setTimeout(flush, 200)
}

async function flush(): Promise<void> {
  timer = null
  const batch = queue.splice(0, 60)
  if (!batch.length) return
  try {
    const r = await fetch(`${import.meta.env.BASE_URL.replace(/\/web\/$/, '/')}v1/market/meta?symbols=${batch.join(',')}`, { cache: 'no-store' })
    if (r.ok) {
      const body = await r.json() as { data?: Record<string, { totalSupply?: number | string }> }
      let hit = false
      for (const [k, v] of Object.entries(body.data || {})) {
        const s = S.symbols.get(k)
        const sup = v?.totalSupply != null ? +v.totalSupply : NaN
        if (s && isFinite(sup) && sup > 0) { s.supply = sup; hit = true }
      }
      if (hit) emit({ type: 'meta' })
    }
  } catch { /* 服务端不通就不显示市值 */ }
  if (queue.length) timer = setTimeout(flush, 200)
}

export function marketCap(symbol: string): number | null {
  const s = S.symbols.get(symbol)
  return s?.supply && s.price ? s.supply * s.price : null
}
